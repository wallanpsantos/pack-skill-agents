---
name: concurrency-java21-review
description: >
  Review Java 21 concurrency for thread safety, race conditions, deadlocks,
  Virtual Threads (carrier saturation, pinning, resource limits, JVM internals),
  CompletableFuture error handling, Spring @Async pitfalls, ThreadLocal
  management, cancellation, financial state under concurrent access, and
  cloud-native deployment concerns. Use when the user asks for concurrency
  review, thread safety check, async code review, Virtual Threads review,
  or multi-threaded code analysis.
license: Apache-2.0
compatibility: Java 21 LTS, Spring Boot >= 3.4.5. No preview/incubating APIs (including StructuredTaskScope and ScopedValue).
metadata:
  author: skill-java-concurrency-review
  version: "4.0"
  domain: java-concurrency
---

# Concurrency Review

Review Java concurrent code for correctness, safety, financial consistency, and modern patterns. Target: Java 21 LTS,
Spring Boot >= 3.4.5. No preview/incubating APIs.

## When to Use

- User asks: "check thread safety", "concurrency review", "async code review"
- Code with `synchronized`, `volatile`, `Lock`, `@Async`, `CompletableFuture`, `ExecutorService`
- Virtual Threads / request-context propagation / resource limits
- Concurrent access to balance or monetary state
- Migration to Virtual Threads (performance qualification required)
- Cloud deployment of high-concurrency Java services

## Review Workflow

Progress:

- [ ]    1. Scope — identify shared mutable state, entry points, thread boundaries
- [ ]    2. Baseline — reject preview/incubating APIs; confirm Spring Boot >= 3.4.5 if Spring is present
- [ ]    3. Checklist pass — walk High → Medium → Modern items below
- [ ]    4. Deep dive — load only the reference files that match findings
- [ ]    5. Report — emit findings in the output format below

### Step 1 — Scope

Map:

- What state is shared across threads?
- Which paths do I/O under locks?
- Where are async boundaries (`@Async`, `supplyAsync`, `Thread.ofVirtual`)?
- Is money/balance mutated under concurrency?
- What downstream resources are accessed concurrently (JDBC, HTTP, brokers)?
- Are there cancellation/interruption paths?
- Are there JNI/native calls in hot VT paths? (pinning risk)
- Is the app deployed in a container (Kubernetes)? Are VT-aware resource configs present?

### Step 2 — Baseline (always apply)

- **Reject preview/incubating** — `StructuredTaskScope`, `ScopedValue` (preview JEP 446), and any `--enable-preview` / `jdk.incubator.*` is **Critical**. Do not suggest preview APIs.
- **Spring Boot minimum** — 3.4.5. Flag versions below 3.4.5 and incompatible transitive deps.
- **I/O must have** timeout, try-with-resources / proper shutdown, and terminal exception handling on async chains.
- **Money** — never `double`/`float`; `BigDecimal` ops need explicit `RoundingMode`; concurrent balance needs
  concurrency control (`@Version` + retry as default, or equivalent with justification).
- **Cancellation** — `InterruptedException` must be restored or propagated, never swallowed.

### Step 3 — Checklist

#### High (likely bugs)

- [ ] No check-then-act on shared state without atomicity
- [ ] No `synchronized` around blocking I/O (pins carrier thread in Java 21 and causes monitor contention)
- [ ] No `synchronized` calling external/unknown code (deadlock risk)
- [ ] `volatile` present for double-checked locking (prefer holder idiom)
- [ ] `ConcurrentHashMap.compute` does not nest other map ops (non-atomic state, reentrant access risk)
- [ ] `@Async` methods are public and called via another bean (proxy)
- [ ] No preview APIs (`StructuredTaskScope`, `ScopedValue`, etc.)
- [ ] Financial state not mutated without concurrency control under concurrent access
- [ ] No `double`/`float` for money; no `BigDecimal` arithmetic without `RoundingMode`
- [ ] No concurrency logic based on `ConcurrentHashMap.size()` / `isEmpty()` (estimates)
- [ ] `InterruptedException` not swallowed — restored or propagated
- [ ] No `ThreadLocal` used as cache in Virtual Thread code paths (2000x+ initialization overhead)
- [ ] `thenApplyAsync` / `supplyAsync` without explicit executor when work is blocking (defaults to `commonPool`)
- [ ] No JNI/native calls in hot VT paths without understanding pinning implications

#### Medium (potential issues)

