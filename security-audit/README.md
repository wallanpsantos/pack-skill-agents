# Auditoria de Segurança (Security Audit Skill)

Checklist e método de auditoria de segurança para backends na JVM — APIs, workers, consumidores de mensageria e serviços
distribuídos em **Java 25 LTS+**, **Kotlin 2.4+** (somente JVM) e **Spring Boot 4.1.1+** (Spring MVC, WebFlux, Spring
Security 7.1, Jackson 3).

Alinhado rigorosamente com o **OWASP Top 10:2025**, **OWASP API Security Top 10:2023** e **OWASP ASVS 5.0**.

---

## Escopo Tecnológico

| Suportado oficialmente                                      | Fora de escopo (não gerar regras ou achados específicos) |
|-------------------------------------------------------------|----------------------------------------------------------|
| Java 25 LTS+                                                | Android, Kotlin Multiplatform (KMP)                      |
| Kotlin 2.4+ **somente JVM** (servidor)                      | Kotlin/Native, Kotlin/JS, Kotlin/Wasm                    |
| Spring Boot 4.1.1+, Spring Framework 7, Spring Security 7.1 | Aplicações mobile, desktop e frontend (SPA, browser)     |
| Spring MVC e Spring WebFlux (inclusive coroutines)          |                                                          |
| Maven e Gradle (inclusive Kotlin DSL)                       |                                                          |
| Contêineres (Docker/Distroless), Kubernetes e Cloud         |                                                          |

---

## Quando Usar

- Revisão de segurança de código próprio ou de terceiros, PR ou módulo.
- Auditoria antes de release ou entrada em produção ("pode ir pra produção?").
- Levantamento e inventário de vulnerabilidades e riscos de arquitetura.
- Revisão de autenticação, autorização, multi-tenancy, OAuth2/OIDC/JWT.
- Hardening de Spring Boot (Actuator, erros, perfis), contêineres, Kubernetes e CI/CD.
- Triagem de CVEs de dependências e avaliação de cadeia de suprimentos (Supply Chain).
- Threat modeling de feature ou API nova (STRIDE / abuso de fluxo de negócio).
- Avaliação de risco criptográfico pós-quântico (ML-KEM/ML-DSA) em setores regulados (bancos, pagamentos, seguradoras,
  saúde).

---

## Modos de Execução

| Modo                          | Gatilhos típicos                                             | Comportamento                                                                                                                            |
|-------------------------------|--------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------|
| **Auditoria completa**        | "audita o serviço", "revisão geral", "pode ir pra produção?" | Escopo = repositório/serviço inteiro, incluindo build, CI, Dockerfile e manifestos.                                                      |
| **Auditoria direcionada**     | Caminho, módulo ou PR informado                              | Escopo = caminho informado + fronteiras (quem chama, o que ele chama, configuração que o afeta).                                         |
| **Levantamento (inventário)** | "lista as vulnerabilidades", "levanta os riscos"             | Apenas a lista (severidade, categoria, local, descrição curta). Sem correção e sem plano estendido — implica *Do Not Commit on Request*. |

---

## Scripts Utilitários de Pré-Varredura (`quick_scan`)

A skill inclui scripts de varredura estática determinística dirigida pelo catálogo unificado
`scripts/quick_scan_rules.txt`.
Os scripts são **somente leitura** e suportam o parâmetro `--fail-on`:

| Shell / Ambiente             | Comando                                                                                                    |
|------------------------------|------------------------------------------------------------------------------------------------------------|
| **Linux / macOS / Git Bash** | `bash scripts/quick_scan.sh [--fail-on alto\|medio\|nunca] <diretório>`                                    |
| **PowerShell (Windows)**     | `powershell -ExecutionPolicy Bypass -File scripts\quick_scan.ps1 <diretório> [-FailOn alto\|medio\|nunca]` |
| **CMD (Windows)**            | `scripts\quick_scan.bat <diretório> [-FailOn alto\|medio\|nunca]`                                          |

- **Níveis de saída:** `ALTO`, `MEDIO`, `INFO` representam a prioridade de triagem do candidato (a severidade final é
  determinada após confirmação manual).
- **Proteção de Segredos:** Regras que detectam credenciais imprimem estritamente `arquivo:linha`, garantindo que o
  valor confidencial **nunca** seja exibido.
