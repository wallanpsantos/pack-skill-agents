# CompletableFuture Patterns

Load when reviewing CF chains, timeouts, combinators, or executor choice.

`CompletableFuture` is a **composition API**; a Virtual Thread is an **execution mechanism**. They coexist; neither
replaces the other. Do not use CF to make synchronous code merely look asynchronous.

---

## 1. Terminal Error Handling (Mandatory for Observable Chains)

Every chain representing an observable or external operation MUST have a terminal handler. Internal stages may
propagate to a single terminal handler.

```java
// ❌ exception swallowed — no terminal handler
CompletableFuture.supplyAsync(() -> riskyOperation());

// ✅ terminal handler with fallback
CompletableFuture.supplyAsync(() -> riskyOperation(), vtExecutor)
    .exceptionally(ex -> {
        log.error("Operation failed", ex);
        return fallbackValue;
    });

// ✅ success + failure in one handler
CompletableFuture.supplyAsync(() -> riskyOperation(), vtExecutor)
    .handle((result, ex) -> ex != null ? fallbackValue : result);

// ✅ Pipeline: internal stages propagate to one terminal handler
CompletableFuture.supplyAsync(() -> fetchData(), vtExecutor)
    .thenApply(this::transform)
    .thenApply(this::enrich)
    .exceptionally(ex -> {
        log.error("Pipeline failed", ex);
        return fallbackValue;
    });
```

---

## 2. Timeouts (Mandatory on Remote/Blocking Work)

```java
CompletableFuture.supplyAsync(() -> slowOperation(), vtExecutor)
    .orTimeout(5, TimeUnit.SECONDS);                       // completes exceptionally on timeout

CompletableFuture.supplyAsync(() -> slowOperation(), vtExecutor)
    .completeOnTimeout(defaultValue, 5, TimeUnit.SECONDS); // completes with a default
```

> `orTimeout` completes the **future**; it does not cancel the work already running. The blocking call must have its own
> client-level timeout, otherwise the thread stays busy after the chain has "timed out".

---

## 3. Combining Results

```java
// Fan-out with result collection
var futures = requests.stream()
    .map(req -> CompletableFuture.supplyAsync(() -> call(req), vtExecutor)
                                 .orTimeout(5, TimeUnit.SECONDS))
    .toList();

CompletableFuture.allOf(futures.toArray(CompletableFuture[]::new))
    .handle((ignored, ex) -> null)   // allOf fails fast; inspect each future below
    .join();                         // every future already carries its own timeout

// ✅ Java 19+: inspect state instead of getNow(null), which cannot tell "failed" from "returned null"
List<Result> ok = futures.stream()
    .filter(f -> f.state() == Future.State.SUCCESS)
    .map(Future::resultNow)
    .toList();

List<Throwable> failures = futures.stream()
    .filter(f -> f.state() == Future.State.FAILED)
    .map(Future::exceptionNow)
    .toList();

// First to complete
CompletableFuture.anyOf(f1, f2, f3).thenAccept(r -> log.info("first: {}", r));

// Combine two independent results
f1.thenCombine(f2, this::merge);
```

> `join()` exists on `CompletableFuture`, **not** on the `Future` interface. `futures.stream().map(Future::join)` does
> not compile — with plain `Future`, use `get(timeout, unit)` and handle
> `InterruptedException` / `ExecutionException` / `TimeoutException`.

---

## 4. Executor Choice

```java
// ❌ blocking I/O on commonPool — saturates a shared pool
CompletableFuture.supplyAsync(() -> blockingIoCall());

// ❌ new VT executor per call, never closed — leak
CompletableFuture.supplyAsync(() -> blockingIoCall(), Executors.newVirtualThreadPerTaskExecutor());

// ✅ shared application-scoped executor
@Bean(destroyMethod = "shutdown")
public ExecutorService vtExecutor() {
    return Executors.newVirtualThreadPerTaskExecutor();
}

// ✅ full chain: executor + timeout + terminal handler
CompletableFuture.supplyAsync(() -> blockingIoCall(), vtExecutor)
    .orTimeout(5, TimeUnit.SECONDS)
    .exceptionally(ex -> {
        log.error("blockingIoCall failed", ex);
        return fallback;
    });
```

### `thenApplyAsync` Without Executor — A Hidden Bug

```java
// ❌ defaults to ForkJoinPool.commonPool; any blocking inside ties up a commonPool thread
future.thenApplyAsync(result -> blockingTransform(result));

// ✅
future.thenApplyAsync(result -> blockingTransform(result), vtExecutor);
```

| Work Type                                | Executor                                                      |
|------------------------------------------|---------------------------------------------------------------|
| Blocking I/O                             | Shared VT executor                                            |
| CPU-bound                                | Dedicated sized platform executor — never `commonPool`        |
| Fire-and-forget I/O without composition  | `Thread.ofVirtual().name("...", 0).start(...)` — skip CF      |

---

## 5. Anti-Patterns

```java
// ❌ CF only to "look async" while blocking commonPool
CompletableFuture.supplyAsync(() -> jdbcQuery());

// ❌ Nesting CF with join() — deadlock risk on bounded pools
return supplyAsync(() -> supplyAsync(() -> call()).join()).join();

// ❌ VT pool (fixed pool of virtual threads)
Executors.newFixedThreadPool(100, Thread.ofVirtual().factory());

// ❌ join() / get() on the request thread without timeout
future.join();
// ✅ orTimeout() on the chain before join(), or get(timeout, unit)
```

### 5.1 `parallelStream()` Hazards

- **Shared pool saturation:** `parallelStream()` runs on `ForkJoinPool.commonPool()`. Blocking I/O inside it starves
  common-pool threads across the whole application.
- **Amdahl overhead:** on small collections or high serial fraction, splitting and submission cost outweigh the gain.
- **No execution control:** no custom executor, no per-task timeout, no fine-grained error handling.

```java
// ❌ blocking I/O inside parallelStream saturates commonPool
items.parallelStream().map(this::callExternalService).toList();

// ✅ explicit VT executor with per-task timeout and cancellation — see references/parallelism.md §3
```

---

## 6. Kotlin Interop

`kotlinx-coroutines-jdk8` bridges `CompletableFuture` and coroutines in both directions:

- `CompletableFuture<T>.await()` — a suspend extension; suspends the coroutine until the future completes, without
  blocking a thread.
- `CoroutineScope.future { ... }` — builds a `CompletableFuture` from a suspend block, for handing coroutine-produced
  results to a Java API that only speaks `CompletableFuture`.

Use these only at a deliberate boundary with a Java library that has no coroutine-native API. In a coroutine-first
Kotlin codebase, prefer `coroutineScope`/`async`/`await` end to end over routing through `CompletableFuture` — see
`kotlin-coroutines.md` §1 and §5.

## 7. Flags

- Missing terminal handler on an observable/external chain
- Missing timeout on remote/blocking calls (`orTimeout` / `completeOnTimeout`)
- `orTimeout` treated as cancellation of the underlying call
- Blocking work on `ForkJoinPool.commonPool`
- `parallelStream()` for small collections or blocking I/O
- Executor created inline and not closed
- `*Async` stage without explicit executor when the stage does I/O
- `join()` / `get()` without timeout on the request thread
- `Future::join` (does not exist) or `getNow(null)` used to detect failure
- CF chain where a plain VT method would be clearer and equivalent

---

## 8. References

- Rahman, A.N.M. Bazlur. *Modern Concurrency in Java*. O'Reilly Media, 2026.
- Evans, Benjamin J., James Gough, and Chris Newland. *Optimizing Cloud Native Java*. O'Reilly Media, 2024.
