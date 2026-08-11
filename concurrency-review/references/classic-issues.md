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

## 2. Visibility

```java
// ❌ Other threads may never see the updated value (no happens-before guarantee)
private boolean running = true;

// ✅
private volatile boolean running = true;
```

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

## 4. Double-Checked Locking (DCL)

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

## 5. ReentrantLock — Acquire/Release Order

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

## 6. Deadlock — Lock Ordering

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

## 7. Interruption Handling

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

## 8. Thread-Safe Collections

| Use Case                        | Wrong        | Right                    |
|---------------------------------|--------------|--------------------------|
| Concurrent map                  | `HashMap`    | `ConcurrentHashMap`      |
| Rare writes, lots of iteration  | CHM          | `CopyOnWriteArrayList`   |
| Producer-consumer               | `ArrayList`  | `BlockingQueue`          |
| Sorted concurrent map           | `TreeMap`    | `ConcurrentSkipListMap`  |

---

## 9. ConcurrentHashMap

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

## 10. Stale Reference After Eviction / Cache Invalidation

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

## 11. Flags

- Check-then-act on shared state without atomicity
- `long` / `double` field mutated by multiple threads without `AtomicLong` or sync
- DCL without `volatile`
- `lock.lock()` inside `try` block instead of before it
- Inconsistent lock acquisition order (deadlock risk)
- `synchronized` calling external/unknown code (deadlock risk)
- `InterruptedException` swallowed (no `interrupt()` restore, no rethrow)
- Non-thread-safe collection (`HashMap`, `ArrayList`) accessed from multiple threads
- Nested `ConcurrentHashMap.compute` (prohibited)
- Financial or control logic gated on `ConcurrentHashMap.size()` / `isEmpty()`
