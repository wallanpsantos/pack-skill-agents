---
name: java-kotlin-security-audit
description: Auditoria de segurança para backends na JVM — APIs, workers, consumidores de mensageria e serviços distribuídos em Java 25 LTS+, Kotlin 2.4+ (somente JVM) e Spring Boot 4.1.1+ (Spring MVC, WebFlux, Spring Security 7) — alinhada ao OWASP Top 10:2025, OWASP API Security Top 10:2023 e OWASP ASVS 5.0. Cobre controle de acesso (BOLA/BFLA/IDOR, multi-tenancy), OAuth2/OIDC/JWT, injeção (SQL, NoSQL, LDAP, comando, SpEL, XXE), SSRF, criptografia e segredos, desserialização (Jackson 3, kotlinx.serialization), coroutines e virtual threads, tratamento de exceções e fail-closed, resiliência, supply chain Maven/Gradle, GitHub Actions, contêineres, Kubernetes e criptografia pós-quântica (ML-KEM/ML-DSA) para bancos, pagamentos, seguradoras e saúde. Usar sempre que o usuário pedir revisão de segurança, auditoria antes de produção, levantamento de vulnerabilidades, threat modeling, conformidade OWASP/ASVS, hardening de Spring Boot/Actuator/Kubernetes, análise de CVEs ou de pipeline, ou perguntar "está seguro?", "pode ir pra produção?", "tem SQLi/XSS/SSRF/IDOR?". Não usar para Android, Kotlin Multiplatform, Kotlin/Native, Kotlin/JS, Kotlin/Wasm, mobile, desktop ou frontend.
compatibility: Java 25 LTS ou superior; Kotlin 2.4+ no alvo JVM; Spring Boot 4.1.1+ (Spring Framework 7, Spring Security 7.1, Jackson 3). Nenhum exemplo depende de recurso preview/incubating. scripts/quick_scan.* exige Bash 3.2+ com grep/find/awk (Linux, macOS, Git Bash) ou PowerShell 5.1+/pwsh 7 (Windows, cmd via .bat).
license: Proprietary - Internal use only
---

# Security Audit Skill

Checklist e método de auditoria para backends na JVM. O objetivo é produzir achados **confirmados, priorizados e com
evidência**, não uma lista de palpites. Os scripts de
triagem geram candidatos; a confirmação é sempre manual.

## Escopo Tecnológico

| Suportado oficialmente                                      | Fora de escopo (não gerar regras, exemplos ou achados específicos) |
|-------------------------------------------------------------|--------------------------------------------------------------------|
| Java 25 LTS+                                                | Android, Kotlin Multiplatform (KMP)                                |
| Kotlin 2.4+ **somente JVM** (servidor)                      | Kotlin/Native, Kotlin/JS, Kotlin/Wasm                              |
| Spring Boot 4.1.1+, Spring Framework 7, Spring Security 7.1 | Aplicações mobile, desktop e frontend (SPA, browser)               |
| Spring MVC e Spring WebFlux (inclusive coroutines)          |                                                                    |
| Maven e Gradle (inclusive Kotlin DSL)                       |                                                                    |
| Contêineres, Kubernetes e cloud                             |                                                                    |

- Padrões de "Java puro" (JCA, JDBC, parsers XML, `ProcessBuilder`) valem para qualquer
  backend JVM. Frameworks diferentes de Spring (Quarkus, Jakarta EE, Micronaut) não têm
  referência dedicada: aplique os princípios e deixe isso explícito no relatório.
- O Spring Boot 4.1.x gerencia Kotlin 2.3.x por padrão. Projetos em Kotlin 2.4+ sobrescrevem
  a versão (`kotlin.version` no Maven; versão do plugin no Gradle). Ver `references/kotlin-jvm.md`.
- Quando o código-alvo estiver abaixo do baseline (ex.: Java 21, Boot 3.x), a própria versão
  é um achado (fim de suporte/patches) e os exemplos desta skill podem não compilar.

## Quando Usar

