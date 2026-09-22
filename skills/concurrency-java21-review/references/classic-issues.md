# Classic Concurrency Issues

Load for races, visibility, deadlocks, DCL, explicit locks, concurrent collections, and interruption handling.

---

## 1. Check-Then-Act (Race Condition)

```java
// ❌ Non-atomic compound check-then-act on shared state
if (!map.containsKey(key)) {
    map.put(key, computeValue()); // another thread may insert between check and put
}

// ✅ Atomic
map.computeIfAbsent(key, k -> computeValue());

// ❌ Non-atomic counter gate
if (count < MAX) {
    count++;
}

// ✅ Atomic update
AtomicInteger count = new AtomicInteger();
count.updateAndGet(c -> c < MAX ? c + 1 : c);
```

---

## 2. Visibility & Weak Memory Models (x86 vs. ARM)

The Java Memory Model (JMM) defines abstract visibility rules, but underlying hardware architectures enforce different physical memory ordering.

```java
// ❌ Implicit reliance on x86 TSO (Total Store Order)
// On x86 (Intel/AMD), hardware prohibits store-store reordering, masking missing volatile annotations.
// On ARM64 (e.g., AWS Graviton, Apple Silicon), weak hardware memory ordering permits aggressive load/store reordering.
private boolean ready; // non-volatile
private int data;

// Thread 1 (Producer)
data = 42;
ready = true;

// Thread 2 (Consumer)
if (ready) {
    System.out.println(data); // On ARM, ready can be seen as true while data is still read as 0!
}

// ✅ Explicit volatile field creates a JMM happens-before relationship across ALL hardware architectures
private volatile boolean ready;
```

> **Hardware Trap:** Code passing tests on x86 developer workstations can silently expose visibility and reordering bugs when deployed on ARM architecture (AWS Graviton) due to weaker hardware store/load ordering guarantees (Evans et al., 2024, Ch. 7 & 13).

---

## 3. Non-Atomic Long/Double Counter

On 32-bit JVMs and in some JMM scenarios, reads/writes to `long` and `double` are not guaranteed atomic.

```java
// ❌ Non-atomic on some platforms; not thread-safe
private long counter;
public void increment() { counter++; } // read-modify-write is not atomic

// ✅
private final AtomicLong counter = new AtomicLong();
public void increment() { counter.incrementAndGet(); }
```

---

## 4. High Contention CAS Loops vs. LongAdder

`AtomicInteger` and `AtomicLong` use Compare-And-Swap (CAS) spin loops (`compareAndSet`). Under high thread contention, CAS operations repeatedly fail and retry, causing linear CPU throughput degradation.

```java
// ❌ Under high multi-thread contention, AtomicLong CAS loop spins continuously, wasting CPU cycles
private final AtomicLong totalRequests = new AtomicLong();
public void recordRequest() {
    totalRequests.incrementAndGet(); // continuous CAS retries under high concurrency
}

// ✅ LongAdder distributes counters across internal cell arrays, eliminating CAS contention
private final LongAdder totalRequests = new LongAdder();
public void recordRequest() {
    totalRequests.increment(); // extremely fast under high thread contention
}
public long getTotal() {
    return totalRequests.sum(); // sums cells when requested
}
```

> **Recommendation:** Use `LongAdder` or `LongAccumulator` for high-concurrency statistics, metrics, and throughput counters where reads are far less frequent than writes (Evans et al., 2024, Ch. 13).

---

## 5. Cache Line False Sharing

CPU cores cache memory in cache lines (typically 64 bytes). When independent variables mutated by different threads reside on the same 64-byte cache line, modifying one field invalidates the entire cache line in other CPU cores' L1/L2 caches (cache coherence traffic), causing severe performance degradation.

```java
// ❌ False sharing: head and tail live on the same 64-byte cache line
public class RingBuffer {
    private volatile long head; // modified by Producer thread
    private volatile long tail; // modified by Consumer thread
}

// ✅ Use @Contended (or manual padding) to isolate hot fields onto dedicated cache lines
public class RingBuffer {
    @jdk.internal.vm.annotation.Contended
    private volatile long head;

    @jdk.internal.vm.annotation.Contended
    private volatile long tail;
}
```

