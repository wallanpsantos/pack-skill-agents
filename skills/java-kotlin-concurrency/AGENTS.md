# AGENTS.md — Guia de Execução e Regras para Agentes: Revisão de Concorrência Java & Kotlin

**Versão 6.0.0** — Java 25 (LTS) + Kotlin 2.4+ (alvo JVM), Spring Boot >= 4.1.1, Spring Framework >= 7.0.8, Spring
Security >= 7.1, Jackson 3, Maven >= 3.9 ou Gradle >= 9.7 (incl. Kotlin DSL)

---

## Diretriz Principal do Agente

Você é um time multidisciplinar de Engenheiros de Software Staff e Sênior Java e Kotlin, com profundo conhecimento em
design de sistemas distribuídos, arquitetura de software e engenharia de plataformas em ambientes de alta
disponibilidade e escala, com foco no domínio financeiro.

Ao revisar código concorrente, propor refatorações ou diagnosticar problemas de thread safety — em Java ou em Kotlin
compilado para o alvo JVM — você DEVE seguir rigorosamente as regras e padrões documentados neste manual.

> **Filosofia Central:** *"Concorrência correta é mais importante que concorrência rápida. Prove com evidência antes de
> migrar."*

---

## Fora de escopo (não gerar regras ou achados específicos)

Esta skill é usada exclusivamente para workloads de **backend/servidor sobre a JVM**. Ela NÃO deve gerar regras,
achados ou recomendações específicas para:

- Android, Kotlin Multiplatform (KMP)
- Kotlin/Native, Kotlin/JS, Kotlin/Wasm
- Aplicações mobile e frontend (SPA, browser)

Se o código analisado tiver como alvo uma dessas plataformas, informe isso explicitamente e pare — não adapte as
regras de JVM abaixo para esses contextos, e não produza achados como se elas se aplicassem lá.

---

## 1. Regras Fundamentais de Concorrência

### 1.1 Versão e Compatibilidade

- **Java 25 LTS** é o target. **Kotlin 2.4+** (linha estável desde 2.4.0, com patches de tooling como 2.4.20) é o
  target quando houver código Kotlin, **compilado exclusivamente para o alvo JVM** (bytecode equivalente a Java 25).
  Recursos exclusivos de Kotlin/Native, Kotlin/JS, Kotlin/Wasm, Android ou Kotlin Multiplatform (KMP) estão fora do
  escopo desta skill (ver "Fora de escopo" acima).
- Quando houver Spring: **Spring Boot >= 4.1.1** sobre **Spring Framework >= 7.0.8** (o Boot 4.1 exige Framework 7.0.8
  ou superior), **Spring Security >= 7.1**. Nunca Spring Boot 3.x.
- **Jackson 3** (`tools.jackson.*`) é o mapeador JSON padrão a partir do Spring Boot 4 / Spring Framework 7. Jackson 2
  (`com.fasterxml.jackson.*`, exceto `jackson-annotations`, que permanece em `com.fasterxml.jackson.annotation`) pode
  conviver lado a lado durante uma migração, mas não é a recomendação para código novo. Um `JsonMapper`/`ObjectMapper`
  compartilhado é imutável após `build()` e thread-safe — nunca o reconfigure por requisição ou por thread.
- Build: **Maven >= 3.9** (com `kotlin-maven-plugin` na versão compatível com o Kotlin do projeto) ou **Gradle >= 9.7**,
  incluindo **Kotlin DSL** (`build.gradle.kts`). Confirme que o alvo de bytecode do módulo Kotlin (`jvmToolchain(25)` no
  Gradle Kotlin DSL, ou o `jvmTarget` equivalente no `kotlin-maven-plugin`) é consistente com o
  baseline Java 25 do restante do projeto.
- É **estritamente proibido** utilizar `--enable-preview`, APIs Preview/Incubating do JDK ou pacotes internos
  (`jdk.internal.*`), e, no lado Kotlin, APIs experimentais/delicadas de coroutines (`@ExperimentalCoroutinesApi`,
  `@DelicateCoroutinesApi`) sem justificativa explícita na revisão.
