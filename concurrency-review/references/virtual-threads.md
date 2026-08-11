# Virtual Threads (Java 25)

Load when reviewing VT usage, pinning, carrier saturation, resource limits, or request-context propagation.

## When to use

Virtual Threads are a **scalability mechanism for predominantly blocking (I/O) tasks**, not a universal performance
optimization. Real-world gains depend on workload, environment, dependencies, and contention profile.

```java
// ✅ I/O-bound (HTTP, DB, file) — high concurrency
try(var executor = Executors.newVirtualThreadPerTaskExecutor()){
        for(
Request request :requests){
        executor.

submit(() ->

callExternalApi(request));
        }
        }

// ❌ CPU-bound — use platform threads / ForkJoinPool
```

Rule of thumb: benefit shows with high concurrent blocking tasks (often thousands+). Few concurrent tasks may not
justify a migration. **Always benchmark before recommending migration for performance reasons.**

## Pinning (Java 25)

In Java 24/25, the JVM no longer pins virtual threads to carriers when blocking inside `synchronized` (monitor pinning
removed). However, **`synchronized` around blocking I/O remains discouraged** because:

- Monitor contention can still serialize access, defeating the scalability benefit of VTs.
- Under high load, contended monitors can saturate carrier threads in critical sections.
- `ReentrantLock` provides `tryLock(timeout, unit)` for bounded waits and deadlock avoidance.

Pinning **still occurs** with:

- Long native/JNI/FFM blocking calls
- Class loading during execution
- Certain local I/O operations

```java
// ⚠️ No longer pins in Java 25, but still causes contention under load
synchronized (lock){

executeBlockingNetworkCall();
}

// ✅ ReentrantLock — better concurrency, bounded waits, no contention
private final ReentrantLock lock = new ReentrantLock();

public void processPayment() {
    lock.lock();
    try {
        executeBlockingNetworkCall();
    } finally {
        lock.unlock();
    }
}
```

Detect residual pinning: JFR event `jdk.VirtualThreadPinned`, `jdk.VirtualThreadSubmitFailed` (JDK 25), or
`-Djdk.tracePinnedThreads=full` in dev.

## Resource Limits

With Virtual Threads, the bottleneck migrates from thread pool size to downstream resources:

- **JDBC connection pool** — HikariCP `maximumPoolSize` becomes the real limiter
- **HTTP client pools** — max connections per route
- **Message brokers** — consumer/producer concurrency limits
- **File descriptors** — OS-level limits under thousands of concurrent VTs
- **Rate limits** — external API throttling

```java
// ✅ Semaphore to protect downstream resource
private final Semaphore dbPermits = new Semaphore(50);

public Result query(String sql) throws InterruptedException {
    dbPermits.acquire();
    try {
        return jdbcTemplate.queryForObject(sql, Result.class);
    } finally {
        dbPermits.release();
    }
}
```

Always verify pool capacities and add explicit backpressure when using VTs at scale.

## Cancellation and Interruption

```java
// ❌ Swallowing InterruptedException
try{
blockingCall();
}catch(
InterruptedException e){
        // silently ignored — BAD
        }

// ✅ Restore interrupt status or propagate
        try{

blockingCall();
}catch(
InterruptedException e){
        Thread.

currentThread().

interrupt();
    throw new

ServiceException("Interrupted during blocking call",e);
}
```

## Gotchas

- **Never pool VTs** — spawn per task (`Thread.ofVirtual().start` or `newVirtualThreadPerTaskExecutor`).
- **Carrier monopolization** — pure CPU on a VT starves the carrier; yield or move to platform threads.
- **Resource exhaustion** — VTs make it trivial to spawn thousands of tasks; ensure downstream systems can handle the
  load.
- **Dumps** — `jstack` omits VTs by default:
  ```bash
  jcmd <PID> Thread.dump_to_file -format=json <FILE>
  ```

## Request context: ScopedValue over ThreadLocal

`ScopedValue` (JEP 506, final) is stable in Java 25. Prefer it for immutable request-scoped data across VTs.

```java
// ❌ ThreadLocal — leak-prone at VT scale
public static final ThreadLocal<UserContext> HOLDER = new ThreadLocal<>();

// ✅ ScopedValue — auto-unbind, no cleanup
public static final ScopedValue<UserContext> CONTEXT = ScopedValue.newInstance();

public void handle(UserContext ctx) {
    ScopedValue.where(CONTEXT, ctx).run(this::process);
}

// Acceptable fallback only when mutability is required
try{
        currentUser.

set(user);

process();
}finally{
        currentUser.

remove();
}
```

### ThreadLocal as cache — PROHIBITED with Virtual Threads

`ThreadLocal` as a per-thread cache becomes catastrophic with VTs: each of thousands/millions of VTs initializes its own
cache instance, causing 2000x+ initialization overhead and GC pressure. Use application-scoped caches or explicit pools
instead.

```java
// ❌ ThreadLocal cache with VTs — memory explosion
private static final ThreadLocal<DateFormat> FORMAT_CACHE =
        ThreadLocal.withInitial(() -> new SimpleDateFormat("yyyy-MM-dd"));

// ✅ Application-scoped cache or pool
private static final DateTimeFormatter FORMAT = DateTimeFormatter.ofPattern("yyyy-MM-dd");
```

## Virtual Thread Performance Qualification

Migration recommendations for performance are ONLY valid with measured evidence:

1. Representative benchmark comparing VTs vs current pools
2. Metrics: throughput, avg latency, p95/p99, CPU, heap, native memory
3. Vary load levels: low, medium, high, peak
4. JFR with `jdk.VirtualThreadPinned` and `jdk.VirtualThreadSubmitFailed` events
5. Thread dumps via `jcmd <PID> Thread.dump_to_file -format=json <FILE>`
6. Third-party benchmarks or theory do NOT substitute real-environment measurement

## Fire-and-forget

```java
Thread.ofVirtual().

name("io-task-",0).

start(() ->

blockingIoCall());
```

For many tasks with lifecycle bound to a method, prefer:

```java
try(var executor = Executors.newVirtualThreadPerTaskExecutor()){
        // submit work; close waits for completion
        }
```