> **Note:** Using `@jdk.internal.vm.annotation.Contended` in application code requires the JVM flag `-XX:-RestrictContended` (Evans et al., 2024, Ch. 7).

---

## 6. Double-Checked Locking (DCL)

```java
// ❌ Without volatile — partial construction visible to other threads
private static Singleton instance;

// ✅ Volatile field prevents partial construction visibility
private static volatile Singleton instance;

public static Singleton getInstance() {
    if (instance == null) {
        synchronized (Singleton.class) {
            if (instance == null) {
                instance = new Singleton();
            }
        }
    }
    return instance;
}

// ✅ PREFERRED — initialization-on-demand holder (no volatile, no sync overhead)
private static class Holder {
    static final Singleton INSTANCE = new Singleton();
}

public static Singleton getInstance() {
    return Holder.INSTANCE;
}
```

---

## 7. Volatile Graceful Shutdown Pattern

For worker threads running task loops, use a `volatile` flag coupled with interrupt checks to ensure cooperative, timely shutdown without leaving resources in an inconsistent state.

```java
// ✅ Standard volatile shutdown flag + interrupt propagation
public class ServerWorker implements Runnable {
    private volatile boolean running = true;

    @Override
    public void run() {
        while (running && !Thread.currentThread().isInterrupted()) {
            try {
                processNextTask();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt(); // restore flag to break loop
            }
        }
        cleanupResources();
    }

    public void stop() {
        this.running = false;
        // Optional: interrupt to wake worker if sleeping or waiting in blocking I/O
    }
}
```

> Ensure the worker loop checks both `running` and `!Thread.currentThread().isInterrupted()` to handle both cooperative stop signals and thread pool cancellation (Evans et al., 2024, Ch. 13 & Rahman, 2026, Ch. 3).

---

## 8. Spinlocks (`Thread.onSpinWait()`) vs. Thread Parking (`LockSupport.park()`)

Choosing between busy-waiting (spinlocks) and sleeping/parking threads directly impacts CPU utilization and thread responsiveness.

```java
// ❌ Spinlock for long or unknown durations consumes 100% CPU core power and starves carrier threads
while (!condition) {
    // busy waiting without yielding or parking
}

// ✅ Spinlock with CPU hint for ultra-short, bounded wait durations
while (!lock.compareAndSet(false, true)) {
    Thread.onSpinWait(); // CPU hint to optimize power and execution pipeline (Java 9+)
}

// ✅ Thread parking for unknown or longer wait durations
LockSupport.park(this);
```

### Selection Guidelines
1. **Spinlocks (`Thread.onSpinWait()`):** Acceptable ONLY when lock hold time is guaranteed to be extremely short (< expected thread context switch latency, typically < 100 ns). Avoids context switch overhead.
2. **Thread Parking (`LockSupport.park()` / `ReentrantLock`):** Required when wait duration is unknown or > 1 µs. Relinquishes CPU cores to the OS scheduler or Virtual Thread carrier pool, preventing CPU starvation (Evans et al., 2024, Ch. 13).

---

## 9. ReentrantLock — Acquire/Release Order

```java
// ❌ lock() inside try — if lock() throws, unlock() runs but lock was never acquired
try {
    lock.lock();
    process();
} finally {
    lock.unlock();
}

// ✅ lock() BEFORE try; unlock() ONLY in finally
lock.lock();
try {
    process();
} finally {
    lock.unlock();
}

// ✅ Bounded wait — avoids indefinite blocking and enables deadlock avoidance
if (!lock.tryLock(5, TimeUnit.SECONDS)) {
    throw new TimeoutException("Could not acquire lock within timeout");
}
try {
    process();
} finally {
    lock.unlock();
}
```

---

## 10. Deadlock — Lock Ordering

