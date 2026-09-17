# CHANGELOG — java25-concurrency

## 5.1.0 — correções de revisão

Baseline unificado em todos os arquivos: **Java 25 LTS, Spring Boot >= 4.1.1, Spring Framework >= 7.0.8**
(Boot 4.1 exige Framework 7.0.8+). Layout ajustado para `SKILL.md` + `references/` + `scripts/`.

### Crítico

| Arquivo | Ajuste |
|---|---|
| `references/virtual-threads.md` §8 | Exemplo de `ScopedValue` herdado por `Thread.ofVirtual().start()` **removido**: a binding só é herdada por threads criadas por `StructuredTaskScope`. Substituído por propagação explícita de `record` de contexto. |
| `AGENTS.md` §1.4, `SKILL.md` | Regra nova: sob este baseline `ScopedValue` é mecanismo *same-thread*; fan-out propaga contexto por parâmetro. |
| `references/financial-consistency.md` | `MathContext(6)` em soma/subtração removido — é dígito significativo, não casa decimal (`1500000.00 - 25.50` virava `1500000`). Soma/subtração sem arredondamento; divisão com escala explícita. |
| `references/financial-consistency.md` | `@Retryable` movido para fora da transação (bean de fachada) e tipo corrigido para `OptimisticLockingFailureException`. Exceções de negócio fora do conjunto de retry. |
| `references/classic-issues.md` §5 | `@jdk.internal.vm.annotation.Contended` removido da recomendação (API interna + flags), substituído por redesenho/padding manual após medição. |
| `references/completable-future.md` §3 | `futures.stream().map(Future::join)` removido (não compila). Substituído por `Future.state()` / `resultNow()` / `exceptionNow()`. |
| `AGENTS.md`, `references/virtual-threads.md`, `references/cloud-native-concurrency.md` | `-Djdk.tracePinnedThreads` marcado como **removido pelo JEP 491 no JDK 24** (sem efeito), inclusive para pinning nativo. Diagnóstico só por JFR. |

### Risco sob carga

| Arquivo | Ajuste |
|---|---|
| `references/virtual-threads.md` §3.1 (nova) | Padrão de fan-out com orçamento total e `cancel(true)` no `finally`: `ExecutorService.close()` espera a terminação e anula o efeito do `get(timeout)`. |
| `references/virtual-threads-vs-completable-future.md`, `references/parallelism.md` | Mesmo padrão aplicado aos exemplos de fan-out. |
| `SKILL.md`, `AGENTS.md`, `references/parallelism.md`, `references/virtual-threads.md` §10 | `Thread.yield()` rebaixado a medida excepcional e documentada. Padrão passa a ser executor de CPU dedicado, dimensionado, com fila limitada, rejeição explícita e métricas. |
| `references/parallelism.md` §2.1 | Alerta novo: `commonPool` tem parallelism `availableProcessors() - 1`; em container de 1 CPU vale 0 e a tarefa roda na thread chamadora — o "offload" é no-op. |
| `references/parallelism.md` §2–3 | `ForkJoinPool` criado por chamada removido; o truque de submeter `parallelStream()` dentro de um FJP próprio foi eliminado (contradizia o próprio material). |
| `references/virtual-threads.md` §6.1 | `Semaphore` padronizado: recurso escasso real, um por dependência, permits `<=` `maximumPoolSize`, `tryAcquire(timeout)` + counter de rejeição + gauge de permits, permit segurado só na operação que usa o recurso. |
| `references/cloud-native-concurrency.md` §2 | Tuning de `jdk.virtualThreadScheduler.*` condicionado a medição e sintoma concreto. |
| `references/financial-consistency.md` §3 | `@Modifying` com `flushAutomatically`/`clearAutomatically`, incremento explícito de `@Version` e checagem de linhas afetadas. |
| Todos | `jdk.MonitorEnter` incluído no conjunto padrão de eventos JFR. |

### Estrutura

| Arquivo | Ajuste |
|---|---|
| `SKILL.md` | Formato de saída deixa de ser redefinido: passa a ser propriedade da instrução de projeto, com fallback em português (5 seções) para uso standalone. |
| `SKILL.md` | Referências apontam para `references/` e `scripts/` — caminhos agora existem. Removida a menção a `/home/workdir/artifacts/`. |
| `scripts/scan-concurrency.sh` | Novos padrões: `jdk.internal`, `tracePinnedThreads`, `commonPool`, `MathContext`, `Future::join`, `acquire()` sem timeout, `newVirtualThreadPerTaskExecutor` sem cancelamento, I/O de arquivo local. |
| `AGENTS.md` §1.1 | Proibição de `StructuredTaskScope` passa a ser condicional ("enquanto preview"), com gatilho de reavaliação. |
| `AGENTS.md` §9 | Casos de teste novos: bloco de fan-out encerrando no orçamento total; teste negativo de `ScopedValue` cruzando thread; tipo correto de exceção no retry otimista. |
| `references/spring-async.md` | Nota para verificar a propagação de contexto assíncrono do Spring Boot 4.1 antes de remover `DelegatingSecurityContext*`; regra de não usar `@Async` como multiplicador de concorrência. |
