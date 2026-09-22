---
name: java-kotlin-concurrency
description: Review and write Java 25 and Kotlin 2.4+ (JVM target) concurrency and parallelism. Use for thread safety, race conditions, deadlocks, Virtual Threads, pinning, ScopedValue, CompletableFuture, Spring @Async, ForkJoinPool, parallelStream, Kotlin coroutines, suspend functions, structured concurrency, Dispatchers, Flow, Mutex, financial state under concurrent access, and cloud-native deployment. Triggers include concurrency review, thread safety, virtual threads, coroutines, suspend, paralelismo, concorrencia, async review, CompletableFuture, @Async. Server-side JVM only — not Android, Kotlin Multiplatform, Kotlin/Native, Kotlin/JS, Kotlin/Wasm, or mobile/frontend code.
license: Apache-2.0
compatibility: Java 25 LTS; Kotlin 2.4+ compiled to the JVM target only; Spring Boot >= 4.1.1 (Spring Framework >= 7.0.8, Spring Security >= 7.1, Jackson 3 as default JSON library); Maven >= 3.9 or Gradle >= 9.7 (Groovy or Kotlin DSL). No preview or incubating APIs — JDK preview features or Kotlin experimental/delicate coroutine APIs.
metadata:
  author: wallanpsantos
  version: "6.0"
  domain: jvm-concurrency
  java-min: "25"
  kotlin-min: "2.4"
  spring-boot-min: "4.1.1"
  spring-framework-min: "7.0.8"
  spring-security-min: "7.1"
  jackson-min: "3.0"
  maven-min: "3.9"
  gradle-min: "9.7"
---

# Java 25 & Kotlin 2.4+ (JVM) — Concurrency and Parallelism

Target Java 25 LTS and Kotlin 2.4+ compiled to the **JVM target only**. When Spring is present: Spring Boot >= 4.1.1
on Spring Framework >= 7.0.8 (Boot 4.1 requires Framework 7.0.8 or later), Spring Security >= 7.1, Jackson 3 as the
default JSON library (Jackson 2 may coexist during migration but is not the recommendation for new code). Build
tooling: Maven >= 3.9 or Gradle >= 9.7, Groovy or Kotlin DSL (`build.gradle.kts`). Reject preview and incubating JDK
APIs, and Kotlin experimental/delicate coroutine APIs used without explicit justification. Never recommend Spring Boot
3.x.

Respond in the user's language. Be direct and production-oriented. If a fact is not in these reference files or in a
verified source, say you do not know instead of guessing.

## Out of scope

This skill targets **server-side JVM workloads only** (Java and Kotlin compiled to the JVM target). Do not produce
platform-specific rules or findings for:

- Android (`Dispatchers.Main`, lifecycle-scoped coroutines, WorkManager, Android-specific threading)
- Kotlin Multiplatform (KMP) — `expect`/`actual`, shared source sets, multiplatform coroutine concerns
- Kotlin/Native, Kotlin/JS, Kotlin/Wasm — non-JVM compiler backends and their concurrency/runtime models
- Mobile and frontend applications (SPA, browser) — UI-thread dispatchers, event loops, DOM/rendering concerns

If the code under review targets one of the platforms above, say so explicitly and stop — do not adapt the JVM rules
below to that platform, and do not generate findings framed as if they applied there.

## When to use

- Review concurrent or async Java or Kotlin (JVM target)
- Write I/O-bound or CPU-bound concurrent code, imperative or coroutine-based
- Diagnose races, deadlocks, pinning, pool saturation, or coroutine cancellation/dispatcher misuse
- Choose Virtual Threads vs Kotlin coroutines vs CompletableFuture vs ForkJoinPool vs reactive
- Protect balances and monetary state under concurrent writers, in Java or Kotlin

## Workflow

1. Identify the language (s) in scope (Java, Kotlin, or both) and confirm the runtime target is server-side JVM — see
   "Out of scope" above.
