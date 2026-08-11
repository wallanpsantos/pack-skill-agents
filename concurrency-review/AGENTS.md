# AGENTS.md — Guia de Execução e Regras para Agentes: Revisão de Concorrência Java

**Versão 4.0.0** — Java 25 (LTS) & Spring Boot 4.0.5+

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
- `ScopedValue` (JEP 506) é final/estável no Java 25 — use para contexto imutável de requisição.

### 1.2 Thread Safety e Estado Compartilhado

- Identifique TODO estado mutável compartilhado entre threads antes de analisar qualquer outro aspecto.
- Operações check-then-act em estado compartilhado DEVEM ser atômicas (`computeIfAbsent`, `AtomicReference`, etc.).
- `volatile` é obrigatório para double-checked locking. Prefira holder idiom quando possível.
- Locks devem ter ordenação consistente para prevenir deadlocks.
- `lock.lock()` ANTES do `try`; `unlock()` SOMENTE no `finally`.
- Use `tryLock(timeout, unit)` quando espera ilimitada ou risco de deadlock estiverem presentes.

### 1.3 Virtual Threads (Java 25)

- Virtual Threads são um **mecanismo de escalabilidade para tarefas majoritariamente bloqueantes (I/O)**, NÃO uma
  otimização universal de performance.
- Ganho real depende de workload, ambiente, dependências e perfil de contenção. Benchmarks de terceiros NÃO são
  evidência suficiente.
- NUNCA "poole" Virtual Threads — spawne uma por tarefa (`Thread.ofVirtual().start` ou
  `newVirtualThreadPerTaskExecutor`).
- CPU-bound pesado DEVE permanecer em pools de plataforma / `ForkJoinPool`. Para CPU-bound em VT, faça yield
  periódico (`Thread.yield()`) ou delegue ao `ForkJoinPool`.
- **VTs são sempre daemon threads** (`setDaemon(false)` lança `IllegalArgumentException`).
- **VTs sempre rodam com `NORM_PRIORITY`** — alterações de prioridade não têm efeito.
- **Nomeie VTs** via `Thread.ofVirtual().name(prefix, start).start(...)` para rastreabilidade.

#### Internals da JVM (Mecanismo de Continuação)

- Stacks de VTs vivem no **heap Java** (não em memória nativa/off-heap). Migração de platform threads para VTs
  **desloca pressão de memória do off-heap para o heap** — aumente `-Xmx` proporcionalmente em containers.
- O scheduler de VTs usa um `ForkJoinPool` **dedicado**, separado do `ForkJoinPool.commonPool()`. Tune com:
  - `-Djdk.virtualThreadScheduler.parallelism=N` (padrão: número de processadores)
  - `-Djdk.virtualThreadScheduler.maxPoolSize=256` (padrão: 256)

#### Pinning (Java 25)

- **JEP 491 (Java 24):** Pinning por `synchronized` foi removido — VTs podem adquirir, manter e liberar monitores
  sem ficar presas ao carrier.
- Porém, `synchronized` em operações de I/O prolongado **continua problemático** por contenção de monitor, sem bounded
  wait, sem interruptibilidade. Use `ReentrantLock`.
- Pinning **persiste** em Java 25 para:
  - Chamadas nativas (JNI / FFM API)
  - Class loading durante execução
  - Alguns I/O de arquivo locais no Linux
- Detecte pinning residual via JFR: `jdk.VirtualThreadPinned` e `jdk.VirtualThreadSubmitFailed`.
- Em dev, use `-Djdk.tracePinnedThreads=full` para diagnóstico (depreciado para `synchronized` no JDK 24+; ainda útil
  para pinning nativo).

#### Limites de Recursos

- Com Virtual Threads, o gargalo migra para recursos downstream: pool JDBC, HTTP clients, rate limits, descritores de
  arquivo, brokers.
- EXIJA `Semaphore` ou mecanismos de rate limiting/backpressure para proteger APIs externas, bancos e brokers.
- Alinhe as permissões do `Semaphore` com o `maximumPoolSize` do HikariCP.
- Verifique capacidade de pools JDBC/HTTP e tamanhos de filas sob cenários de alta concorrência.
- **HikariCP:** Antes do Java 24, blocos `synchronized` internos do HikariCP podiam pinar VTs — resolvido pelo JEP
  491. Em Java 25 não há workaround necessário.

### 1.4 ThreadLocal, ScopedValue e Contexto

- `ScopedValue` para contexto imutável de requisição — é o padrão no Java 25.
- `ThreadLocal` apenas para dados realmente mutáveis, com escopo curto e limpeza garantida (`remove()` em `finally`).
- **PROIBIDO** usar `ThreadLocal` como mecanismo de cache em código executado em Virtual Threads — causa explosão de
  inicializações (2000x+ documentado) e pressão de GC. Prefira pools explícitos ou caches por componente de aplicação.
- NUNCA use `ThreadLocal` para propagar contexto de requisição de longa duração com Virtual Threads.
- **`InheritableThreadLocal`** é proibido em escala de VTs: copia o mapa inteiro do pai na criação de cada VT —
  explosão de memória com milhares de VTs. Use `ScopedValue` em vez disso.
- **`ScopedValue` com objeto mutável**: a referência é imutável, mas o objeto dentro pode não ser — race conditions
  ainda são possíveis se o objeto for mutável e compartilhado.

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
- **`thenApplyAsync` (e demais `*Async`) sem executor também usa `commonPool`** — igualmente errado para estágios
  bloqueantes. Sempre forneça executor explícito.
- NUNCA crie `Executors.newVirtualThreadPerTaskExecutor()` inline sem fechar. Prefira `@Bean` compartilhado.
- `join()` / `get()` sem timeout na thread chamadora: use `orTimeout()` na chain antes do `join()`.

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
- `SecurityContextHolder` é ThreadLocal-bound — use `DelegatingSecurityContextExecutorService` ou
  `DelegatingSecurityContextAsyncTaskExecutor` quando async precisa de auth.