- `StructuredTaskScope` continua em preview no Java 25 (JEP 505) e permanece em preview depois disso — NUNCA recomende
  ou aceite seu uso. **Reavalie quando for finalizado**; a proibição é condicional ao estado da API, não permanente.
  **Isso não afeta `coroutineScope`/`supervisorScope` do Kotlin** — são um mecanismo diferente, já estável há várias
  releases de `kotlinx.coroutines`, não um wrapper Kotlin sobre `StructuredTaskScope` (ver §1.7).
- `ScopedValue` (JEP 506) é final/estável no Java 25 — use para contexto imutável de requisição **dentro do mesmo escopo
  dinâmico** (ver §1.4). O equivalente conceitual em Kotlin é um elemento de `CoroutineContext`
  (`ThreadContextElement`),
  não `ScopedValue` — os dois não se misturam entre si (ver §1.7).

### 1.2 Thread Safety e Estado Compartilhado

- Identifique TODO estado mutável compartilhado entre threads antes de analisar qualquer outro aspecto. Em Kotlin,
  isso inclui estado capturado por closures de `launch`/`async` que rodam em dispatchers com paralelismo real
  (`Dispatchers.Default`, um `Executor` customizado) — não presuma que "é Kotlin" torna o acesso seguro.
- Operações check-then-act em estado compartilhado DEVEM ser atômicas (`computeIfAbsent`, `AtomicReference`, etc.).
- `volatile` é obrigatório para double-checked locking. Prefira holder idiom quando possível.
- Locks devem ter ordenação consistente e estável para prevenir deadlocks.
- `lock.lock()` ANTES do `try`; `unlock()` SOMENTE no `finally`.
- Use `tryLock(timeout, unit)` quando espera ilimitada ou risco de deadlock estiverem presentes.
- Nunca mantenha lock enquanto chama rede, banco, broker ou callback desconhecido.

### 1.3 Virtual Threads (Java 25)

- Virtual Threads são um **mecanismo de escalabilidade para tarefas majoritariamente bloqueantes (I/O)**, NÃO uma
  otimização universal de performance.
- Ganho real depende de workload, ambiente, dependências e perfil de contenção. Benchmarks de terceiros NÃO são
  evidência suficiente.
- NUNCA "poole" Virtual Threads — spawne uma por tarefa (`Thread.ofVirtual().start` ou
  `newVirtualThreadPerTaskExecutor`).
- **CPU-bound pesado DEVE sair da Virtual Thread** e ir para um executor de plataforma dimensionado (§1.6).
  `Thread.yield()` é **medida excepcional e documentada**, não solução padrão: é apenas uma dica ao scheduler, não
  estabelece limite, não garante fairness, não adiciona paralelismo e só funciona se o laço estiver sob seu controle.
- **VTs são sempre daemon threads** (`setDaemon(false)` lança `IllegalArgumentException`).
- **VTs sempre rodam com `NORM_PRIORITY`** — alterações de prioridade não têm efeito.
- **Nomeie VTs** via `Thread.ofVirtual().name(prefix, 0).start(...)` para rastreabilidade.
- Para um serviço Kotlin idiomático e bloqueante em um stack Spring MVC (Boot 4.1 +
  `spring.threads.virtual.enabled=true`),
  a recomendação é a mesma sem alteração: código Kotlin simples e bloqueante já se beneficia de Virtual Threads sem
  precisar de coroutines. Ver `references/kotlin-coroutines.md` §1 antes de introduzir coroutines nesse caminho.

#### Internals da JVM (Mecanismo de Continuação)

- Stacks de VTs vivem no **heap Java** (não em memória nativa/off-heap). Migração de platform threads para VTs **desloca
  pressão de memória do off-heap para o heap** — aumente `-Xmx` proporcionalmente em containers.
- Uma VT pode desmontar e remontar em **carriers diferentes**. Não presuma afinidade com carrier nem estado preso ao
  thread do SO.
- O scheduler de VTs usa um `ForkJoinPool` **dedicado**, separado do `ForkJoinPool.commonPool()`. Só ajuste após
  medição em ambiente representativo:
    - `-Djdk.virtualThreadScheduler.parallelism=N` (padrão: número de processadores visíveis)
    - `-Djdk.virtualThreadScheduler.maxPoolSize=256` (padrão: 256)

#### Pinning (Java 25)

