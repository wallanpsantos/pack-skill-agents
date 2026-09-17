# Virtual Threads (Java 25)

Load when reviewing VT usage, pinning, carrier saturation, cancellation, resource limits, or request-context
propagation.

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
} // close() awaits all submitted tasks — see §3.1 before adding per-task timeouts

// ❌ CPU-bound — use a sized platform executor (see references/parallelism.md)
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
- A pauseable, resumable computation storing call-stack frames (program counter, locals, operand stack) on the
  **Java heap**, not on native memory.
- **Flow:** VT hits a blocking op → the JVM yields the continuation → stack frames move to the heap → the carrier is
  freed → I/O completes → the continuation is restored → the VT is remounted on an available carrier.
- **No carrier affinity:** a VT may resume on a *different* carrier. Local variables are fine; OS-thread-local state
  (native thread IDs, thread-bound native handles) is **not safe** across unmount/remount.

### 2.2 Carrier Thread Scheduler
- **Default scheduler:** a dedicated `ForkJoinPool` — **NOT** `ForkJoinPool.commonPool()`.
- **Algorithm:** FIFO work-stealing, optimized for I/O-bound tasks.
- **Tuning flags — only after measurement in a representative environment:**
  ```
  -Djdk.virtualThreadScheduler.parallelism=<N>    # default = Runtime.availableProcessors()
  -Djdk.virtualThreadScheduler.maxPoolSize=256    # default = 256; hard cap on carrier threads
  ```
- **Warning:** tuning `commonPool` (`-Djava.util.concurrent.ForkJoinPool.common.parallelism`) does NOT affect the VT
  scheduler. They are separate pools.

### 2.3 Memory Model
- Platform thread stacks: ~1 MB native memory each, fixed at creation.
- VT stacks: start at ~1 KB on the **Java heap**; grow as needed; shrink after unmounting.
- **Cloud/Kubernetes implication:** moving to VTs shifts memory pressure from native (off-heap, outside `-Xmx`) to the
  JVM heap (inside `-Xmx`). **Increase `-Xmx`** for VT stack frames at peak concurrency.

---

## 3. Creation Patterns

```java
// ✅ Fire-and-forget — single VT with auto-incrementing name
Thread.ofVirtual()
    .name("io-handler-", 0)    // produces: io-handler-0, io-handler-1, ...
    .start(() -> blockingIoCall());

// ✅ ThreadFactory integration (for frameworks that expect ThreadFactory)
ThreadFactory factory = Thread.ofVirtual()
    .name("vt-worker-", 0)
    .factory();
```

### 3.1 Fan-out with bounded lifetime — cancellation is mandatory

`ExecutorService.close()` calls `shutdown()` and then **waits for termination**. A per-task `get(timeout)` that expires
does *not* release the try-with-resources block: the request thread stays parked in `close()` until the slow task
finishes. Cancel outstanding futures before leaving the block.

```java
// ❌ Timeout that does not actually bound the operation
try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
    Future<User>  user  = executor.submit(() -> userClient.fetch(id));
    Future<Order> order = executor.submit(() -> orderClient.fetch(id));
    return new Result(user.get(5, SECONDS), order.get(5, SECONDS));
} // close() blocks until BOTH tasks end, timeout or not

// ✅ Total budget + cancellation in finally
private static final Duration BUDGET = Duration.ofSeconds(5);

public Result load(String id) {
    List<Future<?>> pending = new ArrayList<>();
    try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
        try {
            long deadline = System.nanoTime() + BUDGET.toNanos();
            Future<User>  user  = executor.submit(() -> userClient.fetch(id));   // client has its own timeout
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
            pending.forEach(f -> f.cancel(true)); // without this, close() outlives the budget
        }
    }
}

private static <T> T await(Future<T> f, long deadlineNanos)
        throws InterruptedException, ExecutionException, TimeoutException {
    long remaining = Math.max(0, deadlineNanos - System.nanoTime());
    return f.get(remaining, TimeUnit.NANOSECONDS);
}
```

`cancel(true)` interrupts the task, but the underlying HTTP/JDBC/broker call only stops if it honours interruption.
**Client-level timeouts remain mandatory** — cancellation is a complement, not a substitute.

### VT Properties (Non-negotiable)
- VTs are **always daemon threads** — `setDaemon(false)` throws `IllegalArgumentException`.
- VTs always run at **`NORM_PRIORITY`** — priority changes have no effect.
- **Name them** — unnamed VTs are nearly impossible to debug at scale.

