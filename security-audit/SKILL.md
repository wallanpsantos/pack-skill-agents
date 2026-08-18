---
name: security-audit
description: Checklist de segurança para Java 21+ (Spring Boot 4.1+, Quarkus, Jakarta EE e Java puro) cobrindo o OWASP Top 10:2025 completo — validação de entrada, SQL Injection, XSS, CSRF, SSRF, autenticação/autorização, JWT, criptografia, gestão de segredos, desserialização, supply chain, containers e headers de segurança — além de criptografia pós-quântica (ML-KEM, ML-DSA, resistência a computação quântica) para sistemas em bancos, meios de pagamento, seguradoras e saúde. Usar sempre que o usuário pedir revisão de segurança de código, auditoria antes de produção, análise de vulnerabilidade, conformidade com OWASP, threat modeling, avaliação de risco quântico/pós-quântico, ou mencionar termos como "SQLi", "XSS", "CSRF", "SSRF", "pentest", "hardening", "post-quantum", "quantum-safe", "está seguro?" ou "pode ir pra produção?".
compatibility: Requer Bash (Linux/macOS/Git Bash) ou PowerShell 5.1+/cmd (Windows) para rodar scripts/quick_scan.*; exemplos de código assumem Java 21+, com ML-KEM/ML-DSA nativos exigindo JDK 24+ (ver references/post-quantum-cryptography.md)
license: Proprietary - Internal use only
---

# Security Audit Skill

Checklist de segurança para aplicações Java 21+ baseado no OWASP Top 10:2025. Funciona com Spring Boot 4.1+, Quarkus,
Jakarta EE e Java puro.

## Quando Usar

- Revisão de segurança de código (código próprio ou de terceiros)
- Auditoria antes de release/produção
- Usuário pergunta sobre "segurança", "vulnerabilidade", "OWASP", "está exposto a X?"
- Revisão de autenticação/autorização
- Verificação de vulnerabilidades de injeção (SQL, XSS, XXE)
- Auditoria de supply chain (dependências, build)
- Revisão de deployment em container/cloud
- Threat modeling de uma feature nova
- Sistema em setor regulado (banco, meios de pagamento, seguradora, saúde/hospital) que precisa avaliar risco de
  computação quântica na criptografia usada

## Fluxo de Trabalho

1. **Triagem rápida (opcional, se houver código-fonte acessível):** execute
   `scripts/quick_scan.sh <diretório>`. É um grep determinístico — trata cada linha retornada como
   **candidato**, nunca como achado confirmado. Falsos positivos são esperados.
2. **Percorra o Security Checklist** abaixo, camada por camada (Desenvolvimento → Pipeline → Infraestrutura).
3. **Para cada item que gerar dúvida técnica ou exigir o padrão de código correto**, abra o arquivo de
   `references/` correspondente ao domínio (mapa abaixo). Leia o arquivo completo — não use `head`/`tail` para
   pré-visualizar, os índices já estão no topo de cada arquivo.
4. **Reporte os achados** com severidade, local (`arquivo:linha`), impacto e mitigação.
5. Se o usuário pedir apenas um plano (vai aplicar as correções manualmente), siga a regra "Do Not Commit on
   Request" em Execution Rules.

## Mapa de Referências

Cada arquivo cobre um domínio coeso e tem seu próprio índice. Leia apenas o que for relevante para o código em
revisão — não é necessário carregar todos.

| Arquivo                                                  | Domínio                                                                        |
|-----------------------------------------------------------|---------------------------------------------------------------------------------|
| `references/input-validation-injection.md`                 | Bean Validation, sanitização de HTML, allowlist, XXE, path traversal/zip slip, SQL Injection, XSS |
| `references/access-control-auth-api.md`                    | CSRF, autenticação, BOLA/IDOR, JWT/OAuth2, rate limiting, exposição de API REST  |
| `references/ssrf-crypto-secrets.md`                         | SSRF, criptografia simétrica (AES/GCM), gestão de segredos                      |
| `references/deserialization-supplychain-container.md`      | Desserialização segura (Jackson), SBOM/assinatura de artefatos, hardening de container/Kubernetes |
| `references/resilience-observability.md`                   | Tratamento de exceções (ProblemDetail RFC 9457), logging/PII masking, auditoria de dependências, security headers |
| `references/spring-boot.md`                                 | Específico de Spring Boot 4.1+: `SecurityFilterChain`, `InetAddressFilter`, Actuator, observability |
| `references/post-quantum-cryptography.md`                   | ML-KEM/ML-DSA (FIPS 203/204/205), suporte em Java (nativo vs Bouncy Castle), TLS híbrido, priorização de migração e panorama regulatório para bancos/seguradoras/saúde |

