#!/usr/bin/env bash
# Scan a Java/Kotlin (JVM target) tree for concurrency review hotspots (java25-concurrency skill).
# Usage: scripts/scan-concurrency.sh [source-root]
set -euo pipefail

ROOT="${1:-.}"
if [[ ! -d "$ROOT" ]]; then
  echo "Not a directory: $ROOT" >&2
  exit 1
fi

echo "=== scan-concurrency ==="
echo "root: $ROOT"
echo

# $1 title, $2 --include glob (e.g. '*.java', '*.kt'), rest: grep -E pattern args
run() {
  local title="$1"
  local include="$2"
  shift 2
  echo "--- $title ---"
  if grep -RIn --include="$include" "$@" "$ROOT" 2>/dev/null | head -n 80; then
    :
  else
    echo "(no hits)"
  fi
  echo
}

# ============================================================
# Java
# ============================================================

# --- Baseline violations (CRITICAL if present) ---
run "preview / incubating / internal APIs" '*.java' -E 'StructuredTaskScope|enable-preview|jdk\.incubator|jdk\.internal\.'
run "removed flag: jdk.tracePinnedThreads (no effect since JDK 24)" '*.java' -E 'tracePinnedThreads'

# --- Locks, visibility, context ---
run "locks / visibility / context" '*.java' -E 'synchronized|@Async|volatile|ThreadLocal|ScopedValue|InheritableThreadLocal|ReentrantLock'
run "ScopedValue reads (check for cross-thread reads: no inheritance without StructuredTaskScope)" '*.java' -E 'ScopedValue|\.get\(\)\s*;.*CONTEXT'

# --- Executors and futures ---
run "executors / futures" '*.java' -E 'CompletableFuture|ExecutorService|Executors\.|ForkJoinPool|parallelStream'
run "commonPool usage (blocking or CPU offload is wrong here)" '*.java' -E 'ForkJoinPool\.commonPool'
run "*Async stages (check for explicit executor)" '*.java' -E 'thenApplyAsync|thenRunAsync|thenAcceptAsync|thenComposeAsync|supplyAsync|runAsync'
run "Future::join (does not compile on the Future interface)" '*.java' -E 'Future::join|\bFuture<[^>]*>\s+\w+\s*=.*;\s*\w+\.join\(\)'
run "VT executor blocks (check cancel(true) in finally before close)" '*.java' -E 'newVirtualThreadPerTaskExecutor'
run "unbounded join/get (check for timeout)" '*.java' -E '\.join\(\)|\.get\(\)'

# --- Backpressure ---
run "backpressure" '*.java' -E 'Semaphore|RateLimiter|bulkhead|backpressure'
run "blocking acquire without timeout" '*.java' -E '\.acquire\(\)'

# --- Interruption / cancellation ---
run "InterruptedException sites" '*.java' -E 'InterruptedException'
run "cancellation" '*.java' -E '\.cancel\(|orTimeout|completeOnTimeout'

# --- Money ---
run "BigDecimal arithmetic (divide/multiply need explicit scale)" '*.java' -E '\.divide\(|\.multiply\('
run "MathContext used as scale limiter (CRITICAL on money)" '*.java' -E 'MathContext'
run "money primitives (CRITICAL if financial)" '*.java' -E '\b(double|float)\b'
run "optimistic lock / version" '*.java' -E '@Version|OptimisticLock|@Retryable'

# --- Pinning risk ---
run "native / FFM pinning risk" '*.java' -E 'System\.loadLibrary|native |Linker\.nativeLinker|Arena\.of'
run "local file I/O on hot paths" '*.java' -E 'FileInputStream|FileOutputStream|Files\.(read|write)'

# ============================================================
# Kotlin (JVM target only — see "Out of scope" in SKILL.md)
# ============================================================

run "unstructured coroutine scope (GlobalScope)" '*.kt' -E 'GlobalScope'
run "runBlocking (check it is not on a request/VT/event-loop thread)" '*.kt' -E 'runBlocking'
run "structured concurrency builders" '*.kt' -E 'coroutineScope|supervisorScope|\blaunch\(|\basync\('
run "dispatchers (check IO vs Default is the right one for the work)" '*.kt' -E 'Dispatchers\.(IO|Default|Unconfined)|withContext|asCoroutineDispatcher'
run "coroutine sync primitives" '*.kt' -E '\bMutex\(|kotlinx\.coroutines\.sync|\bChannel<'
run "Flow (check backpressure and flowOn placement)" '*.kt' -E '\bFlow<|flowOn\(|\.collect\(|\bbuffer\(|\bconflate\('
run "synchronized in Kotlin (should not wrap suspend calls)" '*.kt' -E '\bsynchronized\s*\('
run "experimental / delicate coroutine APIs" '*.kt' -E '@OptIn\([^)]*Experimental|@DelicateCoroutinesApi|@ExperimentalCoroutinesApi'
run "BigDecimal arithmetic (operators need explicit scale on divide)" '*.kt' -E 'BigDecimal|\.divide\(|\.multiply\('
run "money primitives (CRITICAL if financial)" '*.kt' -E '\b(Double|Float)\b'
run "suspend Spring controllers (check Dispatchers.Unconfined context propagation)" '*.kt' -E 'suspend fun.*\b(Controller|Mapping)\b|@(Get|Post|Put|Delete|Patch|Request)Mapping'
run "optimistic lock / version" '*.kt' -E '@Version|OptimisticLock|@Retryable'

echo "=== done ==="
echo "Next: load the matching files under references/ (see SKILL.md), including references/kotlin-coroutines.md for"
echo "any Kotlin hits above."
