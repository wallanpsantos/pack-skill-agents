# Virtual Threads (Java 25)

Load when reviewing VT usage, pinning, carrier saturation, resource limits, or request-context propagation.

---

## 1. When to Use

Virtual Threads are a **scalability mechanism for predominantly blocking (I/O) tasks**, not a universal performance
optimization. Real-world gains depend on workload, environment, dependencies, and contention profile.

```java
// ✅ I/O-bound (HTTP, DB, file) — high concurrency
try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
    for (Request request : requests) {
        executor.submit(() -> callExternalApi(request));
    }
} // close() awaits all submitted tasks

// ❌ CPU-bound — use platform threads / ForkJoinPool
```

Rule of thumb: benefit appears with high concurrent blocking tasks (often thousands+). Few concurrent tasks may not
justify migration. **Always benchmark before recommending migration for performance reasons.**

| Workload                         | VT Benefit    | Reason                                         |
|----------------------------------|---------------|------------------------------------------------|
| I/O-bound (HTTP, DB, file)       | High          | Carrier freed during wait; N× more concurrency |
| CPU-bound (crypto, image)        | None/Negative | Still consumes carrier CPU; minor overhead     |
| Mixed (I/O + some CPU)           | Moderate      | Depends on ratio                               |
| Very few concurrent tasks (<50)  | Minimal       | Thread pool already sufficient                 |

---

## 2. JVM Internals — How Virtual Threads Work

### 2.1 Continuation Mechanism
- **`jdk.internal.vm.Continuation`** — a pauseable, resumable computation; stores call-stack frames (program counter,
  local variables, operand stack) on the **Java heap**, not on native memory.
- **Flow:** VT hits blocking op → JVM "yields" the continuation → stack frames serialized to heap → carrier thread freed
  → I/O completes → continuation restored → VT remounted on an available carrier.
- **No carrier affinity:** A VT may resume on a *different* carrier than it started on. Local variables in
  continuations are fine; OS-thread-local state (e.g., native thread IDs) is **not safe** across unmount/remount.

### 2.2 Carrier Thread Scheduler
- **Default scheduler:** A dedicated `ForkJoinPool` — **NOT** `ForkJoinPool.commonPool()`.
- **Algorithm:** FIFO work-stealing, optimized for I/O-bound tasks.
- **Tuning flags (JVM system properties):**
  ```
  -Djdk.virtualThreadScheduler.parallelism=<N>    # default = Runtime.availableProcessors()
  -Djdk.virtualThreadScheduler.maxPoolSize=256    # default = 256; hard cap on carrier threads
  ```
- **Warning:** Tuning `commonPool` (e.g., `-Djava.util.concurrent.ForkJoinPool.common.parallelism`) does NOT affect
  the VT scheduler. They are completely separate pools.

### 2.3 Memory Model
- Platform thread stacks: ~1 MB native memory each, fixed at creation time.
- VT stacks: start at ~1 KB on the **Java heap**; grow as needed; shrink after unmounting.
- **Cloud/Kubernetes implication:** Moving to VTs shifts memory pressure from native (off-heap, not counted in `-Xmx`)
  to the JVM heap (counted in `-Xmx`). **Increase `-Xmx`** to accommodate VT stack frames under peak concurrency.

---

## 3. Creation Patterns

```java
// ✅ Fire-and-forget — single VT with auto-incrementing name
Thread.ofVirtual()
    .name("io-handler-", 0)    // produces: io-handler-0, io-handler-1, ...
    .start(() -> blockingIoCall());

// ✅ Multiple tasks with lifecycle management (PREFERRED for fan-out)
try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
    Future<User>  user  = executor.submit(() -> userClient.fetch(id));
    Future<Order> order = executor.submit(() -> orderClient.fetch(id));
    return new Result(user.get(5, SECONDS), order.get(5, SECONDS));
} // close() waits for all tasks to complete

// ✅ ThreadFactory integration (for frameworks that expect ThreadFactory)
ThreadFactory factory = Thread.ofVirtual()
    .name("vt-worker-", 0)
    .factory();
```

### VT Properties (Non-negotiable)
- VTs are **always daemon threads** — calling `setDaemon(false)` throws `IllegalArgumentException`.
- VTs always run at **`NORM_PRIORITY`** — priority changes have no effect.
- **Name them** — unnamed VTs are nearly impossible to debug at scale.

---

## 4. NEVER Pool Virtual Threads

