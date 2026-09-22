# Kotlin Coroutines & Structured Concurrency (JVM target)

Load when reviewing or writing Kotlin concurrency: `suspend` functions, `CoroutineScope`, `Dispatchers`,
`Job`/`Deferred`, `Flow`, `Mutex`/`Channel`/`Semaphore`, or the boundary between coroutines and Java Virtual
Threads/CompletableFuture. **JVM target only** — see "Out of scope" in `SKILL.md` for Android, Kotlin Multiplatform,
Kotlin/Native, Kotlin/JS, Kotlin/Wasm, and mobile/frontend code.

Baseline: Kotlin 2.4+ compiled to a Java 25 JVM bytecode target, `kotlinx-coroutines-core` (JVM artifact), Spring Boot
> = 4.1.1 / Spring Framework >= 7.0.8 / Spring Security >= 7.1 when Spring is present.

**Scope of this file.** Classic shared-mutable-state issues (races, visibility, deadlocks, `@Volatile`,
`AtomicReference`), Virtual Thread internals and pinning, CPU-bound parallelism internals, and Kubernetes/cloud-native
configuration apply **identically** to Kotlin classes on the JVM — see `classic-issues.md`, `virtual-threads.md`,
`parallelism.md`, and `cloud-native-concurrency.md`. None of those need a Kotlin-specific variant. This file covers
what is genuinely specific to Kotlin: coroutines, `suspend`, `Dispatchers`, `Flow`, and the Kotlin/Java interop
boundary.

---

## 1. Coroutines vs Virtual Threads — pick one model per call path

Both solve "cheap concurrency for blocking-shaped work", at different layers:

|                        | Virtual Thread                                                         | Kotlin coroutine                                                                                                                   |
|------------------------|------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------|
| Unit of concurrency    | `java.lang.Thread` (virtual)                                           | Suspendable computation — no dedicated thread of its own                                                                           |
| Blocking               | Normal — that is the point                                             | Never blocks *while suspended*; a blocking call made from coroutine code still blocks whatever thread is running it at that moment |
| Cancellation           | Cooperative, via interruption                                          | Cooperative, via `Job` cancellation + `isActive` / `ensureActive()`                                                                |
| Structured concurrency | Only `StructuredTaskScope` — **preview, rejected under this baseline** | `coroutineScope` / `supervisorScope` — **stable for many `kotlinx.coroutines` releases, unaffected by the Java preview boundary**  |
| Context propagation    | `ScopedValue` (same dynamic scope only)                                | `CoroutineContext` elements (`ThreadContextElement`) — designed to survive dispatcher switches                                     |

**Default for a blocking Spring MVC service** (Boot 4.1, `spring.threads.virtual.enabled=true`): write plain,
idiomatic, blocking Kotlin and let the container run it on a Virtual Thread. Coroutines add a second concurrency
model, a second cancellation story, and a second context-propagation mechanism for no benefit when the code is already
sequential and blocking.

**Default when composing several independent suspend/reactive APIs** (WebFlux, R2DBC, a reactive client, or a
codebase that is coroutine-first end to end): use coroutines, and keep Virtual Threads out of that call path except as
an explicit, deliberate bridge (§4).

Do not mix the two per call inside a single method without a clear boundary — a `suspend` method that also blocks on
a Virtual Thread somewhere inside it obscures which cancellation and timeout model actually governs the call.

---

## 2. Dispatchers

