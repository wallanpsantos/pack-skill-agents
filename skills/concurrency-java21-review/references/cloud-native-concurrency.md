# Cloud-Native Concurrency

Load when reviewing Virtual Thread deployments on Kubernetes, GraalVM Native Image compatibility, container resource
configuration, or production observability for concurrent workloads.

---

## 1. Kubernetes: Memory Configuration with Virtual Threads

VT stacks live on the **Java heap** (not native memory). Moving from platform threads to VTs shifts memory pressure
from off-heap (not counted by `-Xmx`) to the JVM heap (counted by `-Xmx`).

```yaml
# ❌ Same -Xmx as before VT migration → OOM under peak load
resources:
  requests:
    memory: "512Mi"
  limits:
    memory: "512Mi"
# JVM: -Xmx256m  ← was sufficient for platform thread stacks off-heap

# ✅ Increase heap allowance to accommodate VT stack frames under peak concurrency
resources:
  requests:
    memory: "768Mi"
  limits:
    memory: "768Mi"
# JVM: -Xmx512m  ← extra headroom for VT stacks on heap
```

**Rule of thumb:** Start with ~1.5× the previous `-Xmx` when migrating to VTs under high concurrency. Tune based on
GC pause frequency and heap utilization dashboards.

---

## 2. Container-Aware Thread Pool Sizing

The JVM reads `Runtime.getRuntime().availableProcessors()` from the container's CPU allocation, not from the host.
Ensure cgroup CPU limits are set; otherwise the JVM may see all host CPUs and over-provision platform thread pools.

```yaml
# ✅ Set CPU limits so JVM reads the correct processor count
resources:
  limits:
    cpu: "2"       # JVM sees 2 processors; tunes ForkJoinPool to 2 carriers
  requests:
    cpu: "500m"
```

VT carrier pool default parallelism = `Runtime.availableProcessors()`. In a container with CPU throttling,
**set a ceiling** to avoid scheduler starvation:

```bash
-Djdk.virtualThreadScheduler.parallelism=4   # explicit, not derived from throttled CPU
-Djdk.virtualThreadScheduler.maxPoolSize=256  # keep default unless you need fewer carriers
```

---

## 3. Single-CPU Container Allocation Warning

Containers configured with 1 CPU or fractional CPUs (e.g., `cpu: "1"` or `cpu: "500m"`) cause JVM ergonomics to default to single-threaded garbage collection (`SerialGC` / `SerialOldGC`) on many JDK distributions.

```yaml
# ❌ Single CPU limit → JVM selects SerialGC, killing concurrent throughput
resources:
  limits:
    cpu: "1"
  requests:
    cpu: "500m"

# ✅ Minimum 2 CPUs → JVM enables G1GC with multi-threaded parallel collectors
resources:
  limits:
    cpu: "2"
  requests:
    cpu: "1"
```

### Impact of Single CPU Allocation
- **GC Performance Fallback:** `SerialGC` performs single-threaded Stop-The-World (STW) pauses, leading to extreme latency spikes during GC cycles.
- **Destroyed Throughput:** Virtual Threads and carrier pools rely on multi-core scheduling. Single-CPU containers prevent parallelism and amplify carrier contention.
- **Rule:** Always allocate **>= 2 CPUs** for containerized Java workloads running concurrent pipelines or Virtual Threads (Evans et al., 2024, Ch. 9).

---

## 4. Liveness and Readiness Probes

VT-based applications under low traffic may have all platform (carrier) threads idle — parked VTs consume no carrier
CPU. **Do not use platform thread activity as a liveness signal.**

```yaml
# ❌ Thread-count-based liveness — will fire false negatives during idle periods
livenessProbe:
  exec:
    command: ["check-thread-count.sh"]

# ✅ HTTP actuator health endpoint — reflects actual application state
livenessProbe:
  httpGet:
    path: /actuator/health/liveness
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /actuator/health/readiness
    port: 8080
```

---

## 5. Horizontal Scaling vs. VT Vertical Scaling

| Scaling Type           | When Appropriate                                         |
|------------------------|----------------------------------------------------------|
| **Vertical (VTs)**     | I/O-bound workloads; more concurrent requests per pod    |
| **Horizontal (HPA)**   | CPU-bound workloads; geo-distribution; fault isolation   |
| **Both together**      | I/O-bound with high total throughput requirements        |

> Do NOT eliminate horizontal scaling because VTs improved per-pod throughput. Use both strategies together.
> VTs improve concurrency within a pod; HPA scales across pods.

---

## 6. GraalVM Native Image + Virtual Threads

GraalVM Native Image **fully supports Virtual Threads** (since GraalVM 21+).

### Constraints