2. Scope shared mutable state, thread/coroutine boundaries, I/O under locks, money mutations, downstream pools (JDBC,
   HTTP, brokers).
3. Baseline — reject preview APIs (`StructuredTaskScope`, `--enable-preview`, `jdk.incubator.*`, `jdk.internal.*`) and
   Kotlin experimental/delicate coroutine markers (`@ExperimentalCoroutinesApi`, `@DelicateCoroutinesApi`) used without
   justification. Confirm Spring Boot >= 4.1.1 if Spring is present, and Kotlin >= 2.4 if Kotlin sources are present.
   When build files are visible, confirm Gradle >= 9.7 / Maven >= 3.9.
4. Decide the execution model — see decision table. Do not mix models without a reason. In mixed Java/Kotlin
   codebases, treat every call boundary explicitly: blocking Java called from a coroutine needs a dispatcher switch
   (`references/kotlin-coroutines.md` §2, §4); a `suspend` function is not directly callable from Java.
5. Run the review checklist — High, then Medium, then Modern.
6. Load only the matching files under `references/`.
7. Emit the review format (see "Output format").

### Decision table (defaults)

| Situation                                                                                          | Default                                                                                                                                 |
|----------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------|
| I/O-bound work you control (Java or idiomatic Kotlin)                                              | Imperative code on Virtual Threads (one VT per task)                                                                                    |
| Compose existing async APIs (Java)                                                                 | CompletableFuture over a shared VT executor                                                                                             |
| Compose many independent suspend/reactive APIs (Kotlin, WebFlux/R2DBC or coroutine-first codebase) | Kotlin coroutines (`suspend`, `coroutineScope`) with an explicit `CoroutineDispatcher`                                                  |
| Kotlin structured fan-out you own                                                                  | `coroutineScope` / `supervisorScope` — stable in Kotlin, unrelated to Java's preview `StructuredTaskScope`                              |
| Blocking Java/JDBC call from inside a coroutine                                                    | `withContext(Dispatchers.IO)`, or a Virtual-Thread-backed dispatcher — never block the coroutine's current dispatcher directly          |
| Mutual exclusion inside a coroutine                                                                | `Mutex` (suspending) — never `synchronized` / `ReentrantLock` around a suspension point                                                 |
| CPU-bound parallel compute                                                                         | Dedicated, sized platform-thread executor (never `commonPool` for heavy work; never `Dispatchers.IO` in Kotlin)                         |
| CPU burst inside a VT path or a coroutine                                                          | Move the burst to the CPU executor / `Dispatchers.Default`. `Thread.yield()` is a documented stopgap only                               |
| Request context, same dynamic scope (Java)                                                         | `ScopedValue` (final in Java 25)                                                                                                        |
| Request context across coroutine dispatcher switches (Kotlin)                                      | `CoroutineContext` element (`ThreadContextElement`) — read `ThreadLocal`-bound state *before* the first suspension point, not after     |
| Request context across forked threads (Java)                                                       | Explicit propagation (parameter / context `record`) — see note below                                                                    |
| Mutable short-lived per-thread state                                                               | `ThreadLocal` with `remove()` in `finally`                                                                                              |
| Lock that may wait on I/O                                                                          | `ReentrantLock` + `tryLock(timeout)`                                                                                                    |
| Shared money / balance                                                                             | `@Version` + retry **outside** the transaction (same rule in Java and Kotlin)                                                           |
| Downstream protection under VTs or coroutines                                                      | `Semaphore` (Java) / `kotlinx.coroutines.sync.Semaphore` (Kotlin) on the scarce resource, permits <= pool size, timeout-bounded acquire |
| Streaming / push backpressure                                                                      | Reactive, or Kotlin `Flow` with `buffer()`/`conflate()` — VTs have no push model                                                        |
| Spring MVC on Boot 4 + Java 25, blocking style                                                     | Sync services; `spring.threads.virtual.enabled=true`; CF only at async edges; plain blocking Kotlin needs no coroutines here            |

