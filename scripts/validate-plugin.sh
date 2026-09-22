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
    if command -v python3 > /dev/null 2>&1; then
        python3 -m json.tool "${REPO_ROOT}/${m}" > /dev/null
    elif command -v python > /dev/null 2>&1; then
        python -m json.tool "${REPO_ROOT}/${m}" > /dev/null
    fi
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
    # Verifica presenca do frontmatter YAML
    if ! grep -q "^---" "${skill_file}"; then
        echo "FALHA: Frontmatter ausente em: ${s}" >&2
        exit 1
    fi
    echo "  [PASS] Skill valida: ${s}"
done

echo "==> SUCESSO: Todos os componentes do agente foram validados!"
exit 0
