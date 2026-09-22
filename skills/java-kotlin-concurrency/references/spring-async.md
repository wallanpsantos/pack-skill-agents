# Spring @Async Pitfalls

Load when reviewing `@Async`, async executors, SecurityContext propagation, or executor configuration.
Baseline: Java 25, Spring Boot >= 4.1.1 on Spring Framework >= 7.0.8.

---

## 1. Missing @EnableAsync

```java
// ❌ silently ignored — @Async has no effect without @EnableAsync
@Service
public class EmailService {
    @Async
    public void sendEmail(String to) {
    }
}

// ✅
@Configuration
@EnableAsync
public class AsyncConfig {
}
```

---

## 2. Self-Invocation

```java
// ❌ same-class call bypasses the proxy → runs synchronously, no error
public void processOrder(Order order) {
    sendConfirmation(order);
}

@Async
public void sendConfirmation(Order order) {
}

// ✅ call through another bean
public void processOrder(Order order) {
    emailService.sendConfirmation(order);
}
```

---

## 3. Visibility

```java
// ❌ private/protected — the proxy cannot intercept
@Async
private void processInBackground() {
}

// ✅ must be public
@Async
public void processInBackground() {
}
```

---

## 4. Do not use `@Async` as a concurrency multiplier

With `spring.threads.virtual.enabled=true`, the container already handles many concurrent blocking requests at low
thread cost. Wrapping a synchronous service in `@Async` only to "increase concurrency" adds a thread boundary, loses
the request context, and complicates error handling for nothing.

Use `@Async` when there is a real requirement: temporal decoupling, background execution, or an asynchronous edge.

---

## 5. Default Executor Is Unbounded

The default `SimpleAsyncTaskExecutor` creates a thread per task → OOM under load.

```java
// ✅ Bounded platform pool (CPU-bound or strictly limited background work)
@Bean(destroyMethod = "shutdown")
public Executor taskExecutor() {
    ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
    executor.setCorePoolSize(10);
    executor.setMaxPoolSize(50);
    executor.setQueueCapacity(100);
    executor.setThreadNamePrefix("async-");
    executor.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
    executor.initialize();
    return executor;
}

// ✅ Virtual-thread executor for I/O-bound @Async
@Bean(destroyMethod = "shutdown")
public Executor taskExecutor() {
    return Executors.newVirtualThreadPerTaskExecutor();
}
```

`CallerRunsPolicy` pushes back onto the caller — acceptable for background work, dangerous on a request thread that
must stay responsive. Choose the rejection policy deliberately.

---

## 6. Context Propagation

`SecurityContextHolder` is `ThreadLocal`-bound, so auth context is lost across thread boundaries.

> Spring Boot 4.1 added async context propagation for `@Async` methods. Check the behaviour and configuration for the
> exact version in use before removing the explicit delegation below — verify, do not assume.

### Option 1: DelegatingSecurityContextExecutorService (recommended)

```java

@Bean(destroyMethod = "shutdown")
public Executor taskExecutor() {
    ExecutorService vtExec = Executors.newVirtualThreadPerTaskExecutor();
    return new DelegatingSecurityContextExecutorService(vtExec);
}
```

### Option 2: DelegatingSecurityContextAsyncTaskExecutor

```java

@Bean
public Executor taskExecutor() {
    ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
    // configure...
    executor.initialize();
    return new DelegatingSecurityContextAsyncTaskExecutor(executor);
}
```

### Option 3: Explicit propagation

```java
SecurityContext ctx = SecurityContextHolder.getContext();
Thread.

ofVirtual().

name("bg-",0).

start(() ->{
        SecurityContextHolder.

setContext(ctx);
    try{

doWork();
    }finally{
            SecurityContextHolder.

clearContext(); // mandatory
    }
            });
```

### `ScopedValue` does not cross this boundary either

`ScopedValue` bindings are inherited only by threads created by `StructuredTaskScope`, which is preview and rejected
here. For any work that leaves the request thread, pass an immutable context `record` explicitly.

> **Warning:** `spring.security.strategy=INHERITABLETHREADLOCAL` copies the inheritable map at every VT creation —
> expensive at scale. Prefer explicit propagation or the `DelegatingSecurityContext*` wrappers.

---

## 7. Executor Observability (Mandatory)

```java

@Bean(destroyMethod = "shutdown")
public ThreadPoolTaskExecutor taskExecutor(MeterRegistry registry) {
    ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
    executor.setCorePoolSize(10);
    executor.setMaxPoolSize(50);
    executor.setQueueCapacity(100);
    executor.setThreadNamePrefix("async-");
    executor.setRejectedExecutionHandler(new ThreadPoolExecutor.AbortPolicy());
    executor.initialize();

    new ExecutorServiceMetrics(executor.getThreadPoolExecutor(), "async-executor", List.of()).bindTo(registry);
    return executor;
}
```

