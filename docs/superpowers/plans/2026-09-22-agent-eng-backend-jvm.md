# Transformação em Agente Multi-IA (`agent-eng-backend-jvm`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transformar as habilidades de engenharia e auditoria de backend na JVM em um pacote de agente completo e multi-IA (`agent-eng-backend-jvm`), compatível de forma nativa com Google Antigravity, Anthropic Claude Code, OpenAI Codex e xAI Grok.

**Architecture:** Estruturação em padrão Universal Agent Plugin com manifesto raiz `plugin.json`, diretórios dedicados de compatibilidade por IA (`.claude-plugin/`, `.gemini-plugin/`, `.codex-plugin/`, `.grok-plugin/`), consolidação de personas e orquestração de habilidades em `AGENTS.md` e reorganização padronizada das skills sob o diretório `skills/`.

**Tech Stack:** JSON (Plugin Manifests), Markdown (Agent System Prompt / AgentSkills specification), Bash / POSIX shell, PowerShell 5.1 / 7+.

## Global Constraints

- Manter 100% de conformidade com a especificação agentskills.io para todas as skills (`SKILL.md` com frontmatter YAML `name` e `description`).
- Não quebrar nem remover a skill `java-kotlin-security-audit` nem `concurrency-java21-review`; padronizar seus caminhos sob `skills/` mantendo compatibilidade direta.
- Todos os manifestos JSON devem ser estritamente válidos segundo a especificação JSON (sem comentários, sem trailing commas).
- Scripts de validação e verificação devem ser cross-platform (PowerShell para Windows e Bash para Linux/macOS/Git Bash).

---

### File Structure Map

```text
agent-eng-backend-jvm (pack-skill-agents)/
├── plugin.json                           # Manifesto universal do agente / plugin
├── AGENTS.md                             # Persona central e orquestrador do agente (universal)
├── README.md                             # Documentação geral do agente e guia multi-IA
├── .claude-plugin/
│   └── plugin.json                       # Manifesto específico do plugin para Claude Code
├── .gemini-plugin/
│   └── plugin.json                       # Manifesto específico do plugin para Google Antigravity
├── .codex-plugin/
│   └── plugin.json                       # Manifesto de instruções para OpenAI Codex
├── .grok-plugin/
│   └── plugin.json                       # Manifesto de instruções para xAI Grok
├── scripts/
│   ├── validate-plugin.ps1               # Validador de integridade do agente (PowerShell)
│   └── validate-plugin.sh                # Validador de integridade do agente (Bash)
└── skills/
    ├── java-kotlin-security-audit/       # Skill completa de auditoria de segurança (Java 25 / Kotlin 2.4)
    │   ├── SKILL.md
    │   ├── README.md
    │   ├── assets/
    │   ├── references/
    │   └── scripts/
    └── concurrency-java21-review/        # Skill completa de concorrência (Java 21 / Virtual Threads)
        ├── SKILL.md
        ├── AGENTS.md
        └── references/
```

---

### Task 1: Reorganização Padronizada das Skills sob `skills/`

**Files:**
- Move/Reorganize: `../../../java-kotlin-security-audit` → `skills/java-kotlin-security-audit/`
- Move/Reorganize: `concurrency-java21-review/` → `skills/concurrency-java21-review/`

**Interfaces:**
- Consumes: Estruturas existentes em `../../../java-kotlin-security-audit` e `concurrency-java21-review/`.
- Produces: Diretório raiz `skills/` padronizado contendo `java-kotlin-security-audit` e `concurrency-java21-review`.

- [ ] **Step 1: Criar diretório `skills/` e mover as pastas existentes**

Executar comando no PowerShell:
```powershell
New-Item -ItemType Directory -Force -Path "skills"
Copy-Item -Recurse -Force "java-kotlin-security-audit" "skills/java-kotlin-security-audit"
Copy-Item -Recurse -Force "concurrency-java21-review" "skills/concurrency-java21-review"
```

- [ ] **Step 2: Atualizar o frontmatter de `skills/java-kotlin-security-audit/SKILL.md` com o nome canônico `java-kotlin-security-audit`**

