#!/usr/bin/env bash
# Scan a Java tree for concurrency review hotspots (Java 25 skill).
# Usage: scan-concurrency.sh [source-root]
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

run "locks / visibility / context" -E 'synchronized|@Async|volatile|ThreadLocal|ScopedValue|InheritableThreadLocal|ReentrantLock'
run "executors / futures" -E 'CompletableFuture|ExecutorService|Executors\.|ForkJoinPool|parallelStream'
run "preview / incubating (CRITICAL if present)" -E 'StructuredTaskScope|enable-preview|jdk\.incubator'
run "BigDecimal arithmetic (review RoundingMode)" -E '\.divide\(|\.multiply\('
run "InterruptedException sites" 'InterruptedException'
run "backpressure" -E 'Semaphore|RateLimiter|backpressure'
run "*Async without nearby Executor (heuristic)" -E 'thenApplyAsync|thenRunAsync|thenAcceptAsync|supplyAsync'
run "native / FFM pinning risk" -E 'System\.loadLibrary|native |Linker\.nativeLinker|Arena\.ofShared'
run "money primitives (CRITICAL if financial)" -E '\bdouble\b|\bfloat\b'
run "optimistic lock / version" -E '@Version|OptimisticLockException'

echo "=== done ==="
echo "Next: load matching references under this skill's references/ directory."
