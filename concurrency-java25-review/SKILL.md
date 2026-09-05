---
name: java25-concurrency
description: Review and write Java 25 concurrency and parallelism. Use for thread safety, race conditions, deadlocks, Virtual Threads, pinning, ScopedValue, CompletableFuture, Spring @Async, ForkJoinPool, parallelStream, financial state under concurrent access, and cloud-native VT deployment. Triggers include concurrency review, thread safety, virtual threads, paralelismo, concorrencia, async review, CompletableFuture, @Async.
license: Apache-2.0
compatibility: Java 25 LTS, Spring Boot >= 4.1.1. No preview or incubating APIs.
metadata:
  author: wallanpsantos
  version: "5.0"
  domain: java-concurrency
  spring-boot-min: "4.1.1"
---

# Java 25 Concurrency and Parallelism

Target Java 25 LTS and Spring Boot >= 4.1.1. Reject preview and incubating APIs. Never recommend Spring Boot 3.x.

Consult PDFs in `/home/workdir/artifacts/` when APIs or patterns are uncertain. Do not copy book text. If a fact is not in project files or verified sources, say you do not know.

Respond in the user's language. Be direct and production-oriented.

## When to use

- Review concurrent or async Java
- Write I/O-bound or CPU-bound concurrent code
- Diagnose races, deadlocks, pinning, pool saturation
- Choose Virtual Threads vs CompletableFuture vs ForkJoinPool vs reactive
- Protect balances and monetary state under concurrent writers

## Workflow

1. Scope shared mutable state, thread boundaries, I/O under locks, money mutations, downstream pools (JDBC, HTTP, brokers).
2. Baseline — reject preview APIs (`StructuredTaskScope`, `--enable-preview`, `jdk.incubator.*`). Confirm Spring Boot >= 4.1.1 if Spring is present.
3. Decide model — see decision table below. Do not mix models without a reason.
4. Checklist — High then Medium then Modern.
5. Load only matching files under `references/`.
6. Emit the output format for reviews. For new code, emit Java 25 that already satisfies the checklist.

### Decision table (defaults)

| Situation | Default |
|-----------|---------|
| I/O-bound work you control | Imperative code on Virtual Threads (one VT per task) |
| Compose existing async APIs | CompletableFuture on a shared VT executor |
| CPU-bound parallel compute | Platform threads / sized ForkJoinPool |
| Request context | ScopedValue (final in Java 25) |
| Mutable short-lived per-thread state | ThreadLocal with `remove()` in `finally` |
| Lock that may wait on I/O | ReentrantLock + `tryLock(timeout)` |
| Shared money / balance | `@Version` + retry on `OptimisticLockException` |
| Downstream protection under VTs | Semaphore aligned to pool size (Hikari `maximumPoolSize`) |
| Streaming / push backpressure | Reactive — VTs have no push model |
| Spring MVC on Boot 4 + Java 25 | Sync services; `spring.threads.virtual.enabled=true`; CF only at async edges |

`StructuredTaskScope` remains preview in Java 25 (JEP 505). Reject it. Stable substitute — `Executors.newVirtualThreadPerTaskExecutor()` in try-with-resources, or CF with timeout + terminal handler.

## Generation rules

When writing code:

- Java 25 only. Records, sealed types, and pattern matching when they simplify. No preview flags.
- Name Virtual Threads (`Thread.ofVirtual().name(prefix, start)`). Never pool VTs. Never `setDaemon(false)` or change priority.
- Shared VT executor as a Spring `@Bean(destroyMethod = "shutdown")`. Never create `newVirtualThreadPerTaskExecutor()` inline and leak it.
- Every blocking I/O has timeout, try-with-resources or explicit shutdown, and terminal exception handling.
- Money is `BigDecimal` + explicit `RoundingMode` (prefer scale 6, `HALF_EVEN`). Encapsulate amount + currency in an immutable `record`.
- Do not put `@Transactional` on controllers or infrastructure adapters.
- Do not use `ThreadLocal` as a cache on VT paths. Do not use `InheritableThreadLocal` at VT scale.
- `supplyAsync` / `*Async` that block must pass an explicit executor.
- CPU bursts on VTs must `Thread.yield()` periodically or move to ForkJoinPool.
- Comment only vital design decisions, risks, and invariants.

## Review checklist

### High (likely bugs)

