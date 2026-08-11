# CompletableFuture Patterns

Load when reviewing CF chains, timeouts, combinators, or executor choice.

## Terminal error handling (mandatory for observable chains)

Every `CompletableFuture` chain that represents an observable or external operation MUST have a terminal error handler.
Internal stages may propagate exceptions to a single terminal handler.

```java
// ❌ exception swallowed — no terminal handler
CompletableFuture.supplyAsync(() ->

riskyOperation());

// ✅ terminal handler
        CompletableFuture.

supplyAsync(() ->

riskyOperation())
        .

exceptionally(ex ->{
        log.

error("Operation failed",ex);
        return fallbackValue;
    });

// ✅ success + failure
            CompletableFuture.

supplyAsync(() ->

riskyOperation())
        .

handle((result, ex) ->{
        if(ex !=null){
        log.

error("Failed",ex);
            return fallbackValue;
        }
                return result;
    });

// ✅ Internal stages propagating to single terminal handler
            CompletableFuture.

supplyAsync(() ->

fetchData())       // may throw
        .

thenApply(data ->

transform(data))                 // may throw
        .

thenApply(result ->

enrich(result))                // may throw
        .

exceptionally(ex ->{                              // single terminal handler
        log.

error("Pipeline failed",ex);
        return fallbackValue;
    });
```

## Timeouts (mandatory on blocking work)

```java
CompletableFuture.supplyAsync(() ->

slowOperation())
        .

orTimeout(5,TimeUnit.SECONDS);

CompletableFuture.

supplyAsync(() ->

slowOperation())
        .

completeOnTimeout(defaultValue, 5,TimeUnit.SECONDS);
```

## Combining

```java
CompletableFuture.allOf(f1, f2, f3)
    .

thenRun(() ->log.

info("all done"));

        CompletableFuture.

anyOf(f1, f2, f3)
    .

thenAccept(r ->log.

info("first: {}",r));

        f1.

thenCombine(f2, (a, b) ->

merge(a, b));
```

## Executor choice

```java
// ❌ blocking I/O on commonPool
CompletableFuture.supplyAsync(() ->

blockingIoCall());

// ❌ new VT executor per call, never closed
        CompletableFuture.

supplyAsync(() ->

blockingIoCall(),
    Executors.

newVirtualThreadPerTaskExecutor());

// ✅ shared application-scoped executor
@Bean
public ExecutorService virtualThreadExecutor() {
    return Executors.newVirtualThreadPerTaskExecutor();
}

CompletableFuture.

supplyAsync(() ->

blockingIoCall(),virtualThreadExecutor)
        .

orTimeout(5,TimeUnit.SECONDS)
    .

exceptionally(ex ->{
        log.

error("blockingIoCall failed",ex);
        return fallback;
    });
```

| Work type                               | Executor                                                  |
| --------------------------------------- | --------------------------------------------------------- |
| Blocking I/O                            | Virtual-thread executor (shared) or dedicated I/O pool    |
| CPU-bound                               | Sized platform pool / FJP — not commonPool for heavy load |
| Fire-and-forget I/O without composition | `Thread.ofVirtual().start(...)` — skip CF                 |

## Flags

- Missing terminal handler on observable/external chain
- Missing timeout on remote/blocking calls
- Blocking work on `commonPool`
- Executor created inline and not closed
- `join()`/`get()` on calling thread without timeout or clear ownership of blocking