```java
// ❌ ANTI-PATTERN — defeats the purpose of VTs
Executors.newFixedThreadPool(100, Thread.ofVirtual().factory());

// ❌ ANTI-PATTERN — artificial artificial back-pressure at the wrong layer
new ThreadPoolExecutor(50, 50, 0, TimeUnit.SECONDS,
    new LinkedBlockingQueue<>(), Thread.ofVirtual().factory());

// ✅ CORRECT — one VT per task; no pooling needed
try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
    // submit tasks
}
```

**Why:** Thread pooling amortizes the expensive cost of OS thread creation. VT creation costs ~microseconds.
Pooling VTs wastes the benefit and adds artificial back-pressure at the wrong layer.

### 4.1 Object Pool Incompatibility

Object Pools (generic resource reuse pools) interact poorly with Virtual Threads because VTs are short-lived. Object pools designed for long-lived threads or per-thread reference management retain weak/garbage references and suffer from pool contention and resource leaks when used with high-volume Virtual Threads (Evans et al., Ch. 13; Rahman, Ch. 7). Do not use per-thread or generic object pools for Virtual Thread workloads; rely on lightweight direct allocations or application-scoped managed resource pools.


---

## 5. Pinning

### 5.1 What Pinning Is
Pinning = a VT **cannot unmount** from its carrier during a blocking operation. The carrier thread remains blocked,
defeating VT scalability.

### 5.2 JEP 491 (Java 24): `synchronized` Pinning Fixed
- Java 21–23: `synchronized` could pin VTs (monitor ownership was tied to carrier thread).
- **Java 24+:** JEP 491 decoupled monitor ownership from carriers. VTs can acquire, hold, and release monitors
  independently. **`synchronized` no longer pins VTs in Java 24+.**

### 5.3 What Still Pins in Java 25

| Scenario                                 | Still Pins? | Action                                          |
|------------------------------------------|-------------|--------------------------------------------------|
| `synchronized` blocking I/O             | ❌ No       | Still discouraged for contention (see §5.4)     |
| JNI / native methods                     | ✅ YES      | Minimize native calls in hot VT paths           |
| Foreign Function & Memory API (FFM)      | ✅ YES      | Same — keep FFM calls off critical VT paths     |
| Class loading during execution           | ✅ YES      | Pre-load critical classes at startup            |
| Certain file system I/O on Linux        | ✅ YES      | Use `AsynchronousFileChannel` or dedicated pool |

### 5.4 Why `synchronized` Is Still Discouraged (Even After Java 24)
- **Monitor contention** serializes access under high load — thousands of VTs queue on one monitor.
- **No bounded wait** — `ReentrantLock.tryLock(timeout)` enables deadlock avoidance.
- **No interruptibility** — `synchronized` blocks cannot be interrupted; `lockInterruptibly()` can be cancelled.

```java
// ⚠️ Java 25: no longer pins, but still causes contention + no bounded wait
synchronized (lock) {
    executeBlockingNetworkCall(); // thousands of VTs will serialize here
}

// ✅ ReentrantLock with timeout and interruptibility
private final ReentrantLock lock = new ReentrantLock();

public void processPayment() throws InterruptedException {
    if (!lock.tryLock(5, TimeUnit.SECONDS)) {
        throw new TimeoutException("Could not acquire payment lock");
    }
    try {
        executeBlockingNetworkCall();
    } finally {
        lock.unlock();
    }
}
```

### 5.5 Detection Tools

```bash
# JFR events (use in production — low overhead)
jdk.VirtualThreadPinned           # VT pinned to carrier (default threshold: 20ms)
jdk.VirtualThreadSubmitFailed     # Carrier pool exhausted (JDK 25)

# Enable JFR recording with fine-grained pinning threshold
java -XX:StartFlightRecording=filename=vt.jfr,settings=profile,\
     +jdk.VirtualThreadPinned#threshold=10ms \
     -jar your-app.jar

# Dev/debug only (verbose, NOT for production)
-Djdk.tracePinnedThreads=full     # prints stack traces on pinning
-Djdk.tracePinnedThreads=short    # summary only
# Note: -Djdk.tracePinnedThreads is deprecated/removed in JDK 24+ for synchronized
#       Still useful for native/JNI pinning detection
```

---

## 6. Resource Limits and Backpressure

VTs eliminate the application-layer thread ceiling but **do not eliminate downstream resource limits**.

