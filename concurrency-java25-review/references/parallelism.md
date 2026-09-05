# Parallelism (CPU-bound) on Java 25

Load when the work is compute-heavy, uses `parallelStream()`, `ForkJoinPool`, `RecursiveTask`, or someone proposed Virtual Threads for CPU work.

Concurrency = overlapping I/O waits. Parallelism = simultaneous use of multiple cores. Virtual Threads help the first. They do not speed up the second.

---

## 1. Default mapping

| Work | Pool | Why |
|------|------|-----|
| Blocking I/O | Virtual Threads, one per task | Carriers unmount during wait |
| CPU-bound (crypto, scoring, image, aggregation) | Sized platform pool or `ForkJoinPool` | Needs real cores; VTs monopolize carriers |
| Mixed | VT coordinates I/O; submit CPU bursts to FJP | Keeps carriers available |

The VT scheduler is a **dedicated** `ForkJoinPool`. It is **not** `ForkJoinPool.commonPool()`. Tuning `-Djava.util.concurrent.ForkJoinPool.common.parallelism` does not change VT carriers. Tune carriers with `-Djdk.virtualThreadScheduler.parallelism` and `-Djdk.virtualThreadScheduler.maxPoolSize`.

---

## 2. ForkJoinPool usage

```java
// ✅ CPU work on commonPool or a dedicated FJP
ForkJoinPool pool = new ForkJoinPool(Math.max(2, Runtime.getRuntime().availableProcessors()));
try {
    return pool.submit(() -> items.parallelStream()
            .map(this::cpuTransform)
            .toList()).get(30, TimeUnit.SECONDS);
} finally {
    pool.shutdown();
}
```

Rules:

- Size FJP to cores visible in the container (`availableProcessors()` after CPU limits).
- Always bound `get` / `join` with timeout when the caller is a request thread.
- Do not run blocking I/O inside FJP tasks — that starves compute workers.
- Dedicated FJP when the job must not compete with `commonPool` users (`parallelStream` elsewhere, CF defaults).

---

## 3. `parallelStream()` — when it is wrong

```java
// ❌ blocking I/O on commonPool
items.parallelStream().map(this::httpCall).toList();

// ❌ tiny list — split overhead exceeds gain
List.of(a, b, c).parallelStream().map(this::cpuTransform).toList();

// ✅ I/O fan-out on VTs
try (var exec = Executors.newVirtualThreadPerTaskExecutor()) {
    var futures = items.stream().map(item -> exec.submit(() -> httpCall(item))).toList();
    return futures.stream().map(f -> {
        try {
            return f.get(5, TimeUnit.SECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        } catch (ExecutionException | TimeoutException e) {
            throw new IllegalStateException(e);
        }
    }).toList();
}
```

Use `parallelStream()` only for CPU work on medium/large in-memory collections, after measuring. It has no custom executor, no per-task timeout, and no terminal error handler.

---

## 4. CPU on a Virtual Thread

VTs are not preempted. A long CPU loop holds the carrier.

```java
// ❌ carrier hog
items.forEach(this::expensiveTransform);

// ✅ yield so other VTs can be mounted
for (int i = 0; i < items.size(); i++) {
    expensiveTransform(items.get(i));
    if (i % 100 == 0) {
        Thread.yield();
    }
}

// ✅ better — move the burst off the VT
CompletableFuture.supplyAsync(() -> expensiveTransform(item), ForkJoinPool.commonPool())
        .orTimeout(10, TimeUnit.SECONDS)
        .join();
```

---

## 5. Counters under high write contention

`AtomicLong` CAS loops waste CPU when many threads update the same counter. Use `LongAdder` / `LongAccumulator` for metrics and throughput counters where reads are rare.

Do not use adders as financial balances — they are not a substitute for `@Version` or atomic SQL.

---

## 6. Amdahl gate

Do not add a thread pool because the code "looks slow". Estimate the serial fraction (locks, single-row DB, JSON parse on one thread). If serial work dominates, extra workers add coordination cost and no latency win.

Qualify parallelism with the same evidence bar as VT migration — throughput, p95/p99, CPU, and downstream wait. Never compare against an undersized baseline.

---

## 7. Flags

- VTs recommended for CPU-bound work
- `parallelStream()` over blocking I/O
- `parallelStream()` on tiny collections
- Blocking I/O submitted to `ForkJoinPool.commonPool`
- `commonPool` tuned as if it were the VT scheduler
- AtomicLong hot counter under high contention (prefer LongAdder for stats)
- Parallelism added without measuring the serial fraction

---

## 8. References

- Rahman, A.N.M. Bazlur. *Modern Concurrency in Java*. O'Reilly Media, 2026.
- Evans, Benjamin J., James Gough, and Chris Newland. *Optimizing Cloud Native Java*. O'Reilly Media, 2024.
