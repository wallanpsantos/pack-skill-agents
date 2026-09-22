# Matriz de Auditoria, Taxonomia e Classificação de Achados

Este documento define a taxonomia normativa cruzada, a matriz de severidade e explorabilidade, os níveis de confiança e
os critérios de evidência mínima exigidos para qualquer achado de auditoria de segurança gerado por esta skill.

---

## 1. Taxonomia Cruzada (OWASP Top 10:2025 × API Top 10:2023 × ASVS 5.0)

A auditoria de backends na JVM deve correlacionar os achados com três referenciais complementares:

1. **OWASP Top 10:2025:** Risco corporativo e sistêmico amplo.
2. **OWASP API Security Top 10:2023:** Vetores focados na arquitetura de APIs REST, GraphQL e mensageria.
3. **OWASP ASVS 5.0 (Application Security Verification Standard):** Requisitos técnicos detalhados de verificação.

| ID 2025 | OWASP Top 10:2025                      | API Security Top 10:2023                                                          | ASVS 5.0 Capítulos Primários                                  | Sinais de Auditoria no Código JVM                                                                                                                                                                                                                                                                                                                                                                               |
|---------|----------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **A01** | Broken Access Control (inclui SSRF)    | **API1** (BOLA), **API3** (BOPLA), **API5** (BFLA), **API7** (SSRF)               | V1 (Arquitetura), V4 (Controle de Acesso), V13 (Serviços Web) | - Ausência de verificação de `ownerId`/`tenantId` na consulta a banco.<br>- Rotas `@PreAuthorize` ausentes ou com SpEL permissivo.<br>- `permitAll()` em rotas com dados sensíveis.<br>- Chamadas HTTP externas com URLs do usuário sem `InetAddressFilter`.<br>- Mass assignment por expor entidades JPA diretamente no controller.                                                                            |
| **A02** | Security Misconfiguration              | **API8** (Security Misconfiguration), **API9** (Improper Inventory)               | V14 (Configuração), V9 (Comunicações)                         | - Actuator expondo `env`, `heapdump`, `beans` ou wildcard `*`.<br>- Swagger UI / OpenAPI exposto sem autenticação em produção.<br>- Headers de segurança ausentes (HSTS, CSP, X-Content-Type-Options).<br>- CORS com `allowedOrigins("*")` combinado com credentials.<br>- Perfis de desenvolvimento ativos em imagem de produção.                                                                              |
| **A03** | Software Supply Chain Failures         | —                                                                                 | V10 (Código Malicioso), V14 (Configuração de Build)           | - Dependências com CVEs críticos conhecidos sem triagem VEX.<br>- Gradle sem `verification-metadata.xml` ou dependency locking.<br>- GitHub Actions com tags mutáveis (`@v4`, `@main`) em vez de commit SHA.<br>- Scripts de CI com interpolação de dados de pull request em comandos `run:`.<br>- Falta de geração de SBOM CycloneDX assinado.                                                                 |
| **A04** | Cryptographic Failures                 | —                                                                                 | V6 (Criptografia), V9 (Comunicações)                          | - Cifras fracas ou inseguras: `AES/ECB`, `DES`, `RC4`, `MD5`, `SHA-1`.<br>- Uso de `new Random()` para tokens, senhas ou nonces criptográficos.<br>- Ausência de IV aleatório de 12 bytes em `AES/GCM`.<br>- Segredos ou chaves privadas gravados em strings ou arquivos de configuração.<br>- TLS com validação de certificado desligada (`TrustAllCerts`).                                                    |
| **A05** | Injection                              | —                                                                                 | V5 (Validação de Entrada e Sanitização)                       | - Concatenação de parâmetros em JPQL, HQL, SQL nativo ou `JdbcClient`.<br>- Interpolação de templates de String Kotlin em consultas SQL.<br>- `ProcessBuilder` ou `Runtime.getRuntime().exec` com entrada do usuário.<br>- `SpelExpressionParser` sem `SimpleEvaluationContext`.<br>- Parsers XML (`DocumentBuilderFactory`) sem desativação de DTDs (XXE).                                                     |
| **A06** | Insecure Design                        | **API4** (Unrestricted Resource Consumption), **API6** (Sensitive Business Flows) | V1 (Arquitetura), V11 (Lógica de Negócio)                     | - Falta de rate limiting em fluxos sensíveis (login, checkout, Pix, SMS).<br>- Paginação sem `max-page-size` (consumo de memória descontrolado).<br>- Operações críticas não idempotentes sem `Idempotency-Key`.<br>- Ausência de limites de tamanho em upload ou profundidade de payload JSON.<br>- Falta de proteções contra abuso de automação (scraping em massa).                                          |
| **A07** | Authentication Failures                | **API2** (Broken Authentication)                                                  | V2 (Autenticação), V3 (Gerenciamento de Sessão)               | - Tokens JWT sem validação de emissor (`iss`), audiência (`aud`) e expiração (`exp`).<br>- Resource Server aceitando algoritmo de assinatura `none` ou chaves fracas.<br>- Hashes de senha com algoritmos sem fator de custo (MD5, SHA-256 simples).<br>- Sessões web sem atributos `Secure`, `HttpOnly` e `SameSite`.<br>- Ausência de bloqueio ou atraso exponencial após falhas repetidas de login.          |
| **A08** | Software or Data Integrity Failures    | **API10** (Unsafe Consumption of APIs)                                            | V10 (Integridade), V12 (Arquivos e Recursos)                  | - Uso de `ObjectInputStream.readObject()` sem `ObjectInputFilter`.<br>- Jackson com `enableDefaultTyping()` ativo sem allowlist restritiva.<br>- Extração de arquivos `.zip` sem validação de caminho relativo (Zip Slip).<br>- Confiança cega em payloads recebidos de webhooks externos sem assinatura HMAC.<br>- Artefatos de build ou imagens Docker não assinados via Cosign/Sigstore.                     |
| **A09** | Security Logging and Alerting Failures | —                                                                                 | V7 (Tratamento de Erros e Logging)                            | - Ausência de registro estruturado de falhas de autenticação e acessos negados.<br>- Vazamento de PII (CPF, senhas, cartões, tokens) nos logs da aplicação.<br>- Uso de `e.printStackTrace()` ou `System.out.println` em produção.<br>- Logs de auditoria sem identificação do usuário (`principal`) ou tenant.<br>- Falta de alertas automatizados no SIEM para anomalias 5xx ou ataques.                      |
| **A10** | Mishandling of Exceptional Conditions  | —                                                                                 | V7 (Tratamento de Erros), V11 (Lógica de Negócio)             | - Respostas de erro HTTP vazando stack trace ou detalhes internos de infraestrutura.<br>- Falha de segurança em modo "fail-open" (exceção em filtro liberando requisição).<br>- Coroutines ou Virtual Threads engolindo `CancellationException` ou travando carrier.<br>- Falta de timeouts explícitos em chamadas a serviços externos e bancos.<br>- Não conformidade com o padrão `ProblemDetail` (RFC 9457). |