**Before VTs:** Fixed thread pool (e.g., 200 threads) → implicit backpressure.
**After VTs:** No implicit backpressure → **must be explicit**.

Without protection, VTs can:
- Exhaust JDBC connection pools
- Overwhelm external APIs (rate limit violations, 429s)
- Hit OS file descriptor limits (`Too many open files`)
- Saturate message broker connections

### 6.1 Semaphore Pattern (Standard)

```java
// ✅ Protect DB connections — align permits with HikariCP maxPoolSize
private final Semaphore dbPermits = new Semaphore(50);

public Result query(String sql) throws InterruptedException {
    dbPermits.acquire();
    try {
        return jdbcTemplate.queryForObject(sql, Result.class);
    } finally {
        dbPermits.release();
    }
}

// ✅ Protect external API with timeout
private final Semaphore apiPermits = new Semaphore(20);

public ApiResponse callExternalApi(Request req) throws InterruptedException {
    if (!apiPermits.tryAcquire(2, TimeUnit.SECONDS)) {
        throw new RateLimitException("External API backpressure limit reached");
    }
    try {
        return httpClient.send(req, BodyHandlers.ofString());
    } finally {
        apiPermits.release();
    }
}
```

### 6.2 Semaphore with Observability

```java
// ✅ Pattern: non-blocking tryAcquire + metric on rejection
private final Semaphore permits = new Semaphore(50);
private final Counter rejectedRequests = Metrics.counter("db.requests.rejected");

public Result query(String sql) {
    if (!permits.tryAcquire()) {
        rejectedRequests.increment();  // observable in dashboards
        throw new ResourceExhaustedException("DB backpressure: queue full");
    }
    try {
        return jdbcTemplate.queryForObject(sql, Result.class);
    } finally {
        permits.release();
    }
}
```

### 6.3 HikariCP with Virtual Threads

- **Do NOT remove the connection pool** — JDBC connections are expensive OS resources.
- **Size the pool to DB capacity**, NOT to thread count.
  - Hikari formula: `(db_cores × 2) + effective_spindle_count`
  - Start conservative; tune based on DB wait metrics, not application thread count.
- **Pre-Java 24:** HikariCP's internal `synchronized` blocks could pin VTs — significant performance issue.
- **Java 24+:** JEP 491 fixed this — HikariCP works well with VTs without pinning.
- **Best practice:** Set Semaphore permits ≤ HikariCP `maximumPoolSize` to prevent pool exhaustion queuing.

```java
// ✅ Aligned semaphore and HikariCP pool size
@Bean
public HikariDataSource dataSource() {
    HikariConfig config = new HikariConfig();
    config.setMaximumPoolSize(50);  // matches semaphore below
    return new HikariDataSource(config);
}

private final Semaphore dbPermits = new Semaphore(50); // <= maxPoolSize
```

### 6.4 Resource Limits Reference

| Resource               | Limit Mechanism                    | Without Protection                           |
|------------------------|------------------------------------|----------------------------------------------|
| JDBC connections       | HikariCP `maxPoolSize` + Semaphore | Pool exhaustion, long queues, timeouts       |
| HTTP client            | Max connections per route          | Connection exhaustion, rejected connections  |
| File descriptors       | OS `ulimit`; monitor with JFR      | `Too many open files` errors                 |
| External APIs          | Semaphore + rate limiter           | 429s, circuit breaker trips                  |
| Message brokers        | Consumer/producer concurrency      | Broker overload, backpressure propagation    |

---

## 7. Cancellation and Interruption

```java
// ❌ Swallowing InterruptedException — breaks cancellation contracts
try {
    blockingCall();
} catch (InterruptedException e) {
    // silently ignored — BAD
}

// ✅ Restore interrupt status or propagate
try {
    blockingCall();
} catch (InterruptedException e) {
    Thread.currentThread().interrupt();
    throw new ServiceException("Interrupted during blocking call", e);
}
```

---

## 8. Request Context: ScopedValue over ThreadLocal

`ScopedValue` (JEP 506, **final/stable** in Java 25) — prefer for immutable request-scoped data across VTs.

```java
// ❌ ThreadLocal — leak-prone at VT scale; requires explicit remove()
public static final ThreadLocal<UserContext> HOLDER = new ThreadLocal<>();

// ✅ ScopedValue — auto-unbound when scope exits; no cleanup needed
public static final ScopedValue<UserContext> CONTEXT = ScopedValue.newInstance();

public void handle(UserContext ctx) {
    ScopedValue.where(CONTEXT, ctx).run(this::process);
}

// ✅ Multiple values: compose with a record
record RequestContext(String userId, String tenantId, TraceId traceId) {}
private static final ScopedValue<RequestContext> REQUEST_CTX = ScopedValue.newInstance();
```

