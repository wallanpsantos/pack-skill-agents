# Virtual Threads (Java 21 LTS)

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

### 5.2 Pinning in Java 21 LTS (`synchronized`)
- **In Java 21, `synchronized` holding a blocking operation ALWAYS pins the carrier thread.** Monitor ownership is tied to the carrier thread in JDK 21.
- JEP 491 (which decoupled monitor ownership from carriers to unpin `synchronized`) was delivered in Java 24 and is **OUT OF SCOPE** for Java 21.
- In Java 21 codebases, you **MUST** replace `synchronized` with `ReentrantLock` for operations holding blocking I/O or wait states.

### 5.3 What Pins in Java 21

| Scenario                                 | Still Pins? | Action                                          |
|------------------------------------------|-------------|--------------------------------------------------|
| `synchronized` blocking I/O / wait       | ✅ YES      | Replace with `ReentrantLock`                    |
| JNI / native methods                     | ✅ YES      | Minimize native calls in hot VT paths           |
| Foreign Function & Memory API (FFM)      | ✅ YES      | Keep FFM calls off critical VT paths     |
| Class loading during execution           | ✅ YES      | Pre-load critical classes at startup            |
| Certain file system I/O on Linux        | ✅ YES      | Use `AsynchronousFileChannel` or dedicated pool |

### 5.4 Why `synchronized` Must Be Replaced with `ReentrantLock` in Java 21
- **Carrier pinning** — in Java 21, a VT holding a `synchronized` block during blocking I/O pins its carrier OS thread, preventing other VTs from executing on that carrier.
- **Monitor contention** serializes access under high load — thousands of VTs queue on one monitor.
- **No bounded wait** — `ReentrantLock.tryLock(timeout)` enables deadlock avoidance.
- **No interruptibility** — `synchronized` blocks cannot be interrupted; `lockInterruptibly()` can be cancelled.

```java
// ❌ Java 21: PINS the carrier thread during network I/O
synchronized (lock) {
    executeBlockingNetworkCall(); // pins carrier thread; carrier cannot run other VTs
}

// ✅ ReentrantLock: unmounts cleanly, with timeout and interruptibility
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

# Enable JFR recording with fine-grained pinning threshold
java -XX:StartFlightRecording=filename=vt.jfr,settings=profile,\
     +jdk.VirtualThreadPinned#threshold=10ms \
     -jar your-app.jar

# Dev/debug only (verbose, NOT for production)
-Djdk.tracePinnedThreads=full     # prints stack traces on pinning
-Djdk.tracePinnedThreads=short    # summary only
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
- **Java 21 — risco não resolvido:** HikariCP mantém `synchronized` em trechos internos (ex.: `getConnection()`). Uma PR para migrar para `ReentrantLock` (#2055) foi fechada pelo mantenedor, que optou por aguardar a JEP 491 (JDK 24) em vez de corrigir na biblioteca. Não há versão do HikariCP que elimine o pinning em Java 21.
- **Mitigação disponível em Java 21:** alinhar `Semaphore` ao `maximumPoolSize`, monitorar `jdk.VirtualThreadPinned` via JFR, e evitar chamadas de I/O adicionais (ex.: logging síncrono) dentro do mesmo carrier sob contenção.

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

## 8. Request Context: ThreadLocal (Standard in Java 21)

In Java 21, `ScopedValue` (JEP 446) is a **Preview API**. Using preview APIs in production is **PROHIBITED**.

For request context in Java 21, use `ThreadLocal` with mandatory cleanup via `remove()` inside a `finally` block, or pass context explicitly via parameter (e.g. immutability records).

```java
// ✅ Java 21 Standard Pattern — ThreadLocal with mandatory remove() in finally
public static final ThreadLocal<UserContext> HOLDER = new ThreadLocal<>();

public void handle(UserContext ctx) {
    HOLDER.set(ctx);
    try {
        process();
    } finally {
        HOLDER.remove(); // MANDATORY cleanup to avoid memory leaks
    }
}

// ✅ Alternative: Explicit Parameter Passing (Records)
record RequestContext(String userId, String tenantId, String traceId) {}

public void handle(RequestContext ctx) {
    process(ctx);
}

// ❌ PROHIBITED in Java 21 — ScopedValue is a Preview API (JEP 446)
// public static final ScopedValue<UserContext> CONTEXT = ScopedValue.newInstance();
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

// ✅ Pass context explicitly to child tasks instead of using InheritableThreadLocal
RequestContext ctx = currentContext();
for (int i = 0; i < 1000; i++) {
    Thread.ofVirtual().start(() -> doWork(ctx));
}
```

---

## 9. Locking Patterns with VTs

### `Object.wait()` / `Condition.await()` — Properly Parks VTs

```java
// Object.wait() inside a VT in Java 21 pins the carrier thread because monitor ownership requires synchronized.
// ❌ Avoid synchronized + Object.wait() on Virtual Threads in Java 21
synchronized (monitor) {
    while (!condition) {
        monitor.wait(); // PINS carrier thread in Java 21
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

- GraalVM Native Image **fully supports Virtual Threads** (since GraalVM for JDK 21+).
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
| `jdk.VirtualThreadSubmitFailed`   | Carrier pool exhausted (JDK 25 — out of scope for Java 21) | Always |

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

| Feature                                              | Status             | JDK Available | Aplicável ao Target (Java 21)? |
|------------------------------------------------------|--------------------|---------------|--------------------------------|
| Virtual Threads                                      | **GA (Final)**     | JDK 21        | ✅ Sim (Padrão)                 |
| ScopedValue (JEP 446/506)                            | **Preview**        | JDK 21-24     | ❌ Não (Preview — Proibido)    |
| StructuredTaskScope                                  | **Preview**        | JDK 21-25+    | ❌ Não (Preview — Proibido)    |
| `synchronized` pinning fix (JEP 491)                 | **GA**             | JDK 24        | ❌ Não (Out of scope - JDK 24+)|
| `jdk.VirtualThreadSubmitFailed` JFR event            | **GA**             | JDK 25        | ❌ Não (Out of scope - JDK 25+)|
| `Thread.dump_to_file` with VT support                | **GA**             | JDK 21+       | ✅ Sim                         |
| Spring VT support (`spring.threads.virtual.enabled`) | **GA**             | Spring Boot 3.2+ | ✅ Sim                       |

> `StructuredTaskScope` e `ScopedValue` permanecem em preview no Java 21. **NUNCA recomende ou aceite em código de produção.**

---

## 17. References

- Rahman, A.N.M. Bazlur. *Modern Concurrency in Java*. O'Reilly Media, 2026.
- Evans, Benjamin J., James Gough, and Chris Newland. *Optimizing Cloud Native Java*. O'Reilly Media, 2024.

