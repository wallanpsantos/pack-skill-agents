<#
.SYNOPSIS
    Validador de integridade do plugin agent-eng-backend-jvm.
#>

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

Write-Output "==> Validando plugin agent-eng-backend-jvm em: $repoRoot"

# 1. Validação de Manifestos JSON
$manifests = @(
    "plugin.json",
    ".claude-plugin/plugin.json",
    ".gemini-plugin/plugin.json",
    ".codex-plugin/plugin.json",
    ".grok-plugin/plugin.json"
)

foreach ($m in $manifests)
{
    $fullPath = Join-Path $repoRoot $m
    if (-not (Test-Path $fullPath))
    {
        Write-Error "FALHA: Manifesto obrigatório ausente: $m"
        exit 1
    }
    try
    {
        Get-Content $fullPath -Raw | ConvertFrom-Json | Out-Null
        Write-Output "  [PASS] JSON valido: $m"
    }
    catch
    {
        Write-Error "FALHA: JSON invalido em $m : $_"
        exit 1
    }
}

# 2. Validação de Arquivos de Persona e Regras
$rules = @("AGENTS.md", "CLAUDE.md", "GEMINI.md", "README.md")
foreach ($r in $rules)
{
    $fullPath = Join-Path $repoRoot $r
    if (-not (Test-Path $fullPath))
    {
        Write-Error "FALHA: Documento obrigatorio ausente: $r"
        exit 1
    }
    Write-Output "  [PASS] Documento presente: $r"
}

# 3. Validação de Skills
$skills = @(
    "java-kotlin-security-audit",
    "java-kotlin-concurrency",
    "concurrency-java21-review",
    "clean-code",
    "design-patterns",
    "solid-principles"
)
foreach ($s in $skills)
{
    $skillDir = Join-Path $repoRoot "skills/$s"
    $skillMd = Join-Path $skillDir "SKILL.md"
    if (-not (Test-Path $skillMd))
    {
        Write-Error "FALHA: SKILL.md ausente na skill: $s"
        exit 1
    }
    # Verifica presença do frontmatter
    $content = Get-Content $skillMd -Raw
    if (-not ($content -match "(?s)^---\s*name:\s*([^\r\n]+)\s*description:"))
    {
        Write-Error "FALHA: Frontmatter YAML invalido em $skillMd"
        exit 1
    }
    Write-Output "  [PASS] Skill valida: $s"
}

Write-Output "==> SUCESSO: Todos os componentes do agente foram validados!"
exit 0