### ScopedValue anti-pattern: mutable object inside

```java
// ❌ ScopedValue reference is immutable, but the object inside may not be
ScopedValue.where(ERRORS, new ArrayList<>()).run(() -> {
    ERRORS.get().add("error1");  // RACE CONDITION if multiple threads access
});

// ✅ If shared mutable state is needed, use thread-safe collection
ScopedValue.where(ERRORS, Collections.synchronizedList(new ArrayList<>())).run(...);
// Or better: avoid shared mutable state in ScopedValue entirely
```

### ThreadLocal as cache — PROHIBITED with Virtual Threads

```java
// ❌ PROHIBITED — 2000x+ initialization overhead; extreme GC pressure with VTs
private static final ThreadLocal<DateFormat> FORMAT_CACHE =
    ThreadLocal.withInitial(() -> new SimpleDateFormat("yyyy-MM-dd"));

// ✅ Use thread-safe immutable formatter (no ThreadLocal needed)
private static final DateTimeFormatter FORMAT =
    DateTimeFormatter.ofPattern("yyyy-MM-dd"); // immutable; thread-safe
```

### InheritableThreadLocal is expensive at scale

```java
// ❌ Each VT created copies the entire parent InheritableThreadLocal map
private static final InheritableThreadLocal<Context> CTX = new InheritableThreadLocal<>();

for (int i = 0; i < 1000; i++) {
    Thread.ofVirtual().start(() -> doWork()); // each copies the ITL map — expensive
}

// ✅ ScopedValue: no copying, efficient sharing across child VTs
ScopedValue.where(CONTEXT, ctx).run(() -> {
    for (int i = 0; i < 1000; i++) {
        Thread.ofVirtual().start(() -> CONTEXT.get()); // zero-copy access
    }
});
```

---

## 9. Locking Patterns with VTs

### `Object.wait()` / `Condition.await()` — Properly Parks VTs

```java
// Object.wait() inside a VT: properly parks the VT; does NOT pin the carrier (Java 24+)
synchronized (monitor) {
    while (!condition) {
        monitor.wait(); // VT parks; carrier is released
    }
}

// ✅ Preferred: Condition.await() on ReentrantLock — cleaner API
Condition ready = lock.newCondition();
lock.lock();
try {
    while (!condition) {
        ready.await(); // equivalent, interruptible, timeout-capable
    }
} finally {
    lock.unlock();
}
```

---

## 10. CPU Burst on Virtual Threads

VTs do not preempt. A VT running pure CPU work monopolizes its carrier, starving other VTs.

```java
// ❌ Continuous CPU work on VT — can starve other VTs by hogging carrier
public void processLargeDataset(List<Item> items) {
    items.forEach(this::expensiveTransform); // continuous CPU on one carrier
}

// ✅ Yield periodically to allow other VTs to run
public void processLargeDataset(List<Item> items) {
    for (int i = 0; i < items.size(); i++) {
        expensiveTransform(items.get(i));
        if (i % 100 == 0) {
            Thread.yield(); // hint to scheduler: allow other VTs to proceed
        }
    }
}

// ✅ Better: delegate CPU work to ForkJoinPool, use VT only for I/O coordination
CompletableFuture<Void> cpuWork = CompletableFuture.runAsync(
    () -> expensiveTransform(item),
    ForkJoinPool.commonPool() // correct pool for CPU-bound work
);
```

---

## 11. File I/O on Linux

On Linux, `java.io.FileInputStream` / `FileOutputStream` may **pin the carrier** because kernel-level async file I/O
(`io_uring`) is not yet fully integrated with the JVM.

```java
// ❌ High-concurrency file reads on VTs may pin carriers on Linux
FileInputStream fis = new FileInputStream("large.dat");

// ✅ Alternatives for high-throughput file processing
// 1. AsynchronousFileChannel (NIO2 — fully async)
AsynchronousFileChannel fc = AsynchronousFileChannel.open(
    Path.of("large.dat"), StandardOpenOption.READ);

// 2. Memory-mapped files (no blocking read syscalls)
MappedByteBuffer buf = FileChannel.open(Path.of("data.dat"))
    .map(FileChannel.MapMode.READ_ONLY, 0, size);

// 3. Off-load to a dedicated platform-thread pool for file I/O
ExecutorService filePool = Executors.newFixedThreadPool(8);
```