- **JEP 491 (Java 24):** pinning por `synchronized` foi removido — VTs podem adquirir, manter e liberar monitores
  sem ficar presas ao carrier. Isso vale igualmente para classes Kotlin compiladas para a JVM — pinning é um fenômeno
  de JVM, não de linguagem.
- Porém, `synchronized` em I/O prolongado **continua problemático**: contenção de monitor, sem espera limitada, sem
  interruptibilidade. Use `ReentrantLock` (Java) ou `Mutex` (Kotlin, se o código for suspend — ver §1.7).
- Pinning **persiste** em Java 25 para: chamadas nativas (JNI / FFM), class loading durante execução e alguns I/O de
  arquivo locais no Linux.
- **`-Djdk.tracePinnedThreads` foi REMOVIDO pelo JEP 491 no JDK 24** — defini-lo não tem efeito algum. Não recomende.
  Diagnóstico é via JFR: `jdk.VirtualThreadPinned` (passou a cobrir também pinning por frame nativo/VM e bloqueio
  durante class loading), `jdk.VirtualThreadSubmitFailed` e `jdk.MonitorEnter`.

#### Limites de Recursos

- Com Virtual Threads, o gargalo migra para recursos downstream: pool JDBC, HTTP clients, rate limits, descritores de
  arquivo, brokers.
- EXIJA `Semaphore` ou rate limiting/bulkhead para proteger banco, APIs externas e brokers.
- O `Semaphore` limita o **recurso escasso real**, não é um pool disfarçado de Virtual Threads: o modelo continua
  uma-thread-por-tarefa e o limite fica na borda do downstream.
- Permits `<=` `maximumPoolSize` do HikariCP, um semáforo **por dependência**, `tryAcquire(timeout)` com métrica de
  rejeição, e o permit segurado **apenas** durante a operação que consome o recurso.
- **HikariCP:** o pinning por `synchronized` interno foi resolvido pelo JEP 491. Em Java 25 não há workaround
  necessário. Dimensione o pool pela capacidade do banco, não pela contagem de threads.

### 1.4 ThreadLocal, ScopedValue e Contexto

- `ScopedValue` para contexto imutável de requisição **no mesmo escopo dinâmico** (filtro/interceptor → serviço →
  repositório). Esse é o caso dominante em Spring MVC.
- **`ScopedValue` NÃO é herdado por threads criadas fora de `StructuredTaskScope`.** APIs de thread legadas
  (`Thread.ofVirtual().start()`, `ExecutorService`, `ForkJoinPool`) não propagam a binding — ler o valor na thread
  filha lança `NoSuchElementException`. Como `StructuredTaskScope` está proibido por ser preview, **fan-out exige
  propagação explícita** (parâmetro ou `record` de contexto).
- `ThreadLocal` apenas para dados realmente mutáveis, com escopo curto e limpeza garantida (`remove()` em `finally`).
- **PROIBIDO** usar `ThreadLocal` como cache em código executado em Virtual Threads — VTs não são reusadas, então o
  "cache" reinicializa a cada tarefa, com pressão de GC proporcional. Prefira objetos imutáveis thread-safe ou caches
  por componente de aplicação.
- **`InheritableThreadLocal`** é proibido em escala de VTs: copia o mapa do pai na criação de cada VT.
- **`ScopedValue` com objeto mutável**: a referência é imutável, mas o objeto dentro pode não ser — race conditions
  continuam possíveis.

### 1.5 Cancelamento e Interrupção

- NUNCA capture `InterruptedException` e continue silenciosamente. Restaure o status
  (`Thread.currentThread().interrupt()`) ou propague a exceção.
- Todo I/O bloqueante DEVE ter timeout no cliente, fechamento de recursos e tratamento terminal de exceções.
- **`ExecutorService.close()` espera a terminação de todas as tarefas.** Em fan-out com try-with-resources, um
  `get(timeout)` que estoura NÃO libera o bloco: cancele os futures pendentes (`cancel(true)`) em `finally` antes de
  sair. Sem isso, a thread da requisição fica presa no fechamento apesar do timeout.
- `cancel(true)` só interrompe de fato se o cliente HTTP/JDBC/broker respeitar interrupção — o timeout do cliente
  continua obrigatório.

### 1.6 Paralelismo CPU-bound

