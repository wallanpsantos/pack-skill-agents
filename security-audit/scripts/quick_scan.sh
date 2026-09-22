#!/usr/bin/env bash
# quick_scan.sh — Pré-varredura estática determinística dirigida por catálogo de regras.
# Suporta Linux, macOS e Git Bash (Bash 3.2+).
#
# Uso:
#   scripts/quick_scan.sh [--fail-on alto|medio|nunca] <diretório>
#
# Códigos de saída:
#   0: Sem candidatos no nível de falha configurado
#   1: Candidatos encontrados no nível de falha configurado
#   2: Erro de uso, diretório inexistente ou catálogo de regras ausente

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_FILE="${SCRIPT_DIR}/quick_scan_rules.txt"

FAIL_ON="alto"
TARGET_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fail-on)
            if [[ $# -lt 2 ]]; then
                echo "Erro: --fail-on requer um argumento (alto|medio|nunca)" >&2
                exit 2
            fi
            FAIL_ON="$(echo "$2" | tr '[:upper:]' '[:lower:]')"
            shift 2
            ;;
        --fail-on=*)
            FAIL_ON="$(echo "${1#*=}" | tr '[:upper:]' '[:lower:]')"
            shift 1
            ;;
        -h|--help)
            echo "Uso: $0 [--fail-on alto|medio|nunca] <diretório>"
            exit 0
            ;;
        *)
            if [[ -z "$TARGET_DIR" ]]; then
                TARGET_DIR="$1"
            else
                echo "Erro: argumento inesperado '$1'" >&2
                exit 2
            fi
            shift 1
            ;;
    esac
done

if [[ "$FAIL_ON" != "alto" && "$FAIL_ON" != "medio" && "$FAIL_ON" != "nunca" ]]; then
    echo "Erro: valor inválido para --fail-on ('$FAIL_ON'). Use alto, medio ou nunca." >&2
    exit 2
fi

if [[ -z "$TARGET_DIR" ]]; then
    echo "Erro: diretório alvo não informado." >&2
    echo "Uso: $0 [--fail-on alto|medio|nunca] <diretório>" >&2
    exit 2
fi

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Erro: diretório '$TARGET_DIR' não existe." >&2
    exit 2
fi

if [[ ! -f "$RULES_FILE" ]]; then
    echo "Erro: catálogo de regras '$RULES_FILE' não encontrado." >&2
    exit 2
fi

# Diretórios excluídos da análise
PRUNE_PATHS=(
    -name ".git" -o
    -name ".gradle" -o
    -name ".idea" -o
    -name ".mvn" -o
    -name "node_modules" -o
    -name "target" -o
    -name "build" -o
    -name "out"
)

TOTAL_ALTO=0
TOTAL_MEDIO=0
TOTAL_INFO=0

echo "# Quick Scan — $TARGET_DIR"
echo "# Catálogo: $RULES_FILE"
echo "# Nível de falha (--fail-on): $FAIL_ON"
echo ""

# Processa linha a linha do catálogo de regras delimitado por TAB (\t)
while IFS=$'\t' read -r rule_id rule_level rule_owasp rule_globs rule_regex rule_desc is_secret || [[ -n "$rule_id" ]]; do
    # Ignora linhas vazias ou comentários
    [[ -z "$rule_id" || "$rule_id" =~ ^[[:space:]]*# ]] && continue

    rule_level="$(echo "$rule_level" | tr '[:lower:]' '[:upper:]')"
    
    # Monta lista de includes para o find a partir dos globs separados por vírgula
    IFS=',' read -r -a globs_array <<< "$rule_globs"
    name_args=()
    for i in "${!globs_array[@]}"; do
        g="$(echo "${globs_array[$i]}" | tr -d ' ')"
        if [[ $i -gt 0 ]]; then
            name_args+=("-o")
        fi
        name_args+=("-name" "$g")
    done

    # Localiza arquivos correspondentes que não estejam nos diretórios ignorados
    matched_files=()
    while IFS= read -r f; do
        [[ -n "$f" ]] && matched_files+=("$f")
    done < <(find "$TARGET_DIR" \( "${PRUNE_PATHS[@]}" \) -prune -o -type f \( "${name_args[@]}" \) -print 2>/dev/null || true)

    if [[ ${#matched_files[@]} -eq 0 ]]; then
        continue
    fi

    # Executa regex nos arquivos localizados
    rule_hits=""
    if [[ "$is_secret" == "true" ]]; then
        # Para segredos, imprime estritamente arquivo:linha sem o valor
        rule_hits=$(grep -rnE "$rule_regex" "${matched_files[@]}" 2>/dev/null | awk -F: '{print $1 ":" $2}' || true)
    else
        rule_hits=$(grep -rnE "$rule_regex" "${matched_files[@]}" 2>/dev/null || true)
    fi

    if [[ -n "$rule_hits" ]]; then
        hit_count=$(echo "$rule_hits" | wc -l | tr -d ' ')
        case "$rule_level" in
            ALTO)  TOTAL_ALTO=$((TOTAL_ALTO + hit_count)) ;;
            MEDIO) TOTAL_MEDIO=$((TOTAL_MEDIO + hit_count)) ;;
            INFO)  TOTAL_INFO=$((TOTAL_INFO + hit_count)) ;;
        esac

        echo "## [$rule_level] [$rule_id] [$rule_owasp] $rule_desc"
        if [[ "$is_secret" == "true" ]]; then
            echo "$rule_hits" | sed 's/^/  [SEGREDO REDIGIDO] /'
        else
            echo "$rule_hits" | sed 's/^/  /'
        fi
        echo ""
    fi

done < "$RULES_FILE"

TOTAL_CANDIDATOS=$((TOTAL_ALTO + TOTAL_MEDIO + TOTAL_INFO))

echo "=========================================================="
echo "# Resumo da Varredura:"
echo "  - Total de candidatos: $TOTAL_CANDIDATOS"
echo "  - ALTO : $TOTAL_ALTO"
echo "  - MEDIO: $TOTAL_MEDIO"
echo "  - INFO : $TOTAL_INFO"
echo "=========================================================="

SHOULD_FAIL=0
if [[ "$FAIL_ON" == "alto" && "$TOTAL_ALTO" -gt 0 ]]; then
    SHOULD_FAIL=1
elif [[ "$FAIL_ON" == "medio" && ($TOTAL_ALTO -gt 0 || $TOTAL_MEDIO -gt 0) ]]; then
    SHOULD_FAIL=1
fi

if [[ "$SHOULD_FAIL" -eq 1 ]]; then
    echo "[FALHA] Candidatos encontrados atendendo ao critério --fail-on $FAIL_ON."
    exit 1
else
    echo "[SUCESSO] Nenhum candidato atingiu o nível de falha ($FAIL_ON)."
    exit 0
fi