- Revisão de segurança de código próprio ou de terceiros, PR ou módulo.
- Auditoria antes de release/produção ("pode ir pra produção?").
- Levantamento/inventário de vulnerabilidades e riscos.
- Revisão de autenticação, autorização, multi-tenancy, OAuth2/OIDC/JWT.
- Hardening de Spring Boot (Actuator, erros, perfis), contêiner, Kubernetes e CI/CD.
- Triagem de CVEs de dependências e avaliação de supply chain.
- Threat modeling de feature ou API nova.
- Avaliação de risco quântico em setores regulados (banco, pagamentos, seguradora, saúde).

## Escopo e Modo de Execução

Antes de ler qualquer código, identifique **modo** e **escopo** — os dois mudam o comportamento.

| Modo                          | Gatilhos típicos                                             | Comportamento                                                                                                                        |
|-------------------------------|--------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------|
| **Auditoria completa**        | "audita o serviço", "revisão geral", "pode ir pra produção?" | Escopo = repositório/serviço inteiro, incluindo build, CI, Dockerfile e manifestos. Ver estratégia para repositório grande.          |
| **Auditoria direcionada**     | Caminho, módulo ou PR informado                              | Escopo = caminho informado + fronteiras (quem chama, o que ele chama, configuração de segurança que o afeta).                        |
| **Levantamento (inventário)** | "lista as vulnerabilidades", "levanta os riscos"             | Só a lista (severidade, categoria, local, descrição curta). Sem correção e sem plano estendido — implica "Do Not Commit on Request". |

**Se o pedido não deixar claro o modo ou o escopo, pergunte antes de ler código.** Não assuma.

### Estratégia para Serviço/Repositório Grande

1. **Triagem estrutural (sem ler corpos de arquivo):**
    - Rode `quick_scan.*` na raiz do escopo (candidatos a baixo custo).
    - Localize por nome/caminho as superfícies de maior risco:
        - entradas síncronas: `*Controller*`, `*Resource*`, `*Endpoint*`, `*Handler*`, `*Router*`
          (endpoints funcionais WebFlux), `*GrpcService*`;
        - entradas assíncronas: classes com `@KafkaListener`, `@RabbitListener`, `@JmsListener`,
          `@SqsListener`, `@Scheduled`, consumidores de webhook;
        - segurança: `*SecurityConfig*`, `*Filter*`, `SecurityFilterChain`, `SecurityWebFilterChain`,
          nomes com `Auth`, `Jwt`, `Token`, `Tenant`, `Permission`, `Crypto`, `Cipher`, `Password`,
          `Payment`, `Upload`, `Serializ`, `Webhook`, `Client` (chamadas de saída);
        - configuração e entrega: `application*.{properties,yml,yaml}`, `pom.xml`, `build.gradle(.kts)`,
          `settings.gradle(.kts)`, `gradle/libs.versions.toml`, `.github/workflows/*`, `Dockerfile*`,
          manifestos Kubernetes/Helm.
2. **Leitura dirigida, nesta ordem:** configuração de segurança → pontos de entrada (síncronos e
   assíncronos) → autorização por objeto/tenant → chamadas de saída (SSRF, APIs de terceiros) →
   criptografia/segredos → desserialização/upload → tratamento de erros e resiliência →
   build/CI/contêiner → restante.

**Reporte a cobertura explicitamente:** lido por completo, só triagem automática, não tocado (com motivo). Nunca dê a
impressão de cobertura total quando parte só passou por regex.

## Fluxo de Trabalho

1. **Modo e escopo** (seção acima). Registre também a stack real encontrada (versões de Java,
   Kotlin, Spring Boot, Spring Security) — ela muda o que é achado.
2. **Triagem:** `scripts/quick_scan.sh|.ps1|.bat <diretório>`. Cada linha é **candidato**.
3. **Checklist** abaixo, camada por camada, dentro do escopo.
4. **Referências:** para cada dúvida técnica ou padrão de correção, abra o arquivo de
   `references/` do domínio (mapa abaixo). Leia o arquivo inteiro — os índices estão no topo.
5. **Classifique** cada achado com `references/audit-matrix.md` (severidade, confiança,
   mapeamento OWASP/API/ASVS e evidência mínima).
6. **Reporte** com `assets/audit-report-template.md` (ou só a lista, em modo Levantamento).
7. Se o modo for Levantamento, ou o usuário pedir só plano, siga "Do Not Commit on Request".