| Constraint                                | Impact                                        | Mitigation                                   |
|-------------------------------------------|-----------------------------------------------|----------------------------------------------|
| Dynamic class loading during VT execution | May pin carrier (class-loading pinning)       | Pre-load critical classes at startup          |
| JNI / native calls inside VTs             | Pin carriers (same as JVM)                    | Minimize JNI in hot VT paths                 |
| AOT compilation (no JIT)                  | Faster startup; potentially lower peak TPS    | Benchmark both modes; tune GraalVM PGO       |
| Reflection/proxy classes                  | Must be declared in `reflect-config.json`     | Use `-agentlib:native-image-agent` to capture|

```java
// ✅ Pre-load at startup to avoid class-loading pinning at runtime
@EventListener(ApplicationReadyEvent.class)
public void warmUp() throws ClassNotFoundException {
    Class.forName("com.example.CriticalService");
    Class.forName("com.example.PaymentProcessor");
}
```

### Verification

```bash
# Run with native image agent to capture reflection/proxy usage
java -agentlib:native-image-agent=config-output-dir=src/main/resources/META-INF/native-image \
     -jar your-app.jar

# Confirm VTs work in native image
./your-app-native --server.port=8080 &
curl http://localhost:8080/actuator/health
```

---

## 7. JFR in Production (Cloud)

JFR is low-overhead and production-safe. Enable it for all VT workloads.

```bash
# Continuous JFR recording (recommended for cloud production)
java -XX:StartFlightRecording=name=production,\
     filename=/var/log/jfr/recording.jfr,\
     maxsize=500m,\
     maxage=1h,\
     settings=default \
     -jar your-app.jar

# Kubernetes: mount a persistent volume or use an init container for JFR output
# Or stream to async profiler / OpenTelemetry collector
```

### Containerized JFR Buffer Configuration: `maxsize` vs. `maxage`

- **`maxage`:** Retains recording data up to a time window (e.g., `maxage=1h`). On its own, `maxage` provides **no memory or disk cap**. During high activity bursts (e.g., VT allocations, locking spikes), data volume can explode.
- **`maxsize`:** Enforces a strict upper bound on the ring buffer size (e.g., `maxsize=500m`). When reached, oldest events are dropped.

> **Critical Warning:** Running continuous JFR in containers with `maxage` but **without `maxsize`** can cause unrestricted disk or off-heap memory growth during activity bursts, triggering cgroup container OOM-kills (`OOMKilled`) (Evans et al., 2024, Ch. 12). Always specify `maxsize`.

Key JFR events for VT workloads:

| Event                              | Production Priority | What to Alert On                        |
|------------------------------------|---------------------|-----------------------------------------|
| `jdk.VirtualThreadPinned`         | High                | Count > 0 with threshold > 50ms         |
| `jdk.VirtualThreadSubmitFailed`   | Critical            | Any occurrence                          |
| `jdk.GarbageCollection`           | Medium              | P99 GC pause > SLA threshold            |
| `jdk.MonitorEnter`                 | Medium              | Long contention on hot monitors         |
| `jdk.ThreadStart` / `ThreadEnd`   | Low                 | Platform thread count change            |

---

## 8. File Descriptor Limits

With VTs, thousands of concurrent I/O operations can exhaust OS file descriptors.

```bash
# Check current limit
ulimit -n          # soft limit
cat /proc/sys/fs/file-max  # kernel hard limit

# ✅ Increase in container or OS
# Kubernetes: set in pod securityContext
securityContext:
  sysctls:
    - name: fs.nr_open
      value: "65536"

# Or in Dockerfile
RUN ulimit -n 65536
```

Monitor with JFR `jdk.FileRead` / `jdk.FileWrite` events or OS `lsof | wc -l`.

---

## 9. Flags

- `-Xmx` not increased after migrating from platform threads to VTs
- CPU limits set to 1 or fractional CPU (`< 2 CPUs`) → JVM falls back to `SerialGC`
- CPU limits not set in container → JVM over-provisions carrier pool
- Continuous JFR configured with `maxage` without `maxsize` (risk of container OOM-kill)
- Liveness probe based on platform thread activity (false negatives with VTs)
- No horizontal scaling strategy (VTs handle concurrency, not geo-distribution)
- GraalVM native image with dynamic class loading in hot VT paths (carrier pinning)
- JFR not enabled in production (missed pinning/contention events)
- File descriptor limits not tuned for high VT concurrency

---

## 10. References & Citations

- **Evans, B. J., Gough, J., & Newland, C.** (2024). *Optimizing Cloud Native Java: Efficient Microservices in Kubernetes and Cloud Environments*. O'Reilly Media. (Chapters 9, 12).
- **Rahman, A.N.M. Bazlur** (2026). *Modern Concurrency in Java: Multi-threading, Virtual Threads, and Structured Concurrency*. O'Reilly Media.