---

## 4. NEVER Pool Virtual Threads

```java
// ❌ ANTI-PATTERN — defeats the purpose of VTs
Executors.newFixedThreadPool(100, Thread.ofVirtual().factory());

// ❌ ANTI-PATTERN — artificial back-pressure at the wrong layer
new ThreadPoolExecutor(50, 50, 0, TimeUnit.SECONDS,
    new LinkedBlockingQueue<>(), Thread.ofVirtual().factory());

// ✅ CORRECT — one VT per task; limit the downstream instead (§6)
try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
    // submit tasks
}
```

**Why:** thread pooling amortizes the cost of OS thread creation. VT creation costs microseconds. Pooling VTs wastes
the benefit and puts back-pressure at the wrong layer — the limit belongs on the scarce downstream resource.

### 4.1 Object Pool Incompatibility

Object pools interact poorly with VTs because VTs are short-lived. Pools designed for long-lived threads or per-thread
reference management retain weak/garbage references and suffer contention and leaks at VT volume (Evans et al., Ch. 13;
Rahman, Ch. 7). Do not use per-thread or generic object pools on VT workloads; rely on lightweight allocation or
application-scoped managed resource pools.

---

## 5. Pinning

### 5.1 What Pinning Is
Pinning = a VT **cannot unmount** from its carrier during a blocking operation. The carrier stays blocked, defeating VT
scalability.

### 5.2 JEP 491 (Java 24): `synchronized` Pinning Fixed
- Java 21–23: `synchronized` could pin VTs (monitor ownership tied to the carrier).
- **Java 24+:** JEP 491 decoupled monitor ownership from carriers. VTs acquire, hold and release monitors
  independently. **`synchronized` no longer pins VTs.**

### 5.3 What Still Pins in Java 25

| Scenario                            | Still Pins? | Action                                             |
|-------------------------------------|-------------|----------------------------------------------------|
| `synchronized` around blocking I/O  | ❌ No       | Still discouraged for contention (see §5.4)        |
| JNI / native methods                | ✅ YES      | Minimize native calls in hot VT paths              |
| Foreign Function & Memory API (FFM) | ✅ YES      | Keep FFM calls off critical VT paths               |
| Class loading during execution      | ✅ YES      | Pre-load critical classes at startup               |
| Certain file system I/O on Linux    | ✅ YES      | See §11 — note the caveats before switching APIs   |

### 5.4 Why `synchronized` Is Still Discouraged (Even After Java 24)
- **Monitor contention** serializes access under load — thousands of VTs queue on one monitor.
- **No bounded wait** — `ReentrantLock.tryLock(timeout)` enables deadlock avoidance.
- **No interruptibility** — monitors cannot be interrupted; `lockInterruptibly()` can be cancelled.

```java
// ⚠️ Java 25: no longer pins, but still serializes and cannot be bounded or cancelled
synchronized (lock) {
    executeBlockingNetworkCall();
}

// ✅ ReentrantLock with timeout and interruptibility
private final ReentrantLock lock = new ReentrantLock();

public void processPayment() throws InterruptedException {
    if (!lock.tryLock(5, TimeUnit.SECONDS)) {
        throw new LockAcquisitionException("Could not acquire payment lock"); // unchecked, domain-specific
    }
    try {
        executeBlockingNetworkCall();
    } finally {
        lock.unlock();
    }
}
```

> `java.util.concurrent.TimeoutException` is checked — throwing it from a method that does not declare it will not
> compile. Use a domain runtime exception at this boundary.

### 5.5 Detection Tools

```bash
# JFR events (production-safe, low overhead)
jdk.VirtualThreadPinned           # VT pinned to carrier (default threshold: 20ms)
jdk.VirtualThreadSubmitFailed     # Carrier pool exhausted — any occurrence is critical
jdk.MonitorEnter                  # Monitor contention on hot locks

# Enable JFR recording with a finer pinning threshold
java -XX:StartFlightRecording=filename=vt.jfr,settings=profile,\
     +jdk.VirtualThreadPinned#threshold=10ms \
     -jar your-app.jar
```

> **Removed API:** `-Djdk.tracePinnedThreads` was **removed by JEP 491 in JDK 24**. Setting it on the command line has
> no effect — it is not a fallback for native/JNI pinning either. JEP 491 expanded `jdk.VirtualThreadPinned` to cover
> parking, monitor enter and `Object.wait` while pinned by a native or VM frame, including blocking during class
> loading. Use JFR.