---

## 2. Matriz de Severidade

A severidade de um achado não é uma opinião estética; é o produto estrito entre **Impacto Técnico/Negócio** e
**Facilidade de Exploração (Explorabilidade)** no ambiente real da JVM.

| Nível                  | Critério Normativo                                                                                                                                                                                                                                                     | Exemplos Típicos na JVM                                                                                                                                                                                                                                                                                                                                                                                       |
|------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Crítico (Critical)** | Explorável remotamente sem autenticação prévia (ou por qualquer usuário não privilegiado), permitindo Execução Remota de Código (RCE), desvio irrestrito de autenticação, vazamento massivo de segredos/chaves de produção ou comprometimento total do banco de dados. | - RCE via desserialização nativa ou Jackson default typing aberto.<br>- RCE via SpEL injection em endpoint público.<br>- SQL Injection permitindo leitura/escrita arbitrária sem restrições.<br>- Bypass completo de `SecurityFilterChain` por configuração incorreta de `securityMatcher`.<br>- Chave privada ou segredo de produção exposto em repositório público.                                         |
| **Alto (High)**        | Acesso não autorizado a dados ou ações de outros usuários ou outros tenants (BOLA/IDOR), escalada vertical de privilégio (BFLA), SSRF permitindo acesso a metadados de nuvem ou rede interna, injeção com pré-condições moderadas.                                     | - BOLA/IDOR em serviço de consulta de transações ou documentos.<br>- SSRF sem filtro permitindo chamada para `169.254.169.254` ou Kubernetes API.<br>- Falta de validação de audiência (`aud`) ou chave assimétrica em JWT Resource Server.<br>- Cross-Tenant data leak devido a falta de filtro por `tenantId` em queries.<br>- Zip Slip em upload de arquivo permitindo sobrescrever arquivos da aplicação. |
| **Médio (Medium)**     | Vulnerabilidade explorável sob condições específicas ou com impacto localizado; quebra de controles de defesa em profundidade onde o ataque é plausível mas requer passos adicionais.                                                                                  | - CSRF desabilitado em endpoint que utiliza autenticação por cookie de sessão.<br>- CORS permissivo com `allowedOrigins("*")` em rota autenticada.<br>- Endpoint de Actuator exposto sem restrição de role na mesma porta da aplicação.<br>- Ausência de rate limiting em endpoint de envio de email/SMS ou login.<br>- Uso de algoritmo criptográfico obsoleto (ex.: MD5 para checksum de integridade).      |
| **Baixo (Low)**        | Desvios de boas práticas ou hardening que não permitem exploração direta isoladamente, mas reduzem a robustez da aplicação.                                                                                                                                            | - Ausência de headers HTTP como `X-Content-Type-Options: nosniff` ou `Strict-Transport-Security`.<br>- Informações de versão do Spring Boot vazando em cabeçalho `Server` ou página de erro.<br>- Uso de `new Random()` para identificadores que não são segredos criptográficos.<br>- OpenAPI documentando endpoints internos sem segregação de ambientes.                                                   |
| **Informativo (Info)** | Observações arquiteturais, inventário de APIs, dívida técnica de segurança, avisos de depreciação futura ou oportunidades de modernização.                                                                                                                             | - Aviso de descontinuação de API ou versão de runtime.<br>- Ausência de inventário formal de dados criptografados para transição quântica (PQC).<br>- Sugestão de migração de `RestTemplate` para `RestClient`.                                                                                                                                                                                               |