- [ ] Thread pools sized, named, bounded; rejection policy set
- [ ] Every `CompletableFuture` chain (observable/external) has terminal `exceptionally` / `handle`
- [ ] Blocking CF ops have `orTimeout` / `completeOnTimeout`
- [ ] `SecurityContext` propagated when async needs auth (prefer `DelegatingSecurityContextExecutorService`)
- [ ] `ExecutorService` closed (try-with-resources or `destroyMethod`)
- [ ] `lock.lock()` before `try`; `unlock()` in `finally`
- [ ] `tryLock(timeout)` used when bounded wait or deadlock avoidance is needed
- [ ] Thread-safe collections for shared data
- [ ] `ThreadLocal` used for request context has mandatory `remove()` in `finally`
- [ ] `InheritableThreadLocal` not used for propagation at VT scale (expensive map copy per VT)
- [ ] `OptimisticLockException` has retry policy (with documented max attempts and backoff)
- [ ] `Semaphore` / backpressure protecting downstream resources under VT concurrency
- [ ] Semaphore permits aligned with HikariCP `maximumPoolSize`
- [ ] Executor has observability with proper Micrometer instruments: `Counter` (counts/events), `Gauge` (queue size/active tasks), `Timer` (latency/durations), `DistributionSummary` (payload sizes/histograms) (Evans et al., Ch. 11)
- [ ] `@Async` executor configured with rejection policy, naming, and metrics
- [ ] No performance antipatterns present, such as "Tuning by Folklore" (applying flags/tunings without context) or "Distracted by Shiny" (adopting VTs without profiling) (Evans et al., App. B)
- [ ] JFR enabled in production for VT workloads (`jdk.VirtualThreadPinned`)

#### Modern (Java 21 defaults)

- [ ] Virtual Threads for I/O-bound work (never pooled; one per task)
- [ ] CPU-bound work stays on platform threads / ForkJoinPool (VTs yield or delegate CPU work)
- [ ] Request context via `ThreadLocal` com `remove()` garantido em `finally` (ou passagem explícita via parâmetro/record)
- [ ] `ReentrantLock` instead of `synchronized` when lock holds blocking I/O
- [ ] Library pinning check: audit dependencies with internal `synchronized` (e.g. HikariCP `getConnection()` pins VTs on Java 21; mitigate via `Semaphore` and JFR monitoring)
- [ ] VT migration backed by benchmark evidence (not theory); p95/p99 measured
- [ ] JFR events monitored for pinning (`jdk.VirtualThreadPinned`)
- [ ] Kubernetes: `-Xmx` increased to account for VT stacks on heap
- [ ] Container CPU limits set so JVM reads correct processor count for VT scheduler
- [ ] `spring.threads.virtual.enabled: true` considered for Spring Boot 3.4.5 + Java 21

### Step 4 — Load references on demand

| If you find…                                                  | Read                                                                                                              |
|---------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------|
| Virtual Threads, pinning, JVM internals, resource limits      | [references/virtual-threads.md](references/virtual-threads.md)                                                   |
| `@Async`, EnableAsync, SecurityContext, executor config       | [references/spring-async.md](references/spring-async.md)                                                         |
| `CompletableFuture` chains, timeouts, executors               | [references/completable-future.md](references/completable-future.md)                                             |
| Race, visibility, deadlock, DCL, locks, CHM, interruption     | [references/classic-issues.md](references/classic-issues.md)                                                     |
| Balance, BigDecimal, `@Version`, optimistic lock              | [references/financial-consistency.md](references/financial-consistency.md)                                       |
| VT vs CF choice, reactive vs VT                               | [references/virtual-threads-vs-completable-future.md](references/virtual-threads-vs-completable-future.md)       |
| Kubernetes, GraalVM Native Image, container config, JFR cloud | [references/cloud-native-concurrency.md](references/cloud-native-concurrency.md)                                 |

Do not load all references up front.

## Output Format

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

Severity:

- **Critical** — likely bug, preview API, money without locking/rounding, swallowed InterruptedException
- **Medium** — potential under load; verify/measure
- **Modern** — safer Java 21 pattern available

## Gotchas

- Virtual Threads are a **scalability mechanism for I/O-bound work**, not a universal performance optimization. Gains
  depend on workload, environment, and dependencies. Always benchmark before recommending migration.
- **JVM internals:** VT stacks live on the **Java heap**, not native memory. Migrating to VTs requires increasing
  `-Xmx` in containers — VT stack frames now count against the heap budget.
- **VT scheduler:** uses a dedicated `ForkJoinPool` separate from `commonPool`. Tuning `commonPool` does NOT affect
  VT scheduling. Use `-Djdk.virtualThreadScheduler.parallelism=N` to tune.
- **Pinning in Java 21:** `synchronized` on blocking operations **always pins** the carrier thread (JEP 491 is Java 24+ — out of scope). Always prefer `ReentrantLock` when locks hold blocking I/O.
- **What pins in Java 21:** `synchronized` active during blocking operations, JNI/native methods, FFM API calls, class loading during execution, some Linux file I/O operations. Detect with `jdk.VirtualThreadPinned` JFR event.
- **VT properties:** VTs are always daemon threads (cannot change); always `NORM_PRIORITY` (priority changes ignored).
  Name them for observability via `Thread.ofVirtual().name(prefix, start).start(...)`.