- Check-then-act on shared state without atomicity
- `synchronized` around blocking I/O (contention; prefer ReentrantLock even after JEP 491)
- `synchronized` calling unknown/external code (deadlock)
- DCL without `volatile` (prefer holder idiom)
- Nested `ConcurrentHashMap.compute`
- Financial logic gated on `ConcurrentHashMap.size()` / `isEmpty()`
- `@Async` not public or self-invoked
- Preview APIs
- Money as `double`/`float`; `BigDecimal` multiply/divide without `RoundingMode`
- Balance mutation without concurrency control
- Swallowed `InterruptedException`
- `ThreadLocal` used as cache on VT paths
- Blocking `supplyAsync` / `thenApplyAsync` on `commonPool`
- JNI / FFM on hot VT paths without pinning awareness

### Medium

- Unbounded or unnamed pools; missing rejection policy
- Observable CF chain without `exceptionally` / `handle`
- Blocking CF without `orTimeout` / `completeOnTimeout`
- SecurityContext not propagated across async
- Executor not closed
- `lock.lock()` inside `try` instead of before it
- Missing `tryLock(timeout)` when wait must be bounded
- `InheritableThreadLocal` at VT scale
- No retry policy on `OptimisticLockException`
- No Semaphore / backpressure for JDBC, HTTP, brokers
- Executor without Micrometer instruments (Counter, Gauge, Timer)
- JFR not planned for VT production (`jdk.VirtualThreadPinned`, `jdk.VirtualThreadSubmitFailed`)
- `parallelStream()` used for blocking I/O or tiny collections

### Modern (Java 25)

- VTs for I/O; platform / FJP for CPU
- ScopedValue for request context
- ReentrantLock when the critical section can block
- VT migration only with measured p95/p99 plus downstream metrics
- Container `-Xmx` increased (VT stacks live on the Java heap)
- Container CPU limit >= 2 so JVM does not fall back to SerialGC
- `spring.threads.virtual.enabled: true` considered

## Pinning (do not regress to Java 21 folklore)

JEP 491 (Java 24+) — `synchronized` no longer pins VTs. Still prefer `ReentrantLock` when the lock can wait on I/O because monitors have no timeout and are not interruptible.

What still pins in Java 25 — JNI/native, FFM, class loading during execution, some Linux local file I/O.

Detect with JFR `jdk.VirtualThreadPinned` (alert above 50 ms) and `jdk.VirtualThreadSubmitFailed` (any event is critical).

## Output format (reviews)

```markdown
## Concurrency Review: [file/feature]

### Critical
- [issue] — [location] — [fix]

### Medium
- [issue] — [location] — [fix]

### Modern opportunities
- [suggestion] — [rationale]

### Good practices observed
- [positive finding]
```

Severity — Critical = likely bug, preview API, money without lock/rounding, swallowed interrupt. Medium = risk under load. Modern = safer Java 25 pattern.

For generated code, add a short "Riscos" section covering pinning leftovers, downstream saturation, and cancellation.

## Analysis

Prefer `scripts/scan-concurrency.sh` on a source tree. Then load references that match hits.

## References (load on demand)

| Finding | File |
|---------|------|
| Virtual Threads, pinning, ScopedValue, resources | [references/virtual-threads.md](references/virtual-threads.md) |
| `@Async`, SecurityContext, VT container | [references/spring-async.md](references/spring-async.md) |
| CF chains, timeouts, executors | [references/completable-future.md](references/completable-future.md) |
| Races, visibility, deadlocks, locks, CHM | [references/classic-issues.md](references/classic-issues.md) |
| Money, `@Version`, optimistic lock | [references/financial-consistency.md](references/financial-consistency.md) |
| VT vs CF vs reactive vs FJP | [references/virtual-threads-vs-completable-future.md](references/virtual-threads-vs-completable-future.md) |
| CPU parallelism, FJP, parallelStream | [references/parallelism.md](references/parallelism.md) |
| Kubernetes, GraalVM, JFR, file descriptors | [references/cloud-native-concurrency.md](references/cloud-native-concurrency.md) |

## Project constraints

- Java 25 LTS. Spring Boot >= 4.1.1. PostgreSQL 18.4. Kafka / RabbitMQ.
- Knowledge base PDFs live in `/home/workdir/artifacts/` (Hook, Tudose, Rahman, Fowler, Martin, Hunt/Thomas, Xu, Shvets).
- Persona and negative prompts — project `AGENTS.md`.
