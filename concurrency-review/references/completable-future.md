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

---

## 6. Flags

- Missing terminal handler on observable/external chain
- Missing timeout on remote/blocking calls (`orTimeout` or `completeOnTimeout`)
- Blocking work on `ForkJoinPool.commonPool`
- Executor created inline and not closed (resource leak)
- `thenApplyAsync` (or any `*Async` variant) without explicit executor when stage does I/O
- `join()` / `get()` on calling thread without timeout or clear ownership of blocking
- CF chain used where a plain VT method would be clearer and equivalent
