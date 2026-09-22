<#
.SYNOPSIS
    Varredura de hotspots de concorrência e paralelismo em Java 25 e Kotlin 2.4 (JVM).
    Equivalente cross-platform de scan-concurrency.sh.
.PARAMETER TargetDir
    Diretório raiz da análise (padrão: '.').
#>
[CmdletBinding()]
param(
    [string]$TargetDir = "."
)

if (-not (Test-Path -Path $TargetDir -PathType Container)) {
    Write-Error "Not a directory: $TargetDir"
    exit 1
}
$targetPath = (Resolve-Path $TargetDir).ProviderPath

Write-Output "=== scan-concurrency ==="
Write-Output "root: $targetPath"
Write-Output ""

$allFiles = Get-ChildItem -Path $targetPath -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
    $_.FullName -notmatch '[\\/](\.git|\.gradle|\.idea|target|build|out|\.superpowers)([\\/]|$)'
}
$javaFiles = @($allFiles | Where-Object { $_.Extension -eq '.java' })
$ktFiles   = @($allFiles | Where-Object { $_.Extension -eq '.kt' })

function Run-Check {
    param(
        [string]$Title,
        [System.IO.FileInfo[]]$Files,
        [string]$Pattern
    )
    Write-Output "--- $Title ---"
    if (-not $Files -or $Files.Count -eq 0) {
        Write-Output "(no hits)"
        Write-Output ""
        return
    }

    $hits = 0
    :fileLoop foreach ($f in $Files) {
        $matches = Select-String -Path $f.FullName -Pattern $Pattern -ErrorAction SilentlyContinue
        foreach ($m in $matches) {
            $hits++
            Write-Output "$($m.Path):$($m.LineNumber):$($m.Line.Trim())"
            if ($hits -ge 80) {
                break fileLoop
            }
        }
    }

    if ($hits -eq 0) {
        Write-Output "(no hits)"
    }
    Write-Output ""
}

# ============================================================
# Java
# ============================================================

# --- Baseline violations (CRITICAL if present) ---
Run-Check "preview / incubating / internal APIs" $javaFiles 'StructuredTaskScope|enable-preview|jdk\.incubator|jdk\.internal\.'
Run-Check "removed flag: jdk.tracePinnedThreads (no effect since JDK 24)" $javaFiles 'tracePinnedThreads'

# --- Locks, visibility, context ---
Run-Check "locks / visibility / context" $javaFiles 'synchronized|@Async|volatile|ThreadLocal|ScopedValue|InheritableThreadLocal|ReentrantLock'
Run-Check "ScopedValue reads (check for cross-thread reads: no inheritance without StructuredTaskScope)" $javaFiles 'ScopedValue|\.get\(\)\s*;.*CONTEXT'

# --- Executors and futures ---
Run-Check "executors / futures" $javaFiles 'CompletableFuture|ExecutorService|Executors\.|ForkJoinPool|parallelStream'
Run-Check "commonPool usage (blocking or CPU offload is wrong here)" $javaFiles 'ForkJoinPool\.commonPool'
Run-Check "*Async stages (check for explicit executor)" $javaFiles 'thenApplyAsync|thenRunAsync|thenAcceptAsync|thenComposeAsync|supplyAsync|runAsync'
Run-Check "Future::join (does not compile on the Future interface)" $javaFiles 'Future::join|\bFuture<[^>]*>\s+\w+\s*=.*;\s*\w+\.join\(\)'
Run-Check "VT executor blocks (check cancel(true) in finally before close)" $javaFiles 'newVirtualThreadPerTaskExecutor'
Run-Check "unbounded join/get (check for timeout)" $javaFiles '\.join\(\)|\.get\(\)'

# --- Backpressure ---
Run-Check "backpressure" $javaFiles 'Semaphore|RateLimiter|bulkhead|backpressure'
Run-Check "blocking acquire without timeout" $javaFiles '\.acquire\(\)'

# --- Interruption / cancellation ---
Run-Check "InterruptedException sites" $javaFiles 'InterruptedException'
Run-Check "cancellation" $javaFiles '\.cancel\(|orTimeout|completeOnTimeout'

# --- Money ---
Run-Check "BigDecimal arithmetic (divide/multiply need explicit scale)" $javaFiles '\.divide\(|\.multiply\('
Run-Check "MathContext used as scale limiter (CRITICAL on money)" $javaFiles 'MathContext'
Run-Check "money primitives (CRITICAL if financial)" $javaFiles '\b(double|float)\b'
Run-Check "optimistic lock / version" $javaFiles '@Version|OptimisticLock|@Retryable'

# --- Pinning risk ---
Run-Check "native / FFM pinning risk" $javaFiles 'System\.loadLibrary|native |Linker\.nativeLinker|Arena\.of'
Run-Check "local file I/O on hot paths" $javaFiles 'FileInputStream|FileOutputStream|Files\.(read|write)'

# ============================================================
# Kotlin (JVM target only — see "Out of scope" in SKILL.md)
# ============================================================

Run-Check "unstructured coroutine scope (GlobalScope)" $ktFiles 'GlobalScope'
Run-Check "runBlocking (check it is not on a request/VT/event-loop thread)" $ktFiles 'runBlocking'
Run-Check "structured concurrency builders" $ktFiles 'coroutineScope|supervisorScope|\blaunch\(|\basync\('
Run-Check "dispatchers (check IO vs Default is the right one for the work)" $ktFiles 'Dispatchers\.(IO|Default|Unconfined)|withContext|asCoroutineDispatcher'
Run-Check "coroutine sync primitives" $ktFiles '\bMutex\(|kotlinx\.coroutines\.sync|\bChannel<'
Run-Check "Flow (check backpressure and flowOn placement)" $ktFiles '\bFlow<|flowOn\(|\.collect\(|\bbuffer\(|\bconflate\('
Run-Check "synchronized in Kotlin (should not wrap suspend calls)" $ktFiles '\bsynchronized\s*\('
Run-Check "experimental / delicate coroutine APIs" $ktFiles '@OptIn\([^)]*Experimental|@DelicateCoroutinesApi|@ExperimentalCoroutinesApi'
Run-Check "BigDecimal arithmetic (operators need explicit scale on divide)" $ktFiles 'BigDecimal|\.divide\(|\.multiply\('
Run-Check "money primitives (CRITICAL if financial)" $ktFiles '\b(Double|Float)\b'
Run-Check "suspend Spring controllers (check Dispatchers.Unconfined context propagation)" $ktFiles 'suspend fun.*\b(Controller|Mapping)\b|@(Get|Post|Put|Delete|Patch|Request)Mapping'
Run-Check "optimistic lock / version" $ktFiles '@Version|OptimisticLock|@Retryable'

Write-Output "=== done ==="
Write-Output "Next: load the matching files under references/ (see SKILL.md), including references/kotlin-coroutines.md for"
Write-Output "any Kotlin hits above."