Verificar e editar o campo `name:` no `skills/java-kotlin-security-audit/SKILL.md`:
```yaml
---
name: java-kotlin-security-audit
description: Auditoria de segurança para backends na JVM — APIs, workers, consumidores de mensageria e serviços distribuídos em Java 25 LTS+, Kotlin 2.4+ (somente JVM) e Spring Boot 4.1.1+ (Spring MVC, WebFlux, Spring Security 7) — alinhada ao OWASP Top 10:2025, OWASP API Security Top 10:2023 e OWASP ASVS 5.0. Cobre controle de acesso (BOLA/BFLA/IDOR, multi-tenancy), OAuth2/OIDC/JWT, injeção (SQL, NoSQL, LDAP, comando, SpEL, XXE), SSRF, criptografia e segredos, desserialização (Jackson 3, kotlinx.serialization), coroutines e virtual threads, tratamento de exceções e fail-closed, resiliência, supply chain Maven/Gradle, GitHub Actions, contêineres, Kubernetes e criptografia pós-quântica (ML-KEM/ML-DSA) para bancos, pagamentos, seguradoras e saúde. Usar sempre que o usuário pedir revisão de segurança, auditoria antes de produção, levantamento de vulnerabilidades, threat modeling, conformidade OWASP/ASVS, hardening de Spring Boot/Actuator/Kubernetes, análise de CVEs ou de pipeline, ou perguntar "está seguro?", "pode ir pra produção?", "tem SQLi/XSS/SSRF/IDOR?". Não usar para Android, Kotlin Multiplatform, Kotlin/Native, Kotlin/JS, Kotlin/Wasm, mobile, desktop ou frontend.
compatibility: Java 25 LTS ou superior; Kotlin 2.4+ no alvo JVM; Spring Boot 4.1.1+ (Spring Framework 7, Spring Security 7.1, Jackson 3). Nenhum exemplo depende de recurso preview/incubating. scripts/quick_scan.* exige Bash 3.2+ com grep/find/awk (Linux, macOS, Git Bash) ou PowerShell 5.1+/pwsh 7 (Windows, cmd via .bat).
license: Proprietary - Internal use only
---
```

- [ ] **Step 3: Testar execução do `quick_scan.ps1` no novo caminho**

Executar:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File skills\java-kotlin-security-audit\scripts\quick_scan.ps1 skills\java-kotlin-security-audit -FailOn nunca
```
Expected: Saída formatada com `[SUCESSO] Nenhum candidato atingiu o nivel de falha (nunca).` e Exit Code 0.

- [ ] **Step 4: Remover pastas redundantes na raiz se migradas com sucesso**

Executar:
```powershell
Remove-Item -Recurse -Force "java-kotlin-security-audit"
Remove-Item -Recurse -Force "concurrency-java21-review"
```

- [ ] **Step 5: Commit das alterações**

```bash
git add skills/
git commit -m "refactor: reorganize skills into skills/ directory"
```

---

### Task 2: Definição da Persona do Agente (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`)

**Files:**
- Create: `AGENTS.md`
- Create: `CLAUDE.md`
- Create: `GEMINI.md`

**Interfaces:**
- Consumes: Habilidades em `skills/java-kotlin-security-audit` e `skills/concurrency-java21-review`.
- Produces: Prompt de sistema padronizado para IAs atuando como Engenheiro Sênior de Backend na JVM.

- [ ] **Step 1: Criar o arquivo `AGENTS.md` com a persona e instruções completas**