**Preview boundary.** `StructuredTaskScope` was still preview in Java 25 (JEP 505) and remains in preview after it.
Reject it while that holds; revisit when it goes final. Stable substitute —
`Executors.newVirtualThreadPerTaskExecutor()`
in try-with-resources **with explicit cancellation** (see `references/virtual-threads.md` §3.1), or CF with timeout plus
a terminal handler. **Kotlin's `coroutineScope`/`supervisorScope` are not affected by this ban** — they are a different,
already-stable mechanism (`references/kotlin-coroutines.md` §5), not a Kotlin wrapper around `StructuredTaskScope`.

**Consequence of that boundary (do not forget it).** `ScopedValue` bindings are inherited only by threads created by
`StructuredTaskScope`. Legacy thread management (plain `Thread.ofVirtual().start()`, `ExecutorService`, `ForkJoinPool`)
does **not** inherit them. Under this baseline, `ScopedValue` is a same-thread mechanism; fan-out context must be passed
explicitly. Kotlin coroutines have their own, unrelated context-propagation story via `CoroutineContext` — see
`references/kotlin-coroutines.md` §3 and §5 for why a `ThreadLocal` read before a coroutine suspends may not be valid
after it resumes.

## Generation rules

When writing code:

- Java 25 only, or Kotlin 2.4+ compiled to the JVM target. Records/data classes, sealed types, and pattern matching
  when they simplify. No preview flags, no `jdk.internal.*`, no unjustified Kotlin experimental/delicate coroutine
  APIs.
- Name Virtual Threads (`Thread.ofVirtual().name(prefix, 0)`). Never pool VTs. Never `setDaemon(false)` or change
  priority.
- Shared VT executor as a Spring `@Bean(destroyMethod = "shutdown")`. Never create `newVirtualThreadPerTaskExecutor()`
  inline and leak it. In Kotlin, the same rule applies to a shared `CoroutineScope` or `ExecutorCoroutineDispatcher` —
  see `references/kotlin-coroutines.md` §4–§5.
- Never use `GlobalScope.launch` / `GlobalScope.async` in Kotlin application code — every coroutine launches inside a
  structured, component-scoped `CoroutineScope`, the coroutine equivalent of "never leak an unmanaged executor".
- Any fan-out inside try-with-resources cancels outstanding futures in `finally`; `close()` waits for termination and
  will otherwise outlive the per-task timeout.
- Every blocking I/O has a client-level timeout, try-with-resources or explicit shutdown, and terminal exception
  handling.
- CPU-bound work goes to a sized platform executor with a bounded queue, a rejection policy and metrics — never
  `Dispatchers.IO` in Kotlin, which is sized for blocking I/O, not compute.
- Money is `BigDecimal` in both languages. Add/subtract without rounding; divide with explicit **scale** +
  `RoundingMode.HALF_EVEN`. `MathContext` is significant digits, not decimal places — do not use it as a scale
  limiter. In Kotlin, do not rely on the `/` operator for money division — it maps to `divide(BigDecimal)` with no
  scale/rounding, the same trap as unscaled `divide()` in Java. Encapsulate amount + currency in an immutable
  `record`/`data class`.
- Do not put `@Transactional` on controllers or infrastructure adapters. Optimistic-lock retry wraps the transaction
  from outside. For a Kotlin `suspend` transactional method, confirm — for the exact Spring version in use — how the
  connection binding survives a dispatcher switch; do not assume it behaves like a blocking `@Transactional` method.
- Do not use `ThreadLocal` as a cache on VT paths. Do not use `InheritableThreadLocal` at VT scale.
- `supplyAsync` / `*Async` that block must pass an explicit executor.
- A shared Jackson 3 `JsonMapper` (built once via `JsonMapper.builder()...build()`) or a Jackson 2 `ObjectMapper` is
  immutable after construction and thread-safe — never reconfigure it per request or per thread.
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
- Preview, incubating, or `jdk.internal.*` APIs; unjustified Kotlin `@ExperimentalCoroutinesApi` /
  `@DelicateCoroutinesApi`
