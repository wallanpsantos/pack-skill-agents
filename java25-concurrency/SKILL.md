---
name: java25-concurrency
description: Review and write Java 25 concurrency and parallelism. Use for thread safety, race conditions, deadlocks, Virtual Threads, pinning, ScopedValue, CompletableFuture, Spring @Async, ForkJoinPool, parallelStream, financial state under concurrent access, and cloud-native VT deployment. Triggers include concurrency review, thread safety, virtual threads, paralelismo, concorrencia, async review, CompletableFuture, @Async.
license: Apache-2.0
compatibility: Java 25 LTS, Spring Boot >= 4.1.1, Spring Framework >= 7.0.8. No preview or incubating APIs.
metadata:
  author: wallanpsantos
  version: "5.1"
  domain: java-concurrency
  java-min: "25"
  spring-boot-min: "4.1.1"
  spring-framework-min: "7.0.8"
---

# Java 25 Concurrency and Parallelism

Target Java 25 LTS. When Spring is present: Spring Boot >= 4.1.1 on Spring Framework >= 7.0.8 (Boot 4.1 requires
Framework 7.0.8 or later). Reject preview and incubating APIs. Never recommend Spring Boot 3.x.

Respond in the user's language. Be direct and production-oriented. If a fact is not in these reference files or in a
verified source, say you do not know instead of guessing.

## When to use

- Review concurrent or async Java
- Write I/O-bound or CPU-bound concurrent code
- Diagnose races, deadlocks, pinning, pool saturation
- Choose Virtual Threads vs CompletableFuture vs ForkJoinPool vs reactive
- Protect balances and monetary state under concurrent writers

## Workflow

1. Scope shared mutable state, thread boundaries, I/O under locks, money mutations, downstream pools (JDBC, HTTP,
   brokers).
2. Baseline — reject preview APIs (`StructuredTaskScope`, `--enable-preview`, `jdk.incubator.*`, `jdk.internal.*`).
   Confirm Spring Boot >= 4.1.1 if Spring is present.
3. Decide the execution model — see decision table. Do not mix models without a reason.
4. Run the review checklist — High, then Medium, then Modern.
5. Load only the matching files under `references/`.
6. Emit the review format (see "Output format").

### Decision table (defaults)

| Situation | Default |
|-----------|---------|
| I/O-bound work you control | Imperative code on Virtual Threads (one VT per task) |
| Compose existing async APIs | CompletableFuture over a shared VT executor |
| CPU-bound parallel compute | Dedicated, sized platform-thread executor (never `commonPool` for heavy work) |
| CPU burst inside a VT path | Move the burst to the CPU executor. `Thread.yield()` is a documented stopgap only |
| Request context, same dynamic scope | `ScopedValue` (final in Java 25) |
| Request context across forked threads | Explicit propagation (parameter / context `record`) — see note below |
| Mutable short-lived per-thread state | `ThreadLocal` with `remove()` in `finally` |
| Lock that may wait on I/O | `ReentrantLock` + `tryLock(timeout)` |
| Shared money / balance | `@Version` + retry **outside** the transaction |
| Downstream protection under VTs | `Semaphore` on the scarce resource, permits <= pool size, `tryAcquire(timeout)` |
| Streaming / push backpressure | Reactive — VTs have no push model |
| Spring MVC on Boot 4 + Java 25 | Sync services; `spring.threads.virtual.enabled=true`; CF only at async edges |

**Preview boundary.** `StructuredTaskScope` was still preview in Java 25 (JEP 505) and remains in preview after it.
Reject it while that holds; revisit when it goes final. Stable substitute — `Executors.newVirtualThreadPerTaskExecutor()`
in try-with-resources **with explicit cancellation** (see `references/virtual-threads.md` §3.1), or CF with timeout plus
a terminal handler.

**Consequence of that boundary (do not forget it).** `ScopedValue` bindings are inherited only by threads created by
`StructuredTaskScope`. Legacy thread management (plain `Thread.ofVirtual().start()`, `ExecutorService`, `ForkJoinPool`)
does **not** inherit them. Under this baseline, `ScopedValue` is a same-thread mechanism; fan-out context must be passed
explicitly.

## Generation rules

When writing code:

- Java 25 only. Records, sealed types, and pattern matching when they simplify. No preview flags, no `jdk.internal.*`.
- Name Virtual Threads (`Thread.ofVirtual().name(prefix, 0)`). Never pool VTs. Never `setDaemon(false)` or change
  priority.
- Shared VT executor as a Spring `@Bean(destroyMethod = "shutdown")`. Never create `newVirtualThreadPerTaskExecutor()`
  inline and leak it.
- Any fan-out inside try-with-resources cancels outstanding futures in `finally`; `close()` waits for termination and
  will otherwise outlive the per-task timeout.
- Every blocking I/O has a client-level timeout, try-with-resources or explicit shutdown, and terminal exception
  handling.
- CPU-bound work goes to a sized platform executor with a bounded queue, a rejection policy and metrics.
- Money is `BigDecimal`. Add/subtract without rounding; divide with explicit **scale** + `RoundingMode.HALF_EVEN`.
  `MathContext` is significant digits, not decimal places — do not use it as a scale limiter. Encapsulate amount +
  currency in an immutable `record`.
- Do not put `@Transactional` on controllers or infrastructure adapters. Optimistic-lock retry wraps the transaction
  from outside.
- Do not use `ThreadLocal` as a cache on VT paths. Do not use `InheritableThreadLocal` at VT scale.
- `supplyAsync` / `*Async` that block must pass an explicit executor.
- Comment only vital design decisions, risks, and invariants.

## Review checklist

### High (likely bugs)