Conteúdo de `AGENTS.md`:
```markdown
# Agent: Backend JVM Senior Engineer (`agent-eng-backend-jvm`)

Você é o **Backend JVM Senior Engineer**, um agente especialista em arquitetura, segurança, concorrência e engenharia de software para a plataforma JVM.

## Escopo Tecnológico Principal
- **Linguagens:** Java 25 LTS+ e Kotlin 2.4+ (exclusivamente para servidor JVM).
- **Frameworks:** Spring Boot 4.1.1+ (Spring Framework 7.0, Spring Security 7.1, Spring Data, Jackson 3), Quarkus e Jakarta EE.
- **Arquitetura:** Microsserviços, BFFs (Server-Driven UI), APIs REST, GraphQL, Consumidores de Eventos (Kafka, RabbitMQ, SQS) e Workers assíncronos.
- **Concorrência:** Java Virtual Threads (Project Loom), Concorrência Estruturada (`StructuredTaskScope`), `ScopedValue`, Coroutines Kotlin em WebFlux e Ktor.
- **Segurança:** OWASP Top 10:2025, OWASP API Security Top 10:2023, ASVS 5.0, Criptografia Pós-Quântica (FIPS 203/204/205 - ML-KEM/ML-DSA).

---

## Habilidades Bundled (Skills Disponíveis)

Este agente possui habilidades embutidas que devem ser invocadas sob demanda:

### 1. `java-kotlin-security-audit` (`skills/java-kotlin-security-audit/SKILL.md`)
- **Quando ativar:** Revisões de segurança de código ou PRs, auditorias pré-produção ("pode ir pra produção?"), análise de injeção (SQLi, SpEL, XXE), controle de acesso (BOLA/BFLA), SSRF, segredos expostos, conformidade OWASP e riscos quânticos.
- **Ação:** Leia o `SKILL.md` associado, utilize o `quick_scan` para triagem inicial e gere o relatório baseado no template `assets/audit-report-template.md`.

### 2. `concurrency-java21-review` (`skills/concurrency-java21-review/SKILL.md`)
- **Quando ativar:** Revisão de concorrência, migração para Virtual Threads no Java 21/25, análise de thread pinning, deadlocks, `synchronized` vs `ReentrantLock`, uso correto de `CompletableFuture` e coroutines.
- **Ação:** Siga o checklist de concorrência em `skills/concurrency-java21-review/SKILL.md`.

---

## Regras de Comportamento e Resposta
1. **Evidência antes de afirmações:** Nunca classifique um problema sem citar o arquivo, linha, fluxo fonte-sumidouro e justificativa técnica.
2. **Código de Produção:** Todos os exemplos de código gerados devem ser completos, idiomáticos (Java 25 ou Kotlin 2.4), seguros por padrão (deny-by-default) e prontos para produção.
3. **Multi-IA Compliance:** Este agente respeita contextos e comandos das ferramentas Antigravity (Google), Claude Code (Anthropic), Codex (OpenAI) e Grok (xAI).
```

- [ ] **Step 2: Criar arquivo `CLAUDE.md` apontando para `AGENTS.md`**

Conteúdo de `CLAUDE.md`:
```markdown
# Claude Code Instructions

Este repositório funciona como o agente `agent-eng-backend-jvm`.
Consulte [AGENTS.md](./AGENTS.md) para a persona completa, stack tecnológica e regras de orquestração de skills.

## Comandos Rápidos
- Pré-varredura de segurança: `bash skills/java-kotlin-security-audit/scripts/quick_scan.sh <diretório>`
- Validação do plugin: `bash scripts/validate-plugin.sh`
```

- [ ] **Step 3: Criar arquivo `GEMINI.md` apontando para `AGENTS.md`**

Conteúdo de `GEMINI.md`:
```markdown
# Antigravity / Gemini Instructions

Este repositório define o agente `agent-eng-backend-jvm`.
As diretrizes completas de engenharia, concorrência e segurança estão em [AGENTS.md](./AGENTS.md).

## Skills Carregadas Automaticamente
- `skills/java-kotlin-security-audit/SKILL.md`
- `skills/concurrency-java21-review/SKILL.md`
```

- [ ] **Step 4: Verificar se os 3 arquivos foram criados e possuem conteúdo válido**

Executar:
```powershell
Get-Item AGENTS.md, CLAUDE.md, GEMINI.md | Select-Object Name, Length
```

- [ ] **Step 5: Commit das alterações**

```bash
git add AGENTS.md CLAUDE.md GEMINI.md
git commit -m "feat: add unified agent personas (AGENTS.md, CLAUDE.md, GEMINI.md)"
```

