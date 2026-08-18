# Auditoria de Segurança (Security Audit)

**Como carregar**: `view_file` no caminho relativo `skills/security-audit/SKILL.md`

---

## Descrição

Checklist de segurança para aplicações Java 21+ baseado no OWASP Top 10:2025. O núcleo é independente de framework e conta com seções e guias detalhados específicos para **Spring Boot 4.1+**, **Quarkus** e **Jakarta EE**, além de suportar análises de **Inteligência Artificial (LLM)** e **Quantum Readiness / Criptografia Pós-Quântica (PQC)**.

---

## Casos de Uso

- "Revise este código em busca de problemas de segurança"
- "Verifique se há vulnerabilidades de injeção de SQL (SQLi)"
- "Esta autenticação é segura?"
- "Auditoria de segurança antes de ir para produção"
- "Verificação de conformidade com o OWASP Top 10"
- "Threat modeling de uma nova funcionalidade ou API"
- "Avaliação de risco de computação quântica (PQC) na criptografia usada"

---

## Fluxo de Trabalho (Workflow)

Para realizar uma auditoria de segurança sistemática com esta skill:
1. **Triagem Rápida:** Execute os scripts utilitários `quick_scan` no diretório do seu código-fonte para detectar de forma rápida potenciais padrões vulneráveis.
2. **Security Checklist:** Percorra as três camadas do Checklist de Segurança (Desenvolvimento, Pipeline e Infraestrutura).
3. **Consulta de Referências:** Sempre que houver dúvidas sobre o padrão de mitigação correto, abra e consulte os arquivos do **Mapa de Referências** na pasta `references/`.
4. **Relatório de Auditoria:** Crie o plano ou relatório preenchendo as vulnerabilidades e propostas de mitigação com base no template `assets/audit-report-template.md`.

---

## Scripts Utilitários (`quick_scan`)

A skill inclui scripts para varredura determinística e *read-only* de código-fonte em busca de falhas comuns (concatenação em queries SQL, uso de `printStackTrace`, algoritmos criptográficos fracos, CSRF desabilitado, etc.). Eles não modificam seus arquivos.

Execute o script de acordo com seu terminal disponível:

| Plataforma / Shell | Comando |
| :--- | :--- |
| **Linux / macOS / Git Bash** | `bash scripts/quick_scan.sh <diretório>` |
| **PowerShell (Windows)** | `powershell -ExecutionPolicy Bypass -File scripts\quick_scan.ps1 <diretório>` |
| **CMD (Windows)** | `scripts\quick_scan.bat <diretório>` |

*Nota: O script realiza busca por padrões de strings (grep determinístico). Trate cada ocorrência como um candidato à análise manual.*

---

## Mapa de Referências Modulares

Cada arquivo abaixo cobre um domínio técnico de segurança com explicações, vulnerabilidades e exemplos de mitigação em Java moderno.

| Arquivo | Domínio Técnico Coberto |
| :--- | :--- |
| [references/input-validation-injection.md](references/input-validation-injection.md) | Bean Validation JSR 380, allowlists, prevenção de SQLi, XSS, XXE e Path Traversal / Zip Slip. |
| [references/access-control-auth-api.md](references/access-control-auth-api.md) | Proteção CSRF, autenticação, BOLA/IDOR, tokens JWT/OAuth2 e estratégias de Rate Limiting. |
| [references/ssrf-crypto-secrets.md](references/ssrf-crypto-secrets.md) | Prevenção de SSRF, criptografia simétrica com AES/GCM e gestão segura de segredos em runtime. |
| [references/deserialization-supplychain-container.md](references/deserialization-supplychain-container.md) | Jackson Polymorphic Type Validation, SBOM com CycloneDX, assinaturas com Cosign e hardening de containers e Kubernetes. |
| [references/resilience-observability.md](references/resilience-observability.md) | Tratamento de exceções com ProblemDetail (RFC 9457), log masking de dados sensíveis (PII) e cabeçalhos de segurança (CSP, HSTS). |
| [references/spring-boot.md](references/spring-boot.md) | Regras específicas para Spring Boot 4.1+, hardening do Actuator, mTLS e SecurityFilterChain. |
| [references/post-quantum-cryptography.md](references/post-quantum-cryptography.md) | Suporte a algoritmos quânticos (ML-KEM, ML-DSA - FIPS 203/204/205) em Java (nativo vs Bouncy Castle), TLS híbrido, agilidade criptográfica e conformidades regulatórias (PCI DSS 4.0, DORA). |

---

## Cobertura do OWASP Top 10:2025

Esta skill e suas referências estão alinhadas com as mitigações exigidas pela versão mais recente do OWASP Top 10:

| # | Risco OWASP | CWE Primário | Mitigação no Java 21+ |
| :--- | :--- | :--- | :--- |
| **A01** | Broken Access Control (inclui SSRF) | CWE-284, CWE-918 | Controle de acesso deny-by-default, validações no service layer, validação rígida de URLs externas. |
| **A02** | Security Misconfiguration | CWE-16 | Headers de segurança ativos, Actuator restrito, remoção de endpoints de debug. |
| **A03** | Software Supply Chain Failures | CWE-1395 | Auditoria de dependências, geração de SBOM, assinatura digital de artefatos. |
| **A04** | Cryptographic Failures | CWE-327 | Uso de algoritmos robustos, chaves criptográficas fortes, mTLS e tráfego HTTPS obrigatório. |
| **A05** | Injection | CWE-89, CWE-79 | Consultas parametrizadas (JPA/Criteria), validação estruturada com Bean Validation e sanitização HTML. |
| **A06** | Insecure Design | CWE-657 | Modelagem de ameaças no design da aplicação (STRIDE / OWASP Cornucopia). |
| **A07** | Authentication Failures | CWE-287 | Multi-factor authentication (MFA), gerenciamento seguro de sessões e rate limiting em endpoints críticos. |
| **A08** | Software or Data Integrity Failures | CWE-345 | Validação de assinaturas de código e deserialização Jackson segura (com allowlists). |
| **A09** | Logging & Alerting Failures | CWE-778 | Registro estruturado de eventos de segurança importantes, auditoria de falhas e mascaramento de PII. |
| **A10** | Mishandling of Exceptional Conditions | CWE-705 | Uso do ProblemDetail (RFC 9457) centralizado e supressão de stack traces em respostas HTTP. |

---

## Recursos e Modelos Relacionados

- **Template de Auditoria:** Acesse [assets/audit-report-template.md](assets/audit-report-template.md) para gerar os relatórios de auditoria técnica da skill.
- **Related Skills:**
  - `java-code-review` — Revisão de código padrão Java.
  - `maven-dependency-audit` — Varredura aprofundada de dependências Maven.
  - `logging-patterns` — Formatação estruturada e segura de logs.
  - `pdf` — Geração e conversão de relatórios de markdown para HTML/PDF.