- **`InheritableThreadLocal` propagation mode** (`INHERITABLETHREADLOCAL`) copia o mapa na criação de cada VT —
  caro em escala. Prefira propagação explícita ou `DelegatingSecurityContext*`.
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
- Métricas obrigatórias: throughput, latência média, **p95/p99/p99.9**, CPU, heap e memória nativa.
- Variar níveis de carga (baixa, média, alta, pico).
- JFR com eventos `jdk.VirtualThreadPinned` e `jdk.VirtualThreadSubmitFailed`.
- Dumps via `jcmd <PID> Thread.dump_to_file -format=json <FILE>` para inspecionar carriers sob carga.
- Teoria ou benchmarks de terceiros NÃO substituem medição no ambiente real.
- **Erros comuns de benchmark**: comparar VTs contra pool subdimensionado (artificialmente favorece VTs); medir só
  throughput sem p99; não medir impacto em recursos downstream (DB wait time, pool saturation).

---

## 7. Observabilidade

- Todo executor DEVE expor métricas via Micrometer/OTel: tarefas ativas, fila, rejeições, latência.
- JFR é obrigatório para diagnóstico de pinning e contenção em produção. Configure com overhead baixo.
- Loggers DEVEM incluir thread name em padrões de log para rastreabilidade.
- **Monitoramento padrão (Prometheus JVM metrics, VisualVM) mostra platform thread count (carriers)**, que permanece
  constante mesmo com milhões de VTs. Use JFR ou métricas customizadas para observar atividade real de VTs.
- Use `jdk.VirtualThreadPinned` com threshold de 50ms para alertas; `jdk.VirtualThreadSubmitFailed` é crítico
  (pool de carriers esgotado).

---

## 8. Concorrência Cloud-Native

- **Memória em containers:** stacks de VTs vivem no heap — aumente `-Xmx` após migrar de platform threads.
- **CPU limits em Kubernetes:** defina `limits.cpu` para que a JVM leia o número correto de processadores para o
  VT scheduler.
- **Liveness probes:** baseie em saúde da aplicação (HTTP actuator), NÃO em contagem de platform threads.
- **GraalVM Native Image:** suporta VTs. Class loading dinâmico durante execução de VT pode pinar o carrier —
  pré-carregue classes críticas no startup.
- **File descriptors:** monitorar limites de OS (`ulimit -n`) em workloads de alta concorrência com VTs.
- **Scaling:** VTs melhoram escalabilidade vertical (mais trabalho por instância); HPA ainda necessário para
  escalabilidade horizontal e workloads CPU-bound.

---

## 9. Superfície de Testes de Concorrência

1. **Condições de corrida**: Testes com múltiplas threads concorrentes em estado compartilhado.
2. **Timeout e cancelamento**: Verificar que timeouts são respeitados e cancelamento propaga.
3. **Consistência financeira**: Testes de débito/crédito concorrente com verificação de saldo final.
4. **Retry em OptimisticLockException**: Confirmar convergência após retries.
5. **Propagação de contexto**: Verificar que `SecurityContext` e `ScopedValue` propagam corretamente.
6. **Pinning**: JFR recording durante testes de carga para validar ausência de pinning inesperado.
7. **Resource exhaustion**: Simular esgotamento de pool JDBC/HTTP com alta concorrência de VTs.

---

## 10. Arquivos de Referência da Skill

Ao atuar no projeto, consulte os arquivos especializados quando necessário:

- [`SKILL.md`](file:///C:/Users/walla/.gemini/antigravity-cli/skills/concurrency-review/SKILL.md): Workflow de revisão,
  checklist e formato de output.
- [
  `references/virtual-threads.md`](file:///C:/Users/walla/.gemini/antigravity-cli/skills/concurrency-review/references/virtual-threads.md):
  Virtual Threads, JVM internals, pinning (JEP 491/Java 25), limites de recursos, ScopedValue vs ThreadLocal,
  InheritableThreadLocal, CPU burst, Linux file I/O, GraalVM, HikariCP, observabilidade.
- [
  `references/spring-async.md`](file:///C:/Users/walla/.gemini/antigravity-cli/skills/concurrency-review/references/spring-async.md):
  `@Async`, EnableAsync, SecurityContext (3 opções), VT container config, executor configuration.
- [
  `references/completable-future.md`](file:///C:/Users/walla/.gemini/antigravity-cli/skills/concurrency-review/references/completable-future.md):
  CF chains, timeouts, executors, terminal handlers, `thenApplyAsync` sem executor, allOf com resultado.
- [
  `references/classic-issues.md`](file:///C:/Users/walla/.gemini/antigravity-cli/skills/concurrency-review/references/classic-issues.md):
  Race conditions, visibility, deadlocks, DCL, locks (tryLock), ConcurrentHashMap, interruption.
- [
  `references/financial-consistency.md`](file:///C:/Users/walla/.gemini/antigravity-cli/skills/concurrency-review/references/financial-consistency.md):
  BigDecimal, `@Version`, optimistic locking, Money value object.
- [
  `references/virtual-threads-vs-completable-future.md`](file:///C:/Users/walla/.gemini/antigravity-cli/skills/concurrency-review/references/virtual-threads-vs-completable-future.md):
  Decision tree VT vs CF vs Reactive.
- [
  `references/cloud-native-concurrency.md`](file:///C:/Users/walla/.gemini/antigravity-cli/skills/concurrency-review/references/cloud-native-concurrency.md):
  Kubernetes memory/CPU config, liveness probes, GraalVM Native Image, JFR em produção, file descriptors.