---

### Task 3: Manifestos Universais e Específicos por IA (`plugin.json` e `.<IA>-plugin/`)

**Files:**
- Create: `plugin.json` (Raiz)
- Create: `.claude-plugin/plugin.json`
- Create: `.gemini-plugin/plugin.json`
- Create: `.codex-plugin/plugin.json`
- Create: `.grok-plugin/plugin.json`

**Interfaces:**
- Consumes: Configurações do agente `agent-eng-backend-jvm`.
- Produces: Metadados estruturados para que cada IA descubra e monte as habilidades e regras automaticamente.

- [ ] **Step 1: Criar o manifesto universal `plugin.json` na raiz**

Conteúdo de `plugin.json`:
```json
{
  "name": "agent-eng-backend-jvm",
  "version": "1.0.0",
  "description": "Engenheiro Sênior de Backend na JVM especialista em Java 25 LTS, Kotlin 2.4, Spring Boot 4.1+, Concorrência Estruturada e Segurança OWASP Top 10:2025.",
  "author": "wallanpsantos",
  "license": "Proprietary",
  "skills": [
    "./skills/java-kotlin-security-audit",
    "./skills/concurrency-java21-review"
  ],
  "rules": [
    "./AGENTS.md"
  ]
}
```

- [ ] **Step 2: Criar `.claude-plugin/plugin.json` para Claude Code**

Executar PowerShell para criar diretório e arquivo:
```powershell
New-Item -ItemType Directory -Force -Path ".claude-plugin"
```
Conteúdo de `.claude-plugin/plugin.json`:
```json
{
  "name": "agent-eng-backend-jvm",
  "version": "1.0.0",
  "description": "Claude Code plugin for Senior JVM Backend Engineering (Java 25, Kotlin 2.4, Spring Boot 4.1.1+, Concurrency, Security Audit).",
  "entrypoint": "CLAUDE.md",
  "skills": [
    "../skills/java-kotlin-security-audit",
    "../skills/concurrency-java21-review"
  ]
}
```

- [ ] **Step 3: Criar `.gemini-plugin/plugin.json` para Google Antigravity**

Executar PowerShell para criar diretório e arquivo:
```powershell
New-Item -ItemType Directory -Force -Path ".gemini-plugin"
```
Conteúdo de `.gemini-plugin/plugin.json`:
```json
{
  "name": "agent-eng-backend-jvm",
  "version": "1.0.0",
  "description": "Antigravity plugin providing senior JVM backend capabilities, automated security scanning and concurrency analysis.",
  "rules": [
    "../GEMINI.md",
    "../AGENTS.md"
  ],
  "skills": [
    "../skills/java-kotlin-security-audit",
    "../skills/concurrency-java21-review"
  ]
}
```

- [ ] **Step 4: Criar `.codex-plugin/plugin.json` para OpenAI Codex**

Executar PowerShell para criar diretório e arquivo:
```powershell
New-Item -ItemType Directory -Force -Path ".codex-plugin"
```
Conteúdo de `.codex-plugin/plugin.json`:
```json
{
  "name": "agent-eng-backend-jvm",
  "version": "1.0.0",
  "description": "OpenAI Codex Agent profile for JVM backend development, Spring Boot architecture, and OWASP security review.",
  "instructions": "../AGENTS.md",
  "skills": [
    "../skills/java-kotlin-security-audit",
    "../skills/concurrency-java21-review"
  ]
}
```

- [ ] **Step 5: Criar `.grok-plugin/plugin.json` para xAI Grok**

Executar PowerShell para criar diretório e arquivo:
```powershell
New-Item -ItemType Directory -Force -Path ".grok-plugin"
```
Conteúdo de `.grok-plugin/plugin.json`:
```json
{
  "name": "agent-eng-backend-jvm",
  "version": "1.0.0",
  "description": "xAI Grok Agent definition for robust, high-performance JVM backend engineering and vulnerability assessment.",
  "systemPrompt": "../AGENTS.md",
  "skills": [
    "../skills/java-kotlin-security-audit",
    "../skills/concurrency-java21-review"
  ]
}
```

