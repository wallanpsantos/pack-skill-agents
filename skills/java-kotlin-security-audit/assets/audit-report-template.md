# Relatório de Auditoria de Segurança — [Nome do Serviço / Repositório]

- **Data da Execução:** [AAAA-MM-DD]
- **Auditor:** [Nome do Auditor / Skill Security-Audit]
- **Modo de Execução:** [Auditoria Completa | Auditoria Direcionada | Levantamento]
- **Escopo Analisado:** [Diretório, Módulo, PR ou Repositório Completo]
- **Stack Tecnológica Detectada:**
    - Runtime: [ex.: Java 25 LTS (Eclipse Temurin)]
    - Linguagem: [ex.: Kotlin 2.4.20 / Java 25]
    - Framework: [ex.: Spring Boot 4.1.1 (Spring Framework 7.0, Spring Security 7.1, Jackson 3)]
    - Build & CI: [ex.: Gradle 9.7.1 com Kotlin DSL / GitHub Actions]

---

## 1. Cobertura da Auditoria

> [!IMPORTANT]
> A cobertura deve ser relatada de forma transparente para não induzir falsa sensação de segurança.

- **Lido e Analisado Manualmente por Completo:**
    - [Listar arquivos críticos, controllers, configurações de segurança, filtros]
- **Apenas Triagem Automática (`quick_scan` sem confirmação manual):**
    - [Listar diretórios ou arquivos cobertos apenas por varredura de regex]
- **Não Tocado (com justificativa técnica):**
    - [Listar pastas/arquivos não analisados e o motivo: ex.: fora do escopo, código legado congelado, fixtures de teste]

---

## 2. Resumo Executivo e Distribuição de Achados

[Parágrafo com diagnóstico geral: avaliação de prontidão para produção ("Pode ir para produção?", "Bloqueado"), principais pontos de atenção e riscos mais urgentes.]

### Tabela de Severidade e Confiança

| Severidade      | Confirmado | Provável | Suspeito (Apenas Levantamento) | Total |
|-----------------|------------|----------|--------------------------------|-------|
| **Crítico**     | 0          | 0        | 0                              | 0     |
| **Alto**        | 0          | 0        | 0                              | 0     |
| **Médio**       | 0          | 0        | 0                              | 0     |
| **Baixo**       | 0          | 0        | 0                              | 0     |
| **Informativo** | 0          | 0        | 0                              | 0     |
| **Total**       | **0**      | **0**    | **0**                          | **0** |

---

## 3. Achados de Segurança

*(Os achados devem ser ordenados estritamente por severidade: Crítico → Alto → Médio → Baixo → Informativo).*

### [SEC-01] [Título Claro e Específico do Problema]

- **Severidade:** Crítico | Alto | Médio | Baixo | Informativo
- **Confiança:** Confirmado | Provável
- **Mapeamento Normativo:**
    - **OWASP Top 10:2025:** [ex.: A01 — Broken Access Control]
    - **OWASP API Security Top 10:2023:** [ex.: API1:2023 — Broken Object Level Authorization (BOLA)]
    - **OWASP ASVS 5.0:** [ex.: V4.1 — General Access Control Design]
    - **CWE:** [ex.: CWE-639: Authorization Bypass Through User-Controlled Key]
- **Localização:** `caminho/do/Arquivo.kt:linha` (ou chave no `application.yml` / GitHub Workflow)
-

**Pré-condições:** [O que o atacante precisa possuir: ex.: token de usuário comum autenticado, acesso à rede interna, etc.]

- **Cadeia Fonte → Sumidouro (Source-to-Sink):**
    - *Fonte (Input):* [ex.: `@PathVariable String accountId` no controller `AccountController`]
    - *Caminho (Data Flow):* [ex.: parâmetro repassado para `accountService.getAccount(accountId)`]
    - *Sumidouro (Sink):* [ex.: consulta SQL `findById` sem filtrar por `owner_id` ou `tenant_id`]
- **Evidência de Código Vulnerável (Redigida):**
  ```kotlin
  // Inserir trecho do código auditado que comprova a vulnerabilidade
  // NUNCA reproduzir valores de segredos, senhas ou tokens reais!
  ```
- **Impacto:** [Consequência real demonstrável no negócio ou nos dados do usuário]
- **Mitigação Recomendada:**
  ```kotlin
  // Inserir código corrigido contrastante seguindo as referências da skill
  ```
- **Como Verificar (Teste Automatizado de Segurança):**
  [Instrução ou teste em MockMvc/WebTestClient/Testcontainers para validar que a correção funciona e evitar regressão]

---

*(Para vulnerabilidades de dependências / supply chain, utilize a estrutura abaixo:)*

### [SEC-CVE] [CVE-AAAA-NNNNN] [Vulnerabilidade na Biblioteca X]

- **Severidade:** Crítico | Alto | Médio
- **Confiança:** Confirmado | Provável
- **Mapeamento:** OWASP A03:2025 — Software Supply Chain Failures
- **Coordenadas da Dependência:** `groupId:artifactId:versão`
- **Grafo de Resolução:** `app -> lib-a:1.0 -> lib-vulneravel:2.1`
- **Versão Corrigida Recomendada:** `2.1.4` (ou superior)
- **Análise de Alcançabilidade (Reachability / VEX):**
    - [O método/classe afetado pelo CVE é invocado no código da aplicação? Sim/Não e justificativa]
- **Métricas:** CISA KEV: [Sim/Não] | EPSS: [Score e Percentil]

---

## 4. Itens Não Aplicáveis (Checklist)

[Liste itens do Security Checklist que foram avaliados e descartados por não se aplicarem à arquitetura do projeto, acompanhados de justificativa técnica formal.]

- *Exemplo: Acesso a metadados de nuvem e SSRF: Não aplicável pois o microsserviço não realiza nenhuma chamada HTTP de
  saída e não aceita URLs como entrada.*

---

## 5. Próximos Passos e Plano de Remediação

*(Em modo Levantamento, esta seção pode ser omitida).*

1. **Bloqueadores de Release (Crítico/Alto):** [Ações imediatas antes de qualquer promoção para ambiente produtivo].
2. **Correções de Curto Prazo (Médio):** [Adequações a serem incluídas na próxima sprint].
3. **Melhorias de Defesa em Profundidade (Baixo/Informativo):** [Hardening e dívida técnica].
