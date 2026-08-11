# Spring @Async Pitfalls

Load when reviewing `@Async`, async executors, SecurityContext propagation, or executor configuration. Requires Spring
Boot >= 4.0.5, Java 25.

## 1. Missing @EnableAsync

```java
// ❌ silently ignored
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

## 2. Self-invocation

```java
// ❌ same-class call bypasses proxy → runs sync
public void processOrder(Order order) {
    sendConfirmation(order);
}

@Async
public void sendConfirmation(Order order) {
}

// ✅ call another Spring bean
public void processOrder(Order order) {
    emailService.sendConfirmation(order);
}
```

## 3. Visibility

```java
// ❌ private/protected — proxy cannot intercept
@Async
private void processInBackground() {
}

// ✅ must be public
@Async
public void processInBackground() {
}
```

## 4. Default executor is unbounded

Default `SimpleAsyncTaskExecutor` creates a thread per task → OOM under load.

```java

@Configuration
@EnableAsync
public class AsyncConfig {

    @Bean
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
```

For I/O-bound `@Async` on Java 25, a virtual-thread executor is a valid alternative:

```java

@Bean
public Executor taskExecutor() {
    return Executors.newVirtualThreadPerTaskExecutor();
}
```

## 5. SecurityContext does not propagate

`SecurityContextHolder` is ThreadLocal-bound.

```java

@Bean
public Executor taskExecutor() {
    ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
    // configure...
    executor.initialize();
    return new DelegatingSecurityContextAsyncTaskExecutor(executor);
}
```

## 6. Executor observability (mandatory)

Every custom executor MUST expose metrics and be properly managed:

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

    // Expose metrics
    new ExecutorServiceMetrics(executor.getThreadPoolExecutor(),
            "async-executor", Collections.emptyList())
            .bindTo(registry);

    return executor;
}
```

Required metrics:

- Active tasks count
- Queue size / capacity
- Rejected task count
- Task completion latency

## 7. Spring Boot 4 + Java 25: VT-aware context

In Spring Boot 4 with Java 25, the container can use Virtual Threads for request handling. In this scenario:

- **Synchronous services are acceptable** — let the container manage VTs for requests.
- Use `CompletableFuture` only at integration edges with APIs that are already async.
- Avoid wrapping synchronous code in `@Async` just to "look async" — the VT container already handles concurrency.

```java
// ✅ In Spring Boot 4 + VT: synchronous service is fine
@Service
public class PaymentService {
    public PaymentResult process(PaymentRequest request) {
        // blocking calls are OK — running on a virtual thread
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

## Flags

- `@Async` without `@EnableAsync`
- Self-invocation
- Non-public `@Async` method
- No custom executor (or unbounded pool)
- Auth-dependent async without context delegation
- Executor without metrics or observability
- Executor without proper shutdown / `destroyMethod`
- Wrapping sync code in `@Async` when container already uses VTs
