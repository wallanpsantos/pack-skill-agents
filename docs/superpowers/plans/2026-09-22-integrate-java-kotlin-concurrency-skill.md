# Integração da Skill `java-kotlin-concurrency` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:
> executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrar a nova skill `java-kotlin-concurrency` de forma completa e consistente em todo o ecossistema do
agente `agent-eng-backend-jvm`, atualizando manifestos multi-IA, personas (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`),
documentação raiz (`README.md`), malha de referências cruzadas das demais skills (`clean-code`, `design-patterns`,
`solid-principles`), suíte de validação automatizada e provendo script de varredura multiplataforma
(`scan-concurrency.ps1`).

**Architecture:** A nova skill `skills/java-kotlin-concurrency` assume o papel principal de autoridade em concorrência,
paralelismo, Virtual Threads (Project Loom) e Kotlin Coroutines para Java 25 LTS e Kotlin 2.4+ no Spring Boot 4.1.1+.
Todas as demais skills que tratavam concorrência redirecionam suas referências para ela. Os manifestos de IA
(`plugin.json` e `.<IA>-plugin/`) e os scripts de validação (`validate-plugin.*`) passam a reconhecer formalmente a nova
skill.

**Tech Stack:** Java 25 LTS (Virtual Threads, ScopedValue, ReentrantLock, ForkJoinPool), Kotlin 2.4+ (Coroutines, Mutex,
Flow, Dispatchers, Structured Concurrency), Spring Boot 4.1.1+ (Spring Framework 7.0, Virtual Threads enabled), JSON,
PowerShell e Bash.

## Global Constraints

- **Preservação de Escopo da Skill:** `java-kotlin-concurrency` é estritamente voltada para JVM de servidor (Java 25 LTS
  e Kotlin 2.4+ no alvo JVM). Mobile, KMP e frontend permanecem fora de escopo.
- **Validade Formal dos Manifestos:** Todos os manifestos JSON (`plugin.json` e `.<IA>-plugin/plugin.json`) devem ser
  JSON RFC 8259 estrito.
- **Conformidade `agentskills.io`:** A nova skill e todas as demais devem manter frontmatter YAML estrito com `name` e
  `description`.
- **Integridade de Links Relativos:** 100% dos links cruzados entre skills e documentações devem ser links relativos
  Markdown válidos e existentes no sistema de arquivos.
- **Validação Cross-Platform:** `scripts/validate-plugin.ps1` e `scripts/validate-plugin.sh` devem validar todas as
  skills registradas com código de saída 0.

---

### File Structure Map

```text
skills/
├── java-kotlin-concurrency/              # NOVA SKILL (Java 25 & Kotlin 2.4 Concorrência)
│   ├── SKILL.md                          # Guia mestre de concorrência e paralelismo
│   ├── AGENTS.md                         # Persona e regras específicas de concorrência
│   ├── references/                       # 9 guias temáticos aprofundados
│   └── scripts/
│       ├── scan-concurrency.sh           # Script de varredura de concorrência (Bash)
│       └── scan-concurrency.ps1          # Script de varredura de concorrência (PowerShell) - A CRIAR
├── clean-code/
│   ├── SKILL.md                          # Atualizar link de concorrência para java-kotlin-concurrency
│   └── README.md                         # Atualizar link de concorrência
├── design-patterns/
│   ├── SKILL.md                          # Atualizar link de concorrência para java-kotlin-concurrency
│   └── README.md                         # Atualizar link de concorrência
├── solid-principles/
│   ├── SKILL.md                          # Atualizar link de concorrência para java-kotlin-concurrency
│   └── README.md                         # Atualizar link de concorrência
plugin.json                               # Atualizar lista de skills
AGENTS.md                                 # Adicionar java-kotlin-concurrency na persona central
CLAUDE.md                                 # Adicionar comando rápido de concorrência
GEMINI.md                                 # Listar java-kotlin-concurrency
README.md                                 # Atualizar diagrama Mermaid, tabela e descrições
.claude-plugin/plugin.json                # Registrar java-kotlin-concurrency
.gemini-plugin/plugin.json                # Registrar java-kotlin-concurrency
.codex-plugin/plugin.json                 # Registrar java-kotlin-concurrency
.grok-plugin/plugin.json                  # Registrar java-kotlin-concurrency
scripts/
├── validate-plugin.ps1                   # Validar java-kotlin-concurrency
└── validate-plugin.sh                    # Validar java-kotlin-concurrency
```

---

### Task 1: Atualização dos Manifestos Multi-IA e Scripts de Validação

**Files:**

- Modify: `plugin.json`
- Modify: `.claude-plugin/plugin.json`
- Modify: `.gemini-plugin/plugin.json`
- Modify: `.codex-plugin/plugin.json`
- Modify: `.grok-plugin/plugin.json`
- Modify: `scripts/validate-plugin.ps1`
- Modify: `scripts/validate-plugin.sh`

**Interfaces:**

- Consumes: A nova skill em `skills/java-kotlin-concurrency/`.
- Produces: Manifestos JSON válidos e scripts de validação atualizados para verificar `java-kotlin-concurrency`.

- [x] **Step 1: Atualizar `plugin.json` na raiz**

Incluir `"./skills/java-kotlin-concurrency"` na lista de skills:

```json
{
  "name": "agent-eng-backend-jvm",
  "version": "1.0.0",
  "description": "Engenheiro Sênior de Backend na JVM especialista em Java 25 LTS, Kotlin 2.4, Spring Boot 4.1+, Concorrência Estruturada, Padrões Arquiteturais e Segurança OWASP Top 10:2025.",
  "author": "wallanpsantos",
  "license": "Proprietary",
  "skills": [
    "./skills/java-kotlin-security-audit",
    "./skills/java-kotlin-concurrency",
    "./skills/concurrency-java21-review",
    "./skills/clean-code",
    "./skills/design-patterns",
    "./skills/solid-principles"
  ],
  "rules": [
    "./AGENTS.md"
  ]
}
```

- [x] **Step 2: Atualizar os manifestos nas pastas `.<IA>-plugin/`**

Adicionar `"../skills/java-kotlin-concurrency"` na lista `"skills"` de:

- `.claude-plugin/plugin.json`
- `.gemini-plugin/plugin.json`
- `.codex-plugin/plugin.json`
- `.grok-plugin/plugin.json`

- [x] **Step 3: Atualizar `scripts/validate-plugin.ps1` e `scripts/validate-plugin.sh`**

Em `scripts/validate-plugin.ps1`:

```powershell
$skills = @(
    "java-kotlin-security-audit",
    "java-kotlin-concurrency",
    "concurrency-java21-review",
    "clean-code",
    "design-patterns",
    "solid-principles"
)
```

Em `scripts/validate-plugin.sh`:

```bash
SKILLS=(
    "java-kotlin-security-audit"
    "java-kotlin-concurrency"
    "concurrency-java21-review"
    "clean-code"
    "design-patterns"
    "solid-principles"
)
```

- [x] **Step 4: Executar validação dos manifestos**

Executar:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\validate-plugin.ps1
```

Expected: `[PASS] Skill valida: java-kotlin-concurrency` e
`==> SUCESSO: Todos os componentes do agente foram validados!` com exit code 0.

- [x] **Step 5: Commit das atualizações dos manifestos**

```bash
git add plugin.json .claude-plugin/ .gemini-plugin/ .codex-plugin/ .grok-plugin/ scripts/validate-plugin.*
git commit -m "feat(manifests): register java-kotlin-concurrency skill across all AI manifests and validation scripts"
```

---

### Task 2: Atualização dos Orquestradores de Persona (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`)

**Files:**

- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Modify: `GEMINI.md`

**Interfaces:**

- Consumes: A taxonomia e gatilhos da skill `java-kotlin-concurrency`.
- Produces: Prompts de sistema e entrypoints atualizados com instruções de concorrência moderna.

- [x] **Step 1: Atualizar `AGENTS.md` para destacar `java-kotlin-concurrency`**

No `AGENTS.md`, atualizar a seção de habilidades bundled:

```markdown
### 2. `java-kotlin-concurrency` (`skills/java-kotlin-concurrency/SKILL.md`)

- **Quando ativar:** Revisão e implementação de concorrência e paralelismo em Java 25 LTS e Kotlin 2.4+ (alvo JVM de servidor), análise de thread safety, race conditions, deadlocks, Virtual Threads (Project Loom), carrier thread pinning, `ScopedValue`, `CompletableFuture`, Spring `@Async`, `ForkJoinPool`, `parallelStream`, Kotlin Coroutines, funções `suspend`, Structured Concurrency, `Dispatchers`, `Flow`, `Mutex`, integridade de estado financeiro sob acesso concorrente e deployment cloud-native.
- **Ação:** Siga o checklist de concorrência em `skills/java-kotlin-concurrency/SKILL.md` e execute a varredura estática de hotspots com `scripts/scan-concurrency.sh` ou `scripts/scan-concurrency.ps1`.

### 3. `concurrency-java21-review` (`skills/concurrency-java21-review/SKILL.md`)

- **Quando ativar:** Auditoria e migração de bases legadas Java 21 para Virtual Threads e análise retroativa.
- **Ação:** Siga as diretrizes de `skills/concurrency-java21-review/SKILL.md`.
```

- [x] **Step 2: Atualizar `CLAUDE.md`**

Adicionar comando de varredura de concorrência:

```markdown
## Comandos Rápidos
- Pré-varredura de segurança: `bash skills/java-kotlin-security-audit/scripts/quick_scan.sh <diretório>`
- Varredura de concorrência: `bash skills/java-kotlin-concurrency/scripts/scan-concurrency.sh <diretório>`
- Validação do plugin: `bash scripts/validate-plugin.sh`
```

- [x] **Step 3: Atualizar `GEMINI.md`**

Listar `skills/java-kotlin-concurrency/SKILL.md` na lista de skills carregadas automaticamente.

- [x] **Step 4: Commit das atualizações de personas**

```bash
git add AGENTS.md CLAUDE.md GEMINI.md
git commit -m "docs(personas): integrate java-kotlin-concurrency in AGENTS.md, CLAUDE.md, and GEMINI.md"
```

---

### Task 3: Criação do Script de Varredura Multiplataforma (`scan-concurrency.ps1`)

**Files:**

- Create: `skills/java-kotlin-concurrency/scripts/scan-concurrency.ps1`

**Interfaces:**

- Consumes: Código-fonte Java e Kotlin na JVM.
- Produces: Varredura automatizada equivalente ao `scan-concurrency.sh` para desenvolvedores Windows (PowerShell 5.1 e
  7+).

- [x] **Step 1: Criar `skills/java-kotlin-concurrency/scripts/scan-concurrency.ps1`**

Conteúdo do script PowerShell implementando as mesmas regras e checagens (preview APIs, thread pinning, locks,
ScopedValue, CompletableFuture, backpressure, interrupção, BigDecimal/MathContext, coroutines, GlobalScope, Dispatchers,
runBlocking):

```powershell
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
```

- [x] **Step 2: Testar execução do `scan-concurrency.ps1` no diretório de skills**

Executar:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File skills\java-kotlin-concurrency\scripts\scan-concurrency.ps1 skills
```

Expected: Saída formatada com cabeçalhos de Java e Kotlin e conclusão com sucesso.

- [x] **Step 3: Commit do script PowerShell**

```bash
git add skills/java-kotlin-concurrency/scripts/scan-concurrency.ps1
git commit -m "feat(concurrency): add cross-platform scan-concurrency.ps1 for Windows environments"
```

---

### Task 4: Atualização da Malha de Referências Cruzadas nas Demais Skills

**Files:**

- Modify: `skills/clean-code/SKILL.md`
- Modify: `skills/clean-code/README.md`
- Modify: `skills/design-patterns/SKILL.md`
- Modify: `skills/design-patterns/README.md`
- Modify: `skills/solid-principles/SKILL.md`
- Modify: `skills/solid-principles/README.md`

**Interfaces:**

- Consumes: Novo caminho `skills/java-kotlin-concurrency/SKILL.md`.
- Produces: Links relativos atualizados apontando para a nova skill canônica de concorrência.

- [x] **Step 1: Atualizar referências em `skills/clean-code/`**

Em `skills/clean-code/SKILL.md` e `skills/clean-code/README.md`, substituir referências de:
`[../concurrency-java21-review/SKILL.md]` ou `[concurrency-java21-review]`
Por:
`[../java-kotlin-concurrency/SKILL.md]` com descrição atualizada:
`- **[Concorrência e Paralelismo JVM](../java-kotlin-concurrency/SKILL.md)**: Virtual Threads (Java 25), Kotlin Coroutines (2.4+), carrier pinning, ScopedValue e concorrência estruturada sem anti-patterns.`

- [x] **Step 2: Atualizar referências em `skills/design-patterns/`**

Em `skills/design-patterns/SKILL.md` e `skills/design-patterns/README.md`, atualizar os links relativos de concorrência
para apontar para `../java-kotlin-concurrency/SKILL.md`.

- [x] **Step 3: Atualizar referências em `skills/solid-principles/`**

Em `skills/solid-principles/SKILL.md` e `skills/solid-principles/README.md`, atualizar os links relativos de
concorrência para apontar para `../java-kotlin-concurrency/SKILL.md`.

- [x] **Step 4: Verificar integridade de todos os links atualizados**

Executar script PowerShell de validação de links:

```powershell
$skillsToCheck = @("skills/clean-code/SKILL.md", "skills/design-patterns/SKILL.md", "skills/solid-principles/SKILL.md")
foreach ($s in $skillsToCheck) {
    $dir = Split-Path $s
    $content = Get-Content $s -Raw
    $matches = [regex]::Matches($content, '\[.*?\]\(((\.\./[^)]+)|(\./[^)]+))\)')
    foreach ($m in $matches) {
        $relPath = $m.Groups[1].Value.Split('#')[0]
        $target = Resolve-Path (Join-Path $dir $relPath) -ErrorAction SilentlyContinue
        if ($target -and (Test-Path $target)) {
            Write-Output "Link OK em $s: $relPath"
        } else {
            Write-Error "Link quebrado em $s: $relPath"
        }
    }
}
```

Expected: Todos `Link OK` sem nenhum erro.

- [x] **Step 5: Commit das referências atualizadas**

```bash
git add skills/clean-code/ skills/design-patterns/ skills/solid-principles/
git commit -m "refactor(skills): update cross-references to point to canonical java-kotlin-concurrency skill"
```

---

### Task 5: Atualização da Documentação Central (`README.md`) e Validação End-to-End

**Files:**

- Modify: `README.md`
- Modify: `docs/superpowers/plans/2026-09-22-integrate-java-kotlin-concurrency-skill.md` (Checklists de progresso)

**Interfaces:**

- Consumes: Todo o ecossistema integrado com `java-kotlin-concurrency`.
- Produces: Documentação raiz consistente com diagrama Mermaid atualizado e validação completa passing.

- [x] **Step 1: Atualizar `README.md` raiz**

1. No diagrama Mermaid arquitetural:
    - Adicionar o nó `SK_CONC_NEW["java-kotlin-concurrency<br/>(Java 25 & Kotlin 2.4)"]`.
2. Na tabela de habilidades do agente:
    - Destacar `java-kotlin-concurrency` como a autoridade moderna em concorrência JVM (Loom, Coroutines, ScopedValue,
      Mutex, Flow).
3. Na seção técnica detalhada:
    - Adicionar subseção explicando a skill `java-kotlin-concurrency`, seus 9 guias temáticos em `references/` e os
      scripts de varredura `scan-concurrency.sh` e `scan-concurrency.ps1`.

- [x] **Step 2: Executar validação completa do agente**

Executar:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\validate-plugin.ps1
```

Expected: Todas as skills (inclusive `java-kotlin-concurrency`) validadas com sucesso e exit code 0.

- [x] **Step 3: Testar varredura de concorrência e segurança**

Executar:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File skills\java-kotlin-security-audit\scripts\quick_scan.ps1 skills -FailOn nunca
powershell -NoProfile -ExecutionPolicy Bypass -File skills\java-kotlin-concurrency\scripts\scan-concurrency.ps1 skills
```

Expected: Ambos os scripts executam com sucesso.

- [x] **Step 4: Commit final de documentação e fechamento**

```bash
git add README.md docs/superpowers/plans/
git commit -m "docs: finalize integration of java-kotlin-concurrency skill in root documentation and validation"
```

---

## Self-Review Checklist

- **Spec Coverage:** A nova skill `java-kotlin-concurrency` está registrada em todos os manifestos JSON (`plugin.json`,
  `.claude-plugin/`, `.gemini-plugin/`, `.codex-plugin/`, `.grok-plugin/`), em `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`,
  `README.md` e nos scripts de validação (`validate-plugin.*`).
- **No Placeholders:** Todos os comandos, snippets de PowerShell, JSON e Markdown contêm código exato.
- **Cross-Platform:** Script `scan-concurrency.ps1` criado para dar suporte nativo a desenvolvedores no Windows,
  mantendo paridade com `scan-concurrency.sh`.
- **Cross-References:** Todos os links cruzados nas demais skills (`clean-code`, `design-patterns`, `solid-principles`)
  foram atualizados para apontar para `java-kotlin-concurrency`.