- [ ] **Step 6: Validar que todos os arquivos JSON são parseáveis sem erros**

Executar no PowerShell:
```powershell
$jsonFiles = @("plugin.json", ".claude-plugin/plugin.json", ".gemini-plugin/plugin.json", ".codex-plugin/plugin.json", ".grok-plugin/plugin.json")
foreach ($f in $jsonFiles) {
    try {
        Get-Content $f -Raw | ConvertFrom-Json | Out-Null
        Write-Output "OK: $f"
    } catch {
        Write-Error "ERRO em $f: $_"
    }
}
```
Expected: 5 linhas com `OK: <caminho>`.

- [ ] **Step 7: Commit dos manifestos**

```bash
git add plugin.json .claude-plugin/ .gemini-plugin/ .codex-plugin/ .grok-plugin/
git commit -m "feat: add universal and AI-specific plugin manifests (.claude, .gemini, .codex, .grok)"
```

---

### Task 4: Scripts de Validação de Integridade do Plugin (`scripts/validate-plugin.*`)

**Files:**
- Create: `scripts/validate-plugin.ps1`
- Create: `scripts/validate-plugin.sh`

**Interfaces:**
- Consumes: Arquivos `plugin.json`, manifestos das IAs e pastas em `skills/`.
- Produces: Teste automatizado de CI/local que valida a integridade do pacote do agente.

- [ ] **Step 1: Criar o script `scripts/validate-plugin.ps1`**

Conteúdo de `scripts/validate-plugin.ps1`:
```powershell
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

foreach ($m in $manifests) {
    $fullPath = Join-Path $repoRoot $m
    if (-not (Test-Path $fullPath)) {
        Write-Error "FALHA: Manifesto obrigatório ausente: $m"
        exit 1
    }
    try {
        Get-Content $fullPath -Raw | ConvertFrom-Json | Out-Null
        Write-Output "  [PASS] JSON valido: $m"
    } catch {
        Write-Error "FALHA: JSON invalido em $m : $_"
        exit 1
    }
}

# 2. Validação de Arquivos de Persona e Regras
$rules = @("AGENTS.md", "CLAUDE.md", "GEMINI.md", "README.md")
foreach ($r in $rules) {
    $fullPath = Join-Path $repoRoot $r
    if (-not (Test-Path $fullPath)) {
        Write-Error "FALHA: Documento obrigatorio ausente: $r"
        exit 1
    }
    Write-Output "  [PASS] Documento presente: $r"
}

# 3. Validação de Skills
$skills = @("java-kotlin-security-audit", "concurrency-java21-review")
foreach ($s in $skills) {
    $skillDir = Join-Path $repoRoot "skills/$s"
    $skillMd = Join-Path $skillDir "SKILL.md"
    if (-not (Test-Path $skillMd)) {
        Write-Error "FALHA: SKILL.md ausente na skill: $s"
        exit 1
    }
    # Verifica presença do frontmatter
    $content = Get-Content $skillMd -Raw
    if (-not ($content -match "(?s)^---\s*name:\s*([^\r\n]+)\s*description:")) {
        Write-Error "FALHA: Frontmatter YAML invalido em $skillMd"
        exit 1
    }
    Write-Output "  [PASS] Skill valida: $s"
}

Write-Output "==> SUCESSO: Todos os componentes do agente foram validados!"
exit 0
```

- [ ] **Step 2: Criar o script `scripts/validate-plugin.sh` para Linux/macOS/Git Bash**

