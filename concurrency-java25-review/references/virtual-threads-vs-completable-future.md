# Virtual Threads vs CompletableFuture

They are **not alternatives at the same layer**.

|            | Virtual Thread                                | CompletableFuture                                          |
|------------|-----------------------------------------------|-------------------------------------------------------------|
| What it is | Lightweight execution carrier                 | Composition / async result API                              |
| Solves     | Cheap blocking, simple imperative concurrency | Pipelines, combinators, adapting async APIs                |
| Style      | Sequential code that blocks                   | Callback / stage chaining                                   |
| Best for   | I/O-bound throughput, readable business flow  | Combining independent async results, legacy Future bridges  |

---

## Default (New Code)

**Prefer imperative code on Virtual Threads** for I/O-bound work:

```java
// ✅ Fan-out: two independent blocking calls, aggregate results
try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
    Future<User>  user  = executor.submit(() -> userClient.fetch(id));
    Future<Order> order = executor.submit(() -> orderClient.fetch(id));
    return new Result(user.get(5, SECONDS), order.get(5, SECONDS));
}
// Readable stack traces, natural try/catch, no callback hell
```

---

## When CompletableFuture Still Wins

- Composing many stages with `thenCombine` / `allOf` / `anyOf` across existing async APIs
- Bridging libraries that already return `CompletionStage` / `CompletableFuture`
- Need timeouts/combinators without owning the whole call graph

```java
// ✅ CF + shared VT executor: best of both worlds
CompletableFuture.supplyAsync(() -> userClient.fetch(id), vtExecutor)
    .thenCombine(
        CompletableFuture.supplyAsync(() -> orderClient.fetch(id), vtExecutor),
        Result::new)
    .orTimeout(5, TimeUnit.SECONDS)
    .exceptionally(ex -> { log.error("failed", ex); return Result.empty(); });

// Always pass an explicit executor for blocking work; prefer a SHARED VT executor bean
```

---

## Reactive (WebFlux / Project Reactor) vs VTs

| Scenario                                        | Prefer Reactive           | Prefer VTs                 |
|-------------------------------------------------|---------------------------|----------------------------|
| Streaming data (SSE, WebSocket, large files)    | ✅ Native backpressure     | ❌ No push model            |
| High-frequency tiny event processing            | ✅ Event-loop efficiency   | ❌ More overhead            |
| API gateway / non-blocking proxy                | ✅ Minimal overhead        | ❌                          |
| Standard request/response (REST, gRPC)          | ❌ Unnecessary complexity  | ✅ Simpler code             |
| Database-heavy CRUD                             | ❌ R2DBC complexity        | ✅ Plain JDBC works         |
| Spring MVC / existing servlet codebase          | ❌ Migration cost          | ✅ Drop-in improvement      |
| Team lacks reactive expertise                   | ❌                         | ✅ No paradigm shift needed |

> **Mixing:** VTs can call JDBC from inside a reactive Flux producer. Use `Flux.create` with a VT to bridge blocking
> JDBC into a reactive stream without blocking the event loop.

---

## Anti-Patterns

```java
// ❌ CF only to "look async" while blocking commonPool
CompletableFuture.supplyAsync(() -> jdbcQuery()); // no executor → commonPool polluted

// ❌ Nesting CF — callback hell equivalent; deadlock risk on bounded pools
return supplyAsync(() -> supplyAsync(() -> call()).join()).join();

// ❌ VT pool (fixed pool of virtual threads — defeats VT purpose)
Executors.newFixedThreadPool(100, Thread.ofVirtual().factory());

// ❌ thenApplyAsync without executor → commonPool
future.thenApplyAsync(result -> blockingTransform(result)); // should provide vtExecutor

// ❌ Platform thread blocked waiting on CF while a VT would be cheaper
platformThreadExecutor.submit(() -> {
    result = future.join(); // blocks a platform thread — wasteful
});
```

---

## Amdahl's Law Evaluation Framework

Before choosing between Virtual Threads, CompletableFuture, or parallel execution paradigms, apply **Amdahl's Law** to evaluate speedup potential:

$$T(N) = S + \frac{1}{N}(T - S)$$

where $T$ is total sequential execution time, $S$ is the serial fraction (inherently non-parallelizable portion), and $N$ is the concurrency level. Recommending parallel execution (VTs or CFs) requires proving that the serial fraction $S$ is small enough to warrant the added complexity (Evans et al., Ch. 13; Rahman, Ch. 1). If $S$ dominates (e.g., sequential DB queries, locks, synchronous serialization), adding concurrency via VTs or CFs yields diminishing returns while introducing context switching and coordination overhead.

---

## Decision Tree

1. **Is the work I/O-bound and you control the code?** → Virtual Thread, imperative style.
2. **Do you need to compose heterogeneous async APIs?** → CompletableFuture (+ VT executor if stages block).
3. **CPU-bound parallel compute?** → Neither as primary: sized platform pool / FJP; CF optional for joining results.
4. **Spring MVC already on VT (Boot 4 + Java 25)?** → Keep controller/service synchronous; let the container use VTs.
   Add CF only at integration edges that are already async.
5. **Streaming / high-frequency events?** → Evaluate reactive (WebFlux). VTs do not provide push-based backpressure.

---

## Review Flags

- CF chain used where a VT method would be clearer and equivalent
- `thenApplyAsync` / `supplyAsync` without explicit executor (blocking work on `commonPool`)
- Missing terminal handler or timeout on CF
- Platform thread blocked waiting on CF `.join()` while a VT would be cheaper
- Nested CF with `.join()` inside a stage (deadlock risk on bounded pools)
- `StructuredTaskScope` suggested — **preview API, reject always**
- Reactive code used for simple request-response when VTs would suffice

---

## References

- Rahman, A.N.M. Bazlur. *Modern Concurrency in Java*. O'Reilly Media, 2026.
- Evans, Benjamin J., James Gough, and Chris Newland. *Optimizing Cloud Native Java*. O'Reilly Media, 2024.

