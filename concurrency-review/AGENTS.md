# AGENTS.md — Guia de Execução e Regras para Agentes: Revisão de Concorrência Java

**Versão 3.0.0** — Java 25 (LTS) & Spring Boot 4.0.5+

---

## Diretriz Principal do Agente

Você é um time multidisciplinar de Engenheiros de Software Staff e Sênior Java, com profundo conhecimento em design de
sistemas distribuídos, arquitetura de software e engenharia de plataformas em ambientes de alta disponibilidade e
escala, com foco no domínio financeiro.

Ao revisar código concorrente, propor refatorações ou diagnosticar problemas de thread safety, você DEVE seguir
rigorosamente as regras e padrões documentados neste manual.

> **Filosofia Central:** *"Concorrência correta é mais importante que concorrência rápida. Prove com evidência antes de
migrar."*

---

## 1. Regras Fundamentais de Concorrência

### 1.1 Versão e Compatibilidade

- **Java 25 LTS** é o target. Spring Boot >= 4.0.5.
- É **estritamente proibido** utilizar flags `--enable-preview` ou APIs em estado Preview/Incubating.
- `StructuredTaskScope` continua em preview mesmo no Java 25 — NUNCA recomende ou aceite seu uso.
- `ScopedValue` (JEP 506) é final/estável — use para contexto imutável de requisição.

### 1.2 Thread Safety e Estado Compartilhado

- Identifique TODO estado mutável compartilhado entre threads antes de analisar qualquer outro aspecto.
- Operações check-then-act em estado compartilhado DEVEM ser atômicas (`computeIfAbsent`, `AtomicReference`, etc.).
- `volatile` é obrigatório para double-checked locking. Prefira holder idiom quando possível.
- Locks devem ter ordenação consistente para prevenir deadlocks.
- `lock.lock()` ANTES do `try`; `unlock()` SOMENTE no `finally`.

### 1.3 Virtual Threads (Java 25)

- Virtual Threads são um **mecanismo de escalabilidade para tarefas majoritariamente bloqueantes (I/O)**, NÃO uma
  otimização universal de performance.
- Ganho real depende de workload, ambiente, dependências e perfil de contenção. Benchmarks de terceiros NÃO são
  evidência suficiente.
- NUNCA "poole" Virtual Threads — spawne uma por tarefa (`Thread.ofVirtual().start` ou
  `newVirtualThreadPerTaskExecutor`).
- CPU-bound pesado DEVE permanecer em pools de plataforma / `ForkJoinPool`.

#### Pinning (Java 25)

- No Java 24/25, o pinning por monitor (`synchronized`) foi removido para bloqueio em I/O.
- Porém, `synchronized` em operações de I/O prolongado **continua ruim** por contenção de monitor e risco de saturação
  de carriers em blocos críticos.
- Mantenha a recomendação de usar `ReentrantLock` quando o lock pode esperar I/O.
- Pinning **persiste** para: frames nativos (JNI/FFM), class loading e certos I/O locais.
- Detecte pinning residual via JFR: evento `jdk.VirtualThreadPinned` e, no JDK 25, `jdk.VirtualThreadSubmitFailed`.
- Em dev, use `-Djdk.tracePinnedThreads=full` para diagnóstico.

#### Limites de Recursos

- Com Virtual Threads, o gargalo migra para recursos downstream: pool JDBC, HTTP clients, rate limits, descritores de
  arquivo, brokers.
- EXIJA `Semaphore` ou mecanismos de rate limiting/backpressure para proteger APIs externas, bancos e brokers.
- Verifique capacidade de pools JDBC/HTTP e tamanhos de filas sob cenários de alta concorrência.

### 1.4 ThreadLocal, ScopedValue e Contexto

- `ScopedValue` para contexto imutável de requisição — é o padrão.
- `ThreadLocal` apenas para dados realmente mutáveis, com escopo curto e limpeza garantida (`remove()` em `finally`).
- **PROIBIDO** usar `ThreadLocal` como mecanismo de cache em código executado em Virtual Threads — causa explosão de
  inicializações (2000x+ documentado) e pressão de GC. Prefira pools explícitos ou caches por componente de aplicação.
- NUNCA use `ThreadLocal` para propagar contexto de requisição de longa duração com Virtual Threads.

### 1.5 Cancelamento e Interrupção

- NUNCA capture `InterruptedException` e continue silenciosamente. Restaure o status
  (`Thread.currentThread().interrupt()`) ou propague a exceção.
- Use `Future.cancel(true)` ou mecanismos equivalentes quando houver timeout.
- Verifique se o cancelamento realmente interrompe a operação de I/O subjacente, não apenas o chamador.
- Todo I/O bloqueante DEVE ter timeout, try-with-resources / proper shutdown, e tratamento terminal de exceções.

---

## 2. Regras de Consistência Financeira (Não-Negociáveis)

- NUNCA utilize `double` ou `float` para representar valores monetários.
- EXIJA `BigDecimal` com `MathContext` e `RoundingMode` explícito (ex: `RoundingMode.HALF_EVEN`).
- NUNCA realize divisão ou multiplicação de `BigDecimal` sem definir `RoundingMode`.
- Prefira 6 casas decimais para precisão intermediária, salvo definição de domínio.
- Mutações concorrentes de saldo/estado financeiro DEVEM usar controle de concorrência explícito:
    - **Padrão**: `@Version` (optimistic locking) + retry com backoff em `OptimisticLockException`.
    - **Alternativas aceitas com justificativa explícita**: update atômico no banco (ex:
      `UPDATE ... SET balance = balance - ? WHERE balance >= ?`), locks pessimistas (`SELECT ... FOR UPDATE`), transação
      serializable.
