#!/usr/bin/env bash
# Scan a Java tree for concurrency review hotspots (java25-concurrency skill).
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

run() {
  local title="$1"
  shift
  echo "--- $title ---"
  if grep -RIn --include='*.java' "$@" "$ROOT" 2>/dev/null | head -n 80; then
    :
  else
    echo "(no hits)"
  fi
  echo
}

# --- Baseline violations (CRITICAL if present) ---
run "preview / incubating / internal APIs" -E 'StructuredTaskScope|enable-preview|jdk\.incubator|jdk\.internal\.'
run "removed flag: jdk.tracePinnedThreads (no effect since JDK 24)" -E 'tracePinnedThreads'

# --- Locks, visibility, context ---
run "locks / visibility / context" -E 'synchronized|@Async|volatile|ThreadLocal|ScopedValue|InheritableThreadLocal|ReentrantLock'
run "ScopedValue reads (check for cross-thread reads: no inheritance without StructuredTaskScope)" -E 'ScopedValue|\.get\(\)\s*;.*CONTEXT'

# --- Executors and futures ---
run "executors / futures" -E 'CompletableFuture|ExecutorService|Executors\.|ForkJoinPool|parallelStream'
run "commonPool usage (blocking or CPU offload is wrong here)" -E 'ForkJoinPool\.commonPool'
run "*Async stages (check for explicit executor)" -E 'thenApplyAsync|thenRunAsync|thenAcceptAsync|thenComposeAsync|supplyAsync|runAsync'
run "Future::join (does not compile on the Future interface)" -E 'Future::join|\bFuture<[^>]*>\s+\w+\s*=.*;\s*\w+\.join\(\)'
run "VT executor blocks (check cancel(true) in finally before close)" -E 'newVirtualThreadPerTaskExecutor'
run "unbounded join/get (check for timeout)" -E '\.join\(\)|\.get\(\)'

# --- Backpressure ---
run "backpressure" -E 'Semaphore|RateLimiter|bulkhead|backpressure'
run "blocking acquire without timeout" -E '\.acquire\(\)'

# --- Interruption / cancellation ---
run "InterruptedException sites" 'InterruptedException'
run "cancellation" -E '\.cancel\(|orTimeout|completeOnTimeout'

# --- Money ---
run "BigDecimal arithmetic (divide/multiply need explicit scale)" -E '\.divide\(|\.multiply\('
run "MathContext used as scale limiter (CRITICAL on money)" -E 'MathContext'
run "money primitives (CRITICAL if financial)" -E '\b(double|float)\b'
run "optimistic lock / version" -E '@Version|OptimisticLock|@Retryable'

# --- Pinning risk ---
run "native / FFM pinning risk" -E 'System\.loadLibrary|native |Linker\.nativeLinker|Arena\.of'
run "local file I/O on hot paths" -E 'FileInputStream|FileOutputStream|Files\.(read|write)'

echo "=== done ==="
echo "Next: load the matching files under references/ (see SKILL.md)."