| Dispatcher                                      | Backing                                                                                                                                                                                                                          | Use for                                                                         | Do not use for                                                                                                                                      |
|-------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------|
| `Dispatchers.Default`                           | Shared pool sized to `availableProcessors()` (minimum 2)                                                                                                                                                                         | CPU-bound work                                                                  | Blocking I/O — starves the pool it shares with `Dispatchers.IO`                                                                                     |
| `Dispatchers.IO`                                | Elastic pool, capped at 64 threads or the core count (whichever is larger); the cap is configurable via the `kotlinx.coroutines.io.parallelism` system property and hard-limited by `kotlinx.coroutines.scheduler.max.pool.size` | Blocking I/O you don't control (a blocking JDBC driver, a blocking HTTP client) | CPU-bound work — the cap is not a compute budget                                                                                                    |
| `Dispatchers.Unconfined`                        | No dedicated thread; resumes on whichever thread signalled the coroutine's continuation                                                                                                                                          | Rare — tests, specific immediate-continuation tricks                            | General backend code. Spring's own use of it as the default for `suspend` controllers is a known trade-off, not a pattern to imitate elsewhere (§3) |
| Custom (`someExecutor.asCoroutineDispatcher()`) | Whatever `Executor` you hand it                                                                                                                                                                                                  | A dedicated pool for one downstream dependency, or a Virtual-Thread bridge (§4) | —                                                                                                                                                   |

`Dispatchers.IO` and `Dispatchers.Default` **share their underlying threads** — switching from `Default` to `IO` (or
back) via `withContext` frequently does *not* move execution to a different thread. Do not assume a `withContext`
switch relieves pressure on one dispatcher by itself; measure with real thread dumps when diagnosing starvation.

```kotlin
// ❌ CPU-bound work "just" dispatched to IO — steals capacity meant for blocking calls
suspend fun score(input: List<Double>) = withContext(Dispatchers.IO) {
    heavyCpuScoring(input)
}

// ✅ CPU-bound → Default (or a dedicated custom dispatcher sized to cores)
suspend fun score(input: List<Double>) = withContext(Dispatchers.Default) {
    heavyCpuScoring(input)
}

// ✅ Blocking JDBC call you don't control → IO
suspend fun findAccount(id: Long) = withContext(Dispatchers.IO) {
    jdbcTemplate.queryForObject(sql, RowMapper, id)
}
```

Never launch a coroutine with no explicit dispatcher and assume it is safe by default — `launch`/`async` with no
dispatcher argument run on the parent scope's dispatcher, which in a hand-built `CoroutineScope` is often
`Dispatchers.Default`. Confirm what the parent scope actually is before relying on it for blocking work.

---

## 3. Spring integration — `Dispatchers.Unconfined` for suspend controllers

As of Spring Framework 7 — **verify against the exact patch release you run; there is an open enhancement discussion (
`spring-projects/spring-framework#33788`) about a Virtual-Thread-backed alternative, so do not assume this has
changed without checking** — Spring MVC and WebFlux both invoke a `suspend` `@Controller`/`@RestController` method on **
`Dispatchers.Unconfined`**. In practice:

- The method body runs on the request-handling thread **up to its first suspension point**.
- After that first suspension, it resumes on whatever thread the suspended call's own machinery uses to signal
  completion — commonly a shared default executor, not the original request thread and not necessarily any dispatcher
  you chose.
- Anything bound to the original thread via `ThreadLocal` — `SecurityContextHolder`, MDC/logging context, a JDBC
  connection bound by `@Transactional` — is **not guaranteed** to still be the correct one after that first
  suspension.

```kotlin
// ⚠️ Fine until the coroutine suspends — after that, SecurityContextHolder may not be the same thread's context
@GetMapping("/accounts/{id}")
suspend fun getAccount(@PathVariable id: Long): AccountDto {
    val user = SecurityContextHolder.getContext().authentication // read BEFORE the first suspension point
    val account = accountService.findSuspending(id)              // suspension point
    return toDto(account, user)                                   // 'user' captured above, not re-read here
}
```

Read anything `ThreadLocal`-bound **before** the first suspension point and carry it forward explicitly (a parameter,
or a `CoroutineContext` element — §5) — the same discipline the Java side of this skill applies to `ScopedValue` and
fan-out (`virtual-threads.md` §8).

`@Transactional` on a `suspend` function carries the same caveat: Spring's transaction synchronization is
`ThreadLocal`-bound. Confirm, for the exact Spring Framework/Boot version in use, whether — and how — a transactional
suspend method keeps its connection bound across a dispatcher switch. Do not assume it behaves like a blocking
`@Transactional` method on a Virtual Thread just because both eventually commit.

