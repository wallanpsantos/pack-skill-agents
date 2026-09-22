<#
.SYNOPSIS
    Pre-varredura estatica deterministica dirigida por catalogo de regras (quick_scan_rules.txt).

.DESCRIPTION
    Analisa codigo-fonte Java, Kotlin, configuracoes Spring, manifestos de build,
    workflows do GitHub Actions, Dockerfiles e YAMLs de Kubernetes.
    Compativel com Windows PowerShell 5.1 e PowerShell 7+.
    Somente leitura - nao modifica nenhum arquivo.

.PARAMETER TargetDir
    Diretorio a escanear recursivamente.

.PARAMETER FailOn
    Nivel de severidade para codigo de saida 1: 'alto' (padrao), 'medio' ou 'nunca'.

.EXAMPLE
    .\quick_scan.ps1 -TargetDir src\main\java -FailOn medio
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $false)]
    [string]$TargetDir,

    [Parameter(Mandatory = $false)]
    [ValidateSet('alto', 'medio', 'nunca', IgnoreCase = $true)]
    [string]$FailOn = 'alto'
)

$ErrorActionPreference = 'Stop'

if ( [string]::IsNullOrWhiteSpace($TargetDir))
{
    Write-Error "Uso: quick_scan.ps1 [-TargetDir] <diretorio> [-FailOn alto|medio|nunca]"
    exit 2
}

if (-not (Test-Path -Path $TargetDir -PathType Container))
{
    Write-Error "Erro: diretorio '$TargetDir' nao existe."
    exit 2
}

$rulesFile = Join-Path -Path $PSScriptRoot -ChildPath "quick_scan_rules.txt"
if (-not (Test-Path -Path $rulesFile -PathType Leaf))
{
    Write-Error "Erro: catalogo de regras '$rulesFile' nao encontrado."
    exit 2
}

$pruneDirs = @('.git', '.gradle', '.idea', '.mvn', 'node_modules', 'target', 'build', 'out')

# Coleta todos os arquivos validos excluindo diretorios ignorados
$allFiles = Get-ChildItem -Path $TargetDir -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object {
    $itemPath = $_.FullName
    $skip = $false
    foreach ($d in $pruneDirs)
    {
        $part = [System.IO.Path]::DirectorySeparatorChar + $d + [System.IO.Path]::DirectorySeparatorChar
        if ($itemPath.Contains($part) -or $itemPath.EndsWith([System.IO.Path]::DirectorySeparatorChar + $d))
        {
            $skip = $true
            break
        }
    }
    -not $skip
}

if (-not $allFiles -or $allFiles.Count -eq 0)
{
    Write-Output "Nenhum arquivo encontrado em '$TargetDir' para analise."
    exit 0
}

$totalAlto = 0
$totalMedio = 0
$totalInfo = 0

Write-Output ("# Quick Scan - " + $TargetDir)
Write-Output ("# Catalogo: " + $rulesFile)
Write-Output ("# Nivel de falha (-FailOn): " + $FailOn)
Write-Output ""

$rules = Get-Content -Path $rulesFile -Encoding UTF8
foreach ($line in $rules)
{
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#'))
    {
        continue
    }

    # Delimitador: TAB (\t)
    $parts = $trimmed.Split("`t")
    if ($parts.Length -lt 7)
    {
        continue
    }

    $ruleId = $parts[0].Trim()
    $ruleLevel = $parts[1].Trim().ToUpperInvariant()
    $ruleOwasp = $parts[2].Trim()
    $ruleGlobs = $parts[3].Split(',') | ForEach-Object { $_.Trim() }
    $ruleRegex = $parts[4].Trim()
    $ruleDesc = $parts[5].Trim()
    $isSecret = ($parts[6].Trim().ToLowerInvariant() -eq 'true')

    # Filtra arquivos que batem com os globs da regra
    $targetFilesForRule = @($allFiles | Where-Object {
        $fileName = $_.Name
        $matchedGlob = $false
        foreach ($g in $ruleGlobs)
        {
            if ($fileName -like $g)
            {
                $matchedGlob = $true
                break
            }
        }
        $matchedGlob
    })

    if ($targetFilesForRule.Count -eq 0)
    {
        continue
    }

    $hits = @()
    foreach ($fileItem in $targetFilesForRule)
    {
        try
        {
            $matches = Select-String -Path $fileItem.FullName -Pattern $ruleRegex -AllMatches -ErrorAction SilentlyContinue
            if ($matches)
            {
                $hits += $matches
            }
        }
        catch
        {
            # Ignora erros de leitura de arquivos binarios/bloqueados
        }
    }

    if ($hits.Count -gt 0)
    {
        switch ($ruleLevel)
        {
            'ALTO'  {
                $totalAlto += $hits.Count
            }
            'MEDIO' {
                $totalMedio += $hits.Count
            }
            'INFO'  {
                $totalInfo += $hits.Count
            }
        }

        Write-Output ("## [{0}] [{1}] [{2}] {3}" -f $ruleLevel, $ruleId, $ruleOwasp, $ruleDesc)
        foreach ($h in $hits)
        {
            if ($isSecret)
            {
                Write-Output ("  [SEGREDO REDIGIDO] {0}:{1}" -f $h.Path, $h.LineNumber)
            }
            else
            {
                Write-Output ("  {0}:{1}: {2}" -f $h.Path, $h.LineNumber,$h.Line.Trim())
            }
        }
        Write-Output ""
    }
}

$totalCandidatos = $totalAlto + $totalMedio + $totalInfo

Write-Output "=========================================================="
Write-Output "# Resumo da Varredura:"
Write-Output ("  - Total de candidatos: " + $totalCandidatos)
Write-Output ("  - ALTO : " + $totalAlto)
Write-Output ("  - MEDIO: " + $totalMedio)
Write-Output ("  - INFO : " + $totalInfo)
Write-Output "=========================================================="

$failLevel = $FailOn.ToLowerInvariant()
$shouldFail = $false
if ($failLevel -eq 'alto' -and $totalAlto -gt 0)
{
    $shouldFail = $true
}
elseif ($failLevel -eq 'medio' -and ($totalAlto -gt 0 -or $totalMedio -gt 0))
{
    $shouldFail = $true
}

if ($shouldFail)
{
    Write-Output ("[FALHA] Candidatos encontrados atendendo ao criterio -FailOn " + $FailOn + ".")
    exit 1
}
else
{
    Write-Output ("[SUCESSO] Nenhum candidato atingiu o nivel de falha (" + $FailOn + ").")
    exit 0
}
