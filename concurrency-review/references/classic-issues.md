# Classic Concurrency Issues

Load for races, visibility, deadlocks, DCL, explicit locks, concurrent collections, and interruption handling.

## Check-then-act

```java
// ❌
if(!map.containsKey(key)){
        map.

put(key, computeValue());
        }

// ✅
        map.

computeIfAbsent(key, k ->

computeValue());

// ❌ counter
        if(count<MAX){
count++;
        }

// ✅
AtomicInteger count = new AtomicInteger();
count.

updateAndGet(c ->c<MAX ?c +1:c);
```

## Visibility

```java
// ❌ other threads may never see false
private boolean running = true;

// ✅
private volatile boolean running = true;
```

## Non-atomic long counter

```java
// ❌
private long counter;

public void increment() {
    counter++;
}

// ✅
private final AtomicLong counter = new AtomicLong();
```

## Double-checked locking

```java
// ❌ without volatile — partial construction
private static Singleton instance;

// ✅
private static volatile Singleton instance;

// ✅ preferred — holder idiom
private static class Holder {
    static final Singleton INSTANCE = new Singleton();
}

public static Singleton getInstance() {
    return Holder.INSTANCE;
}
```

## ReentrantLock acquire order

```java
// ❌ unlock if lock() throws
try{
        lock.lock();

process();
}finally{
        lock.

unlock();
}

// ✅
        lock.

lock();
try{

process();
}finally{
        lock.

unlock();
}
```

Prefer `tryLock(timeout, unit)` when deadlock avoidance or bounded wait is required.

## Deadlock — lock ordering

```java
// ❌ inconsistent order
synchronized (from){
synchronized (to){ /* transfer */ }
        }

// ✅ stable order by id
Account first = from.getId() < to.getId() ? from : to;
Account second = from.getId() < to.getId() ? to : from;
synchronized (first){
synchronized (second){ /* transfer */ }
        }
```

## Interruption handling

```java
// ❌ Swallowing InterruptedException — breaks cancellation contracts
try{
        Thread.sleep(1000);
}catch(
InterruptedException e){
        // silently ignored
        }

// ✅ Restore interrupt status
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

// ✅ Propagate directly when method signature allows
public void process() throws InterruptedException {
    blockingCall();
}
```

Never swallow `InterruptedException`. Either restore the interrupt flag and handle, or propagate.

## Thread-safe collections

| Use case                       | Wrong       | Right                   |
| ------------------------------ | ----------- | ----------------------- |
| Concurrent map                 | `HashMap`   | `ConcurrentHashMap`     |
| Rare writes, lots of iteration | CHM         | `CopyOnWriteArrayList`  |
| Producer-consumer              | `ArrayList` | `BlockingQueue`         |
| Sorted concurrent map          | `TreeMap`   | `ConcurrentSkipListMap` |

### ConcurrentHashMap

```java
// ❌ compound non-atomic
if(!map.containsKey(key))map.

put(key, value);

// ✅
map.

putIfAbsent(key, value);
map.

computeIfAbsent(key, k ->

createValue());

// ❌ nested compute — non-atomic state and reentrant access risk
//    May produce inconsistent state; in some implementations can deadlock
//    on the same segment. PROHIBITED in production code.
        map.

compute(key1, (k, v) ->map.

compute(key2, ...));
```

> `size()` and `isEmpty()` are estimates under contention. Never use them for strict control or financial gates.