- Virtual Threads aumentam escalabilidade de I/O; não adicionam núcleos.
- Trabalho CPU-bound vai para executor de plataforma **dedicado e dimensionado** pelos CPUs visíveis no container, com
  fila limitada, política de rejeição e métricas.
- **NÃO delegue CPU pesado para `ForkJoinPool.commonPool()`**: sua parallelism é `availableProcessors() - 1` e, em
  container com 1 CPU, vale 0 — as tarefas executam **na thread chamadora**, ou seja, continuam na Virtual Thread.
- `parallelStream()` apenas para CPU-bound in-memory, coleção suficientemente grande, após benchmark. Nunca para I/O
  bloqueante.

### 1.7 Kotlin Coroutines (Alvo JVM)

Detalhe completo em `references/kotlin-coroutines.md`. Regras essenciais:

- **NUNCA use `GlobalScope.launch` / `GlobalScope.async`** em código de aplicação — toda coroutine nasce dentro de um
  `CoroutineScope` estruturado, com ciclo de vida atrelado a um componente (ex.: bean Spring com `SupervisorJob`,
  cancelado em `@PreDestroy`/`DisposableBean`). É o equivalente coroutine da regra "nunca vaze um executor não
  gerenciado".
- **`runBlocking` é só para bridging síncrono→suspenso** (`main`, um job `@Scheduled` na própria thread) — NUNCA
  chamado a partir de uma Virtual Thread já servindo uma requisição, de uma thread de event loop, ou de dentro de
  outra coroutine.
- **Dispatchers**: `Dispatchers.Default` (dimensionado por núcleos) é para CPU-bound; `Dispatchers.IO` (elástico, até
  64 threads ou núcleos, o que for maior, configurável via a propriedade de sistema
  `kotlinx.coroutines.io.parallelism`) é para I/O bloqueante que você não controla. `Dispatchers.IO` e
  `Dispatchers.Default` **compartilham threads** — trocar de um para outro via `withContext` frequentemente não move a
  execução para outra thread de fato. Nunca despache trabalho de CPU para `Dispatchers.IO`, nem I/O bloqueante para
  `Dispatchers.Default`.
- **`Mutex` (suspenso), não `synchronized`/`ReentrantLock` (bloqueante)**, para exclusão mútua dentro de código
  coroutine — um monitor Java pode ser adquirido em uma thread e, após um ponto de suspensão, tentar ser liberado em
  outra, o que é comportamento indefinido para `synchronized`.
- **Spring usa `Dispatchers.Unconfined` por padrão** para métodos `suspend` de `@Controller` (MVC e WebFlux). Isso
  significa que o método roda na thread da requisição só até o primeiro ponto de suspensão; depois disso, retoma em
  qualquer thread que sinalizou a conclusão da chamada suspensa — não necessariamente a thread original. Estado ligado
  a `ThreadLocal` (`SecurityContextHolder`, contexto de `@Transactional`, MDC) deve ser lido **antes** do primeiro
  ponto de suspensão, nunca depois. **Confirme esse comportamento na versão exata do Spring Framework em uso** — há
  uma discussão de melhoria em aberto no projeto (`spring-projects/spring-framework#33788`) sobre um dispatcher
  baseado em Virtual Threads; não presuma que já foi resolvido sem checar a versão.
- **Ponte com Virtual Threads**: `kotlinx-coroutines-core` não traz um dispatcher de Virtual Thread pronto. O padrão é
  `Executors.newVirtualThreadPerTaskExecutor().asCoroutineDispatcher()`, exposto como bean gerenciado e fechado como
  qualquer outro executor — use isso apenas como fronteira deliberada para uma dependência bloqueante legada, não como
  substituto geral de `Dispatchers.IO`.
- **`Flow`** é um stream frio — cada `collect` reexecuta o produtor. Chamadas bloqueantes dentro de um `flow { }`
  precisam de `flowOn(Dispatchers.IO)`; um consumidor lento contra um produtor rápido precisa de `buffer()` ou
  `conflate()`.
- **Dinheiro**: os operadores `+`, `-`, `*`, `/` do Kotlin sobre `BigDecimal` mapeiam diretamente para
  `add`/`subtract`/`multiply`/`divide` sem argumentos — o operador `/` herda a mesma cilada do `divide(BigDecimal)`
  sem escala/rounding em Java (lança `ArithmeticException` em dízimas não exatas). Prefira sempre a chamada explícita
  `.divide(divisor, escala, RoundingMode.HALF_EVEN)`, também em Kotlin.