---

## 4. Bridging coroutines and Virtual Threads

`kotlinx-coroutines-core` ships no built-in Virtual-Thread dispatcher. The standard bridge wraps a Virtual-Thread
executor:

```kotlin
// ✅ Managed, shared bean — same "don't leak an executor" rule as the Java skill
@Bean(destroyMethod = "close")
fun virtualThreadDispatcher(): ExecutorCoroutineDispatcher =
    Executors.newVirtualThreadPerTaskExecutor().asCoroutineDispatcher()

suspend fun callBlockingLegacyClient(id: Long): Result =
    withContext(virtualThreadDispatcher) {
        legacyBlockingClient.fetch(id) // one Virtual Thread per call; blocking is fine here
    }
```

Use this only at a deliberate boundary — a single legacy blocking dependency inside an otherwise coroutine-first
codebase — never as a blanket replacement for `Dispatchers.IO`.

Going the other way — calling a `suspend` function from plain Java, or from non-suspending Kotlin code — needs
`runBlocking` (§6) or a `Future`/`CompletableFuture` adapter. `kotlinx-coroutines-jdk8` provides
`CompletableFuture<T>.await()` (a suspend extension) and `CoroutineScope.future { }` (builds a `CompletableFuture`
from suspend code) for that boundary — see `completable-future.md` §8.

---

## 5. Structured concurrency and context propagation

`coroutineScope` / `supervisorScope` give real structured concurrency in Kotlin: a child failing cancels its siblings
(`coroutineScope`) or is isolated (`supervisorScope`), and the enclosing block does not return until every child has
finished. **This is unrelated to Java's `StructuredTaskScope`** and is not subject to the preview-API ban in this
skill — it has been stable for many `kotlinx.coroutines` releases, well before Java's own structured-concurrency JEP.

```kotlin
// ✅ Structured fan-out — both children are awaited or cancelled together
suspend fun loadDashboard(id: String): Dashboard = coroutineScope {
    val user = async(Dispatchers.IO) { userClient.fetchSuspending(id) }
    val orders = async(Dispatchers.IO) { orderClient.fetchSuspending(id) }
    Dashboard(user.await(), orders.await())
}
```

```kotlin
// ❌ GlobalScope — no structure, no cancellation propagation, outlives the caller
fun onEvent(event: Event) {
    GlobalScope.launch { handle(event) } // fire-and-forget forever; never do this in application code
}

// ✅ A component-scoped CoroutineScope with a SupervisorJob, closed with the component
@Component
class EventHandler(
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
) : DisposableBean {
    fun onEvent(event: Event) {
        scope.launch { handle(event) }
    }
    override fun destroy() = scope.cancel()
}
```

**Context propagation across dispatcher switches:** a `CoroutineContext` element implementing `ThreadContextElement`
is the coroutine equivalent of explicit context propagation — its `restoreThreadContext`/`updateThreadContext` hooks
run on whichever thread actually resumes the coroutine, unlike a plain `ThreadLocal`. Prefer this, or an explicit
parameter/data class, over assuming a `ThreadLocal` read before a suspension point is still valid after it (§3).

---

## 6. Cancellation, `runBlocking`, and blocking-call hygiene

- Cooperative cancellation only works if suspend code actually checks for it. A CPU-heavy loop inside a coroutine must
  call `ensureActive()` (or `yield()`) periodically — the coroutine equivalent of checking `Thread.interrupted()`
  inside a long Java loop.
- `withContext(NonCancellable)` is the escape hatch for cleanup that must run even after cancellation (closing a
  resource, releasing a `Mutex`) — do not wrap ordinary work in it just to sidestep cancellation handling.
