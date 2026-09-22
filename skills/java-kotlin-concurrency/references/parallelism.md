# Parallelism (CPU-bound) on Java 25

Load when the work is compute-heavy, uses `parallelStream()`, `ForkJoinPool`, `RecursiveTask`, or someone proposed
Virtual Threads for CPU work.

Concurrency = overlapping I/O waits. Parallelism = simultaneous use of multiple cores. Virtual Threads help the first.
They do not speed up the second.

---

## 1. Default mapping

| Work                                            | Executor                                               | Why                                       |
|-------------------------------------------------|--------------------------------------------------------|-------------------------------------------|
| Blocking I/O                                    | Virtual Threads, one per task                          | Carriers unmount during wait              |
| CPU-bound (crypto, scoring, image, aggregation) | Dedicated sized platform executor                      | Needs real cores; VTs monopolize carriers |
| Recursive divide-and-conquer, pure compute      | Dedicated `ForkJoinPool` (managed singleton)           | Work-stealing fits the shape              |
| Mixed                                           | VT coordinates I/O; CPU burst goes to the CPU executor | Keeps carriers available                  |

The VT scheduler is a **dedicated** `ForkJoinPool`, not `ForkJoinPool.commonPool()`. Tuning
`-Djava.util.concurrent.ForkJoinPool.common.parallelism` does not change VT carriers. Tune carriers with
`-Djdk.virtualThreadScheduler.parallelism` / `maxPoolSize`, and only after measurement.

---

## 2. The default CPU executor

```java

@Bean(destroyMethod = "shutdown")
public ExecutorService cpuExecutor(MeterRegistry registry) {
    int cores = Math.max(2, Runtime.getRuntime().availableProcessors()); // container-visible CPUs, not host CPUs
    var exec = new ThreadPoolExecutor(
            cores, cores,
            0L, TimeUnit.MILLISECONDS,
            new ArrayBlockingQueue<>(256),                 // bounded queue: saturation is observable
            Thread.ofPlatform().name("cpu-", 0).factory(), // named for diagnostics
            new ThreadPoolExecutor.AbortPolicy());         // explicit rejection policy
    new ExecutorServiceMetrics(exec, "cpu-executor", List.of()).bindTo(registry);
    return exec;
}
```

Rules:

- **One managed instance**, injected. Never create an executor or a `ForkJoinPool` per call: under load that spawns one
  pool per in-flight request.
- Size by the CPUs visible **inside the container** (set `limits.cpu`; see `cloud-native-concurrency.md`).
- Always bound `get` / `join` with a timeout when the caller is a request thread, and `cancel(true)` on timeout —
  `shutdown()` in a `finally` does not stop a running task.
- Do not run blocking I/O inside CPU-executor or FJP tasks — it starves compute workers.

### 2.1 `ForkJoinPool.commonPool()` — why it is not the CPU executor

`commonPool` parallelism defaults to `availableProcessors() - 1`. In a 1-CPU container that is **0**, and the pool
executes tasks **in the calling thread**. "Delegating CPU work to the common pool" from a virtual thread then does
nothing at all: the work stays on the VT and still hogs the carrier. It is also shared with every `parallelStream()` and
default `*Async` stage in the JVM.

---

## 3. `parallelStream()` — when it is wrong

```java
// ❌ blocking I/O on commonPool
items.parallelStream().

map(this::httpCall).

toList();

// ❌ tiny list — split overhead exceeds gain
List.

of(a, b, c).

parallelStream().

map(this::cpuTransform).

toList();

// ✅ I/O fan-out on VTs, with cancellation (see virtual-threads.md §3.1)
List<Future<Item>> pending = new ArrayList<>();
try(
var exec = Executors.newVirtualThreadPerTaskExecutor()){
        try{
        for(
Item item :items){
        pending.

add(exec.submit(() ->

httpCall(item)));
        }
List<Item> out = new ArrayList<>(pending.size());
        for(
Future<Item> f :pending){
        out.

add(f.get(5, TimeUnit.SECONDS));
        }
        return out;
    }catch(
InterruptedException e){
        Thread.

currentThread().

interrupt();
        throw new

ServiceException("fan-out interrupted",e);
    }catch(ExecutionException |
TimeoutException e){
        throw new

ServiceException("fan-out failed",e);
    }finally{
            pending.

forEach(f ->f.

cancel(true));
        }
        }
```

Use `parallelStream()` only for CPU work on medium/large in-memory collections, after measuring. It has no custom
executor, no per-task timeout and no terminal error handler.

> **Do not use the "submit the stream into your own ForkJoinPool" trick.** It relies on an implementation detail of how
> the stream picks up the ambient pool, gives no per-task timeout or error handling, and is usually paired with a pool
> created per call. If you need executor control, write the loop with an explicit executor instead.

---

## 4. CPU on a Virtual Thread

VTs are not time-sliced. A long CPU loop holds the carrier.

```java
// ❌ carrier hog
items.forEach(this::expensiveTransform);

// ✅ move the burst off the VT
Future<Result> f = cpuExecutor.submit(() -> expensiveTransform(item));
try{
        return f.

get(10,TimeUnit.SECONDS);
}catch(
InterruptedException e){
        Thread.

currentThread().

interrupt();
    f.

cancel(true);
    throw new

ServiceException("interrupted",e);
}catch(
TimeoutException e){
        f.

cancel(true);                     // orTimeout/get timeout does NOT stop the computation by itself
    throw new

ServiceException("cpu budget exceeded",e);
}catch(
ExecutionException e){
        throw new

ServiceException("cpu task failed",e.getCause());
        }
```

```java
// ⚠️ Exceptional stopgap only, documented in the code
for(int i = 0; i <items.

size();

i++){

expensiveTransform(items.get(i));
        if(i %100==0){
        Thread.

yield(); // hint only: no bound, no fairness guarantee, no extra parallelism
    }
            }
```

`Thread.yield()` does not limit anything, does not guarantee fairness, does not add cores, and has no effect inside
third-party code you cannot instrument. With N carriers, N CPU-bound VTs still saturate the machine. Treat it as a
temporary measure on a path you cannot refactor yet, never as the recommendation.

---

## 5. Counters under high write contention

`AtomicLong` CAS loops waste CPU when many threads update the same counter. Use `LongAdder` / `LongAccumulator` for
metrics and throughput counters where reads are rare.

Do not use adders as financial balances — they are not a substitute for `@Version` or atomic SQL.

---

## 6. Amdahl gate

Do not add a thread pool because the code "looks slow". Estimate the serial fraction (locks, single-row DB, JSON parse
on one thread). If serial work dominates, extra workers add coordination cost and no latency win.

Qualify parallelism with the same evidence bar as VT migration — throughput, p95/p99, CPU, downstream wait. Never
compare against an undersized baseline.

---

## 7. Flags

- VTs recommended for CPU-bound work
- CPU work "delegated" to `ForkJoinPool.commonPool()` (no-op on small containers)
- `Thread.yield()` presented as the standard answer for CPU on VTs
- `ForkJoinPool` / executor created per call instead of a managed singleton
- Timeout without `cancel(true)` on a running compute task
- `parallelStream()` over blocking I/O, or on tiny collections
- `commonPool` tuned as if it were the VT scheduler
- `AtomicLong` hot counter under high contention (prefer `LongAdder` for stats)
- Parallelism added without measuring the serial fraction

---

## 8. References

- Rahman, A.N.M. Bazlur. *Modern Concurrency in Java*. O'Reilly Media, 2026.
- Evans, Benjamin J., James Gough, and Chris Newland. *Optimizing Cloud Native Java*. O'Reilly Media, 2024.