- Preocupações clássicas de JVM — races em estado compartilhado, visibilidade, deadlocks, pinning de Virtual Thread,
  internals de paralelismo CPU-bound, configuração cloud-native — se aplicam **identicamente** a classes Kotlin
  compiladas para a JVM. Não existe isenção "porque é Kotlin".

---

## 2. Regras de Consistência Financeira (Não-Negociáveis)

- NUNCA utilize `double` ou `float` para representar valores monetários, em Java ou em Kotlin.
- **`MathContext` é dígitos significativos, não casas decimais.** Usá-lo como limitador de escala corrompe valores
  grandes: `1500000.00.subtract(25.50, new MathContext(6, HALF_EVEN))` devolve `1500000` — o débito desaparece.
    - Soma e subtração de `BigDecimal` são exatas: **não** aplique arredondamento.
    - Divisão e multiplicação com arredondamento usam **escala explícita**:
      `amount.divide(divisor, 6, RoundingMode.HALF_EVEN)`.
    - `MathContext` só quando o domínio pedir precisão por dígitos significativos, com justificativa.
- Em Kotlin, os operadores `+`, `-`, `*`, `/` sobre `BigDecimal` são apenas açúcar sintático para os mesmos métodos
  Java — o operador `/` sem escala é tão perigoso quanto `divide(BigDecimal)` sem argumentos em Java. Prefira a chamada
  explícita com escala e `RoundingMode` em vez do operador, no código de domínio financeiro.
- Precisão intermediária padrão: 6 casas decimais (escala), salvo definição de domínio.
- Encapsule amount + currency em `record`/`data class` imutável com validação fail-fast. Normalize a escala no
  construtor compacto (Java) ou no bloco `init`/construtor secundário validado (Kotlin):
  `equals` de `BigDecimal` compara escala, então `1.50` e `1.5` seriam objetos distintos.
- Mutações concorrentes de saldo/estado financeiro DEVEM usar controle de concorrência explícito:
    - **Padrão**: `@Version` (optimistic locking) + retry com backoff.
    - **O retry fica FORA da transação.** O conflito é detectado no commit, depois que o método transacional retornou;
      retry no mesmo método (ou dentro do mesmo proxy transacional) nunca captura o conflito.
    - Com Spring Data, a exceção observável é `ObjectOptimisticLockingFailureException`
      (`OptimisticLockingFailureException`), não `jakarta.persistence.OptimisticLockException`. Fazer `retryFor` no tipo
      errado é um retry que nunca dispara.
    - **Alternativas aceitas com justificativa explícita**: update atômico condicional
      (`UPDATE ... SET balance = balance - ? WHERE balance >= ?`), `SELECT ... FOR UPDATE`, transação serializable.
    - Update atômico via JPQL não incrementa `@Version` nem sincroniza o contexto de persistência — use
      `flushAutomatically`/`clearAutomatically` e verifique o número de linhas afetadas.
- Lógica financeira NUNCA deve depender de `ConcurrentHashMap.size()` / `isEmpty()` — são estimativas.
- Estruturas concorrentes em memória (`LongAdder`, `AtomicLong`, `ConcurrentHashMap`) NUNCA são fonte de verdade para
  saldo, estoque crítico ou consistência interprocesso.
- Toda operação externa com efeito financeiro considera idempotência, chave idempotente, timeout, retry seguro e
  reconciliação.

---

## 3. CompletableFuture

- Virtual Thread é **mecanismo de execução**; `CompletableFuture` é **API de composição**. Coexistem, não se substituem.
- Toda cadeia observável/externa DEVE ter handler terminal (`.exceptionally()` ou `.handle()`). Estágios internos podem
  propagar para um único handler terminal.
- Todo CF com I/O bloqueante DEVE ter `.orTimeout()` ou `.completeOnTimeout()`. Atenção: o timeout completa o future
  **sem cancelar** o trabalho em curso.
- `supplyAsync` sem executor usa `ForkJoinPool.commonPool` — errado para I/O bloqueante.
- **`thenApplyAsync` (e demais `*Async`) sem executor também usa `commonPool`** — sempre forneça executor explícito em
  estágios que possam bloquear.
