---
name: concurrency-review
description: >
  Review Java concurrency for thread safety, race conditions, deadlocks,
  Virtual Threads (carrier saturation, resource limits), CompletableFuture error
  handling, Spring @Async pitfalls, ScopedValue vs ThreadLocal, cancellation,
  and financial state under concurrent access. Use when the user asks for
  concurrency review, thread safety check, async code review, Virtual Threads
  review, or multi-threaded code analysis.
license: Apache-2.0
compatibility: Java 25 LTS, Spring Boot >= 4.0.5. No preview/incubating APIs.
metadata:
  author: skill-java-concurrency-review
  version: "3.0"
  domain: java-concurrency
---

# Concurrency Review

Review Java concurrent code for correctness, safety, financial consistency, and modern patterns. Target: Java 25 LTS,
Spring Boot >= 4.0.5. No preview/incubating APIs.

## When to Use

- User asks: "check thread safety", "concurrency review", "async code review"
- Code with `synchronized`, `volatile`, `Lock`, `@Async`, `CompletableFuture`, `ExecutorService`
- Virtual Threads / request-context propagation / resource limits
- Concurrent access to balance or monetary state
- Migration to Virtual Threads (performance qualification required)

## Review Workflow

Progress:

- [ ]
  1. Scope — identify shared mutable state, entry points, thread boundaries
- [ ] 2. Baseline — reject preview/incubating APIs; confirm Spring Boot >= 4.0.5 if Spring is present
- [ ] 3. Checklist pass — walk High → Medium → Modern items below
- [ ] 4. Deep dive — load only the reference files that match findings
- [ ] 5. Report — emit findings in the output format below

### Step 1 — Scope

Map:

- What state is shared across threads?
- Which paths do I/O under locks?
- Where are async boundaries (`@Async`, `supplyAsync`, `Thread.ofVirtual`)?
- Is money/balance mutated under concurrency?
- What downstream resources are accessed concurrently (JDBC, HTTP, brokers)?
- Are there cancellation/interruption paths?

### Step 2 — Baseline (always apply)

- **Reject preview/incubating** — `StructuredTaskScope` and any `--enable-preview` / `jdk.incubator.*` is **Critical**.
  Do not suggest preview APIs.
- **Spring Boot minimum** — 4.0.5. Flag 3.x and incompatible transitive deps.
- **I/O must have** timeout, try-with-resources / proper shutdown, and terminal exception handling on async chains.
- **Money** — never `double`/`float`; `BigDecimal` ops need explicit `RoundingMode`; concurrent balance needs
  concurrency control (`@Version` + retry as default, or equivalent with justification).
- **Cancellation** — `InterruptedException` must be restored or propagated, never swallowed.

### Step 3 — Checklist

#### High (likely bugs)

- [ ] No check-then-act on shared state without atomicity
- [ ] No `synchronized` around blocking I/O (contention + carrier saturation risk with VTs)
- [ ] No `synchronized` calling external/unknown code (deadlock risk)
- [ ] `volatile` present for double-checked locking
- [ ] `ConcurrentHashMap.compute` does not nest other map ops (non-atomic state, reentrant access risk)
- [ ] `@Async` methods are public and called via another bean (proxy)
- [ ] No preview APIs (`StructuredTaskScope`, etc.)
- [ ] Financial state not mutated without concurrency control under concurrent access
- [ ] No `double`/`float` for money; no `BigDecimal` arithmetic without `RoundingMode`
- [ ] No concurrency logic based on `ConcurrentHashMap.size()` / `isEmpty()` (estimates)
- [ ] `InterruptedException` not swallowed — restored or propagated
- [ ] No `ThreadLocal` used as cache in Virtual Thread code paths

#### Medium (potential issues)

- [ ] Thread pools sized, named, bounded; rejection policy set
- [ ] Every `CompletableFuture` chain (observable/external) has terminal `exceptionally` / `handle`
- [ ] Blocking CF ops have `orTimeout` / `completeOnTimeout`
- [ ] `SecurityContext` propagated when async needs auth
- [ ] `ExecutorService` closed (try-with-resources or shutdown)
- [ ] `lock.lock()` before `try`; `unlock()` in `finally`
- [ ] Thread-safe collections for shared data
- [ ] `ThreadLocal` only when `ScopedValue` does not fit; always `remove()` in `finally`
- [ ] `OptimisticLockException` has retry policy (with documented max attempts and backoff)
- [ ] `Semaphore` / backpressure protecting downstream resources under VT concurrency
- [ ] Executor has observability (metrics: queue size, active tasks, rejections)
- [ ] `@Async` executor configured with rejection policy, naming, and metrics

#### Modern (Java 25 defaults)