---

## 6. Resource Limits and Backpressure

VTs eliminate the application-layer thread ceiling but **do not eliminate downstream resource limits**.

**Before VTs:** a fixed pool (e.g. 200 threads) gave implicit backpressure.
**After VTs:** no implicit backpressure → **it must be explicit**.

Without protection, VTs can exhaust JDBC pools, trip external rate limits (429s), hit file descriptor limits, and
saturate broker connections.

### 6.1 Semaphore Pattern (Standard)

The semaphore limits the **real scarce resource** (a JDBC connection, a partner's HTTP capacity). It is **not** a
disguised VT pool: the execution model stays one-VT-per-task and the limit sits at the downstream edge.

```java
// ❌ acquire() with no timeout — an unbounded, invisible queue of VTs; no rejection, no metric
dbPermits.acquire();

// ✅ Bounded wait + rejection metric + permit held only around the scarce operation
private final Semaphore dbPermits = new Semaphore(50);           // <= Hikari maximumPoolSize
private final Counter rejected = Metrics.counter("db.permits.rejected");
private final Gauge available = Gauge.builder("db.permits.available", dbPermits, Semaphore::availablePermits)
                                     .register(registry);

public Result query(Query q) {
    boolean acquired;
    try {
        acquired = dbPermits.tryAcquire(200, TimeUnit.MILLISECONDS);
    } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
        throw new ServiceException("interrupted waiting for DB permit", e);
    }
    if (!acquired) {
        rejected.increment();
        throw new ResourceExhaustedException("DB backpressure limit reached");
    }
    Row row;
    try {
        row = jdbcTemplate.queryForObject(q.sql(), Row.class);   // only the JDBC call holds the permit
    } finally {
        dbPermits.release();
    }
    return transform(row);                                        // CPU work outside the permit
}
```

Rules:

- One semaphore **per dependency** (bulkhead), never one global gate.
- Permits `<=` the pool size they protect. Permits above `maximumPoolSize` protect nothing.
- With blocking `acquire()` and permits equal to the pool size, the semaphore is nearly redundant with Hikari's own
  `connectionTimeout` queue — its value comes from **fail-fast plus observability**.
- Never hold a permit across work that does not use the resource.

### 6.2 HikariCP with Virtual Threads

- **Do NOT remove the connection pool** — JDBC connections are expensive OS resources.
- **Size the pool to DB capacity**, not to thread count. Hikari formula: `(db_cores × 2) + effective_spindle_count`.
  Start conservative; tune on DB wait metrics.
- **Java 24+:** JEP 491 removed the `synchronized` pinning issue inside HikariCP. No workaround needed on Java 25.
- Spring Boot 4.1 added lazy datasource connections — confirm the behaviour for your version; acquiring the connection
  later shortens the window in which a permit and a connection are both held.

### 6.3 Resource Limits Reference

| Resource               | Limit Mechanism                    | Without Protection                           |
|------------------------|------------------------------------|----------------------------------------------|
| JDBC connections       | HikariCP `maxPoolSize` + Semaphore | Pool exhaustion, long queues, timeouts       |
| HTTP client            | Max connections per route + Semaphore | Connection exhaustion, rejected connections |
| File descriptors       | OS `ulimit`; monitor with JFR      | `Too many open files` errors                 |
| External APIs          | Semaphore + rate limiter           | 429s, circuit breaker trips                  |
| Message brokers        | Consumer/producer concurrency      | Broker overload, backpressure propagation    |

Every fan-out defines: max concurrency, per-task timeout, total operation timeout, partial-failure strategy, retry with
backoff and jitter where idempotency allows, and saturation/rejection handling. Retries must not amplify incidents.

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

Checklist for every blocking call: client timeout, resource closing, terminal failure handling, and explicit
cancellation semantics (§3.1).

---

## 8. Request Context: ScopedValue and its boundary

`ScopedValue` (JEP 506) is **final/stable in Java 25**. Prefer it for immutable request-scoped data **within the same
dynamic scope**.

```java
// ✅ Same-thread dynamic scope — the dominant Spring MVC case
public static final ScopedValue<RequestContext> CONTEXT = ScopedValue.newInstance();

record RequestContext(String userId, String tenantId, String traceId) {}

public void handle(RequestContext ctx) {
    ScopedValue.where(CONTEXT, ctx).run(this::process); // process() and everything it calls can read CONTEXT
}
```

### 8.1 ScopedValue is NOT inherited outside StructuredTaskScope

```java
// ❌ WRONG — the binding is not inherited; CONTEXT.get() throws NoSuchElementException
ScopedValue.where(CONTEXT, ctx).run(() -> {
    for (int i = 0; i < 1000; i++) {
        Thread.ofVirtual().start(() -> CONTEXT.get());
    }
});
```

Scoped values are inherited only by threads created by `StructuredTaskScope`; legacy thread management (plain virtual
threads, `ExecutorService`, `ForkJoinPool`) cannot guarantee the child exits before the scope ends, so it does not
inherit them. `StructuredTaskScope` is preview and rejected under this baseline, therefore:

```java
// ✅ Fan-out under this baseline — pass the context explicitly
RequestContext ctx = CONTEXT.get();                 // read once, in the parent
try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
    executor.submit(() -> callApi(ctx, id));        // immutable record travels as a parameter
}
```

### 8.2 ScopedValue anti-pattern: mutable object inside

```java
// ❌ the reference is immutable, the object inside may not be
ScopedValue.where(ERRORS, new ArrayList<>()).run(() -> ERRORS.get().add("error1"));

// ✅ keep the payload immutable; collect results through return values instead
```

### 8.3 ThreadLocal as cache — PROHIBITED with Virtual Threads

```java
// ❌ VTs are never reused, so this "cache" reinitializes per task and pressures GC
private static final ThreadLocal<DateFormat> FORMAT_CACHE =
    ThreadLocal.withInitial(() -> new SimpleDateFormat("yyyy-MM-dd"));

// ✅ immutable, thread-safe, no ThreadLocal at all
private static final DateTimeFormatter FORMAT = DateTimeFormatter.ofPattern("yyyy-MM-dd");
```

### 8.4 InheritableThreadLocal is expensive at scale

Each VT created copies the entire parent map. Prohibited at VT scale — use explicit propagation (§8.1).

---

## 9. Locking Patterns with VTs

```java
// Object.wait() inside a VT parks the VT; it does NOT pin the carrier (Java 24+)
synchronized (monitor) {
    while (!condition) {
        monitor.wait();
    }
}

// ✅ Preferred: Condition.await() on ReentrantLock — interruptible, timeout-capable
lock.lock();
try {
    while (!condition) {
        ready.await(5, TimeUnit.SECONDS);
    }
} finally {
    lock.unlock();
}
```

---

## 10. CPU Burst on Virtual Threads

VTs are not time-sliced. A VT running pure CPU work monopolizes its carrier and starves other VTs.

```java
// ❌ Continuous CPU work on a VT — hogs the carrier
public void processLargeDataset(List<Item> items) {
    items.forEach(this::expensiveTransform);
}

// ❌ ALSO WRONG — "delegating" to the common pool
CompletableFuture.runAsync(() -> expensiveTransform(item), ForkJoinPool.commonPool());
// commonPool parallelism = availableProcessors() - 1. In a 1-CPU container that is 0,
// and tasks run in the CALLING thread — i.e. still on the virtual thread.

// ✅ Move the burst to a dedicated, sized CPU executor
@Bean(destroyMethod = "shutdown")
public ExecutorService cpuExecutor(MeterRegistry registry) {
    int cores = Math.max(2, Runtime.getRuntime().availableProcessors()); // container-visible CPUs
    var exec = new ThreadPoolExecutor(
            cores, cores,
            0L, TimeUnit.MILLISECONDS,
            new ArrayBlockingQueue<>(256),                  // bounded: saturation becomes visible
            Thread.ofPlatform().name("cpu-", 0).factory(),
            new ThreadPoolExecutor.AbortPolicy());          // explicit rejection
    new ExecutorServiceMetrics(exec, "cpu-executor", List.of()).bindTo(registry);
    return exec;
}

// The VT coordinates I/O and waits for the CPU result
Future<Item> f = cpuExecutor.submit(() -> expensiveTransform(item));
Item result = f.get(10, TimeUnit.SECONDS);   // handle Interrupted/Execution/Timeout; cancel on timeout
```

`Thread.yield()` inside the loop is an **exceptional, documented stopgap** — for example, a hot path you cannot refactor
right now. It is a scheduler hint: no bound, no guaranteed fairness, no added parallelism, no effect inside third-party
code, and N CPU-bound VTs still saturate N carriers. Never present it as the standard answer.

---

## 11. File I/O on Linux

`java.io.FileInputStream` / `FileOutputStream` may **pin the carrier**, because kernel async file I/O is not fully
integrated with the JVM.

Options, with their trade-offs:

1. **Dedicated platform-thread pool for file I/O** — simplest and most predictable; keeps carriers free.
2. **Memory-mapped files** (`FileChannel.map`) — no blocking read syscalls, but page faults can still stall and
   mapping has its own costs.
3. **`AsynchronousFileChannel`** — does not remove the blocking, it moves it to its own thread pool; useful, not magic.

Measure before switching: on moderate file volume the pinning may be irrelevant.

---

## 12. GraalVM Native Image + Virtual Threads

- Native Image **supports Virtual Threads**.
- **Caveat:** dynamic class loading during VT execution may pin the carrier.
- **Pre-load critical classes** at startup (`Class.forName(...)` in an `ApplicationReadyEvent` listener).
- AOT: faster startup, potentially lower peak throughput than JIT. Benchmark both.

---

## 13. Observability and Debugging

```bash
# ❌ jstack — omits virtual threads or shows an unhelpful flat list
jstack <PID>

# ✅ JSON — machine-parseable; shows VT/carrier relationships
jcmd <PID> Thread.dump_to_file -format=json /tmp/threads.json

# ✅ Text — human-readable with VT grouping
jcmd <PID> Thread.dump_to_file -format=text /tmp/threads.txt

# VT-specific diagnostics
jcmd <PID> Thread.vthread_pollers       # VTs blocked in network I/O
jcmd <PID> Thread.vthread_scheduler     # scheduler activity
```

| Event                            | What It Captures                            | Default Threshold |
|----------------------------------|---------------------------------------------|-------------------|
| `jdk.VirtualThreadPinned`        | VT pinned to carrier (incl. native/VM frame)| 20 ms             |
| `jdk.VirtualThreadSubmitFailed`  | Carrier pool exhausted                       | Always            |
| `jdk.MonitorEnter`               | Monitor contention                           | Threshold-based   |
| `jdk.VirtualThreadStart` / `End` | VT lifecycle                                 | Always            |

> **Monitoring misconception:** standard Prometheus JVM metrics and VisualVM show **platform thread count** (carriers),
> which stays roughly constant even with millions of VTs. Use JFR or custom VT metrics.

---

## 14. Virtual Thread Performance Qualification

1. Representative benchmark comparing VTs vs current pools
2. Metrics: throughput, avg latency, **p95, p99, p99.9**
3. Vary load: low, medium, high, peak
4. JFR with `jdk.VirtualThreadPinned`, `jdk.VirtualThreadSubmitFailed`, `jdk.MonitorEnter`
5. Thread dumps via `jcmd <PID> Thread.dump_to_file -format=json <FILE>`
6. CPU, heap, native memory under load
7. Downstream metrics (DB connection wait time, HTTP pool utilization)
8. Never compare VTs against an **under-configured** platform pool — it artificially favours VTs

Third-party benchmarks or theory do **NOT** substitute real-environment measurement.

---

## 15. API Status Reference

| Feature                                              | Status                   | JDK          |
|------------------------------------------------------|--------------------------|--------------|
| Virtual Threads                                      | **GA (Final)**           | 21           |
| ScopedValue (JEP 506)                                | **GA (Final)**           | 25           |
| StructuredTaskScope                                  | **Preview — NEVER USE**  | 21–25 and on |
| `synchronized` pinning fix (JEP 491)                 | **GA**                   | 24           |
| `-Djdk.tracePinnedThreads`                           | **REMOVED (no effect)**  | 24           |
| `jdk.VirtualThreadSubmitFailed` JFR event            | **GA**                   | 25           |
| `Thread.dump_to_file` with VT support                | **GA**                   | 21+          |
| Spring VT support (`spring.threads.virtual.enabled`) | **GA**                   | Boot 3.2+    |

> Revisit the `StructuredTaskScope` ban only when the JEP reaches final status.

---

## 16. References

- Rahman, A.N.M. Bazlur. *Modern Concurrency in Java*. O'Reilly Media, 2026.
- Evans, Benjamin J., James Gough, and Chris Newland. *Optimizing Cloud Native Java*. O'Reilly Media, 2024.
- JEP 491, JEP 505, JEP 506.
