# Classic Concurrency Issues

Load for races, visibility, deadlocks, DCL, explicit locks, concurrent collections, and interruption handling.

---

## 1. Check-Then-Act (Race Condition)

```java
// ❌ Non-atomic compound check-then-act
if(!map.containsKey(key)){
        map.

put(key, computeValue());
        }

// ✅ Atomic
        map.

computeIfAbsent(key, k ->

computeValue());

// ❌ Non-atomic counter gate
        if(count<MAX){count++;}

// ✅ Atomic update
AtomicInteger count = new AtomicInteger();
count.

updateAndGet(c ->c<MAX ?c +1:c);
```

---

## 2. Visibility & Weak Memory Models (x86 vs ARM)

The JMM defines abstract visibility rules; hardware enforces different physical orderings.

```java
// ❌ Implicit reliance on x86 TSO
private boolean ready; // non-volatile
private int data;

// Producer
data =42;
ready =true;

// Consumer
        if(ready){
        System.out.

println(data); // on ARM64, ready may be true while data still reads 0
}

// ✅ volatile creates a happens-before relationship on every architecture
private volatile boolean ready;
```

> **Hardware trap:** code that passes on x86 workstations can expose reordering bugs on ARM (AWS Graviton, Apple
> Silicon) (Evans et al., Ch. 7 & 13).

---

## 3. Non-Atomic Compound Updates on `long` / `double`

`counter++` is read-modify-write and is never atomic. Additionally, non-`volatile` `long`/`double` reads and writes are
not guaranteed atomic by the JMM.

```java
// ❌
private long counter;

public void increment() {
    counter++;
}

// ✅
private final AtomicLong counter = new AtomicLong();

public void increment() {
    counter.incrementAndGet();
}
```

---

## 4. High Contention CAS Loops vs `LongAdder`

```java
// ❌ under high contention the CAS loop spins and burns CPU
private final AtomicLong totalRequests = new AtomicLong();

// ✅ LongAdder spreads updates across cells
private final LongAdder totalRequests = new LongAdder();

public void recordRequest() {
    totalRequests.increment();
}

public long total() {
    return totalRequests.sum();
}
```

> For statistics, metrics and throughput counters where reads are far rarer than writes (Evans et al., Ch. 13).
> Never as a financial balance.

---

## 5. Cache Line False Sharing

Independent fields mutated by different threads on the same 64-byte cache line cause coherence traffic and severe
slowdown.

```java
// ❌ head and tail share a cache line
public class RingBuffer {
    private volatile long head; // producer
    private volatile long tail; // consumer
}
```

> **Out of baseline:** `@jdk.internal.vm.annotation.Contended` is an **internal JDK API**. Using it from application
> code requires `-XX:-RestrictContended` **and** `--add-exports java.base/jdk.internal.vm.annotation=ALL-UNNAMED`,
> which violates the "stable APIs, no special flags" rule of this project. Do not recommend it.
>
> Within the baseline: redesign so the hot fields live on separate objects (the allocator usually separates them), or
> pad manually with filler fields, and only after measuring that false sharing is the actual bottleneck.

---

## 6. Double-Checked Locking (DCL)

```java
// ✅ PREFERRED — initialization-on-demand holder (no volatile, no sync)
private static class Holder {
    static final Singleton INSTANCE = new Singleton();
}

public static Singleton getInstance() {
    return Holder.INSTANCE;
}

// If DCL is unavoidable, the field MUST be volatile
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
```

---

## 7. Cooperative Shutdown

```java
public class ServerWorker implements Runnable {
    private volatile boolean running = true;

    @Override
    public void run() {
        try {
            while (running && !Thread.currentThread().isInterrupted()) {
                processNextTask();
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt(); // restore before exiting
        } finally {
            cleanupResources();
        }
    }

    public void stop() {
        this.running = false;
        // interrupt the worker as well if it may be parked in a blocking call
    }
}
```

`volatile` gives visibility and simple signalling only — it does not make compound operations atomic.

---

## 8. Spinning vs Parking

```java
// ❌ busy wait for long or unknown durations — burns a core, starves carriers
while(!condition){}

// ✅ spin hint for ultra-short, bounded waits
        while(!lock.

compareAndSet(false,true)){
        Thread.

onSpinWait();
}

// ✅ parking for unknown or longer waits — always in a loop (park can return spuriously)
        while(!condition){
        LockSupport.

park(this);
}
```

1. **Spin (`Thread.onSpinWait()`)**: only when hold time is guaranteed shorter than a context switch.
2. **Park (`LockSupport.park` / `ReentrantLock` / `Condition`)**: whenever the wait is unknown or longer. Prefer the
   higher-level `Condition.await(timeout)` in application code.