---

## 12. GraalVM Native Image + Virtual Threads

- GraalVM Native Image **fully supports Virtual Threads**.
- **Caveat:** Dynamic class loading during VT execution may pin the carrier (class-loading pinning persists in Native Image).
- **Pre-load critical classes** at startup to avoid class-loading pinning at runtime:
  ```java
  // In application startup
  Class.forName("com.example.CriticalService"); // pre-warm class loading
  ```
- AOT-compiled VT apps: faster startup, potentially lower peak throughput than JIT.

---

## 13. Observability and Debugging

### Thread Dumps

```bash
# ❌ jstack — omits virtual threads or shows them in a flat, unhelpful list
jstack <PID>

# ✅ JSON format — machine-parseable; shows VT/carrier relationships
jcmd <PID> Thread.dump_to_file -format=json /tmp/threads.json

# ✅ Text format — human-readable with VT grouping
jcmd <PID> Thread.dump_to_file -format=text /tmp/threads.txt

# VT-specific diagnostics
jcmd <PID> Thread.vthread_pollers       # VTs blocked in network I/O
jcmd <PID> Thread.vthread_scheduler     # scheduler activity
```

### JFR Events for VTs

| Event                              | What It Captures                  | Default Threshold |
|------------------------------------|-----------------------------------|-------------------|
| `jdk.VirtualThreadPinned`         | VT pinned to carrier              | 20 ms             |
| `jdk.VirtualThreadStart`          | VT lifecycle start                | Always            |
| `jdk.VirtualThreadEnd`            | VT lifecycle end                  | Always            |
| `jdk.VirtualThreadSubmitFailed`   | Carrier pool exhausted (JDK 25)   | Always            |

> **Monitoring misconception:** Standard Prometheus JVM metrics and VisualVM default views show **platform thread
> count** (carrier threads), which stays roughly constant even with millions of VTs. Use JFR or custom VT metrics to
> observe actual VT activity.

---

## 14. Virtual Thread Performance Qualification

Migration recommendations for performance are ONLY valid with measured evidence:

1. Representative benchmark comparing VTs vs current pools
2. Metrics: throughput, avg latency, **p95, p99, p99.9**
3. Vary load levels: low, medium, high, peak (not just peak)
4. JFR with `jdk.VirtualThreadPinned` and `jdk.VirtualThreadSubmitFailed` events
5. Thread dumps via `jcmd <PID> Thread.dump_to_file -format=json <FILE>`
6. CPU, heap, native memory usage under load
7. Downstream resource metrics (DB connection wait time, HTTP pool utilization)
8. Never compare VTs against an **under-configured** platform thread pool — it artificially favors VTs

Third-party benchmarks or theory do **NOT** substitute real-environment measurement.

---

## 15. Fire-and-Forget

```java
Thread.ofVirtual()
    .name("io-task-", 0)
    .start(() -> blockingIoCall());
```

For many tasks with lifecycle bound to a method scope, prefer try-with-resources:

```java
try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
    // submit work; close() waits for completion
}
```

---

## 16. API Status Reference

| Feature                                              | Status             | JDK Available |
|------------------------------------------------------|--------------------|---------------|
| Virtual Threads                                      | **GA (Final)**     | JDK 21        |
| ScopedValue (JEP 506)                                | **GA (Final)**     | JDK 25        |
| StructuredTaskScope                                  | **Preview — NEVER USE** | JDK 21-25+ |
| `synchronized` pinning fix (JEP 491)                 | **GA**             | JDK 24        |
| `jdk.VirtualThreadSubmitFailed` JFR event            | **GA**             | JDK 25        |
| `Thread.dump_to_file` with VT support                | **GA**             | JDK 21+       |
| Spring VT support (`spring.threads.virtual.enabled`) | **GA**             | Spring Boot 3.2+ |

> `StructuredTaskScope` remains preview through Java 25. **Never recommend or accept in production code review.**

---

## 17. References

- Rahman, A.N.M. Bazlur. *Modern Concurrency in Java*. O'Reilly Media, 2026.
- Evans, Benjamin J., James Gough, and Chris Newland. *Optimizing Cloud Native Java*. O'Reilly Media, 2024.