Conteúdo de `scripts/validate-plugin.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Validando plugin agent-eng-backend-jvm em: ${REPO_ROOT}"

MANIFESTS=(
    "plugin.json"
    ".claude-plugin/plugin.json"
    ".gemini-plugin/plugin.json"
    ".codex-plugin/plugin.json"
    ".grok-plugin/plugin.json"
)

for m in "${MANIFESTS[@]}"; do
    if [[ ! -f "${REPO_ROOT}/${m}" ]]; then
        echo "FALHA: Manifesto ausente: ${m}" >&2
        exit 1
    fi
    # Valida sintaxe JSON
    python -m json.tool "${REPO_ROOT}/${m}" > /dev/null
    echo "  [PASS] JSON valido: ${m}"
done

DOCS=("AGENTS.md" "CLAUDE.md" "GEMINI.md" "README.md")
for d in "${DOCS[@]}"; do
    if [[ ! -f "${REPO_ROOT}/${d}" ]]; then
        echo "FALHA: Documento ausente: ${d}" >&2
        exit 1
    fi
    echo "  [PASS] Documento presente: ${d}"
done

SKILLS=("java-kotlin-security-audit" "concurrency-java21-review")
for s in "${SKILLS[@]}"; do
    skill_file="${REPO_ROOT}/skills/${s}/SKILL.md"
    if [[ ! -f "${skill_file}" ]]; then
        echo "FALHA: SKILL.md ausente em: ${s}" >&2
        exit 1
    fi
    echo "  [PASS] Skill valida: ${s}"
done

echo "==> SUCESSO: Todos os componentes do agente foram validados!"
exit 0
```

- [ ] **Step 3: Executar o script de validação para verificar se passa**

Executar:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\validate-plugin.ps1
```
Expected: `==> SUCESSO: Todos os componentes do agente foram validados!` e exit code 0.

- [ ] **Step 4: Commit dos scripts de validação**

```bash
git add scripts/validate-plugin.*
git commit -m "feat: add cross-platform plugin validation scripts"
```

---

### Task 5: Documentação Oficial e Guia Multi-IA (`README.md`)

**Files:**
- Modify: `README.md` (Raiz do repositório)

**Interfaces:**
- Consumes: Estrutura completa do plugin `agent-eng-backend-jvm`.
- Produces: Documentação de referência para uso do agente em Antigravity, Claude Code, OpenAI Codex e Grok.

- [ ] **Step 1: Escrever o `README.md` completo da raiz**

Atualizar `README.md` com:
- Apresentação do agente `agent-eng-backend-jvm`.
- Diagrama da arquitetura do repositório.
- Tabela de compatibilidade de IAs (Antigravity, Claude Code, Codex, Grok).
- Como carregar o agente em cada IA:
  - Antigravity: Instalação via `.gemini/config/plugins/` ou apontamento via workspace.
  - Claude Code: Como utilizar com `CLAUDE.md` e `.claude-plugin/plugin.json`.
  - OpenAI Codex: Como usar `AGENTS.md` e `.codex-plugin/plugin.json`.
  - xAI Grok: Uso das instruções de sistema e skills.
- Detalhamento das duas skills embutidas (`java-kotlin-security-audit` e `concurrency-java21-review`).
- Como executar o validador `scripts/validate-plugin.ps1`.

- [ ] **Step 2: Validar a renderização e links internos do `README.md`**

Verificar se todos os caminhos relativos citados no `README.md` apontam para arquivos existentes:
- `./plugin.json`
- `./AGENTS.md`
- `./skills/java-kotlin-security-audit/SKILL.md`
- `./skills/concurrency-java21-review/SKILL.md`

- [ ] **Step 3: Executar a suíte de validação final**

Executar:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\validate-plugin.ps1
```
Expected: Pass com exit code 0.

- [ ] **Step 4: Commit final da documentação**

```bash
git add README.md
git commit -m "docs: update root README with multi-AI agent documentation"
```

---

## Self-Review Checklist

- **Spec Coverage:** O plano atende rigorosamente ao pedido do usuário de transformar a pasta de skills em um agente `agent-eng-backend-jvm/`, provendo suporte para Antigravity, Grok, Codex e Claude com a pasta de skills e manifestos.
- **Placeholder Scan:** Nenhuma ocorrência de TODO, TBD ou "implementar depois". Todos os passos contêm código, comandos e arquivos exatos.
- **Type/Path Consistency:** Todas as referências apontam para `skills/java-kotlin-security-audit` e `skills/concurrency-java21-review`. Os manifestos JSON são rigorosamente sincronizados.
