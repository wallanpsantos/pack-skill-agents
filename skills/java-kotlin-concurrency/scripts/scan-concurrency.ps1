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

$ErrorActionPreference = 'Continue'
$targetPath = Resolve-Path $TargetDir

Write-Output "=== scan-concurrency ==="
Write-Output "root: $targetPath"
Write-Output ""

function Run-Check {
    param(
        [string]$Title,
        [string[]]$Extensions,
        [string]$Pattern
    )
    Write-Output "--- $Title ---"
    $files = Get-ChildItem -Path $targetPath -Recurse -File | Where-Object {
        $ext = $_.Extension
        $Extensions -contains $ext -and
        $_.FullName -notmatch "(\.git|\.gradle|\.idea|target|build|out|\.superpowers)"
    }
    
    $hits = 0
    foreach ($f in $files) {
        $matches = Select-String -Path $f.FullName -Pattern $Pattern
        foreach ($m in $matches) {
            $hits++
            if ($hits -le 80) {
                Write-Output "$($m.Path):$($m.LineNumber):$($m.Line.Trim())"
            }
        }
    }
    if ($hits -eq 0) {
        Write-Output "(no hits)"
    }
    Write-Output ""
}

# --- Java 25 ---
Run-Check "preview / incubating / internal APIs" @(".java") "StructuredTaskScope|enable-preview|jdk\.incubator|jdk\.internal\."
Run-Check "removed flag: jdk.tracePinnedThreads" @(".java") "tracePinnedThreads"
Run-Check "locks / visibility / context" @(".java") "synchronized|@Async|volatile|ThreadLocal|ScopedValue|InheritableThreadLocal|ReentrantLock"
Run-Check "ScopedValue reads" @(".java") "ScopedValue|\.get\(\)\s*;.*CONTEXT"
Run-Check "executors / futures" @(".java") "CompletableFuture|ExecutorService|Executors\.|ForkJoinPool|parallelStream"
Run-Check "commonPool usage" @(".java") "ForkJoinPool\.commonPool"
Run-Check "VT executor blocks" @(".java") "newVirtualThreadPerTaskExecutor"
Run-Check "unbounded join/get" @(".java") "\.join\(\)|\.get\(\)"
Run-Check "backpressure" @(".java") "Semaphore|RateLimiter|bulkhead|backpressure"
Run-Check "InterruptedException sites" @(".java") "InterruptedException"
Run-Check "BigDecimal arithmetic" @(".java") "\.divide\(|\.multiply\("
Run-Check "MathContext on money" @(".java") "MathContext"

# --- Kotlin 2.4 ---
Run-Check "GlobalScope / delicate coroutines" @(".kt") "GlobalScope|@DelicateCoroutinesApi|@ExperimentalCoroutinesApi"
Run-Check "runBlocking (forbidden on VT / event loops)" @(".kt") "runBlocking"
Run-Check "Dispatchers usage" @(".kt") "Dispatchers\.IO|Dispatchers\.Default|Dispatchers\.Unconfined"
Run-Check "coroutine primitives" @(".kt") "CoroutineScope|async|launch|withContext"
Run-Check "channel / flow" @(".kt") "Channel<|Flow<|SharedFlow|StateFlow|callbackFlow"
Run-Check "concurrency primitives" @(".kt") "Mutex|Semaphore|AtomicReference|AtomicInteger"
Run-Check "BigDecimal arithmetic Kotlin" @(".kt") "\.divide\(|\.multiply\(|\s*\/\s*|\s*\*\s*.*BigDecimal"

Write-Output "=== Varredura de concorrência concluída ==="