- Check-then-act on shared state without atomicity
- `synchronized` around blocking I/O (contention; prefer `ReentrantLock` even after JEP 491)
- `synchronized` calling unknown/external code (deadlock)
- DCL without `volatile` (prefer holder idiom)
- Nested `ConcurrentHashMap.compute`
- Financial logic gated on `ConcurrentHashMap.size()` / `isEmpty()`
- `@Async` not public or self-invoked
- Preview, incubating or `jdk.internal.*` APIs
- Money as `double`/`float`; `BigDecimal` divide without scale + `RoundingMode`; `MathContext` used as a scale limiter
- Balance mutation without concurrency control; optimistic-lock retry placed inside the transaction
- Swallowed `InterruptedException`
- `ThreadLocal` used as cache on VT paths
- `ScopedValue` expected to propagate into threads not forked by `StructuredTaskScope`
- Blocking `supplyAsync` / `thenApplyAsync` on `commonPool`
- JNI / FFM on hot VT paths without pinning awareness

### Medium (risk under load)

- Fan-out in try-with-resources without cancellation in `finally` (`close()` blocks past the timeout)
- Unbounded or unnamed pools; missing rejection policy
- `ForkJoinPool` or VT executor created per call instead of a managed singleton
- Observable CF chain without `exceptionally` / `handle`
- Blocking CF without `orTimeout` / `completeOnTimeout`
- `Semaphore.acquire()` without timeout or rejection metric; permits above `maximumPoolSize`; permit held across work
  that does not use the scarce resource
- SecurityContext not propagated across async
- Executor not closed
- `lock.lock()` inside `try` instead of before it
- Missing `tryLock(timeout)` when wait must be bounded
- `InheritableThreadLocal` at VT scale
- No retry policy on optimistic-lock failures, or retry matching the wrong exception type
- Executor without Micrometer instruments (Counter, Gauge, Timer)
- JFR not planned for VT production (`jdk.VirtualThreadPinned`, `jdk.VirtualThreadSubmitFailed`, `jdk.MonitorEnter`)
- `parallelStream()` used for blocking I/O or tiny collections
- Carrier tuning (`jdk.virtualThreadScheduler.*`) applied without measurement

### Modern (Java 25)

- VTs for I/O; sized platform executor for CPU
- `ScopedValue` for same-scope request context; explicit `record` for cross-thread context
- `ReentrantLock` when the critical section can block
- `Future.state()` / `resultNow()` / `exceptionNow()` instead of `getNow(null)` after `allOf`
- VT migration only with measured p95/p99 plus downstream metrics
- Container `-Xmx` increased (VT stacks live on the Java heap)
- Container CPU limit >= 2 so the JVM does not fall back to SerialGC
- `spring.threads.virtual.enabled: true` considered

## Pinning (do not regress to Java 21 folklore)

JEP 491 (Java 24+) — `synchronized` no longer pins VTs. Still prefer `ReentrantLock` when the lock can wait on I/O:
monitors have no timeout and are not interruptible.

What still pins in Java 25 — JNI/native, FFM, class loading during execution, some Linux local file I/O.

`-Djdk.tracePinnedThreads` was **removed by JEP 491 in JDK 24**; setting it has no effect. Detect with JFR
`jdk.VirtualThreadPinned` (alert above 50 ms; default threshold 20 ms) and `jdk.VirtualThreadSubmitFailed` (any event is
critical). Watch `jdk.MonitorEnter` for monitor contention.

## Output format (reviews)

The review format is owned by the project instruction (`AGENTS.md` / project prompt). Follow it verbatim when present.
When this skill runs standalone, use:

```markdown
## Revisão de Concorrência: [arquivo ou componente]

### Crítico
- [problema] — [localização] — [impacto] — [correção objetiva]

### Risco sob carga
- [problema] — [localização] — [cenário de falha] — [correção objetiva]

### Oportunidades Java 25
- [melhoria] — [justificativa técnica]

### Boas práticas observadas
- [achado positivo]

### Riscos operacionais
- [pinning residual, saturação downstream, timeout, cancelamento, memória, observabilidade ou consistência]
```

Severity — **Crítico**: race condition, deadlock, preview/internal API, lost interrupt, blocking I/O on `commonPool`,
money as `double`/`float` or wrong rounding, missing concurrency control on balance, resource without timeout.
**Risco sob carga**: unbounded pool, no backpressure, unbounded lock wait, executor without shutdown, no metrics,
missing cancellation, inadequate `ThreadLocal` on VTs. **Oportunidade**: safer Java 25 pattern.

For generated code, add a short "Riscos" section covering pinning leftovers, downstream saturation, and cancellation.

## Analysis

Run `scripts/scan-concurrency.sh` on a source tree, then load the references that match the hits.

## References (load on demand)

| Finding | File |
|---------|------|
| Virtual Threads, pinning, ScopedValue, cancellation, resource limits | `references/virtual-threads.md` |
| `@Async`, SecurityContext, VT container | `references/spring-async.md` |
| CF chains, timeouts, executors | `references/completable-future.md` |
| Races, visibility, deadlocks, locks, CHM | `references/classic-issues.md` |
| Money, `@Version`, optimistic lock | `references/financial-consistency.md` |
| VT vs CF vs reactive vs FJP | `references/virtual-threads-vs-completable-future.md` |
| CPU parallelism, sized executors, parallelStream | `references/parallelism.md` |
| Kubernetes, GraalVM, JFR, file descriptors | `references/cloud-native-concurrency.md` |

## Project constraints

- Java 25 LTS. Spring Boot >= 4.1.1 on Spring Framework >= 7.0.8. PostgreSQL 18.4. Kafka / RabbitMQ.
- Persona, baseline and negative prompts — project `AGENTS.md`.
