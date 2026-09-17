# Virtual Threads vs CompletableFuture

They are **not alternatives at the same layer**.

|            | Virtual Thread                                | CompletableFuture                                          |
|------------|-----------------------------------------------|------------------------------------------------------------|
| What it is | Lightweight execution mechanism               | Composition / async result API                             |
| Solves     | Cheap blocking, simple imperative concurrency | Pipelines, combinators, adapting async APIs                |
| Style      | Sequential code that blocks                   | Stage chaining                                             |
| Best for   | I/O-bound throughput, readable business flow  | Combining independent async results, `CompletionStage` bridges |

They coexist: a CF chain whose blocking stages run on a shared VT executor is the normal combination. Neither replaces
the other.

---

## Default (New Code)

**Prefer imperative code on Virtual Threads** for I/O-bound work you control.

```java
// ✅ Fan-out: two independent blocking calls, aggregated — with cancellation
List<Future<?>> pending = new ArrayList<>();
try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
    try {
        long deadline = System.nanoTime() + Duration.ofSeconds(5).toNanos();
        Future<User>  user  = executor.submit(() -> userClient.fetch(id));
        Future<Order> order = executor.submit(() -> orderClient.fetch(id));
        pending.add(user);
        pending.add(order);
        return new Result(await(user, deadline), await(order, deadline));
    } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
        throw new ServiceException("fan-out interrupted", e);
    } catch (ExecutionException | TimeoutException e) {
        throw new ServiceException("fan-out failed", e);
    } finally {
        pending.forEach(f -> f.cancel(true)); // close() would otherwise wait past the deadline
    }
}
```

Readable stack traces, natural try/catch, no callback chaining — but **the cancellation in `finally` is not optional**:
`ExecutorService.close()` waits for termination. See `references/virtual-threads.md` §3.1.

---

## When CompletableFuture Still Wins

- Composing many stages with `thenCombine` / `allOf` / `anyOf` across existing async APIs
- Bridging libraries that already return `CompletionStage` / `CompletableFuture`
- Timeouts and combinators without owning the whole call graph
- Bounding a set of tasks with one timeout, now that `StructuredTaskScope` is off the table

```java
// ✅ CF + shared VT executor
CompletableFuture.supplyAsync(() -> userClient.fetch(id), vtExecutor)
    .thenCombine(
        CompletableFuture.supplyAsync(() -> orderClient.fetch(id), vtExecutor),
        Result::new)
    .orTimeout(5, TimeUnit.SECONDS)
    .exceptionally(ex -> { log.error("failed", ex); return Result.empty(); });
```

Always pass an explicit executor for blocking work, and remember `orTimeout` completes the future without stopping the
underlying call — client timeouts stay mandatory.

---

## Reactive (WebFlux / Reactor) vs VTs

| Scenario                                        | Prefer Reactive           | Prefer VTs                 |
|-------------------------------------------------|---------------------------|----------------------------|
| Streaming data (SSE, WebSocket, large files)    | ✅ Native backpressure     | ❌ No push model            |
| High-frequency tiny event processing            | ✅ Event-loop efficiency   | ❌ More overhead            |
| API gateway / non-blocking proxy                | ✅ Minimal overhead        | ❌                          |
| Standard request/response (REST, gRPC)          | ❌ Unnecessary complexity  | ✅ Simpler code             |
| Database-heavy CRUD                             | ❌ R2DBC complexity        | ✅ Plain JDBC works         |
| Spring MVC / existing servlet codebase          | ❌ Migration cost          | ✅ Incremental improvement  |
| Team lacks reactive expertise                   | ❌                         | ✅ No paradigm shift        |

> **Mixing:** a VT can call JDBC from inside a reactive producer (`Flux.create` with a VT) to bridge blocking JDBC into
> a stream without blocking the event loop. Virtual Threads provide no backpressure by themselves.

---

## Anti-Patterns

```java
// ❌ CF only to "look async" while blocking commonPool
CompletableFuture.supplyAsync(() -> jdbcQuery());

// ❌ Nesting CF — deadlock risk on bounded pools
return supplyAsync(() -> supplyAsync(() -> call()).join()).join();

// ❌ VT pool
Executors.newFixedThreadPool(100, Thread.ofVirtual().factory());

// ❌ *Async without executor → commonPool
future.thenApplyAsync(result -> blockingTransform(result));

// ❌ Platform thread blocked waiting on a CF while a VT would be cheaper
platformThreadExecutor.submit(() -> future.join());

// ❌ Fan-out in try-with-resources with per-task timeout and no cancel(true)
```

---

## Amdahl's Law Evaluation

Before choosing any concurrency model, estimate the serial fraction:

$$T(N) = S + \frac{1}{N}(T - S)$$

where `T` is total sequential time, `S` the serial fraction and `N` the concurrency level. If `S` dominates (sequential
DB queries, locks, synchronous serialization), adding concurrency yields diminishing returns while adding coordination
cost (Evans et al., Ch. 13; Rahman, Ch. 1).

---

## Decision Tree

1. **I/O-bound and you control the code?** → Virtual Thread, imperative style, with cancellation on fan-out.
2. **Composing heterogeneous async APIs?** → CompletableFuture (+ VT executor if stages block).
3. **CPU-bound parallel compute?** → Neither as primary: dedicated sized platform executor; CF optional for joining.
4. **Spring MVC already on VTs (Boot 4 + Java 25)?** → Keep controller/service synchronous; CF only at async edges.
5. **Streaming / high-frequency events?** → Evaluate reactive. VTs give no push-based backpressure.

---

## Review Flags

- CF chain where a VT method would be clearer and equivalent
- `*Async` without explicit executor (blocking work on `commonPool`)
- Missing terminal handler or timeout on CF
- `orTimeout` mistaken for cancellation of the underlying call
- Platform thread blocked on `.join()` where a VT would be cheaper
- Nested CF with `.join()` inside a stage (deadlock risk)
- Fan-out without cancellation in `finally`
- `StructuredTaskScope` suggested — preview API, reject while it remains preview
- Reactive used for simple request-response where VTs suffice

---

## References

- Rahman, A.N.M. Bazlur. *Modern Concurrency in Java*. O'Reilly Media, 2026.
- Evans, Benjamin J., James Gough, and Chris Newland. *Optimizing Cloud Native Java*. O'Reilly Media, 2024.