## Mapa de Referências

| Arquivo                                               | Domínio                                                                                                                                                                                                                                                      |
|-------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `references/audit-matrix.md`                          | Taxonomia (Top 10:2025 × API Top 10:2023 × ASVS 5.0), severidade, confiança, sinais auditáveis e evidência por categoria                                                                                                                                     |
| `references/access-control-auth-api.md`               | `SecurityFilterChain`/`SecurityWebFilterChain`, autorização por URL/método/objeto/propriedade, BOLA/BFLA, multi-tenancy, OAuth2/OIDC/JWT/opaque token, senhas, sessão, CSRF, CORS, redirects, rate limiting, abuso de fluxo, idempotência, inventário de API |
| `references/input-validation-injection.md`            | Bean Validation (Java e Kotlin), SQL/JPQL, NoSQL, LDAP, comando, SpEL, XXE, YAML, upload/path traversal/zip slip, ReDoS, reflexão                                                                                                                            |
| `references/ssrf-crypto-secrets.md`                   | SSRF (`InetAddressFilter`, validação manual, DNS rebinding), AES-GCM, KDF/HKDF, aleatoriedade, comparação constante, TLS de cliente, gestão de segredos                                                                                                      |
| `references/deserialization-supplychain-container.md` | Serialização Java, Jackson 3, kotlinx.serialization, supply chain Maven/Gradle, CVEs/VEX, SBOM/proveniência, GitHub Actions, Dockerfile, Kubernetes                                                                                                          |
| `references/resilience-observability.md`              | Fail-closed, ProblemDetail, timeouts/retries/circuit breaker/backpressure, virtual threads, mensageria assíncrona, logging/PII, alertas, headers                                                                                                             |
| `references/spring-boot.md`                           | Spring Boot 4.1.1+: default × dev × produção, Actuator, perfis, erros, clientes HTTP, observabilidade, testes de segurança                                                                                                                                   |
| `references/kotlin-jvm.md`                            | Kotlin 2.4+ no servidor: nulidade/platform types, alvos de anotação, data classes, serialização, coroutines e contexto de segurança, proxies/`kotlin-spring`, build e dependências                                                                           |
| `references/post-quantum-cryptography.md`             | ML-KEM/ML-DSA nativos no JDK 25, TLS híbrido (JDK 27+/BCJSSE/terminação externa), priorização e panorama regulatório                                                                                                                                         |

## Script Utilitário

Varredura **somente leitura** dirigida pelo catálogo `scripts/quick_scan_rules.txt`
(regras compartilhadas pelas duas implementações; cada regra tem ID, nível, categoria OWASP e
descrição). Analisa `*.java`, `*.kt`, configuração Spring, `pom.xml`/Gradle, workflows do GitHub
Actions, Dockerfile e YAML de Kubernetes. Ignora `.git`, `.gradle`, `.idea`, `.mvn`,
`node_modules`, `target`, `build`, `out`. Execute o script — não o use como referência de correção.

| Shell                    | Comando                                                                                                  |
|--------------------------|----------------------------------------------------------------------------------------------------------|
| Linux / macOS / Git Bash | `bash scripts/quick_scan.sh [--fail-on alto\|medio\|nunca] <diretório>`                                  |
| PowerShell               | `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\quick_scan.ps1 <diretório> [-FailOn medio]` |
| cmd                      | `scripts\quick_scan.bat <diretório> [-FailOn medio]`                                                     |

- Níveis da saída: `ALTO`, `MEDIO`, `INFO` = prioridade de **triagem** do candidato, não
  severidade final (essa sai de `audit-matrix.md` depois da confirmação).
- Regras de segredo imprimem só `arquivo:linha` — o valor nunca aparece. Mantenha isso no
  relatório: evidência de segredo é localização + tipo, nunca o valor.
- Códigos de saída: `0` sem candidatos no nível de falha (padrão `alto`); `1` há candidatos no
  nível de falha; `2` uso inválido, pré-requisito ausente ou catálogo inválido.
- Nenhum candidato ≠ código seguro. Siga o checklist mesmo com saída vazia.

