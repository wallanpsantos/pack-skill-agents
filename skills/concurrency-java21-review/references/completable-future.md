# CompletableFuture Patterns

Load when reviewing CF chains, timeouts, combinators, or executor choice.

---

## 1. Terminal Error Handling (Mandatory for Observable Chains)

Every `CompletableFuture` chain that represents an observable or external operation MUST have a terminal error handler.
Internal stages may propagate exceptions to a single terminal handler.

```java
// ❌ exception swallowed — no terminal handler
CompletableFuture.supplyAsync(() -> riskyOperation());

// ✅ terminal handler with fallback
CompletableFuture.supplyAsync(() -> riskyOperation())
    .exceptionally(ex -> {
        log.error("Operation failed", ex);
        return fallbackValue;
    });

// ✅ success + failure in one handler
CompletableFuture.supplyAsync(() -> riskyOperation())
    .handle((result, ex) -> {
        if (ex != null) {
            log.error("Failed", ex);
            return fallbackValue;
        }
        return result;
    });

// ✅ Pipeline: internal stages propagate to single terminal handler
CompletableFuture.supplyAsync(() -> fetchData())       // may throw
    .thenApply(data -> transform(data))                // may throw
    .thenApply(result -> enrich(result))               // may throw
    .exceptionally(ex -> {                             // single terminal handler
        log.error("Pipeline failed", ex);
        return fallbackValue;
    });
```

---

## 2. Timeouts (Mandatory on Remote/Blocking Work)

```java
CompletableFuture.supplyAsync(() -> slowOperation())
    .orTimeout(5, TimeUnit.SECONDS);  // completes exceptionally on timeout

CompletableFuture.supplyAsync(() -> slowOperation())
    .completeOnTimeout(defaultValue, 5, TimeUnit.SECONDS); // completes with default
```

---

## 3. Combining Results

```java
// Wait for all — fan-out pattern with result collection
var futures = requests.stream()
    .map(req -> CompletableFuture.supplyAsync(() -> call(req), vtExecutor))
    .toList();

CompletableFuture.allOf(futures.toArray(new CompletableFuture[0]))
    .orTimeout(10, TimeUnit.SECONDS)
    .exceptionally(ex -> { log.error("One or more calls failed", ex); return null; })
    .join();

List<Result> results = futures.stream()
    .map(f -> f.getNow(null))  // safe after allOf completed
    .filter(Objects::nonNull)
    .toList();

// First to complete
CompletableFuture.anyOf(f1, f2, f3)
    .thenAccept(r -> log.info("first: {}", r));

// Combine two independent results
f1.thenCombine(f2, (a, b) -> merge(a, b));
```

---

## 4. Executor Choice

```java
// ❌ blocking I/O on commonPool — wrong; will saturate shared pool
CompletableFuture.supplyAsync(() -> blockingIoCall());

// ❌ new VT executor per call, never closed — resource leak
CompletableFuture.supplyAsync(() -> blockingIoCall(),
    Executors.newVirtualThreadPerTaskExecutor()); // executor leaked

// ✅ shared application-scoped executor (prefer @Bean)
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
// ❌ thenApplyAsync without executor defaults to ForkJoinPool.commonPool
//    Any blocking inside this stage will tie up a commonPool thread
future.thenApplyAsync(result -> blockingTransform(result));

// ✅ Always provide an explicit executor for blocking stages
future.thenApplyAsync(result -> blockingTransform(result), vtExecutor);
```

| Work Type                                | Executor                                                  |
|------------------------------------------|-----------------------------------------------------------|
| Blocking I/O                             | VT executor (shared) or dedicated I/O pool                |
| CPU-bound                                | Sized platform pool / FJP — not commonPool for heavy load |
| Fire-and-forget I/O without composition  | `Thread.ofVirtual().start(...)` — skip CF                 |

---

## 5. Anti-Patterns

```java
// ❌ CF only to "look async" while actually blocking commonPool
CompletableFuture.supplyAsync(() -> jdbcQuery()); // no executor → commonPool

// ❌ Nesting CF with join() — deadlock risk on bounded pools
return supplyAsync(() -> supplyAsync(() -> call()).join()).join();

// ❌ VT pool (fixed pool of virtual threads — defeats the purpose)
Executors.newFixedThreadPool(100, Thread.ofVirtual().factory());

// ❌ join() / get() on calling thread without timeout
future.join(); // hangs indefinitely if remote call stalls
// ✅ use orTimeout() on the chain before .join(), or get(timeout, unit)
```

### 5.1 `parallelStream()` Hazards

`parallelStream()` is frequently misused as a quick concurrency fix, leading to major performance and stability hazards:
- **Shared Pool Saturation**: `parallelStream()` implicitly executes on `ForkJoinPool.commonPool()`. Invoking blocking I/O inside a parallel stream starves shared common pool threads across the entire application.
- **Amdahl's Law Overhead**: On small collections or tasks with high serial fraction ($S$), thread splitting and task submission overhead outweigh parallel execution gains (Evans et al., Ch. 13; Rahman, Ch. 7).
- **Lack of Execution Control**: `parallelStream()` does not support custom executors (without fragile hacks), timeouts, or fine-grained error handlers.

```java
// ❌ ANTI-PATTERN — blocking I/O inside parallelStream saturates commonPool
items.parallelStream().map(item -> callExternalService(item)).toList();

// ✅ PREFERRED — use explicit Virtual Thread executor for I/O parallelization
try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
    var futures = items.stream()
        .map(item -> executor.submit(() -> callExternalService(item)))
        .toList();
    return futures.stream().map(Future::join).toList();
}
```

---

## 6. Flags

- Missing terminal handler on observable/external chain
- Missing timeout on remote/blocking calls (`orTimeout` or `completeOnTimeout`)
- Blocking work on `ForkJoinPool.commonPool`
- Overuse of `parallelStream()` for small collections or blocking I/O operations
- Executor created inline and not closed (resource leak)
- `thenApplyAsync` (or any `*Async` variant) without explicit executor when stage does I/O
- `join()` / `get()` on calling thread without timeout or clear ownership of blocking
- CF chain used where a plain VT method would be clearer and equivalent

---

## 7. References

- Rahman, A.N.M. Bazlur. *Modern Concurrency in Java*. O'Reilly Media, 2026.
- Evans, Benjamin J., James Gough, and Chris Newland. *Optimizing Cloud Native Java*. O'Reilly Media, 2024.