## Script Utilitário

Varredura read-only por padrões comuns de vulnerabilidade (concatenação em query, `printStackTrace`, algoritmo
criptográfico fraco, CSRF desabilitado, CORS wildcard, segredo hardcoded candidato). Não modifica arquivos. Execute
o script apropriado ao shell disponível — não leia o código-fonte deles como referência.

| Shell disponível          | Comando                                                          |
|------------------------------|---------------------------------------------------------------------|
| Linux / macOS / Git Bash     | `bash scripts/quick_scan.sh <diretório>`                            |
| cmd (Windows)                 | `scripts\quick_scan.bat <diretório>`                                 |
| PowerShell (Windows)          | `powershell -ExecutionPolicy Bypass -File scripts\quick_scan.ps1 <diretório>` |

`quick_scan.bat` é apenas um wrapper que chama `quick_scan.ps1` — use-o quando só houver acesso a cmd. Os três
scripts aplicam exatamente os mesmos padrões e produzem a mesma saída.

---

## OWASP Top 10:2025 Quick Reference

| #   | Risk                                        | Primary CWE      | Mitigation in Java 21+                                                   |
|-----|---------------------------------------------|------------------|--------------------------------------------------------------------------|
| A01 | Broken Access Control (includes SSRF)       | CWE-284, CWE-918 | Service layer role checks, deny-by-default, validate outgoing URLs/hosts |
| A02 | Security Misconfiguration                   | CWE-16           | Disable debug, secure headers, container hardening                       |
| A03 | Software Supply Chain Failures (new)        | CWE-1395         | SBOM, artifact signing, provenance verification, dependency scanning     |
| A04 | Cryptographic Failures                      | CWE-327          | Strong algorithms, no hardcoded secrets, TLS 1.2+                        |
| A05 | Injection                                   | CWE-89, CWE-79   | Parameterized queries, input validation, allowlist                       |
| A06 | Insecure Design                             | CWE-657          | Threat modeling (STRIDE/Cornucopia), secure defaults                     |
| A07 | Authentication Failures                     | CWE-287          | MFA, session management, strict JWT validation, OAuth2 resource server   |
| A08 | Software or Data Integrity Failures         | CWE-345          | Verify signatures, secure deserialization, explicit Jackson allowlist    |
| A09 | Logging & Alerting Failures                 | CWE-778          | Log security events, mask PII, automated SIEM alerts                     |
| A10 | Mishandling of Exceptional Conditions (new) | CWE-705          | Explicit error handling, ProblemDetail (RFC 9457), no stack trace leak   |

> Note: In OWASP Top 10:2021, SSRF was a standalone category (A10). In Top 10:2025, it was merged into Broken Access
> Control (A01). The technical SSRF section below remains fully relevant.

---

## Security Checklist

### 1. Camada de Desenvolvimento (Design & Código)

- [ ] **Input Validation:** Allowlist com `@Pattern`, `@Size` em todos os inputs de fronteira.
- [ ] **HTML Sanitization:** OWASP Java HTML Sanitizer centralizado para prevenir XSS/HTML injection.
- [ ] **XXE:** Parsers XML configurados com DTDs desabilitados.
- [ ] **Path Traversal & Zip Slip:** Validação de paths em uploads e extrações de `.zip`.
- [ ] **SQL Injection:** Queries parametrizadas (JPA, Criteria API, PreparedStatement).
- [ ] **BOLA/IDOR:** Verificação de ownership no service layer para cada recurso acessado.
- [ ] **Access Control:** `@PreAuthorize` / `@RolesAllowed` + verificação programática no service layer.
- [ ] **Cryptography:** AES/GCM para dados em repouso. AES/ECB proibido. `SecureRandom` obrigatório.
- [ ] **Spring Security Crypto:** `BytesEncryptor` (Encryptors.stronger) para campos sensíveis em BD.
- [ ] **Rate Limiting:** Implementado em endpoints de autenticação e reset de senha (Bucket4j / SCG).
- [ ] **Exception Handling (A10):** `@ControllerAdvice` com `ProblemDetail` (RFC 9457). Sem stack trace leak.
- [ ] **Secure Deserialization:** Jackson com `deactivateDefaultTyping()` ou allowlist explícita
  (`BasicPolymorphicTypeValidator`).