## Taxonomia

### OWASP Top 10:2025

| #   | Risco                                  | Mitigação típica em Java 25 / Kotlin 2.4 / Spring Boot 4.1                                                                                           |
|-----|----------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------|
| A01 | Broken Access Control (inclui SSRF)    | Deny-by-default na `SecurityFilterChain`; checagem de dono/tenant na consulta; `@PreAuthorize`; `InetAddressFilter` + allowlist em chamadas de saída |
| A02 | Security Misconfiguration              | Actuator mínimo e em porta separada; erros sem detalhes; perfis de produção explícitos; headers; K8s restrito                                        |
| A03 | Software Supply Chain Failures         | Versões fixas, verificação/locking Gradle, checksums estritos, SBOM, proveniência, Actions por SHA                                                   |
| A04 | Cryptographic Failures                 | AES-GCM, HKDF (`javax.crypto.KDF`), `SecureRandom`, segredos em cofre, TLS validado, inventário para PQC                                             |
| A05 | Injection                              | Parâmetros vinculados (JPA/`JdbcClient`), Criteria, argv sem shell, `SimpleEvaluationContext`, parsers XML endurecidos                               |
| A06 | Insecure Design                        | Threat modeling, limites de negócio, idempotência, anti-automação                                                                                    |
| A07 | Authentication Failures                | Resource server com `iss`/`aud`/`exp`/algoritmo validados, MFA, Argon2id/bcrypt, sessão segura                                                       |
| A08 | Software or Data Integrity Failures    | Sem default typing; filtros de desserialização; artefatos assinados; mensagens validadas                                                             |
| A09 | Security Logging and Alerting Failures | Eventos de segurança estruturados, sem segredos/PII, alertas acionáveis                                                                              |
| A10 | Mishandling of Exceptional Conditions  | Fail-closed, `ProblemDetail` sem stack trace, timeouts, cancelamento correto de coroutines                                                           |

### OWASP API Security Top 10:2023

| #     | Risco                                           | Onde tratar                                                             |
|-------|-------------------------------------------------|-------------------------------------------------------------------------|
| API1  | Broken Object Level Authorization               | A01 — `access-control-auth-api.md`                                      |
| API2  | Broken Authentication                           | A07 — `access-control-auth-api.md`                                      |
| API3  | Broken Object Property Level Authorization      | A01 — DTOs de entrada/saída, mass assignment                            |
| API4  | Unrestricted Resource Consumption               | A06/A10 — limites, paginação, rate limit, `resilience-observability.md` |
| API5  | Broken Function Level Authorization             | A01 — rotas administrativas, `@PreAuthorize`                            |
| API6  | Unrestricted Access to Sensitive Business Flows | A06 — anti-automação, quotas, idempotência                              |
| API7  | Server Side Request Forgery                     | A01 — `ssrf-crypto-secrets.md`                                          |
| API8  | Security Misconfiguration                       | A02 — `spring-boot.md`                                                  |
| API9  | Improper Inventory Management                   | A02/A06 — inventário, versões depreciadas, shadow APIs                  |
| API10 | Unsafe Consumption of APIs                      | A08/A10 — validar respostas, timeouts, TLS, SSRF                        |

Mapeamento para capítulos do ASVS 5.0 e sinais por categoria: `references/audit-matrix.md`.

## Severidade, Confiança e Evidência

Severidade = **impacto × explorabilidade** no contexto real (exposição, autenticação exigida,
sensibilidade do dado, alcance). Resumo (definições completas em `audit-matrix.md`):

| Severidade  | Critério resumido                                                                                                                                                                                 |
|-------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Crítico     | Explorável remotamente sem autenticação (ou por qualquer usuário) levando a RCE, bypass de autenticação/autorização em massa, vazamento massivo de dados sensíveis ou segredo de produção exposto |
| Alto        | Acesso a dados/ações de outro usuário ou tenant, escalada de privilégio, SSRF para rede interna/metadata, injeção com pré-condições moderadas                                                     |
| Médio       | Exige condições específicas ou tem impacto limitado; ausência de controle de defesa em profundidade com exploração plausível                                                                      |
| Baixo       | Hardening/boa prática com impacto mínimo                                                                                                                                                          |
| Informativo | Observação sem risco direto (inventário, dívida técnica relevante)                                                                                                                                |

