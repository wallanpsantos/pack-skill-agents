# Virtual Threads vs CompletableFuture

They are **not alternatives at the same layer**.

|            | Virtual Thread                                | CompletableFuture                                          |
|------------|-----------------------------------------------|------------------------------------------------------------|
| What it is | Lightweight execution carrier                 | Composition / async result API                             |
| Solves     | Cheap blocking, simple imperative concurrency | Pipelines, combinators, adapting async APIs                |
| Style      | Sequential code that blocks                   | Callback / stage chaining                                  |
| Best for   | I/O-bound throughput, readable business flow  | Combining independent async results, legacy Future bridges |

## Default (new code)

**Prefer imperative code on Virtual Threads** for I/O-bound work:

```java
try(var executor = Executors.newVirtualThreadPerTaskExecutor()){
Future<User> user = executor.submit(() -> userClient.fetch(id));
Future<Order> order = executor.submit(() -> orderClient.fetch(id));
    return new

Result(user.get(),order.

get()); // blocks the VT, not a platform thread
        }
```

Readable stack traces, natural try/catch, no callback hell.

## When CompletableFuture still wins

- Composing many stages with `thenCombine` / `allOf` / `anyOf` across existing async APIs
- Bridging libraries that already return `CompletionStage` / `CompletableFuture`
- Need timeouts/combinators without owning the whole call graph

```java
CompletableFuture
        .supplyAsync(() ->userClient.

fetch(id),vtExecutor)
        .

thenCombine(
        CompletableFuture.supplyAsync(() ->orderClient.

fetch(id),vtExecutor),
Result::new)
        .

orTimeout(5,TimeUnit.SECONDS)
    .

exceptionally(ex ->{log.

error("failed",ex); return Result.

empty(); });
```

Always pass an explicit executor for blocking work. Prefer a **shared** VT executor bean.

## Anti-patterns

```java
// ❌ CF only to "look async" while blocking commonPool
CompletableFuture.supplyAsync(() ->

jdbcQuery());

// ❌ nesting CF when a simple VT method would do
        return

supplyAsync(() ->

supplyAsync(() ->

call()).

join()).

join();

// ❌ VT pool (fixed pool of virtual threads)
Executors.

newFixedThreadPool(100,Thread.ofVirtual().

factory());
```

## Decision tree

1. **Is the work I/O-bound and you control the code?** → Virtual Thread, imperative.
2. **Do you need to compose heterogeneous async APIs?** → CompletableFuture (+ VT executor if stages block).
3. **CPU-bound parallel compute?** → neither as primary: sized platform pool / FJP; CF optional for joining.
4. **Spring MVC already on VT (Boot 4 + Java 25)?** → keep controller/service synchronous; let the container use VTs.
   Add CF only at integration edges that are already async.

## Review flags

- CF chain used where a VT method would be clearer and equivalent
- Blocking CF stages on `ForkJoinPool.commonPool`
- Missing terminal handler / timeout on CF
- Platform thread blocked waiting on CF while a VT would be cheaper
- Structured Concurrency (`StructuredTaskScope`) suggested — **preview, reject**
