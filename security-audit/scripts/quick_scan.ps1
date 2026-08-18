<#
.SYNOPSIS
    Pre-varredura estatica deterministica (regex) para Java/Spring/Quarkus/Jakarta EE.

.DESCRIPTION
    Equivalente Windows de scripts/quick_scan.sh. Mesmos padroes, mesma saida.
    NAO substitui SAST (Semgrep/SpotBugs), revisao manual, nem os padroes GOOD/BAD
    documentados em references/. Todo achado aqui e um candidato a ser confirmado
    manualmente - regex nao entende contexto, entao falsos positivos sao esperados.

.PARAMETER TargetDir
    Diretorio a escanear recursivamente por arquivos .java.

.EXAMPLE
    .\quick_scan.ps1 src\main\java

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\quick_scan.ps1 src\main\java
    (uso a partir do cmd.exe, sem precisar mudar a policy do sistema)

.NOTES
    Compativel com Windows PowerShell 5.1 (embutido no Windows) e PowerShell 7+.
    Somente leitura - nao modifica nenhum arquivo.
#>

param(
    [Parameter(Position = 0)]
    [string]$TargetDir
)

if ([string]::IsNullOrWhiteSpace($TargetDir)) {
    Write-Error "Uso: quick_scan.ps1 <diretorio-alvo>`nExemplo: quick_scan.ps1 src\main\java"
    exit 1
}

if (-not (Test-Path -Path $TargetDir -PathType Container)) {
    Write-Error "Erro: diretorio '$TargetDir' nao existe."
    exit 1
}

$javaFiles = Get-ChildItem -Path $TargetDir -Filter '*.java' -Recurse -File -ErrorAction SilentlyContinue
if (-not $javaFiles -or $javaFiles.Count -eq 0) {
    Write-Warning "Nenhum arquivo .java encontrado em '$TargetDir'. Nada para escanear."
    exit 0
}

$totalHits = 0

function Invoke-Check {
    param(
        [string]$Label,
        [string]$Owasp,
        [string]$Pattern,
        [System.IO.FileInfo[]]$Files
    )

    $matches = $Files | Select-String -Pattern $Pattern -AllMatches
    if ($matches) {
        Write-Output ""
        Write-Output "## [$Owasp] $Label"
        foreach ($m in $matches) {
            Write-Output ("  {0}:{1}:{2}" -f $m.Path, $m.LineNumber, $m.Line.Trim())
        }
        $script:totalHits += $matches.Count
    }
}

Write-Output "# Quick Scan - $TargetDir"
Write-Output "# $($javaFiles.Count) arquivo(s) .java analisados"

# A05 - Injection
Invoke-Check -Label "Concatenacao de String em Query (candidato a SQL Injection)" -Owasp "A05" `
    -Pattern '(createQuery|createNativeQuery)\([^)]*\+' -Files $javaFiles
Invoke-Check -Label "Statement.createStatement (candidato a SQL Injection)" -Owasp "A05" `
    -Pattern 'Statement .*=.*createStatement' -Files $javaFiles

# A09 - Logging & Alerting Failures
Invoke-Check -Label "printStackTrace (vaza stack trace / nao estruturado)" -Owasp "A09" `
    -Pattern '\.printStackTrace\(' -Files $javaFiles

# A08 - Software or Data Integrity Failures
Invoke-Check -Label "ObjectInputStream / readObject (candidato a deserializacao insegura)" -Owasp "A08" `
    -Pattern '(ObjectInputStream|\.readObject\()' -Files $javaFiles
Invoke-Check -Label "Jackson enableDefaultTyping (polymorphic deserialization sem allowlist)" -Owasp "A08" `
    -Pattern 'enableDefaultTyping' -Files $javaFiles

# A04 - Cryptographic Failures
Invoke-Check -Label "Algoritmo criptografico fraco ou obsoleto" -Owasp "A04" `
    -Pattern '(AES/ECB|DES/|"MD5"|"SHA-1"|"SHA1")' -Files $javaFiles
Invoke-Check -Label "new Random() (nao e criptograficamente seguro)" -Owasp "A04" `
    -Pattern 'new Random\(\)' -Files $javaFiles
Invoke-Check -Label "TLS/hostname verification desabilitado" -Owasp "A04" `
    -Pattern '(TrustAllCerts|ALLOW_ALL_HOSTNAME_VERIFIER|NoopHostnameVerifier)' -Files $javaFiles

# A01 - Broken Access Control (CSRF/CORS inclusos)
Invoke-Check -Label "CSRF desabilitado" -Owasp "A01" `
    -Pattern 'csrf\([^)]*\.disable\(\)' -Files $javaFiles
Invoke-Check -Label "CORS com origem wildcard" -Owasp "A01" `
    -Pattern '(allowedOrigins\("\*"\)|@CrossOrigin\(origins\s*=\s*"\*"\))' -Files $javaFiles

# A05 - XXE
Invoke-Check -Label "DocumentBuilderFactory sem hardening visivel (verificar se DTD esta desabilitado)" -Owasp "A05" `
    -Pattern 'DocumentBuilderFactory\.newInstance\(\)' -Files $javaFiles

# A04 - Secrets Management
Invoke-Check -Label "Possivel segredo hardcoded (confirmar manualmente - regex nao distingue placeholder de valor real)" -Owasp "A04" `
    -Pattern '(password|secret|apiKey|api_key)\s*=\s*"[^"$]{3,}"' -Files $javaFiles

Write-Output ""
Write-Output "# Total de achados candidatos: $totalHits"
if ($totalHits -gt 0) {
    Write-Output "# Proximo passo: para cada achado, abra o arquivo, confirme se e um falso positivo e,"
    Write-Output "# se for real, consulte o arquivo de references/ correspondente a categoria OWASP para"
    Write-Output "# o padrao de correcao (GOOD/BAD)."
} else {
    Write-Output "# Nenhum candidato encontrado pelos padroes deste script. Isto NAO significa que o"
    Write-Output "# codigo esta seguro - continue com o Security Checklist completo do SKILL.md."
}