- [ ] **JWT Tokens:** `spring-boot-starter-oauth2-resource-server` ou validação explícita de `iss`, `aud`, `exp`, `alg`.
- [ ] **Threat Modeling:** STRIDE ou OWASP Cornucopia aplicado no design de novas features.
- [ ] **AI/LLM Security:** Se LLMs integrados, OWASP Top 10 for LLM aplicado.
- [ ] **Testcontainers:** Versão `2.0.5+` para alinhamento com Java 25.

### 2. Camada de Pipeline (CI/CD & SCA)

- [ ] **SAST:** Semgrep ou SpotBugs + FindSecBugs no pipeline de CI (falha o build em críticos).
- [ ] **SCA:** OWASP Dependency Check — falha em CVSS > 7.
- [ ] **SBOM:** CycloneDX plugin gerando BOM em todo build de release.
- [ ] **Artifact Signing:** Imagens e artefatos assinados com Sigstore/Cosign.
- [ ] **CodeQL:** GitHub CodeQL ou equivalente para análise semântica.
- [ ] **DAST:** OWASP ZAP / Nuclei integrado no pipeline de staging.
- [ ] **Dependabot:** Habilitado para alertas automáticos de dependências vulneráveis.

### 3. Camada de Infraestrutura & Runtime

- [ ] **CORS:** Configuração restritiva — proibido `*` com `Allow-Credentials: true`.
- [ ] **Security Headers:** CSP, HSTS, `X-Content-Type-Options`, `X-Frame-Options`, `Permissions-Policy`.
- [ ] **Secrets Management:** Vault / AWS Secrets Manager / Spring Cloud Config. Zero hardcode.
- [ ] **Container Hardening:** Imagens distroless, `non-root`, `readOnlyRootFilesystem`, capabilities dropadas.
- [ ] **Kubernetes Security Context:** `runAsNonRoot`, `allowPrivilegeEscalation: false`, `capabilities: drop ALL`.
- [ ] **Zero Trust / mTLS:** mTLS entre serviços via Istio/Linkerd em produção.
- [ ] **Actuator Hardening:** Expor apenas endpoints necessários, em porta separada, protegidos por role.
- [ ] **Logging Masking:** PII mascarado (CPF, email, cartão) via MaskingConverter ou Jackson serializer.
- [ ] **Security Alerts:** Falhas de autenticação, escaladas de privilégio e anomalias 5xx geram alertas no SIEM.
- [ ] **Penetration Testing:** ZAP, Burp ou Nuclei executados antes de releases críticos.

### 4. Quantum Readiness (Bancos, Meios de Pagamento, Seguradoras, Saúde — quando aplicável)

Aplica-se quando o sistema processa dados de retenção regulatória longa (anos) ou está sujeito a PCI DSS 4.0, HIPAA,
DORA ou norma equivalente. Ver `references/post-quantum-cryptography.md` antes de reportar qualquer item aqui como
achado — a severidade correta depende do tempo de retenção do dado, não é automaticamente crítica.

- [ ] **Inventário Criptográfico:** Uso de RSA/ECDH/ECDSA mapeado por serviço, com o dado protegido e o tempo de
  retenção de cada um documentados.
- [ ] **Dados de Retenção Longa:** Backups e dados com retenção regulatória de anos (prontuário médico, registro
  contábil, apólice) têm plano de migração para ML-KEM/ML-DSA (ou esquema híbrido) na proteção de chave/assinatura.
- [ ] **Crypto-Agility:** Nome do algoritmo isolado em configuração central, não hardcoded em múltiplos call sites.
- [ ] **TLS em Trânsito:** Terminação TLS externa (gateway/CDN/load balancer) avaliada quanto a suporte a hybrid key
  exchange (`X25519MLKEM768`), independente da versão do JDK da aplicação.

---

## Threat Modeling

Antes de codificar, aplique threat modeling no design com **STRIDE** ou **OWASP Cornucopia**:

| Ameaça STRIDE              | Pergunta-chave             | Mitigação                      |
|----------------------------|----------------------------|--------------------------------|
| **S**poofing               | Quem está chamando?        | Autenticação forte, JWT/mTLS   |
| **T**ampering              | Dados podem ser alterados? | Integridade (HMAC, signatures) |
| **R**epudiation            | Ações podem ser negadas?   | Audit log imutável             |
| **I**nfo Disclosure        | O que vaza?                | Masking, RBAC, HTTPS           |
| **D**enial of Service      | O que pode sobrecarregar?  | Rate limiting, circuit breaker |
| **E**levation of Privilege | Como escalar permissões?   | Deny-by-default, @PreAuthorize |

## AI/ML Security (LLM Apps)

Se a aplicação integra modelos de linguagem (LLMs), aplique o **OWASP Top 10 for LLM Applications**:

| Risco LLM                        | Mitigação                                          |
|----------------------------------|----------------------------------------------------|
| Prompt Injection                 | Sanitização de inputs, sistema de prompts separado |
| Sensitive Information Disclosure | Não incluir PII/secrets no contexto do LLM         |
| Insecure Output Handling         | Tratar saída do LLM como dado não confiável        |
| Model Denial of Service          | Rate limiting por usuário nos endpoints de IA      |

## Quantum Readiness (Post-Quantum Cryptography)

Não é uma categoria do OWASP Top 10:2025 — é uma extensão setorial para sistemas com dados de retenção longa ou sob
PCI DSS/HIPAA/DORA. Risco real hoje: **Harvest Now, Decrypt Later** (dado capturado hoje, descriptografado quando
houver hardware quântico capaz). Detalhes completos, código e panorama regulatório em
`references/post-quantum-cryptography.md`.

| Componente                        | Efeito da Computação Quântica          | Ação                                             |
|--------------------------------------|--------------------------------------------|-----------------------------------------------------|
| Troca de chave (RSA, ECDH)            | Quebrado por completo (Shor's algorithm)   | Migrar para ML-KEM (FIPS 203) ou híbrido            |
| Assinatura (RSA, ECDSA)               | Quebrada por completo (Shor's algorithm)   | Migrar para ML-DSA (FIPS 204) ou híbrido            |
| Cifragem simétrica (AES-256)          | Enfraquecida pela metade (Grover's algorithm) | Já adequado — não trocar de algoritmo, só evitar AES-128 |
| TLS em trânsito                       | Vulnerável a HNDL sem hybrid key exchange   | Ver suporte por versão de JDK/BouncyCastle no arquivo de referência |

## Execution Rules

* **Do Not Commit on Request:** Se o usuário especificar que fará os ajustes manualmente ou pedir apenas um plano, NÃO
  modifique o codebase. Em vez disso, crie um plano de auditoria como artefato markdown usando
  `assets/audit-report-template.md` como modelo, preenchendo vulnerabilidade, impacto e bloco de mitigação para
  cada achado.
* **Generate HTML Report Option:** Quando solicitado, gere um relatório de findings em HTML usando a skill `pdf` ou
  templates Markdown → HTML.
* **GitHub Security Integration:** Ao criar planos de CI/CD, inclua CodeQL, Dependabot e Dependency Review actions do
  GitHub.

---

## Referências e Ferramentas

| Categoria            | Ferramenta / Link                                                                                                                                 |
|----------------------|---------------------------------------------------------------------------------------------------------------------------------------------------|
| OWASP Top 10:2025    | [owasp.org/Top10](https://owasp.org/Top10)                                                                                                        |
| OWASP Cheat Sheets   | [cheatsheetseries.owasp.org](https://cheatsheetseries.owasp.org)                                                                                  |
| OWASP Top 10 for LLM | [owasp.org/www-project-top-10-for-large-language-model-applications](https://owasp.org/www-project-top-10-for-large-language-model-applications/) |
| SAST                 | Semgrep, SpotBugs + FindSecBugs                                                                                                                   |
| DAST                 | OWASP ZAP, Burp Suite, Nuclei                                                                                                                     |
| SCA                  | OWASP Dependency Check, GitHub Dependabot                                                                                                         |
| Secrets Scanning     | GitHub Secret Scanning, Trufflehog                                                                                                                |
| Supply Chain         | Cosign (Sigstore), Syft, Grype                                                                                                                    |
| Threat Modeling      | OWASP Cornucopia, STRIDE (Microsoft Threat Modeling Tool)                                                                                         |
| Crypto               | Google Tink, Spring Security Crypto                                                                                                               |
| Service Mesh         | Istio, Linkerd (mTLS)                                                                                                                             |
| Secrets Manager      | HashiCorp Vault, AWS Secrets Manager                                                                                                              |
| SIEM                 | ELK + Wazuh, OpenSearch, Grafana + Loki                                                                                                           |
| Padrões PQC          | NIST CSRC PQC Standardization (FIPS 203/204/205), NSA CNSA 2.0                                                                                    |
| PQC em Java          | OpenJDK JEP 496/497/527, Bouncy Castle PQC Almanac (`bcprov-jdk18on`)                                                                              |

---

## Related Skills

- `java-code-review` — General code review
- `maven-dependency-audit` — Dependency vulnerability scanning
- `logging-patterns` — Secure logging practices
- `pdf` — Geração de relatórios de auditoria em PDF/HTML