---

## 9. ReentrantLock — Acquire/Release Order

```java
// ❌ lock() inside try — if lock() throws, unlock() runs without ownership
try{
        lock.lock();

process();
}finally{
        lock.

unlock();
}

// ✅ lock() BEFORE try; unlock() ONLY in finally
        lock.

lock();
try{

process();
}finally{
        lock.

unlock();
}

// ✅ Bounded wait
        if(!lock.

tryLock(5,TimeUnit.SECONDS)){   // method must declare InterruptedException
        throw new

LockAcquisitionException("Could not acquire lock within timeout"); // unchecked, domain-specific
}
        try{

process();
}finally{
        lock.

unlock();
}
```

> `java.util.concurrent.TimeoutException` is **checked** — throwing it from a method that does not declare it does not
> compile. Use a domain runtime exception here.

Never hold a lock while calling network, database, broker or unknown callback code.

---

## 10. Deadlock — Lock Ordering

```java
// ❌ inconsistent acquisition order
synchronized (from){synchronized (to){ /* transfer */ }}

// ✅ total ordering by stable ID
Account first = from.getId() < to.getId() ? from : to;
Account second = from.getId() < to.getId() ? to : from;
synchronized (first){
synchronized (second){ /* transfer */ }
        }
```

In-memory transfer locking is illustrative only — money still requires database-level concurrency control
(`references/financial-consistency.md`).

---

## 11. Interruption Handling

```java
// ❌ Swallowing
try{Thread.sleep(1000); }catch(
InterruptedException e){}

// ✅ Restore then handle
        try{
        Thread.

sleep(1000);
}catch(
InterruptedException e){
        Thread.

currentThread().

interrupt();
    throw new

ServiceException("Interrupted",e);
}

// ✅ Propagate when the signature allows (cleanest)
public void process() throws InterruptedException {
    blockingCall();
}
```

> Swallowing breaks `Future.cancel(true)` and cooperative shutdown.

---

## 12. Thread-Safe Collections

| Use Case                       | Wrong       | Right                     |
|--------------------------------|-------------|---------------------------|
| Concurrent map                 | `HashMap`   | `ConcurrentHashMap`       |
| Rare writes, lots of iteration | CHM         | `CopyOnWriteArrayList`    |
| Producer-consumer              | `ArrayList` | `BlockingQueue` (bounded) |
| Sorted concurrent map          | `TreeMap`   | `ConcurrentSkipListMap`   |

---

## 13. ConcurrentHashMap

```java
// ❌ compound non-atomic
if(!map.containsKey(key))map.

put(key, value);

// ✅ atomic
map.

putIfAbsent(key, value);
map.

computeIfAbsent(key, k ->

createValue());
        map.

merge(key, newValue, mergeFn);

// ❌ nested compute — non-atomic state, reentrancy risk, possible deadlock. PROHIBITED.
map.

compute(key1, (k, v) ->map.

compute(key2, ...));
```

Keep mapping functions short and side-effect free: they run while holding a bin lock. Never perform I/O inside them.

> `size()` and `isEmpty()` are **estimates** under contention. Never use them for strict control or financial gates.

---

## 14. Stale Reference After Eviction

```java
// ❌ value may be removed between get() and use
Object value = cache.get(key);
if(value !=null){

process(value); }

// ✅ atomic get-or-create
Object value = cache.computeIfAbsent(key, this::loadFromSource);
```

---

## 15. Flags

- Check-then-act without atomicity
- Missing `volatile` where visibility is assumed (x86 passes, ARM fails)
- `long` / `double` mutated by multiple threads without atomics or sync
- High-contention counters on `AtomicLong` instead of `LongAdder`
- `jdk.internal.*` annotations or APIs (out of baseline)
- DCL without `volatile`
- `lock.lock()` inside `try`
- Checked `TimeoutException` thrown from a method that does not declare it
- Inconsistent lock acquisition order
- Lock held across network / DB / broker / unknown callback
- `InterruptedException` swallowed
- Non-thread-safe collection shared across threads
- Nested `ConcurrentHashMap.compute`, or I/O inside a mapping function
- Control or financial logic gated on `ConcurrentHashMap.size()` / `isEmpty()`
- Busy-wait without `onSpinWait()`; `park()` outside a loop

---

## 16. References & Citations

- **Evans, B. J., Gough, J., & Newland, C.** (2024). *Optimizing Cloud Native Java*. O'Reilly Media. (Ch. 7, 13).
- **Rahman, A.N.M. Bazlur** (2026). *Modern Concurrency in Java*. O'Reilly Media. (Ch. 3).