- `runBlocking` parks the calling thread until its block completes. Calling it from:
    - `main`, a CLI entry point, a `@Scheduled`/Quartz job running on its own thread — fine; this is the intended bridge
      from synchronous to suspending code.
    - a Virtual Thread already serving a request, or a Netty/event-loop thread — defeats the model: that thread cannot
      be reused while `runBlocking` waits, the coroutine equivalent of an unbounded `future.join()` on a request thread
      (`completable-future.md` §5).
- A blocking call (a blocking JDBC driver, `Thread.sleep`, a blocking HTTP client) made directly inside a coroutine
  body **without** `withContext(Dispatchers.IO)` blocks whatever thread is currently running that coroutine — which
  may be a `Dispatchers.Default` thread shared with unrelated CPU-bound work elsewhere in the application.
- Trying to guard a *suspending* critical section with a JVM monitor forces `runBlocking` inside the lock to make the
  suspend call fit, which blocks the underlying thread and defeats both models at once — use `Mutex` instead (§7).

```kotlin
// ❌ synchronized can't host a suspend call directly, so this pattern forces runBlocking inside the monitor —
// blocking the thread while holding the lock, and defeating the point of both synchronized and coroutines.
private val lock = Any()
suspend fun update(id: Long) {
    synchronized(lock) {
        runBlocking { repository.save(id) }
    }
}

// ✅ Mutex suspends the coroutine instead of blocking a thread, and composes naturally with suspend calls
private val mutex = Mutex()
suspend fun update(id: Long) = mutex.withLock {
    repository.save(id) // ordinary suspend call, no runBlocking needed
}
```

---

## 7. `Mutex`, `Channel`, `Semaphore` — coroutine-native synchronization

`kotlinx.coroutines.sync.Mutex` suspends the coroutine instead of blocking a thread — the correct primitive for
mutual exclusion around a suspending critical section. Never `synchronized` or
`java.util.concurrent.locks.ReentrantLock` around a suspension point: both block the underlying thread, and a monitor
acquired before a suspension may need to be released from a *different* thread after the coroutine resumes elsewhere,
which is undefined behaviour for a JVM monitor.

`kotlinx.coroutines.sync.Semaphore` is the suspending counterpart to `java.util.concurrent.Semaphore`, for bounding
concurrent access to a downstream dependency from coroutine code — same bulkhead-per-dependency discipline as
`virtual-threads.md` §6, just suspending instead of blocking.

Never treat in-process coroutine synchronization as a substitute for the database-level concurrency control a shared
financial balance requires (`financial-consistency.md`) — a `Mutex` or `Semaphore` coordinates within one process, not
across concurrent writers from multiple instances.

---

## 8. `Flow` — cold streams and backpressure

`Flow` is Kotlin's cold, coroutine-native stream type — conceptually the closest coroutine equivalent to a reactive
`Publisher`.

- A slow consumer against a fast producer needs `buffer()` (a bounded queue between producer and consumer) or
  `conflate()` (drop intermediate values, keep only the latest) — an unbuffered `collect` couples producer speed
  directly to consumer speed.
- Blocking calls inside a `flow { }` builder must be moved off the collector's dispatcher with
  `flowOn(Dispatchers.IO)` — `flowOn` affects everything upstream of it, not the `collect` call itself.
- `Flow` is cold: each `collect` re-runs the producer from scratch. Do not assume a `Flow` behaves like a hot, shared
  stream unless it is actually a `SharedFlow`/`StateFlow`.

```kotlin
// ✅ blocking DB polling moved off the collector's context
fun pollAccounts(): Flow<Account> = flow {
    while (currentCoroutineContext().isActive) {
        emit(jdbcTemplate.queryForObject(sql, RowMapper))
        delay(1.seconds)
    }
}.flowOn(Dispatchers.IO)
```

---

## 9. Testing

- Use `kotlinx-coroutines-test`'s `runTest { }` and `TestDispatcher` — not `runBlocking` — for suspend-function tests.
  `runTest` runs on virtual time for `delay()`, so a test awaiting `delay(5.seconds)` does not actually wait 5 seconds.