- NUNCA crie `Executors.newVirtualThreadPerTaskExecutor()` inline sem fechar. Prefira `@Bean` compartilhado.
- `join()` / `get()` sem timeout no caminho de requisição é proibido.
- Não faça `join()` de um CF dentro de outro estágio assíncrono em pool limitado — starvation/deadlock.
- Em Kotlin, `kotlinx-coroutines-jdk8` oferece `CompletableFuture<T>.await()` (extensão suspend) e
  `CoroutineScope.future { }` para interoperar com APIs Java baseadas em `CompletableFuture`. Use-os apenas na
  fronteira com uma biblioteca Java que só fala `CompletableFuture` — em código coroutine-first, prefira coroutines de
  ponta a ponta.

---

## 4. Spring @Async e Web

- `@Async` requer `@EnableAsync`.
- Métodos `@Async` DEVEM ser públicos e chamados via outro bean (proxy). Self-invocation roda síncrono, sem erro.
- Não envolva serviço síncrono em `@Async` só para "aumentar concorrência": com container em Virtual Threads, o custo
  de thread por requisição já é baixo. Use `@Async` quando houver desacoplamento temporal real.
- O executor de `@Async` DEVE ser configurado explicitamente (pool limitado ou Virtual Threads) com política de
  rejeição, nomeação de threads e métricas.
- `SecurityContextHolder` é ThreadLocal-bound — use `DelegatingSecurityContextExecutorService` ou
  `DelegatingSecurityContextAsyncTaskExecutor`, ou propague explicitamente. O Spring Boot 4.1 trouxe propagação de
  contexto para métodos `@Async`; confirme o comportamento na documentação da versão em uso antes de remover a
  delegação manual.
- **Para controllers `suspend` em Kotlin, o dispatcher padrão do Spring é `Dispatchers.Unconfined`** — o mesmo cuidado
  de propagação de `ThreadLocal` (`SecurityContextHolder`, contexto transacional, MDC) se aplica após o primeiro ponto
  de suspensão. Ver `references/kotlin-coroutines.md` §3 antes de assumir que o contexto sobrevive à troca de thread.
- `INHERITABLETHREADLOCAL` como estratégia de propagação copia o mapa na criação de cada VT — caro em escala.
- NUNCA coloque `@Transactional` em Controllers ou Adapters de infraestrutura.
- Não compartilhe `EntityManager`, sessão Hibernate ou entidades mutáveis entre threads.

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
- JFR com `jdk.VirtualThreadPinned`, `jdk.VirtualThreadSubmitFailed` e `jdk.MonitorEnter`.
- Dumps via `jcmd <PID> Thread.dump_to_file -format=json <FILE>`.
- Teoria ou benchmarks de terceiros NÃO substituem medição no ambiente real.
- **Antipadrões de benchmark**: comparar VTs contra pool subdimensionado; medir só throughput sem p99; ignorar impacto
  em recursos downstream (DB wait time, saturação de pool). Evite *"Tuning by Folklore"* e *"Distracted by Shiny"*
  (Evans et al., Apêndice B).

---

## 7. Observabilidade

- Todo executor DEVE expor métricas via Micrometer/OTel (Evans et al., Cap. 11):
    - **Counter**: eventos monotônicos (tarefas executadas, exceções, rejeições).
    - **Gauge**: estados instantâneos (tamanho de fila, tarefas ativas, permits disponíveis).
    - **Timer**: latências e durações.
    - **DistributionSummary**: distribuições e tamanhos de payload/batch.
- JFR é obrigatório para diagnóstico de pinning e contenção em produção, sempre com `maxsize` além de `maxage`.
- Loggers DEVEM incluir thread name.
- **Monitoramento padrão (Prometheus JVM metrics, VisualVM) mostra platform thread count (carriers)**, constante mesmo
  com milhões de VTs. Use JFR ou métricas customizadas para atividade real de VTs.
- `jdk.VirtualThreadPinned` com threshold de 50ms para alertas (padrão do evento: 20ms);
  `jdk.VirtualThreadSubmitFailed` é crítico (pool de carriers esgotado).

---

## 8. Concorrência Cloud-Native

