#!/usr/bin/env bash
# quick_scan.sh — Pré-varredura estática determinística (grep) para Java/Spring/Quarkus/Jakarta EE.
#
# Objetivo: triagem RÁPIDA de candidatos a problema antes da revisão manual usando o checklist
# do SKILL.md. Isto NÃO substitui SAST (Semgrep/SpotBugs), revisão manual, nem os padrões
# GOOD/BAD documentados nos arquivos de references/. Todo achado aqui é um candidato a ser
# confirmado manualmente — grep não entende contexto, então falsos positivos são esperados.
#
# Uso:
#   scripts/quick_scan.sh <diretório-alvo>
#
# Saída: lista de achados agrupados por categoria OWASP, no formato arquivo:linha.

set -euo pipefail

TARGET_DIR="${1:-}"

if [[ -z "$TARGET_DIR" ]]; then
    echo "Uso: quick_scan.sh <diretório-alvo>" >&2
    echo "Exemplo: quick_scan.sh src/main/java" >&2
    exit 1
fi

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Erro: diretório '$TARGET_DIR' não existe." >&2
    exit 1
fi

JAVA_FILES_COUNT=$(find "$TARGET_DIR" -name '*.java' | wc -l | tr -d ' ')
if [[ "$JAVA_FILES_COUNT" -eq 0 ]]; then
    echo "Nenhum arquivo .java encontrado em '$TARGET_DIR'. Nada para escanear." >&2
    exit 0
fi

TOTAL_HITS=0

# grep_check <label> <owasp-ref> <regex> <glob>
grep_check() {
    local label="$1" owasp="$2" pattern="$3" glob="$4"
    local hits
    hits=$(grep -rnE --include="$glob" "$pattern" "$TARGET_DIR" 2>/dev/null || true)
    if [[ -n "$hits" ]]; then
        echo ""
        echo "## [$owasp] $label"
        echo "$hits" | sed 's/^/  /'
        local count
        count=$(echo "$hits" | wc -l | tr -d ' ')
        TOTAL_HITS=$((TOTAL_HITS + count))
    fi
}

echo "# Quick Scan — $TARGET_DIR"
echo "# $JAVA_FILES_COUNT arquivo(s) .java analisados"

# A05 — Injection
grep_check "Concatenação de String em Query (candidato a SQL Injection)" "A05" \
    '(createQuery|createNativeQuery)\([^)]*\+' '*.java'
grep_check "Statement.executeQuery com concatenação (candidato a SQL Injection)" "A05" \
    'Statement .*=.*createStatement' '*.java'

# A09 — Logging & Alerting Failures
grep_check "printStackTrace (vaza stack trace / não estruturado)" "A09" \
    '\.printStackTrace\(' '*.java'

# A08 — Software or Data Integrity Failures
grep_check "ObjectInputStream / readObject (candidato a deserialização insegura)" "A08" \
    '(ObjectInputStream|\.readObject\()' '*.java'
grep_check "Jackson enableDefaultTyping (polymorphic deserialization sem allowlist)" "A08" \
    'enableDefaultTyping' '*.java'

# A04 — Cryptographic Failures
grep_check "Algoritmo criptográfico fraco ou obsoleto" "A04" \
    '(AES/ECB|DES/|"MD5"|"SHA-1"|"SHA1")' '*.java'
grep_check "new Random() (não é criptograficamente seguro)" "A04" \
    'new Random\(\)' '*.java'
grep_check "TLS/hostname verification desabilitado" "A04" \
    '(TrustAllCerts|ALLOW_ALL_HOSTNAME_VERIFIER|NoopHostnameVerifier)' '*.java'

# A01 — Broken Access Control (CSRF/CORS incluídos)
grep_check "CSRF desabilitado" "A01" \
    'csrf\([^)]*\.disable\(\)' '*.java'
grep_check "CORS com origem wildcard" "A01" \
    '(allowedOrigins\("\*"\)|@CrossOrigin\(origins\s*=\s*"\*"\))' '*.java'

# A05 — XXE
grep_check "DocumentBuilderFactory sem hardening visível (verificar se DTD está desabilitado)" "A05" \
    'DocumentBuilderFactory\.newInstance\(\)' '*.java'

# A04 — Secrets Management
grep_check "Possível segredo hardcoded (confirmar manualmente — grep não distingue placeholder de valor real)" "A04" \
    '(password|secret|apiKey|api_key)\s*=\s*"[^"$]{3,}"' '*.java'

echo ""
echo "# Total de achados candidatos: $TOTAL_HITS"
if [[ "$TOTAL_HITS" -gt 0 ]]; then
    echo "# Próximo passo: para cada achado, abra o arquivo, confirme se é um falso positivo e,"
    echo "# se for real, consulte o arquivo de references/ correspondente à categoria OWASP para"
    echo "# o padrão de correção (GOOD/BAD)."
else
    echo "# Nenhum candidato encontrado pelos padrões deste script. Isto NÃO significa que o"
    echo "# código está seguro — continue com o Security Checklist completo do SKILL.md."
fi