- Money as `double`/`float`; `BigDecimal` divide without scale + `RoundingMode` (Java or Kotlin's `/` operator);
  `MathContext` used as a scale limiter
- Balance mutation without concurrency control; optimistic-lock retry placed inside the transaction
- Swallowed `InterruptedException`
- `ThreadLocal` used as cache on VT paths
- `ScopedValue` expected to propagate into threads not forked by `StructuredTaskScope`
- Blocking `supplyAsync` / `thenApplyAsync` on `commonPool`
- JNI / FFM on hot VT paths without pinning awareness
- `GlobalScope.launch` / `GlobalScope.async` in Kotlin application code
- `runBlocking` invoked on a request-handling thread (Virtual Thread or event loop) or inside another coroutine
- Blocking call inside a Kotlin coroutine with no dispatcher switch (`withContext(Dispatchers.IO)` or equivalent)

### Medium (risk under load)

- Fan-out in try-with-resources without cancellation in `finally` (`close()` blocks past the timeout)
- Unbounded or unnamed pools; missing rejection policy
- `ForkJoinPool` or VT executor created per call instead of a managed singleton
- Observable CF chain without `exceptionally` / `handle`
- Blocking CF without `orTimeout` / `completeOnTimeout`
- `Semaphore.acquire()` without timeout or rejection metric; permits above `maximumPoolSize`; permit held across work
  that does not use the scarce resource
- SecurityContext not propagated across async, or across a coroutine's first suspension point
- Executor not closed
- `lock.lock()` inside `try` instead of before it
- Missing `tryLock(timeout)` when wait must be bounded
- `InheritableThreadLocal` at VT scale
- No retry policy on optimistic-lock failures, or retry matching the wrong exception type
- Executor without Micrometer instruments (Counter, Gauge, Timer)
- JFR not planned for VT production (`jdk.VirtualThreadPinned`, `jdk.VirtualThreadSubmitFailed`, `jdk.MonitorEnter`)
- `parallelStream()` used for blocking I/O or tiny collections
- Carrier tuning (`jdk.virtualThreadScheduler.*`) applied without measurement
- `Dispatchers.Default` used for blocking work, or `Dispatchers.IO` used for CPU-bound work
- `synchronized`/`ReentrantLock` held across a coroutine suspension point instead of `Mutex`
- Coroutine exception swallowed (no `CoroutineExceptionHandler`, `launch` result never inspected)
- Kotlin `Flow` collected with no backpressure handling against a slow consumer
- Kotlin module's JVM bytecode target inconsistent with the project's Java 25 baseline

### Modern (Java 25 / Kotlin 2.4+)

- VTs for I/O; sized platform executor for CPU; Kotlin coroutines for composing many independent suspend/reactive APIs
- `ScopedValue` for same-scope Java request context; `CoroutineContext` element for Kotlin context across dispatcher
  switches; explicit `record`/`data class` for cross-thread context in either language
- `ReentrantLock` when the critical section can block; `Mutex` when it can suspend
- `Future.state()` / `resultNow()` / `exceptionNow()` instead of `getNow(null)` after `allOf`
- VT migration only with measured p95/p99 plus downstream metrics
- Container `-Xmx` increased (VT stacks live on the Java heap)
- Container CPU limit >= 2 so the JVM does not fall back to SerialGC
- `spring.threads.virtual.enabled: true` considered
- `Executors.newVirtualThreadPerTaskExecutor().asCoroutineDispatcher()` as the deliberate bridge when coroutine code
  must call blocking VT-friendly work, closed like any other executor

## Pinning (do not regress to Java 21 folklore)

JEP 491 (Java 24+) — `synchronized` no longer pins VTs. Still prefer `ReentrantLock` when the lock can wait on I/O:
monitors have no timeout and are not interruptible.

What still pins in Java 25 — JNI/native, FFM, class loading during execution, some Linux local file I/O. This applies
identically to Kotlin classes compiled to the JVM target — pinning is a JVM-level phenomenon, not a language one.

`-Djdk.tracePinnedThreads` was **removed by JEP 491 in JDK 24** — setting it has no effect. Detect with JFR
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

### Oportunidades Java 25 / Kotlin 2.4+

- [melhoria] — [justificativa técnica]

### Boas práticas observadas

- [achado positivo]

### Riscos operacionais

- [pinning residual, saturação downstream, timeout, cancelamento, memória, observabilidade, consistência ou dispatcher/coroutine errado]
```

Severity — **Crítico**: race condition, deadlock, preview/internal/experimental API, lost interrupt or uncancelled
coroutine, blocking I/O on `commonPool` or on a coroutine dispatcher not meant for it, money as `double`/`float` or
wrong rounding (Java or Kotlin), missing concurrency control on balance, resource without timeout, `GlobalScope`,
`runBlocking` on a live request path. **Risco sob carga**: unbounded pool, no backpressure (executor or `Flow`),
unbounded lock/`Mutex` wait, executor not shut down, no metrics, missing cancellation, inadequate `ThreadLocal` on VTs
or across a coroutine suspension. **Oportunidade**: safer Java 25 or Kotlin 2.4+ pattern.

For generated code, add a short "Riscos" section covering pinning leftovers, downstream saturation, and cancellation.

## Analysis

Run `scripts/scan-concurrency.sh` on a source tree, then load the references that match the hits. The script scans
both `*.java` and `*.kt` sources.

## References (load on demand)

| Finding                                                                                                 | File                                                  |
|---------------------------------------------------------------------------------------------------------|-------------------------------------------------------|
| Virtual Threads, pinning, ScopedValue, cancellation, resource limits                                    | `references/virtual-threads.md`                       |
| `@Async`, SecurityContext, VT container                                                                 | `references/spring-async.md`                          |
| CF chains, timeouts, executors                                                                          | `references/completable-future.md`                    |
| Races, visibility, deadlocks, locks, CHM                                                                | `references/classic-issues.md`                        |
| Money, `@Version`, optimistic lock                                                                      | `references/financial-consistency.md`                 |
| VT vs CF vs reactive vs FJP                                                                             | `references/virtual-threads-vs-completable-future.md` |
| CPU parallelism, sized executors, parallelStream                                                        | `references/parallelism.md`                           |
| Kubernetes, GraalVM, JFR, file descriptors                                                              | `references/cloud-native-concurrency.md`              |
| Kotlin coroutines, Dispatchers, structured concurrency, Mutex, Flow, VT/CF interop, build compatibility | `references/kotlin-coroutines.md`                     |

Classic JVM-level concerns — shared-mutable-state races, visibility, deadlocks, Virtual Thread internals and pinning,
CPU-bound parallelism internals, and Kubernetes/cloud-native configuration — apply identically to Kotlin classes on the
JVM. Those reference files need no Kotlin-specific variant; only what is genuinely language-specific to Kotlin
(coroutines, `suspend`, `Dispatchers`, `Flow`, the Kotlin/Java interop boundary) lives in `kotlin-coroutines.md`.

## Project constraints

- Java 25 LTS. Kotlin 2.4+ (JVM target only — see "Out of scope"). Spring Boot >= 4.1.1 on Spring Framework >= 7.0.8,
  Spring Security >= 7.1, Jackson 3. Maven >= 3.9 or Gradle >= 9.7 (Groovy or Kotlin DSL). PostgreSQL 18.4. Kafka /
  RabbitMQ.
- Persona, baseline and negative prompts — project `AGENTS.md`.