Confiança: **Confirmado** (lido e com caminho de exploração claro), **Provável** (padrão
inseguro confirmado, alcance não demonstrado), **Suspeito** (candidato não confirmado — não
entra como achado em Auditoria; só em Levantamento, marcado como tal).

Evidência mínima por achado: `arquivo:linha` (ou chave de configuração/commit), trecho redigido,
pré-condições, cadeia fonte→sumidouro ou raciocínio de exploração, impacto, mitigação e como
verificar a correção (teste). Para CVE: coordenada da dependência, caminho no grafo, versão
corrigida e análise de alcance.

## Security Checklist

Nunca assuma que o default do Spring Boot basta para produção: diferencie **default**, **desenvolvimento** e
**produção** (`references/spring-boot.md`).

### 1. Design e Código (Java e Kotlin)

- [ ] **Threat model** (STRIDE/Cornucopia) para features novas, incluindo abuso de fluxo de negócio.
- [ ] **Validação na fronteira:** Bean Validation com allowlist e limites; em Kotlin, anotações
  chegando ao campo (alvos de anotação); tamanhos de coleção e profundidade limitados.
- [ ] **Injeção:** consultas parametrizadas (JPA/Criteria/`JdbcClient`), nada de template de
  String Kotlin em SQL; NoSQL/LDAP/SpEL/comando sem entrada crua; parsers XML endurecidos.
- [ ] **Upload/path traversal/zip slip:** nomes gerados, `normalize()` + `startsWith`, limites de extração.
- [ ] **Desserialização:** sem serialização nativa de entrada externa (ou `ObjectInputFilter`);
  Jackson 3 sem default typing; polimorfismo por nome lógico; kotlinx.serialization fechado.
- [ ] **Criptografia:** AES-GCM com IV aleatório de 12 bytes, sem ECB/`"AES"` implícito, HKDF
  para derivação, `SecureRandom`, `MessageDigest.isEqual` para segredos.
- [ ] **Segredos:** zero literal em código/config/imagem; cofre; `toString()`/logs sem segredos (records e data classes
  incluídos).
- [ ] **Erros (A10):** fail-closed; `ProblemDetail` sem stack trace/mensagem interna; exceções
  em decisões de segurança negam acesso.
- [ ] **Concorrência:** timeouts e cancelamento; coroutines sem `GlobalScope`/`runBlocking` no
  caminho de request; `CancellationException` não engolida; virtual threads com limite de
  concorrência e contexto propagado.
- [ ] **Kotlin:** platform types tratados na fronteira Java; `kotlin-spring` aplicado (proxies de
  `@PreAuthorize`/`@Transactional` não podem cair em classe/método `final`).
- [ ] **LLM integrado:** OWASP Top 10 for LLM Applications (entrada, saída, dados sensíveis, custo).

### 2. Spring Security, API e Autorização

- [ ] `SecurityFilterChain`/`SecurityWebFilterChain` explícitos, `anyRequest().authenticated()`
  (ou `denyAll()`) no final; sem `permitAll()` amplo; cadeias com `securityMatcher` na ordem certa.
- [ ] Autorização por **objeto** (BOLA) e **tenant** na consulta; por **função** (BFLA) em rotas
  administrativas; por **propriedade** (DTOs de entrada/saída, sem mass assignment).
- [ ] Resource server com `issuer-uri`, `audiences`, algoritmo fixo, `exp` obrigatório
  (`setAllowEmptyExpiryClaim(false)`), clock skew mínimo, scopes/authorities mapeados.
- [ ] Senhas com `DelegatingPasswordEncoder` (Argon2id/bcrypt); MFA onde o risco exigir.
- [ ] Sessão/cookies: `Secure`, `HttpOnly`, `SameSite`; CSRF ativo quando houver cookie de sessão.
- [ ] CORS com origens explícitas; nunca `allowedOriginPatterns("*")` com credenciais.
- [ ] Redirects só para destinos em allowlist.
- [ ] Rate limit/quotas por principal/tenant (e IP via proxy confiável), `429` + `Retry-After`;
  idempotência em operações de efeito colateral; proteção contra replay em webhooks.