---

## 3. Modelo de Confiança (Confidence Level)

Ao registrar um achado no relatório de auditoria, atribua um nível de confiança explícito:

1. **Confirmado (Verified):**
    - O auditor inspecionou manualmente o código-fonte, a configuração e o fluxo de dados.
    - Existe um caminho demonstrável da fonte não confiável (*source*) até o ponto de impacto (*sink*).
    - O impacto e as pré-condições foram verificados contra a stack real (Java 25, Spring Boot 4.1.1, etc.).
    - Deve ser corrigido obrigatoriamente.

2. **Provável (Probable):**
    - O padrão inseguro foi identificado no código (ex.: chamada a método inseguro, classe permissiva), mas a
      explorabilidade final depende de configurações externas, WAF, Gateway ou componentes não visíveis no escopo
      imediato.
    - Deve ser investigado e tratado como risco real até prova em contrário.

3. **Suspeito (Suspect / Candidato de Triagem):**
    - Ocorrência gerada exclusivamente por casamento de padrões de regex (`quick_scan`).
    - Não foi verificado manualmente no fluxo da aplicação.
    - **Regra de ouro:** NUNCA incluir itens no estado "Suspeito" em relatórios finais de auditoria. Eles servem
      exclusivamente como fila de triagem interna do auditor. Em modo Levantamento, se listados, devem ser
      explicitamente rotulados como *Candidatos Pendentes de Confirmação*.

---

## 4. Critérios de Evidência Mínima por Achado

Nenhum achado é válido sem evidência concreta. Todo item no relatório técnico deve conter obrigatoriamente os seguintes
campos estruturados:

```markdown
### [SEC-ID] Título Claro e Específico do Problema

- **Severidade:** Crítico | Alto | Médio | Baixo | Informativo
- **Confiança:** Confirmado | Provável
- **Mapeamento Normativo:**
  - OWASP Top 10:2025: [ex.: A01 — Broken Access Control]
  - OWASP API Security: [ex.: API1:2023 — Broken Object Level Authorization]
  - ASVS 5.0: [ex.: V4.1 — General Access Control Design]
  - CWE: [ex.: CWE-639]
- **Localização:** `caminho/do/Arquivo.kt:linha` (ou chave no `application.yml`)
- **Pré-condições:** O que o atacante precisa para explorar (ex.: conta de usuário comum válida, rede interna, token expirado).
- **Cadeia Fonte → Sumidouro (Source-to-Sink):**
  - *Fonte:* De onde vem a entrada (ex.: `@PathVariable("id") String accountId`).
  - *Fluxo:* Por onde o dado transita sem validação (ex.: `controller.getAccount` → `service.findAccount`).
  - *Sumidouro:* Onde o dano ocorre (ex.: `accountRepository.findById(accountId)` sem conferir `userId`).
- **Trecho de Código Vulnerável (Redigido):**
  ```java
  // Código do projeto evidenciando o defeito
  ```

- **Impacto:** Consequência prática demonstrável (ex.: vazamento de saldo e dados bancários de qualquer correntista).
- **Mitigação Recomendada:** Padrão correto de correção com código seguro contrastante:
  ```java
  // Código seguro recomendado
  ```
- **Como Verificar (Teste de Regressão):** Instrução ou teste em código (`MockMvc`, `WebTestClient`) para garantir que a
  vulnerabilidade foi eliminada e não voltará a ocorrer.

```

### Regras Especiais de Evidência

1. **Segredos e Credenciais:**
   - **PROIBIDO** copiar o valor do token, senha ou chave no relatório.
   - Evidência = `arquivo:linha`, tipo da credencial (ex.: AWS Secret Key, JWT Private Key, Database Password) e primeiras/últimas 2 letras ou SHA-256 da chave.
   - Ação imediata recomendada: revogação e rotação no cofre.

2. **CVEs de Dependências (Supply Chain):**
   - Coordenadas completas (`groupId:artifactId:version`).
   - Caminho de resolução no grafo (`mvn dependency:tree` ou `gradle dependencies`).
   - Versão mínima corrigida recomendada pelo mantenedor.
   - Análise de alcançabilidade (*reachability analysis*): a classe vulnerável da biblioteca é importada ou executada no runtime da aplicação?
   - Informações de CISA KEV (Known Exploited Vulnerabilities) e percentil EPSS (Exploit Prediction Scoring System).