```java
// ❌ Inconsistent acquisition order — classic deadlock with two threads
synchronized (from) {
    synchronized (to) { /* transfer */ }
}

// ✅ Total ordering by stable ID — always acquire locks in the same global order
Account first  = from.getId() < to.getId() ? from : to;
Account second = from.getId() < to.getId() ? to : from;
synchronized (first) {
    synchronized (second) { /* transfer */ }
}
```

---

## 11. Interruption Handling

```java
// ❌ Swallowing InterruptedException — breaks cancellation contracts
try {
    Thread.sleep(1000);
} catch (InterruptedException e) {
    // silently ignored — WRONG
}

// ✅ Restore interrupt status, then handle (or rethrow wrapped)
try {
    Thread.sleep(1000);
} catch (InterruptedException e) {
    Thread.currentThread().interrupt();         // restore interrupt flag
    throw new ServiceException("Interrupted", e);
}

// ✅ Propagate directly when method signature allows (cleanest)
public void process() throws InterruptedException {
    blockingCall();
}
```

> Never swallow `InterruptedException`. Either restore the interrupt flag and handle, or propagate. Swallowing breaks
> `Future.cancel(true)` and cooperative shutdown.

---

## 12. Thread-Safe Collections

| Use Case                        | Wrong        | Right                    |
|---------------------------------|--------------|--------------------------|
| Concurrent map                  | `HashMap`    | `ConcurrentHashMap`      |
| Rare writes, lots of iteration  | CHM          | `CopyOnWriteArrayList`   |
| Producer-consumer               | `ArrayList`  | `BlockingQueue`          |
| Sorted concurrent map           | `TreeMap`    | `ConcurrentSkipListMap`  |

---

## 13. ConcurrentHashMap

```java
// ❌ Compound non-atomic — race between check and put
if (!map.containsKey(key)) map.put(key, value);

// ✅ Atomic alternatives
map.putIfAbsent(key, value);
map.computeIfAbsent(key, k -> createValue());
map.merge(key, newValue, mergeFn);

// ❌ Nested compute — non-atomic state and reentrant access risk
//    May produce inconsistent state; some implementations can deadlock on same segment.
//    PROHIBITED in production code.
map.compute(key1, (k, v) -> map.compute(key2, ...));
```

> `size()` and `isEmpty()` are **estimates** under contention. Never use them for strict control or financial gates.

---

## 14. Stale Reference After Eviction / Cache Invalidation

```java
// ❌ Cache returns a stale entry that was concurrently removed
Object value = cache.get(key);
if (value != null) {
    process(value); // value may have been removed between get() and use
}

// ✅ Use computeIfAbsent for atomic get-or-create
Object value = cache.computeIfAbsent(key, k -> loadFromSource(k));
```

---

## 15. Flags

- Check-then-act on shared state without atomicity
- Code relying on x86 TSO memory model breaking under ARM architecture (missing `volatile`)
- `long` / `double` field mutated by multiple threads without `AtomicLong` or sync
- High-contention counters using `AtomicLong` instead of `LongAdder` / `LongAccumulator`
- Hot shared fields causing cache line false sharing without padding or `@Contended`
- Busy-waiting spin loops without `Thread.onSpinWait()` or parking (`LockSupport.park()`)
- DCL without `volatile`
- `lock.lock()` inside `try` block instead of before it
- Inconsistent lock acquisition order (deadlock risk)
- `synchronized` calling external/unknown code (deadlock risk)
- `InterruptedException` swallowed (no `interrupt()` restore, no rethrow)
- Non-thread-safe collection (`HashMap`, `ArrayList`) accessed from multiple threads
- Nested `ConcurrentHashMap.compute` (prohibited)
- Financial or control logic gated on `ConcurrentHashMap.size()` / `isEmpty()`

---

## 16. References & Citations

- **Evans, B. J., Gough, J., & Newland, C.** (2024). *Optimizing Cloud Native Java: Efficient Microservices in Kubernetes and Cloud Environments*. O'Reilly Media. (Chapters 7, 13).
- **Rahman, A.N.M. Bazlur** (2026). *Modern Concurrency in Java: Multi-threading, Virtual Threads, and Structured Concurrency*. O'Reilly Media. (Chapter 3).