- Assert on `Job`/`Deferred` completion and exceptions explicitly. An exception thrown inside `launch` (unlike
  `async`) never surfaces through a return value — only through the enclosing scope's `CoroutineExceptionHandler` or
  an uncaught-exception hook. A swallowed `launch` exception is a silent failure unless the test checks for it.

---

## 10. Build tooling compatibility

- **Kotlin 2.4.x** (2.4.0, June 2026; 2.4.20, September 2026, a tooling release) is the minimum for this baseline.
  Context parameters, explicit backing fields, and annotation use-site targets are **Stable** as of 2.4.0 — usable
  without an opt-in. Anything still marked `@ExperimentalCoroutinesApi`, `@DelicateCoroutinesApi`, or an
  experimental-status Kotlin language feature is flagged the same way this skill flags a Java preview API: reject in
  production code unless the review explicitly accepts the risk and states why.
- **Gradle >= 9.7** (Groovy or Kotlin DSL, `build.gradle.kts`) — Kotlin 2.4.20 explicitly supports the Gradle 9.7.0
  Tooling API. Confirm the Kotlin Gradle plugin version tracks the Kotlin compiler version actually in use; a stale
  Kotlin Gradle plugin against a newer language version is a baseline mismatch worth flagging.
- **Maven >= 3.9**, with the `kotlin-maven-plugin` version matching the project's Kotlin release. The Maven plugin
  does not always ship the same day as the compiler — check both when bumping either.
- Confirm the JVM bytecode target (`jvmToolchain(25)` in Gradle Kotlin DSL, or the equivalent `jvmTarget`
  configuration in `kotlin-maven-plugin`) matches the Java 25 baseline used everywhere else in the project. A Kotlin
  module compiled to an older bytecode target inside an otherwise Java-25 codebase is a baseline mismatch, not a
  neutral choice.

---

## 11. Flags

- `GlobalScope.launch` / `GlobalScope.async` in application code
- `runBlocking` called from a Virtual Thread, an event-loop thread, or from inside another coroutine
- Blocking call inside a coroutine with no dispatcher switch (`withContext(Dispatchers.IO)` or equivalent)
- CPU-bound work dispatched to `Dispatchers.IO`, or blocking I/O dispatched to `Dispatchers.Default`
- `synchronized` / `ReentrantLock` held across a suspension point instead of `Mutex`
- `ThreadLocal`-bound context (`SecurityContextHolder`, MDC, a transactional connection) read *after* a coroutine's
  first suspension point instead of before it
- Coroutine exception swallowed — no `CoroutineExceptionHandler`, and a `launch` result never inspected
- `Flow` collected with no backpressure handling against a slow consumer
- Kotlin `BigDecimal` `/`, `*`, `+`, `-` operators relied on for money without explicit scale + `RoundingMode` where
  rounding applies
- Experimental/delicate coroutine API (`@OptIn(ExperimentalCoroutinesApi::class)`, `@DelicateCoroutinesApi`) in
  production code without explicit justification
- Kotlin module's JVM bytecode target inconsistent with the project's Java 25 baseline
- A `suspend` controller or `@Transactional` method assumed to preserve `ThreadLocal` context without checking the
  exact Spring version's dispatcher behaviour

---

## 12. References

- Kotlin 2.4 release notes — kotlinlang.org (`whatsnew24.html`, `whatsnew2420.html`).
- `kotlinx.coroutines` API reference — `Dispatchers`, `Mutex`, `Semaphore`, `Flow`
  (kotlinlang.org/api/kotlinx.coroutines).
- Spring Framework reference documentation — Kotlin coroutines support (docs.spring.io).
- `spring-projects/spring-framework#33788` — open discussion on a Virtual-Thread-backed coroutine dispatcher for
  Spring MVC/WebFlux; check current status before assuming it changed the `Dispatchers.Unconfined` default.
- Rahman, A.N.M. Bazlur. *Modern Concurrency in Java*. O'Reilly Media, 2026.
- Evans, Benjamin J., James Gough, and Chris Newland. *Optimizing Cloud Native Java*. O'Reilly Media, 2024.
