# Cloud-Native Concurrency

Load when reviewing Virtual Thread deployments on Kubernetes, GraalVM Native Image compatibility, container resource
configuration, or production observability for concurrent workloads.

---

## 1. Kubernetes: Memory Configuration with Virtual Threads

VT stacks live on the **Java heap**. Moving from platform threads to VTs shifts memory pressure from off-heap (outside
`-Xmx`) to the heap (inside `-Xmx`).

```yaml
# ❌ Same -Xmx as before the VT migration → OOM under peak load
resources:
  requests: { memory: "512Mi" }
  limits:   { memory: "512Mi" }
# JVM: -Xmx256m

# ✅ Room for VT stack frames at peak concurrency
resources:
  requests: { memory: "768Mi" }
  limits:   { memory: "768Mi" }
# JVM: -Xmx512m
```

**Rule of thumb:** start at roughly 1.5× the previous `-Xmx` when migrating under high concurrency, then tune on GC
pause frequency and heap utilization. Validate after migration — this is a measurement, not a constant.

---

## 2. Container-Aware Sizing

`Runtime.getRuntime().availableProcessors()` reflects the container's CPU allocation, not the host — **if** cgroup CPU
limits are set. Without limits the JVM sees every host CPU and over-provisions platform pools.

```yaml
# ✅ Set CPU limits so the JVM reads the correct processor count
resources:
  limits:   { cpu: "2" }
  requests: { cpu: "1" }
```

Size CPU executors and `ForkJoinPool` instances from `availableProcessors()` **inside** the container.

### Carrier tuning — only with evidence

VT carrier parallelism defaults to `availableProcessors()`, and `maxPoolSize` to 256:

```bash
-Djdk.virtualThreadScheduler.parallelism=<N>
-Djdk.virtualThreadScheduler.maxPoolSize=<N>
```

Do **not** set these preemptively. Change them only after measuring in a representative environment, with a specific
symptom to fix (for example `jdk.VirtualThreadSubmitFailed` events, or carriers idle while throughput is capped).
Setting parallelism above the container's CPU allocation adds contention and CPU throttling, not throughput.

---

## 3. Single-CPU Container Warning

Containers with 1 CPU or fractional CPUs commonly cause JVM ergonomics to select `SerialGC` on many distributions.

```yaml
# ❌ Single CPU → SerialGC, long STW pauses, no real parallelism
resources:
  limits:   { cpu: "1" }
  requests: { cpu: "500m" }

# ✅ >= 2 CPUs → G1GC with parallel collectors
resources:
  limits:   { cpu: "2" }
  requests: { cpu: "1" }
```

There is a second consequence specific to concurrency: with 1 CPU, `ForkJoinPool.commonPool()` has parallelism 0 and
runs tasks in the calling thread — any code that "offloads" CPU work to the common pool silently does nothing
(`references/parallelism.md` §2.1).

---

## 4. Liveness and Readiness Probes

Under low traffic a VT application can have every carrier idle. **Do not use platform thread activity as a liveness
signal.**

```yaml
# ✅ application-level health
livenessProbe:
  httpGet: { path: /actuator/health/liveness, port: 8080 }
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet: { path: /actuator/health/readiness, port: 8080 }
```

---

## 5. Horizontal Scaling vs VT Vertical Scaling

| Scaling Type         | When Appropriate                                       |
|----------------------|--------------------------------------------------------|
| **Vertical (VTs)**   | I/O-bound workloads; more concurrent requests per pod  |
| **Horizontal (HPA)** | CPU-bound workloads; geo-distribution; fault isolation |
| **Both**             | I/O-bound with high total throughput requirements      |

> VTs do not replace horizontal scaling, fault isolation, or database capacity. More in-flight requests per pod means
> more pressure on the same database.

---

## 6. GraalVM Native Image + Virtual Threads

| Constraint                                | Impact                                     | Mitigation                                    |
|-------------------------------------------|--------------------------------------------|-----------------------------------------------|
| Dynamic class loading during VT execution | May pin the carrier                        | Pre-load critical classes at startup          |
| JNI / native calls inside VTs             | Pin carriers (same as on the JVM)          | Minimize JNI on hot VT paths                  |
| AOT compilation (no JIT)                  | Faster startup; potentially lower peak TPS | Benchmark both modes; tune PGO                |
| Reflection / proxies                      | Must be declared in reachability metadata  | Capture with the native-image agent           |

```java
@EventListener(ApplicationReadyEvent.class)
public void warmUp() throws ClassNotFoundException {
    Class.forName("com.example.CriticalService");
    Class.forName("com.example.PaymentProcessor");
}
```

---

## 7. JFR in Production

```bash
java -XX:StartFlightRecording=name=production,\
     filename=/var/log/jfr/recording.jfr,\
     maxsize=500m,\
     maxage=1h,\
     settings=default \
     -jar your-app.jar
```

- **`maxage`** bounds retention by time; on its own it caps nothing in volume.
- **`maxsize`** bounds the ring buffer; oldest events are dropped when reached.

> **Critical:** continuous JFR with `maxage` and **without `maxsize`** can grow disk/off-heap during activity bursts and
> trigger container OOM-kills (Evans et al., Ch. 12). Always specify `maxsize`.

| Event                            | Priority | Alert on                                  |
|----------------------------------|----------|-------------------------------------------|
| `jdk.VirtualThreadSubmitFailed`  | Critical | Any occurrence (carrier pool exhausted)   |
| `jdk.VirtualThreadPinned`        | High     | Occurrences above 50 ms (default 20 ms)   |
| `jdk.MonitorEnter`               | Medium   | Long contention on hot monitors           |
| `jdk.GarbageCollection`          | Medium   | P99 pause above SLA                       |
| `jdk.ThreadStart` / `ThreadEnd`  | Low      | Platform thread count changes             |

`-Djdk.tracePinnedThreads` was removed in JDK 24 and has no effect — do not put it in container manifests.

---

## 8. File Descriptor Limits

```bash
ulimit -n                    # soft limit
cat /proc/sys/fs/file-max    # kernel limit
```

```yaml
securityContext:
  sysctls:
    - name: fs.nr_open
      value: "65536"
```

Thousands of concurrent VT I/O operations can exhaust descriptors before anything else breaks. Monitor alongside
connection pool metrics.

---

## 9. Flags

- `-Xmx` not increased after migrating from platform threads to VTs
- CPU limits below 2 CPUs (SerialGC fallback; `commonPool` parallelism 0)
- CPU limits not set (JVM over-provisions pools from host CPUs)
- Carrier tuning flags set without a measured symptom
- `-Djdk.tracePinnedThreads` present in manifests (removed in JDK 24)
- Continuous JFR with `maxage` and no `maxsize`
- Liveness probe based on platform thread activity
- No horizontal scaling strategy alongside VTs
- Dynamic class loading on hot VT paths under Native Image
- File descriptor limits not tuned for high VT concurrency

---

## 10. References & Citations

- **Evans, B. J., Gough, J., & Newland, C.** (2024). *Optimizing Cloud Native Java*. O'Reilly Media. (Ch. 9, 12).
- **Rahman, A.N.M. Bazlur** (2026). *Modern Concurrency in Java*. O'Reilly Media.