- [ ] Virtual Threads for I/O-bound work (never pooled; one per task)
- [ ] CPU-bound work stays on platform threads / ForkJoinPool
- [ ] Request context via `ScopedValue`, not `ThreadLocal`
- [ ] `ReentrantLock` instead of `synchronized` when lock holds blocking I/O
- [ ] VT migration backed by benchmark evidence (not theory)
- [ ] JFR events monitored for pinning (`jdk.VirtualThreadPinned`, `jdk.VirtualThreadSubmitFailed`)

### Step 4 — Load references on demand

| If you find…                                              | Read                                                                                                       |
| --------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| Virtual Threads, pinning, resource limits, ScopedValue    | [references/virtual-threads.md](references/virtual-threads.md)                                             |
| `@Async`, EnableAsync, SecurityContext, executor config   | [references/spring-async.md](references/spring-async.md)                                                   |
| `CompletableFuture` chains, timeouts, executors           | [references/completable-future.md](references/completable-future.md)                                       |
| Race, visibility, deadlock, DCL, locks, CHM, interruption | [references/classic-issues.md](references/classic-issues.md)                                               |
| Balance, BigDecimal, `@Version`, optimistic lock          | [references/financial-consistency.md](references/financial-consistency.md)                                 |
| VT vs CF choice                                           | [references/virtual-threads-vs-completable-future.md](references/virtual-threads-vs-completable-future.md) |

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
- **Modern** — safer Java 25 pattern available

## Gotchas

- Virtual Threads are a **scalability mechanism for I/O-bound work**, not a universal performance optimization. Gains
  depend on workload, environment, and dependencies. Always benchmark before recommending migration.
- In Java 25, `synchronized` no longer pins VTs, but still causes contention under load with blocking I/O. Prefer
  `ReentrantLock`.
- `CompletableFuture.supplyAsync` without executor uses `ForkJoinPool.commonPool` — wrong for blocking I/O.
- Creating `Executors.newVirtualThreadPerTaskExecutor()` per call without closing leaks resources; prefer shared `@Bean`
  or `Thread.ofVirtual().start`.
- `@Async` self-invocation bypasses proxy — runs synchronously with no error.
- Default Spring `@Async` executor is unbounded thread-per-task (OOM risk). In Spring Boot 4 + Java 25, synchronous
  services on VT container are preferred; use CF only at async integration edges.
- `ThreadLocal` under millions of VTs retains heap until thread ends; prefer `ScopedValue` for request context.
- `ThreadLocal` as per-thread cache causes 2000x+ initialization overhead with VTs — use application-scoped caches.
- `map.size()` / `isEmpty()` on `ConcurrentHashMap` are estimates — never gate financial logic on them.
- Nested `ConcurrentHashMap.compute` — non-atomic state and reentrant access risk. Prohibited in production.
- Acquire `ReentrantLock` **before** `try`; unlock only in `finally`.
- Never leave a CF chain (observable/external) without terminal error handling.
- Never swallow `InterruptedException` — restore interrupt status or propagate.
- With VTs, the bottleneck shifts to downstream resources (JDBC pool, HTTP clients, brokers). Use `Semaphore` /
  backpressure to protect them.

## Analysis Commands

```bash
grep -rn "synchronized\|@Async\|volatile\|ThreadLocal\|ScopedValue" --include="*.java"
grep -rn "CompletableFuture\|ExecutorService\|Executors\." --include="*.java"
grep -rn "StructuredTaskScope\|enable-preview" --include="*.java" .
grep -rn "\.divide(\|\.multiply(" --include="*.java" | grep -v "RoundingMode"
grep -rn "InterruptedException" --include="*.java" | grep -v "interrupt()\|throws"
grep -rn "Semaphore\|RateLimiter\|backpressure" --include="*.java"
```

## Defaults (do not offer menus)

| Situation                                        | Default                                                                           |
| ------------------------------------------------ | --------------------------------------------------------------------------------- |
| I/O-bound concurrency (new code)                 | Imperative style on Virtual Threads                                               |
| Compose async results / adapt legacy Future APIs | `CompletableFuture` on a VT executor or dedicated pool                            |
| Request context across VTs                       | `ScopedValue`                                                                     |
| Lock around blocking I/O                         | `ReentrantLock` (not `synchronized`)                                              |
| Shared money/balance                             | `@Version` + retry on `OptimisticLockException` (alternatives with justification) |
| CPU-bound parallel work                          | Platform threads / `ForkJoinPool`                                                 |
| Downstream resource protection with VTs          | `Semaphore` / explicit backpressure                                               |
| VT migration recommendation                      | Only with benchmark evidence                                                      |

## Related Skills

- `java-code-review` — general review (includes basic concurrency)
- `performance-smell-detection` — performance, not thread safety