- [ ] Limites de payload, paginação (`max-page-size`), profundidade JSON e buffers de codec.
- [ ] Inventário de APIs: OpenAPI desabilitado ou protegido em produção; versões depreciadas
  com prazo; nenhum endpoint fora do inventário (shadow API).
- [ ] Consumo de APIs externas: TLS validado, timeouts, validação de resposta, SSRF.

### 3. Pipeline e Supply Chain

- [ ] SAST (Semgrep/SpotBugs+FindSecBugs/CodeQL) e SCA (Dependency-Check/Dependabot/OSV) falham o build em críticos.
- [ ] Versões fixas; Gradle com dependency locking e verification metadata; Maven com
  checksums estritos, enforcer e repositório interno via HTTPS.
- [ ] CVEs priorizados por alcance, exposição, CISA KEV e EPSS; decisões registradas (VEX).
- [ ] SBOM CycloneDX por release; artefatos/imagens assinados e com proveniência (SLSA).
- [ ] GitHub Actions: `permissions` mínimas, actions fixadas por SHA, sem interpolação de dados
  do evento em `run:`, cuidado com `pull_request_target`, OIDC em vez de segredos longos.
- [ ] Secret scanning no código **e no histórico Git**; push protection.

### 4. Infraestrutura e Runtime

- [ ] Actuator: exposição mínima, porta de management separada, endpoints sensíveis fechados.
- [ ] Imagem mínima (distroless/JRE mínimo), não root, fixada por digest, sem segredos em camadas.
- [ ] Kubernetes: Pod Security `restricted`, `readOnlyRootFilesystem`, `drop: [ALL]`,
  `automountServiceAccountToken: false`, RBAC mínimo, NetworkPolicy default-deny, limites de recurso.
- [ ] Segredos via cofre/External Secrets/workload identity; mTLS entre serviços quando exigido.
- [ ] Logs estruturados sem PII; alertas para falhas de autenticação, escalada e anomalias 5xx.
- [ ] DAST/pentest antes de releases críticos.

### 5. Quantum Readiness (setores regulados, quando aplicável)

Ver `references/post-quantum-cryptography.md` antes de reportar — a severidade depende do tempo
de retenção do dado.

- [ ] Inventário criptográfico (algoritmo, serviço, dado protegido, retenção).
- [ ] Dados de retenção longa com plano de migração para ML-KEM/ML-DSA ou híbrido.
- [ ] Crypto-agility: algoritmo em configuração central.
- [ ] TLS externo avaliado para `X25519MLKEM768` (terminação no gateway/CDN ou JDK 27+).

## Threat Modeling

| Ameaça STRIDE              | Pergunta-chave                                    | Mitigação                                                     |
|----------------------------|---------------------------------------------------|---------------------------------------------------------------|
| **S**poofing               | Quem está chamando (usuário, serviço, webhook)?   | OAuth2/OIDC, mTLS, assinatura HMAC com timestamp              |
| **T**ampering              | Dado ou mensagem pode ser alterado?               | HMAC/assinatura, validação de schema, integridade de artefato |
| **R**epudiation            | Ações podem ser negadas?                          | Audit log imutável com principal, tenant e correlação         |
| **I**nfo Disclosure        | O que vaza (erros, logs, Actuator, BOLA)?         | Masking, autorização por objeto, erros genéricos              |
| **D**enial of Service      | O que pode ser esgotado (threads, pool, memória)? | Limites, timeouts, backpressure, rate limit                   |
| **E**levation of Privilege | Como escalar (BFLA, mass assignment, tenant)?     | Deny-by-default, `@PreAuthorize`, DTOs                        |

Inclua também **abuso de fluxo de negócio** (compra em massa, enumeração, scraping, bônus
repetido): quais fluxos, se automatizados, causam dano mesmo sem "bug"?

## AI/ML Security (LLM Apps)

Se o backend integra LLMs, aplique o OWASP Top 10 for LLM Applications: prompt injection (separar instruções de dados),
divulgação de informação sensível (sem PII/segredos no
contexto), saída do modelo tratada como entrada não confiável (nunca executar/concatenar em
SQL/comando), consumo irrestrito (rate limit e orçamento por usuário).