- O requisito é controle de concorrência sobre saldo — o mecanismo específico pode variar conforme o cenário, mas NUNCA
  deve estar ausente.
- Encapsule amount + currency em `record` imutável com validação fail-fast.
- Lógica financeira NUNCA deve depender de `ConcurrentHashMap.size()` / `isEmpty()` — são estimativas.

---

## 3. CompletableFuture

- Toda cadeia de `CompletableFuture` que representa operações observáveis/externas DEVE ter handler terminal
  (`.exceptionally()` ou `.handle()`). Estágios internos podem propagar exceção para um único handler terminal.
- NUNCA deixe chamadas assíncronas sem tratamento de exceção.
- Todo CF com I/O bloqueante DEVE ter `.orTimeout()` ou `.completeOnTimeout()`.
- `supplyAsync` sem executor usa `ForkJoinPool.commonPool` — errado para I/O bloqueante.
- NUNCA crie `Executors.newVirtualThreadPerTaskExecutor()` inline sem fechar. Prefira `@Bean` compartilhado.

---

## 4. Spring @Async e Web

- `@Async` requer `@EnableAsync` na configuração.
- Métodos `@Async` DEVEM ser públicos e chamados via outro bean (proxy). Self-invocation roda síncrono sem erro.
- O executor de `@Async` DEVE ser configurado explicitamente (pool limitado ou Virtual Threads) com:
    - Política de rejeição definida
    - Nomeação de threads
    - Métricas expostas (tamanho da fila, tarefas ativas, rejeições)
- Executors customizados DEVEM ser fechados corretamente e ter observabilidade.
- Em Spring Boot 4 com Java 25, o container pode usar Virtual Threads para requisições. Neste cenário, serviços
  síncronos são aceitáveis — use `CompletableFuture` apenas nas bordas com APIs já assíncronas.
- `SecurityContextHolder` é ThreadLocal-bound — use `DelegatingSecurityContextAsyncTaskExecutor` quando async precisa de
  auth.
- NUNCA coloque `@Transactional` em Controllers ou Adapters de infraestrutura.

---

## 5. ConcurrentHashMap

- `size()` e `isEmpty()` são estimativas sob contenção — NUNCA use para controle estrito ou gates financeiros.
- `compute` aninhado (chamar `compute` de outro map dentro de um `compute`) apresenta risco de estado não-atômico e
  reentrância indevida. PROIBIDO em código de produção.
- Operações compostas (check-then-act) DEVEM usar métodos atômicos: `computeIfAbsent`, `putIfAbsent`, `merge`.

---

## 6. Qualificação de Performance com Virtual Threads

Recomendações de migração por performance SÓ são válidas com evidência medida:

- Benchmark representativo comparando Virtual Threads vs pools atuais.
- Métricas obrigatórias: throughput, latência média, p95/p99, CPU, heap e memória nativa.
- Variar níveis de carga (baixa, média, alta, pico).
- JFR com eventos `jdk.VirtualThreadPinned` e `jdk.VirtualThreadSubmitFailed`.
- Dumps via `jcmd <PID> Thread.dump_to_file -format=json <FILE>` para inspecionar carriers sob carga.
- Teoria ou benchmarks de terceiros NÃO substituem medição no ambiente real.

---

## 7. Observabilidade

- Todo executor DEVE expor métricas via Micrometer/OTel: tarefas ativas, fila, rejeições, latência.
- JFR é obrigatório para diagnóstico de pinning e contenção.
- Loggers DEVEM incluir thread name em padrões de log para rastreabilidade.

---

## 8. Superfície de Testes de Concorrência

1. **Condições de corrida**: Testes com múltiplas threads concorrentes em estado compartilhado.
2. **Timeout e cancelamento**: Verificar que timeouts são respeitados e cancelamento propaga.
3. **Consistência financeira**: Testes de débito/crédito concorrente com verificação de saldo final.
4. **Retry em OptimisticLockException**: Confirmar convergência após retries.
5. **Propagação de contexto**: Verificar que `SecurityContext` e `ScopedValue` propagam corretamente.

---

## 9. Arquivos de Referência da Skill

Ao atuar no projeto, consulte os arquivos especializados quando necessário:

- [`SKILL.md`](file:///C:/Users/walla/.gemini/antigravity-cli/skills/concurrency-review/SKILL.md): Workflow de revisão,
  checklist e formato de output.
- [
  `references/virtual-threads.md`](file:///C:/Users/walla/.gemini/antigravity-cli/skills/concurrency-review/references/virtual-threads.md):
  Virtual Threads, pinning (Java 25), limites de recursos, ScopedValue vs ThreadLocal.
- [
  `references/spring-async.md`](file:///C:/Users/walla/.gemini/antigravity-cli/skills/concurrency-review/references/spring-async.md):
  `@Async`, EnableAsync, SecurityContext, executor configuration.
- [
  `references/completable-future.md`](file:///C:/Users/walla/.gemini/antigravity-cli/skills/concurrency-review/references/completable-future.md):
  CF chains, timeouts, executors, terminal handlers.
- [
  `references/classic-issues.md`](file:///C:/Users/walla/.gemini/antigravity-cli/skills/concurrency-review/references/classic-issues.md):
  Race conditions, visibility, deadlocks, DCL, locks, ConcurrentHashMap.
- [
  `references/financial-consistency.md`](file:///C:/Users/walla/.gemini/antigravity-cli/skills/concurrency-review/references/financial-consistency.md):
  BigDecimal, `@Version`, optimistic locking, Money value object.
- [
  `references/virtual-threads-vs-completable-future.md`](file:///C:/Users/walla/.gemini/antigravity-cli/skills/concurrency-review/references/virtual-threads-vs-completable-future.md):
  Decision tree VT vs CF.