- **Códigos de Saída:**
    - `0`: Nenhum candidato encontrado no nível de falha configurado (padrão `alto`).
    - `1`: Candidatos encontrados atingindo ou superando o critério de falha.
    - `2`: Erro de uso, diretório inexistente ou catálogo ausente.

---

## Mapa de Referências Técnicas

A pasta `references/` contém guias detalhados com explicações normativas e exemplos de código contrastantes (*BAD* vs
*GOOD*):

| Arquivo                                                                                                    | Domínio Técnico Coberto                                                                                                                                                                                                                                             |
|------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [references/audit-matrix.md](references/audit-matrix.md)                                                   | Taxonomia cruzada (Top 10:2025 × API Top 10:2023 × ASVS 5.0), matriz de severidade, níveis de confiança, sinais auditáveis e evidência mínima por categoria.                                                                                                        |
| [references/access-control-auth-api.md](references/access-control-auth-api.md)                             | `SecurityFilterChain`/`SecurityWebFilterChain`, autorização em camadas, BOLA/BFLA, multi-tenancy, OAuth2/OIDC/JWT, senhas (Argon2id), CSRF, CORS, open redirects, rate limit, idempotência e inventário de APIs.                                                    |
| [references/input-validation-injection.md](references/input-validation-injection.md)                       | Bean Validation em Java e Kotlin, SQL/JPQL/HQL Injection, NoSQL, LDAP, command injection, SpEL injection, XXE, YAML injection, upload de arquivos, Path Traversal, Zip Slip e ReDoS.                                                                                |
| [references/ssrf-crypto-secrets.md](references/ssrf-crypto-secrets.md)                                     | SSRF e `InetAddressFilter`, mitigação de DNS Rebinding, AES-GCM (proibição de ECB), derivação HKDF (`javax.crypto.KDF`), `SecureRandom`, comparação em tempo constante e gestão de segredos.                                                                        |
| [references/deserialization-supplychain-container.md](references/deserialization-supplychain-container.md) | Desserialização nativa (`ObjectInputFilter`), Jackson 3 sem default typing, kotlinx.serialization, supply chain Maven/Gradle, triagem de CVEs com VEX, SBOM CycloneDX, GitHub Actions seguro, Dockerfile Distroless e Kubernetes Pod Security Standards Restricted. |
| [references/resilience-observability.md](references/resilience-observability.md)                           | Princípio Fail-Closed, tratamento de erros com `ProblemDetail` (RFC 9457), timeouts, Circuit Breaker, Virtual Threads, mensageria assíncrona segura, mascaramento de PII em logs e Security Headers HTTP.                                                           |
| [references/spring-boot.md](references/spring-boot.md)                                                     | Spring Boot 4.1.1+: diferenciação estrita de perfis (dev vs prod), hardening do Actuator, `RestClient` com filtro de SSRF, observabilidade OpenTelemetry e testes automatizados de segurança com `MockMvc`.                                                         |
| [references/kotlin-jvm.md](references/kotlin-jvm.md)                                                       | Kotlin 2.4+ no servidor: nulidade e platform types, alvos de anotação (`@field:` em Bean Validation), data classes e vazamento em `toString()`, coroutines e propagação de contexto de segurança, proxies AOP com plugin `kotlin-spring`.                           |
| [references/post-quantum-cryptography.md](references/post-quantum-cryptography.md)                         | Criptografia Pós-Quântica (ML-KEM/ML-DSA - FIPS 203/204/205) nativa no JDK 25, TLS híbrido, agilidade criptográfica e panoramas regulatórios em setores financeiros e de saúde.                                                                                     |

---

## Modelo de Relatório de Auditoria

Para formalizar os achados confirmados, utilize o template padronizado
em [assets/audit-report-template.md](assets/audit-report-template.md), registrando:

- Cobertura explícita da análise (lido, apenas triagem, não tocado).
- Resumo executivo com contagem de vulnerabilidades por severidade e confiança.
- Lista de achados com evidência mínima: `arquivo:linha`, trecho redigido, pré-condições, cadeia fonte-a-sumidouro,
  impacto e teste de regressão automatizado.
- Plano de remediação priorizado.