Required meters (Evans et al., Ch. 11): active tasks (`Gauge`), queue size (`Gauge`), completed and rejected tasks
(`Counter`), execution latency (`Timer` or `DistributionSummary`).

A virtual-thread executor has no queue or pool size to expose — instrument the **work** instead (in-flight gauge,
timer, failure counter) and the downstream semaphores.

---

## 8. Spring Boot 4 + Java 25: VT-Aware Architecture

```yaml
spring:
  threads:
    virtual:
      enabled: true
```

Enables VTs for Tomcat request handling, `@Async`, `@Scheduled`, Spring GraphQL listeners and Kafka/RabbitMQ listeners.

Standalone Tomcat (WAR): `<Connector port="8080" protocol="HTTP/1.1" useVirtualThreads="true" />`.

### Architecture decision

- **Synchronous services are the default** — let the container manage VTs for requests.
- Use `CompletableFuture` only at integration edges with APIs that are already async.
- Do not wrap synchronous code in `@Async` to "look async".

```java
// ✅ synchronous service on a VT-enabled container
@Service
public class PaymentService {
    public PaymentResult process(PaymentRequest request) {
        var account = accountClient.fetch(request.accountId());   // blocking is fine on a VT
        return paymentGateway.charge(account, request.amount());  // both clients have timeouts
    }
}

// ✅ CF only at an async edge
@Service
public class NotificationService {
    public CompletableFuture<Void> notifyAsync(Event event) {
        return CompletableFuture.supplyAsync(() -> externalNotificationApi.send(event), vtExecutor)
                .orTimeout(5, TimeUnit.SECONDS)
                .<Void>thenApply(r -> null)
                .exceptionally(ex -> {
                    log.error("Notification failed", ex);
                    return null;
                });
    }
}
```

VT-enabled containers still need downstream limits: the JDBC pool, HTTP client and brokers do not grow with thread
count (`references/virtual-threads.md` §6).

---

## 9. `@Transactional` with Virtual Threads

- `@Transactional` binds the connection/session to a `ThreadLocal`, and a VT carries its own `ThreadLocal` map with it
  (not with the carrier). This is safe.
- JPA/Hibernate sessions are **not** designed for concurrent access — never share an `EntityManager`, a session or
  mutable entities across threads.
- `@Transactional` on controllers or infrastructure adapters is prohibited — keep it in the application/service layer.
- A transaction holds a connection: do not fan out I/O inside a transaction, and do not let a transaction span a
  semaphore wait.

---

## 10. Kotlin Interop

A Kotlin `suspend` `@Controller`/`@RestController` method is **not** dispatched through this file's `@Async` executor
— Spring invokes it on `Dispatchers.Unconfined` by default (verify against the exact Framework version in use). The
same `SecurityContextHolder`/`ThreadLocal` propagation risk described in §6 applies, but the fix is different: read
`ThreadLocal`-bound state before the method's first suspension point, not by wrapping an executor. See
`kotlin-coroutines.md` §3.

A shared Jackson 3 `JsonMapper` (or Jackson 2 `ObjectMapper`) used from an `@Async` method or a coroutine is safe to
share as-is — it is immutable after `build()` and thread-safe by design. Do not add locking or per-thread instances
around it "to be safe" for concurrent access; that only adds contention for no correctness gain.

## 11. Flags

- `@Async` without `@EnableAsync`
- Self-invocation; non-public `@Async` method
- Unbounded default executor; rejection policy chosen by accident
- Synchronous code wrapped in `@Async` on a VT-enabled container
- Auth-dependent async without context propagation
- `ScopedValue` expected to cross the `@Async` / thread boundary
- Executor without metrics or without shutdown
- `*Async` stage without explicit executor (defaults to `commonPool`)
- `@Transactional` on controller or infrastructure adapter
- Fan-out or semaphore wait inside an open transaction
- `suspend` controller method assumed to run on the request thread throughout, without checking Spring's
  `Dispatchers.Unconfined` default for the version in use

---

## 12. References & Literature

- Rahman, A.N.M. Bazlur. *Modern Concurrency in Java*. O'Reilly Media, 2026. (Ch. 7).
- Evans, Benjamin J., James Gough, and Chris Newland. *Optimizing Cloud Native Java*. O'Reilly Media, 2024. (Ch. 11).