## Quantum Readiness (Post-Quantum Cryptography)

Extensão setorial, fora do OWASP Top 10:2025. Risco atual: **Harvest Now, Decrypt Later**.

| Componente                 | Efeito quântico                     | Ação                                                       |
|----------------------------|-------------------------------------|------------------------------------------------------------|
| Troca de chave (RSA, ECDH) | Quebrado (Shor)                     | ML-KEM (FIPS 203) ou híbrido                               |
| Assinatura (RSA, ECDSA)    | Quebrada (Shor)                     | ML-DSA (FIPS 204) ou híbrido                               |
| AES-256                    | Margem reduzida (Grover), adequado  | Manter; evitar AES-128 em retenção longa                   |
| TLS em trânsito            | Vulnerável a HNDL sem troca híbrida | JDK 27+, BCJSSE ou terminação externa com `X25519MLKEM768` |

## Execution Rules

* **Do Not Commit on Request:** em modo Levantamento, ou se o usuário for aplicar as correções
  ou pedir só um plano, NÃO modifique o codebase. Gere o relatório com
  `assets/audit-report-template.md` (em Levantamento, só a lista de achados).
* **Nunca recomende desligar controles** como correção (trust-all, `permitAll()` amplo, CORS
  curinga, CSRF desligado sem justificativa stateless, algoritmo fraco, bypass de autenticação).
* **Segredos:** não reproduza valores de segredo encontrados em relatórios, logs ou mensagens;
  cite localização e tipo e recomende rotação.
* **Comandos:** prefira inspeção somente leitura. Não execute builds, testes, scanners com
  acesso à rede ou comandos que alterem arquivos sem pedir confirmação.
* **Fontes:** fundamente recomendações de versão/API em documentação oficial; se não puder
  confirmar, diga isso no relatório em vez de afirmar.
* **Relatório HTML/PDF:** quando pedido, use a skill `pdf` ou conversão Markdown → HTML.
* **GitHub Security:** em planos de CI/CD, inclua CodeQL, Dependabot e Dependency Review.

## Referências Normativas

| Categoria     | Fonte                                                                                                                                                                                                                                                                          |
|---------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| OWASP         | [Top 10:2025](https://owasp.org/Top10/2025/) · [API Security Top 10:2023](https://owasp.org/API-Security/editions/2023/en/) · [ASVS 5.0](https://owasp.org/www-project-application-security-verification-standard/) · [Cheat Sheet Series](https://cheatsheetseries.owasp.org) |
| Spring        | [Spring Boot](https://docs.spring.io/spring-boot/) · [Spring Boot 4.1 Release Notes](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.1-Release-Notes) · [Spring Security](https://docs.spring.io/spring-security/reference/)                                 |
| Java / Kotlin | [OpenJDK JEPs](https://openjdk.org/jeps/0) · [What's new in Kotlin 2.4](https://kotlinlang.org/docs/whatsnew24.html)                                                                                                                                                           |
| Supply chain  | [SLSA](https://slsa.dev) · [OpenSSF Scorecard](https://scorecard.dev) · [NIST SSDF SP 800-218](https://csrc.nist.gov/pubs/sp/800/218/final) · [CISA Secure by Design](https://www.cisa.gov/securebydesign)                                                                     |
| Runtime       | [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) · [Distroless](https://github.com/GoogleContainerTools/distroless)                                                                                                   |
| PQC           | [NIST PQC](https://csrc.nist.gov/projects/post-quantum-cryptography) · [JEP 496](https://openjdk.org/jeps/496) · [JEP 497](https://openjdk.org/jeps/497) · [JEP 527](https://openjdk.org/jeps/527)                                                                             |

## Related Skills

- `agent-skills:code-review-and-quality` — Conducts multi-axis code review. Use before merging any change. Use when
  reviewing code written by yourself, another agent, or a human.
- `agent-skills:code-simplification` — Simplifies code for clarity. Use when refactoring code for clarity without
  changing behavior. Use when code works but is harder to read, maintain, or extend than it should be.
