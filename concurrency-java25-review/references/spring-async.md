# Spring @Async Pitfalls

Load when reviewing `@Async`, async executors, SecurityContext propagation, or executor configuration. Requires Spring
Boot >= 4.0.5, Java 25.

---

## 1. Missing @EnableAsync

```java
// ❌ silently ignored — @Async has no effect without @EnableAsync
@Service
public class EmailService {
    @Async
    public void sendEmail(String to) { }
}

// ✅
@Configuration
@EnableAsync
public class AsyncConfig { }
```

---

## 2. Self-Invocation

```java
// ❌ same-class call bypasses Spring proxy → runs synchronously with no error
public void processOrder(Order order) {
    sendConfirmation(order); // calls this.sendConfirmation — NOT the proxy
}

@Async
public void sendConfirmation(Order order) { }

// ✅ call via another Spring bean
public void processOrder(Order order) {
    emailService.sendConfirmation(order); // proxy intercepts @Async correctly
}
```

---

## 3. Visibility

```java
// ❌ private/protected — Spring proxy cannot intercept
@Async
private void processInBackground() { }

// ✅ must be public
@Async
public void processInBackground() { }
```

---

## 4. Default Executor Is Unbounded

Default `SimpleAsyncTaskExecutor` creates a thread per task → OOM under load.

```java
// ✅ Bounded platform thread pool for @Async
@Configuration
@EnableAsync
public class AsyncConfig {

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
}

// ✅ Virtual-thread executor for I/O-bound @Async on Java 25
@Bean(destroyMethod = "shutdown")
public Executor taskExecutor() {
    return Executors.newVirtualThreadPerTaskExecutor();
}
```

---

## 5. SecurityContext Does Not Propagate

`SecurityContextHolder` is `ThreadLocal`-bound. Auth context is lost across thread boundaries. In modern Java, `ScopedValue` (Rahman, 2026, Ch. 7) provides immutable, scoped context propagation across thread boundaries without `ThreadLocal` memory leak risks.

### Option 1: DelegatingSecurityContextExecutorService (Recommended)

```java
@Bean(destroyMethod = "shutdown")
public Executor taskExecutor() {
    ExecutorService vtExec = Executors.newVirtualThreadPerTaskExecutor();
    return new DelegatingSecurityContextExecutorService(vtExec);
}
```

### Option 2: `ThreadPoolTaskExecutor` with `DelegatingSecurityContextAsyncTaskExecutor`

```java
@Bean
public Executor taskExecutor() {
    ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
    // configure...
    executor.initialize();
    return new DelegatingSecurityContextAsyncTaskExecutor(executor);
}
```

### Option 3: Explicit Context Propagation (Most Correct with VTs)

```java
SecurityContext ctx = SecurityContextHolder.getContext();
Thread.ofVirtual().start(() -> {
    SecurityContextHolder.setContext(ctx);
    try {
        doWork();
    } finally {
        SecurityContextHolder.clearContext(); // mandatory cleanup
    }
});
```

> **Warning:** `INHERITABLETHREADLOCAL` propagation mode (`spring.security.strategy=INHERITABLETHREADLOCAL`) copies
> the ITL map at VT creation time — expensive at scale (Rahman, 2026, Ch. 7). Prefer explicit propagation or `DelegatingSecurityContext*`.

---

## 6. Executor Observability (Mandatory)

Every custom executor MUST expose metrics and be properly managed using appropriate Micrometer meter types (Evans et al., 2024, Ch. 11):

```java
@Bean(destroyMethod = "shutdown")
public ThreadPoolTaskExecutor taskExecutor(MeterRegistry registry) {
    ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
    executor.setCorePoolSize(10);
    executor.setMaxPoolSize(50);
    executor.setQueueCapacity(100);
    executor.setThreadNamePrefix("async-");
    executor.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
    executor.initialize();

    // Expose metrics via Micrometer
    new ExecutorServiceMetrics(executor.getThreadPoolExecutor(),
            "async-executor", Collections.emptyList())
            .bindTo(registry);

    return executor;
}
```

Required metrics & Micrometer meter types (Evans et al., 2024, Ch. 11):
- Active tasks count (`Gauge`)
- Queue size / capacity (`Gauge`)
- Completed and rejected task counts (`Counter`)
- Task execution latency / duration (`Timer` or `DistributionSummary`)

---

## 7. Spring Boot 4 + Java 25: VT-Aware Architecture

### Option A: Single Config Flag (Preferred)

```yaml
# application.yaml
spring:
  threads:
    virtual:
      enabled: true
```

This enables VTs for: Tomcat request handling, `@Async`, `@Scheduled`, Spring GraphQL listeners, Kafka/RabbitMQ
listeners.

### Option B: Standalone Tomcat (WAR deployment)

```xml
<!-- server.xml — Tomcat 11+ -->
<Connector port="8080" protocol="HTTP/1.1" useVirtualThreads="true" />
```

### Architecture Decision

In Spring Boot 4 with Java 25 + VT container:

- **Synchronous services are acceptable** — let the container manage VTs for requests.
- Use `CompletableFuture` only at integration edges with APIs that are already async.
- **Avoid wrapping synchronous code in `@Async`** just to "look async" — the VT container already handles
  concurrency for you.

```java
// ✅ In Spring Boot 4 + VT: synchronous service is fine
@Service
public class PaymentService {
    public PaymentResult process(PaymentRequest request) {
        // blocking calls are OK — running on a VT managed by container
        var account = accountClient.fetch(request.accountId());
        var result = paymentGateway.charge(account, request.amount());
        return result;
    }
}

// ✅ CF only at async integration edges
@Service
public class NotificationService {
    public CompletableFuture<Void> notifyAsync(Event event) {
        return CompletableFuture.supplyAsync(
                        () -> externalNotificationApi.send(event), vtExecutor)
                .orTimeout(5, TimeUnit.SECONDS)
                .exceptionally(ex -> {
                    log.error("Notification failed", ex);
                    return null;
                });
    }
}
```

---

## 8. @Transactional with Virtual Threads

- `@Transactional` binds the JDBC connection/session to a `ThreadLocal` — but **VTs maintain their own `ThreadLocal`
  map** that travels with the VT, not with the carrier. This is safe.
- **However:** JPA/Hibernate sessions are not designed for concurrent multi-threaded access — never share entity
  sessions or entity manager state across threads.
- `@Transactional` on Controllers or infrastructure adapters is prohibited — keep it on service layer only.

---

## 9. Flags

- `@Async` without `@EnableAsync`
- Self-invocation (same-class call bypasses proxy)
- Non-public `@Async` method
- No custom executor (or unbounded default executor)
- Auth-dependent async without `SecurityContext` delegation
- Executor without metrics or observability
- Executor without proper shutdown / `destroyMethod`
- Wrapping synchronous code in `@Async` when container already uses VTs
- `thenApplyAsync` / `supplyAsync` without explicit executor (defaults to `commonPool`)
- `@Transactional` on Controller or infrastructure adapter

---

## 10. References & Literature

- Rahman, A.N.M. Bazlur. *Modern Concurrency in Java*. O'Reilly Media, 2026. (Chapter 7: Scoped Values & Context Propagation).
- Evans, Benjamin J., James Gough, and Chris Newland. *Optimizing Cloud Native Java*. O'Reilly Media, 2024. (Chapter 11: Application Observability & Micrometer Metrics).