- `CompletableFuture.supplyAsync` without executor uses `ForkJoinPool.commonPool` — wrong for blocking I/O.
- `thenApplyAsync` without executor also uses `commonPool` — equally wrong for blocking stages.
- Creating `Executors.newVirtualThreadPerTaskExecutor()` inline without closing leaks resources; prefer shared `@Bean`.
- `@Async` self-invocation bypasses proxy — runs synchronously with no error.
- Default Spring `@Async` executor is unbounded thread-per-task (OOM risk). In Spring Boot 3.4.5 + Java 21, synchronous
  services on VT container are preferred; use CF only at async integration edges.
- `ThreadLocal` under millions of VTs retains heap until thread ends; always clear with `remove()` in `finally` (or pass context as explicit record parameters). `ScopedValue` is preview in Java 21 (JEP 446) — prohibited in production code.
- `ThreadLocal` as per-thread cache causes 2000x+ initialization overhead with VTs — use application-scoped caches.
- `InheritableThreadLocal` copies the entire map at VT creation — expensive at scale. Avoid or pass context explicitly.
- `map.size()` / `isEmpty()` on `ConcurrentHashMap` are estimates — never gate financial logic on them.
- Nested `ConcurrentHashMap.compute` — non-atomic state and reentrant access risk. Prohibited in production.
- Acquire `ReentrantLock` **before** `try`; unlock only in `finally`. Use `tryLock(timeout)` for bounded waits.
- Never leave a CF chain (observable/external) without terminal error handling.
- Never swallow `InterruptedException` — restore interrupt status or propagate.
- With VTs, the bottleneck shifts to downstream resources (JDBC pool, HTTP clients, brokers). Use `Semaphore` /
  backpressure to protect them. Align `Semaphore` permits with HikariCP `maximumPoolSize`.
- CPU-bound work on VTs can monopolize carriers — use `Thread.yield()` periodically or delegate to `ForkJoinPool`.
- Kubernetes: set CPU `limits` so JVM reads correct processor count; set liveness probes on app health, not thread
  count (carrier threads are idle during low traffic with VTs).
- HikariCP VT safety in Java 21: HikariCP retains internal `synchronized` blocks (PR #2055 was closed without merge). No version resolves pinning in Java 21 — mitigate by aligning `Semaphore` permits with `maximumPoolSize` and monitoring `jdk.VirtualThreadPinned`.

## Analysis Commands

```bash
grep -rn "synchronized\|@Async\|volatile\|ThreadLocal\|ScopedValue" --include="*.java" # Note: ScopedValue in Java 21 is Critical (preview API)
grep -rn "CompletableFuture\|ExecutorService\|Executors\." --include="*.java"
grep -rn "StructuredTaskScope\|enable-preview" --include="*.java" .
grep -rn "\.divide(\|\.multiply(" --include="*.java" | grep -v "RoundingMode"
grep -rn "InterruptedException" --include="*.java" | grep -v "interrupt()\|throws"
grep -rn "Semaphore\|RateLimiter\|backpressure" --include="*.java"
grep -rn "thenApplyAsync\|thenRunAsync\|thenAcceptAsync" --include="*.java" | grep -v "Executor\|vtExec\|executor"
grep -rn "InheritableThreadLocal" --include="*.java"
grep -rn "System.loadLibrary\|native " --include="*.java"
```

## Defaults (do not offer menus)

| Situation                                        | Default                                                                           |
|--------------------------------------------------|-----------------------------------------------------------------------------------|
| I/O-bound concurrency (new code)                 | Imperative style on Virtual Threads                                               |
| Compose async results / adapt legacy Future APIs | `CompletableFuture` on a VT executor or dedicated pool                            |
| Request context across VTs                       | `ThreadLocal` com `remove()` em `finally` (ou parâmetro explícito)                |
| Mutable per-thread state (short-lived)           | `ThreadLocal` with `remove()` in `finally`                                        |
| Lock around blocking I/O                         | `ReentrantLock` with `tryLock(timeout)` (not `synchronized`)                     |
| Shared money/balance                             | `@Version` + retry on `OptimisticLockException` (alternatives with justification) |
| CPU-bound parallel work                          | Platform threads / `ForkJoinPool`                                                 |
| Downstream resource protection with VTs          | `Semaphore` with permits aligned to resource pool size                            |
| VT migration recommendation                      | Only with benchmark evidence (throughput + p95/p99 + downstream metrics)         |
| Streaming data / push model                      | Reactive (WebFlux/Reactor) — VTs do not provide push-based backpressure          |
| SecurityContext with VTs                         | `DelegatingSecurityContextExecutorService` wrapping VT executor                  |

## References & Literature

- Rahman, A.N.M. Bazlur. *Modern Concurrency in Java*. O'Reilly Media, 2026. (Foundational text for Java concurrency, Virtual Threads, and execution models).
- Evans, Benjamin J., James Gough, and Chris Newland. *Optimizing Cloud Native Java*. O'Reilly Media, 2024. (Foundational text for cloud-native performance, JVM tuning, Micrometer metrics, and performance antipatterns).

## Related Skills

- `java-code-review` — general review (includes basic concurrency)
- `performance-smell-detection` — performance, not thread safety