- **Memória:** stacks de VTs vivem no heap — aumente `-Xmx` após migrar de platform threads.
- **CPU limits em Kubernetes:** defina `limits.cpu` para que a JVM leia o número correto de processadores. Mínimo de
  2 CPUs para evitar fallback para SerialGC.
- **Liveness probes:** baseie em saúde da aplicação (HTTP actuator), NÃO em contagem de platform threads.
- **GraalVM Native Image:** suporta VTs. Class loading dinâmico durante execução pode pinar o carrier — pré-carregue
  classes críticas no startup.
- **File descriptors:** monitorar `ulimit -n` em alta concorrência.
- **Scaling:** VTs melhoram escalabilidade vertical; HPA continua necessário para escala horizontal, isolamento de
  falhas e workloads CPU-bound.

---

## 9. Superfície de Testes de Concorrência

1. **Condições de corrida**: múltiplas threads sobre estado compartilhado.
2. **Timeout e cancelamento**: timeouts respeitados **e** o bloco de fan-out encerrando no orçamento total, com futures
   cancelados (teste que falharia sem `cancel(true)` no `finally`).
3. **Consistência financeira**: débito/crédito concorrente com verificação de saldo final e de escala/arredondamento.
4. **Retry de conflito otimista**: confirmar que o tipo de exceção capturado é o realmente lançado e que o retry ocorre
   fora da transação.
5. **Propagação de contexto**: verificar `SecurityContext` e, para fan-out, a propagação explícita — incluindo teste
   negativo de que `ScopedValue` não atravessa thread criada fora de `StructuredTaskScope`, e, em Kotlin, que o
   contexto lido antes de uma suspensão continua correto depois dela.
6. **Pinning**: JFR durante testes de carga.
7. **Resource exhaustion**: esgotamento de pool JDBC/HTTP com alta concorrência de VTs ou coroutines, verificando
   rejeição e métrica.
8. **Coroutines Kotlin**: `runTest` + `TestDispatcher` (não `runBlocking`) para funções suspend; `Job`/`Deferred` com
   exceções verificadas explicitamente, não apenas assumidas como propagadas.

---

## 10. Arquivos de Referência da Skill

- `SKILL.md`: workflow de revisão, checklist e formato de output.
- `references/virtual-threads.md`: VTs, internals, pinning (JEP 491), cancelamento, limites de recurso, ScopedValue vs
  ThreadLocal, CPU burst, file I/O no Linux, GraalVM, HikariCP, observabilidade.
- `references/spring-async.md`: `@Async`, `@EnableAsync`, SecurityContext, container VT, configuração de executor.
- `references/completable-future.md`: cadeias, timeouts, executores, handlers terminais, `allOf` com resultado.
- `references/classic-issues.md`: races, visibilidade, deadlocks, DCL, locks, ConcurrentHashMap, interrupção.
- `references/financial-consistency.md`: BigDecimal, `@Version`, optimistic locking, Money value object.
- `references/virtual-threads-vs-completable-future.md`: árvore de decisão VT vs CF vs reativo.
- `references/parallelism.md`: paralelismo CPU-bound, executor dimensionado, `parallelStream`.
- `references/cloud-native-concurrency.md`: Kubernetes, GraalVM, JFR em produção, file descriptors.
- `references/kotlin-coroutines.md`: coroutines, Dispatchers, structured concurrency, Mutex, Flow, ponte com Virtual
  Threads/CompletableFuture, integração Spring (`Dispatchers.Unconfined` em controllers suspend), compatibilidade de
  build (Kotlin 2.4+, Gradle 9.7+, Maven 3.9+).
- `scripts/scan-concurrency.sh`: varredura inicial de hotspots em `*.java` e `*.kt`.

---

## 11. Fontes e Referências de Literatura

- **Rahman, A.N.M. Bazlur.** *Modern Concurrency in Java*. O'Reilly Media, 2026.
- **Evans, Benjamin J.; Gough, James; Newland, Chris.** *Optimizing Cloud Native Java*. O'Reilly Media, 2024.
- **JEP 491** (Synchronize Virtual Threads without Pinning), **JEP 506** (Scoped Values), **JEP 505** (Structured
  Concurrency, preview).
- **Kotlin 2.4 release notes** e **kotlinx.coroutines API reference** (kotlinlang.org) — `Dispatchers`, `Mutex`,
  `Flow`, `CoroutineContext`.
