# Modernização e Alinhamento das Skills Clean Code, Design Patterns e SOLID Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:
> executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Modernizar e alinhar as skills `clean-code`, `design-patterns` e `solid-principles` ao baseline tecnológico
Java 25 LTS, Kotlin 2.4+ e Spring Boot 4.1.1+, garantindo paridade idiomática entre Java e Kotlin, preservando o foco
primordial de cada disciplina (sem transformá-las em tutoriais de framework) e estabelecendo uma malha de referências
cruzadas explícita ("o que uma não cobrir referencia a outra").

**Architecture:** Cada skill atua como autoridade em seu próprio domínio conceitual, oferecendo exemplos canônicos
espelhados em Java 25 e Kotlin 2.4. Violações conceituais ou necessidades arquiteturais adjacentes são delegadas
explicitamente às skills parceiras através de links markdown relativos. Os manifestos de plugin universal e de cada IA
(`.claude-plugin/`, `.gemini-plugin/`, `.codex-plugin/`, `.grok-plugin/`), bem como o orquestrador `AGENTS.md` e a suíte
`scripts/validate-plugin.*`, são expandidos para cobrir as 5 skills oficiais do agente.

**Tech Stack:** Java 25 LTS (Records, Compact Constructors, Pattern Matching, Sealed Interfaces, Text Blocks), Kotlin
2.4+ (Data Classes, Value Classes, Extension Functions, Class Delegation `by`, Sealed Hierarchies, Null-Safety), Spring
Boot 4.1.1+ (Spring Framework 7.0, Constructor Injection estrito, ProblemDetail), Markdown (`agentskills.io` spec),
JSON, PowerShell e Bash.

## Global Constraints

- **Preservação de Escopo Conceitual:** Não descaracterizar as skills com foco excessivo em frameworks; cada skill
  cumpre rigorosamente seu papel (Clean Code = legibilidade/DRY/KISS/refatoração; Design Patterns = soluções GoF e
  estruturais idiomáticas; SOLID = princípios de design orientado a objetos na JVM).
- **Paridade de Linguagens:** Todos os conceitos centrais devem apresentar implementações canônicas tanto em Java 25
  quanto em Kotlin 2.4+.
- **Rede de Referências Cruzadas:** O que pertence ao escopo de outra skill deve ser referenciado explicitamente via
  link relativo Markdown (ex: violações de SRP em Clean Code apontam para `skills/solid-principles/SKILL.md`;
  refatoração de condicionais para Strategy aponta para `skills/design-patterns/SKILL.md`).
- **Validade Formal dos Manifestos:** Todos os manifestos JSON (`plugin.json` e `.<IA>-plugin/plugin.json`) devem ser
  JSON RFC 8259 válido, sem comentários e sem trailing commas.
- **Conformidade `agentskills.io`:** Todas as skills devem manter frontmatter YAML estrito com `name` e `description`.
- **Validação Cross-Platform:** Scripts de validação (`validate-plugin.ps1` e `validate-plugin.sh`) devem validar as 5
  skills com código de saída 0.

---

### File Structure Map

```text
skills/
├── clean-code/
│   ├── SKILL.md                          # Guia mestre Clean Code (Java 25 + Kotlin 2.4, DRY/KISS/YAGNI, refatoração)
│   └── README.md                         # Visão geral e guia rápido da skill
├── design-patterns/
│   ├── SKILL.md                          # Padrões GoF & Idiomáticos (Java 25 + Kotlin 2.4, monetário BigDecimal)
│   └── README.md                         # Visão geral e catálogo de padrões
├── solid-principles/
│   ├── SKILL.md                          # Princípios SOLID na JVM (Java 25 + Kotlin 2.4, SRP/OCP/LSP/ISP/DIP)
│   └── README.md                         # Visão geral e checklist SOLID
plugin.json                               # Manifesto raiz do agente com as 5 skills
AGENTS.md                                 # Persona unificada orquestrando as 5 skills
CLAUDE.md                                 # Instruções Claude Code atualizadas
GEMINI.md                                 # Instruções Antigravity / Gemini atualizadas
README.md                                 # Documentação central do agente com as 5 skills
.claude-plugin/plugin.json                # Manifesto Claude Code com 5 skills
.gemini-plugin/plugin.json                # Manifesto Gemini com 5 skills
.codex-plugin/plugin.json                 # Manifesto Codex com 5 skills
.grok-plugin/plugin.json                  # Manifesto Grok com 5 skills
scripts/
├── validate-plugin.ps1                   # Validador PowerShell verificando as 5 skills
└── validate-plugin.sh                    # Validador Bash verificando as 5 skills
```

---

### Task 1: Modernização e Paridade Java/Kotlin na Skill `clean-code`

**Files:**

- Modify: `skills/clean-code/SKILL.md`
- Modify: `skills/clean-code/README.md`

**Interfaces:**

- Consumes: Conceitos fundamentais de Clean Code, DRY, KISS, YAGNI, Boy Scout Rule, Guard Clauses, Naming Conventions.
- Produces: Skill completa com exemplos espelhados em Java 25 e Kotlin 2.4+, eliminando referências desatualizadas a
  Java 15/16 e adicionando referências cruzadas a `skills/solid-principles` e `skills/design-patterns`.

- [x] **Step 1: Atualizar `skills/clean-code/SKILL.md` com suporte idiomático a Java 25 e Kotlin 2.4+**

Garantir no `skills/clean-code/SKILL.md`:

1. **Frontmatter YAML:**
   ```yaml
   ---
   name: clean-code
   description: Princípios de Clean Code (DRY, KISS, YAGNI), convenções de nomenclatura, design de funções e refatoração idiomática para Java 25 LTS e Kotlin 2.4+. Use quando o usuário solicitar "limpe este código", "refatore", "melhore a legibilidade", ou durante revisões de qualidade de código.
   ---
   ```
2. **DRY, KISS, YAGNI com exemplos bivalentes:**
    - Java 25: validação de email / domínio encapsulada em `record` com compact constructor; uso de guard clauses.
    - Kotlin 2.4: validação usando `value class` ou extensão; expressões concisas evitando boilerplates sem cair em code
      golf.
3. **Naming & Functions:**
    - Funções pequenas com nível único de abstração.
    - Paridade Java (métodos expressivos, retorno tipado com `Optional` sem anti-pattern) e Kotlin (funções de extensão
      bem dosadas, evitar cadeias de `let`/`apply`/`also` obscuras).
4. **Substituição da seção Java 15/16 por "Modern JVM Clean Code Patterns (Java 25 LTS & Kotlin 2.4)":**
    - Java 25: `record` para data carriers imutáveis; Pattern Matching para `switch` com guard clauses (`when`);
      Sequenced Collections (`getFirst()`, `getLast()`).
    - Kotlin 2.4: `data class` com `val`; `value class` para combate à Primitive Obsession; smart casting idiomático;
      `sealed interface` para modelagem fechada.
5. **Seção explícita de Referências Cruzadas ("Skills Relacionadas"):**
    - Se uma função violar o Princípio da Responsabilidade Única (SRP) ou necessitar de inversão de dependência:
      referenciar [
      `../solid-principles/SKILL.md`](file:///C:/Users/walla/GitHub/java/pack-skill-agents/skills/solid-principles/SKILL.md).
    - Se um bloco condicional exigir refatoração para Strategy, Factory ou State: referenciar [
      `../design-patterns/SKILL.md`](file:///C:/Users/walla/GitHub/java/pack-skill-agents/skills/design-patterns/SKILL.md).
    - Se a refatoração envolver concorrência ou Virtual Threads: referenciar [
      `../concurrency-java21-review/SKILL.md`](file:///C:/Users/walla/GitHub/java/pack-skill-agents/skills/concurrency-java21-review/SKILL.md).
    - Se envolver validação de segurança ou sanitização de entrada: referenciar [
      `../java-kotlin-security-audit/SKILL.md`](file:///C:/Users/walla/GitHub/java/pack-skill-agents/skills/java-kotlin-security-audit/SKILL.md).

- [x] **Step 2: Atualizar `skills/clean-code/README.md`**

Refletir o escopo atualizado (Java 25 LTS + Kotlin 2.4+) no `skills/clean-code/README.md`, adicionando a matriz de
conceitos e links para as demais skills.

- [x] **Step 3: Testar integridade do frontmatter e links do `clean-code`**

Executar no PowerShell:

```powershell
$c = Get-Content skills/clean-code/SKILL.md -Raw
if ($c -match "(?s)^---\s*name:\s*clean-code\s*description:") { Write-Output "Frontmatter: PASS" } else { Write-Error "Frontmatter: FAIL" }
```

Expected: `Frontmatter: PASS`.

- [x] **Step 4: Commit das alterações de `clean-code`**

```bash
git add skills/clean-code/
git commit -m "feat(clean-code): align with Java 25 and Kotlin 2.4 idioms with cross-references"
```

---

### Task 2: Modernização e Padrões Idiomáticos na Skill `design-patterns`

**Files:**

- Modify: `skills/design-patterns/SKILL.md`
- Modify: `skills/design-patterns/README.md`

**Interfaces:**

- Consumes: Padrões GoF (Criacionais, Estruturais, Comportamentais), Regras de Domínio Financeiro (`BigDecimal`).
- Produces: Catálogo idiomático onde cada padrão é resolvido em Java 25 e Kotlin 2.4, vinculando-se aos princípios SOLID
  e Clean Code.

- [x] **Step 1: Atualizar `skills/design-patterns/SKILL.md` com padrões em Java 25 e Kotlin 2.4+**

Garantir no `skills/design-patterns/SKILL.md`:

1. **Frontmatter YAML:**
   ```yaml
   ---
   name: design-patterns
   description: Padrões de projeto GoF e padrões arquiteturais idiomáticos para Java 25 LTS, Kotlin 2.4+ e Spring Boot 4.1.1+. Use ao desenhar arquiteturas de classes, refatorar condicionais para polimorfismo, implementar factories/builders ou estruturar integrações desacopladas.
   ---
   ```
2. **Padrões Criacionais (Java 25 & Kotlin 2.4):**
    - **Builder:** Java 25 (Fluent Builder com validação no `build()` e imutabilidade) vs Kotlin (argumentos nomeados
      com valores default para dados simples; DSL Builder com `@DslMarker` para estruturas aninhadas complexas).
    - **Factory Method:** Java 25 (Static factories em `record`/interfaces com pattern matching `switch`) vs Kotlin
      (Companion object factory functions e funções top-level).
    - **Singleton:** Java 25 (Spring managed singleton ou Enum thread-safe) vs Kotlin (`object` thread-safe nativo da
      JVM).
3. **Padrões Comportamentais (Java 25 & Kotlin 2.4):**
    - **Strategy:** Java 25 (`@FunctionalInterface` ou `sealed interface` com pattern matching) vs Kotlin (First-class
      functions `(T) -> R` ou `fun interface`).
    - **Observer:** Java 25 (Spring Boot 4.1.1+ `ApplicationEventPublisher` / `@EventListener`) vs Kotlin
      (`Delegates.observable` ou Spring Events idiomáticos).
    - **Template Method:** Java 25 (Abstrações herdadas com métodos finais) vs Kotlin (Higher-Order Functions com
      trailing lambdas, preferindo composição sobre herança).
4. **Padrões Estruturais (Java 25 & Kotlin 2.4):**
    - **Decorator:** Java 25 (Composição de interfaces com delegação explícita) vs Kotlin (Class delegation nativa via
      keyword `by`).
    - **Adapter:** Java 25 (Adapter wrapper clássico) vs Kotlin (Extension functions para mapeamento ou object adapter).
5. **Regra Monetária Inviolável:**
    - Manter e reforçar: `BigDecimal` e `CurrencyUnit`, arredondamento explícito (`RoundingMode.HALF_EVEN`), nunca
      `double`/`float`.
6. **Vínculo Explícito com SOLID e Clean Code:**
    - Para cada padrão, indicar qual princípio SOLID ele promove (ex: Strategy promove OCP; Factory promove DIP e SRP).
      Referenciar explicitamente [
      `../solid-principles/SKILL.md`](file:///C:/Users/walla/GitHub/java/pack-skill-agents/skills/solid-principles/SKILL.md).
    - Seção de Anti-Patterns ("Patternitis"): Não introduzir padrões prematuramente quando uma função simples resolve
      (KISS/YAGNI). Referenciar explicitamente [
      `../clean-code/SKILL.md`](file:///C:/Users/walla/GitHub/java/pack-skill-agents/skills/clean-code/SKILL.md).

- [x] **Step 2: Atualizar `skills/design-patterns/README.md`**

Documentar a tabela de padrões GoF vs Idiomas Modernos da JVM (Java 25 Records vs Kotlin `by`/Lambdas), matriz de uso e
links.

- [x] **Step 3: Testar integridade do frontmatter e sintaxe de `design-patterns`**

Executar no PowerShell:

```powershell
$c = Get-Content skills/design-patterns/SKILL.md -Raw
if ($c -match "(?s)^---\s*name:\s*design-patterns\s*description:") { Write-Output "Frontmatter: PASS" } else { Write-Error "Frontmatter: FAIL" }
```

Expected: `Frontmatter: PASS`.

- [x] **Step 4: Commit das alterações de `design-patterns`**

```bash
git add skills/design-patterns/
git commit -m "feat(design-patterns): provide idiomatic Java 25 and Kotlin 2.4 patterns with SOLID mapping"
```

---

### Task 3: Modernização e Paridade Java/Kotlin na Skill `solid-principles`

**Files:**

- Modify: `skills/solid-principles/SKILL.md`
- Modify: `skills/solid-principles/README.md`

**Interfaces:**

- Consumes: Princípios SOLID (SRP, OCP, LSP, ISP, DIP), Spring Boot 4.1.1+, Java 25 LTS, Kotlin 2.4+.
- Produces: Guia detalhado de SOLID na JVM com exemplos emparelhados de violação e solução em Java e Kotlin, com
  referências para padrões de projeto e clean code.

- [x] **Step 1: Atualizar `skills/solid-principles/SKILL.md` com paridade Java 25 e Kotlin 2.4+**

Garantir no `skills/solid-principles/SKILL.md`:

1. **Frontmatter YAML:**
   ```yaml
   ---
   name: solid-principles
   description: Princípios SOLID (SRP, OCP, LSP, ISP, DIP) aplicados de forma idiomática em Java 25 LTS e Kotlin 2.4+ no Spring Boot 4.1.1+. Use durante revisões de arquitetura de classes, refatoração de serviços monolíticos ou análise de acoplamento e extensibilidade.
   ---
   ```
2. **SRP (Single Responsibility):**
    - Violação: Serviço misturando validação, persistência, notificação e auditoria.
    - Refatoração Java 25: `record` imutável com validação compacta + repositório dedicado + serviço de notificação.
    - Refatoração Kotlin 2.4: `data class` imutável + repositório + notificador injetado via construtor primário.
    - Link cruzado: Para manter funções e métodos pequenos e coesos, consulte [
      `../clean-code/SKILL.md`](file:///C:/Users/walla/GitHub/java/pack-skill-agents/skills/clean-code/SKILL.md).
3. **OCP (Open/Closed):**
    - Violação: `switch`/`if` em `String` para cálculo de taxas ou desconto.
    - Refatoração Java 25: `sealed interface` com `permits` e pattern matching exaustivo no `switch`.
    - Refatoração Kotlin 2.4: `sealed interface` / `sealed class` avaliado em `when` exaustivo, ou polimorfismo via
      interfaces funcionais.
    - Link cruzado: Para implementação com o padrão Strategy ou Factory Method, consulte [
      `../design-patterns/SKILL.md`](file:///C:/Users/walla/GitHub/java/pack-skill-agents/skills/design-patterns/SKILL.md).
4. **LSP (Liskov Substitution):**
    - Violação: Subclasse lançando `UnsupportedOperationException` ou violando pré/pós-condições.
    - Refatoração Java 25 e Kotlin 2.4: Segregação correta de hierarquia via `sealed interface` e composição sobre
      herança.
5. **ISP (Interface Segregation):**
    - Violação: "Fat interfaces" (ex: repositório com 20 métodos onde um consumidor só precisa de leitura).
    - Refatoração Java 25: Role interfaces funcionais e pequenas (`ReadOnlyRepository`, `OrderCanceller`).
    - Refatoração Kotlin 2.4: Interfaces segregadas e composição via delegação (`by`).
6. **DIP (Dependency Inversion):**
    - Violação: Instanciação direta com `new` / acoplamento a implementações concretas / injeção via `@Autowired` em
      campo.
    - Refatoração Java 25 & Kotlin 2.4: Injeção estrita via construtor com dependência exclusiva em interfaces de
      domínio.
    - Atualização Spring Boot 4.1.1+: Sem anotações `@Autowired` em construtores únicos; classes de serviço final por
      padrão em Kotlin com `all-open`/`kotlin-spring`.

- [x] **Step 2: Atualizar `skills/solid-principles/README.md`**

Atualizar o `README.md` com a matriz de resumo SOLID, exemplos concisos e mapa de referências para `design-patterns` e
`clean-code`.

- [x] **Step 3: Testar integridade do frontmatter e links em `solid-principles`**

Executar no PowerShell:

```powershell
$c = Get-Content skills/solid-principles/SKILL.md -Raw
if ($c -match "(?s)^---\s*name:\s*solid-principles\s*description:") { Write-Output "Frontmatter: PASS" } else { Write-Error "Frontmatter: FAIL" }
```

Expected: `Frontmatter: PASS`.

- [x] **Step 4: Commit das alterações de `solid-principles`**

```bash
git add skills/solid-principles/
git commit -m "feat(solid-principles): comprehensive Java 25 and Kotlin 2.4 examples with design-patterns cross-linking"
```

---

### Task 4: Atualização de Manifestos Multi-IA, Personas e Scripts de Validação

**Files:**

- Modify: `plugin.json`
- Modify: `.claude-plugin/plugin.json`
- Modify: `.gemini-plugin/plugin.json`
- Modify: `.codex-plugin/plugin.json`
- Modify: `.grok-plugin/plugin.json`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Modify: `GEMINI.md`
- Modify: `scripts/validate-plugin.ps1`
- Modify: `scripts/validate-plugin.sh`
- Modify: `README.md`

**Interfaces:**

- Consumes: As 5 skills oficializadas sob `skills/` (`java-kotlin-security-audit`, `concurrency-java21-review`,
  `clean-code`, `design-patterns`, `solid-principles`).
- Produces: Manifestos e testes atualizados reconhecendo as 5 skills em todas as IAs suportadas.

- [x] **Step 1: Atualizar `plugin.json` na raiz com as 5 skills**

Atualizar a lista de `"skills"` em `plugin.json`:

```json
{
  "name": "agent-eng-backend-jvm",
  "version": "1.0.0",
  "description": "Engenheiro Sênior de Backend na JVM especialista em Java 25 LTS, Kotlin 2.4, Spring Boot 4.1+, Concorrência Estruturada, Padrões Arquiteturais e Segurança OWASP Top 10:2025.",
  "author": "wallanpsantos",
  "license": "Proprietary",
  "skills": [
    "./skills/java-kotlin-security-audit",
    "./skills/concurrency-java21-review",
    "./skills/clean-code",
    "./skills/design-patterns",
    "./skills/solid-principles"
  ],
  "rules": [
    "./AGENTS.md"
  ]
}
```

- [x] **Step 2: Atualizar os manifestos nas pastas `.<IA>-plugin/`**

Atualizar os 4 manifestos para incluir as 5 skills (`../skills/clean-code`, `../skills/design-patterns`,
`../skills/solid-principles`):

- `.claude-plugin/plugin.json`
- `.gemini-plugin/plugin.json`
- `.codex-plugin/plugin.json`
- `.grok-plugin/plugin.json`

- [x] **Step 3: Atualizar `AGENTS.md`, `CLAUDE.md` e `GEMINI.md` com a taxonomia das 5 skills**

Em `AGENTS.md`, adicionar a descrição e gatilhos de ativação para:

- `3. clean-code (skills/clean-code/SKILL.md)`: Legibilidade, DRY, KISS, YAGNI, refatoração de código, redução de
  complexidade ciclomática.
- `4. design-patterns (skills/design-patterns/SKILL.md)`: Padrões GoF e arquiteturais idiomáticos em Java 25 e Kotlin
  2.4, cálculo monetário seguro (`BigDecimal`).
- `5. solid-principles (skills/solid-principles/SKILL.md)`: Avaliação e refatoração arquitetural baseada em SRP, OCP,
  LSP, ISP e DIP.

Atualizar `CLAUDE.md` e `GEMINI.md` para listar as 5 skills carregadas automaticamente.

- [x] **Step 4: Atualizar os scripts de validação (`validate-plugin.ps1` e `validate-plugin.sh`)**

Em `scripts/validate-plugin.ps1`:

```powershell
$skills = @(
    "java-kotlin-security-audit",
    "concurrency-java21-review",
    "clean-code",
    "design-patterns",
    "solid-principles"
)
```

Em `scripts/validate-plugin.sh`:

```bash
SKILLS=(
    "java-kotlin-security-audit"
    "concurrency-java21-review"
    "clean-code"
    "design-patterns"
    "solid-principles"
)
```

- [x] **Step 5: Atualizar `README.md` raiz com o ecossistema completo de 5 skills**

Atualizar o diagrama arquitetural Mermaid e a tabela de skills no `README.md` raiz para apresentar detalhadamente as 5
competências do agente.

- [x] **Step 6: Executar a suíte de validação completa**

Executar:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\validate-plugin.ps1
```

Expected: `[PASS] Skill valida: clean-code`, `[PASS] Skill valida: design-patterns`,
`[PASS] Skill valida: solid-principles` e `==> SUCESSO: Todos os componentes do agente foram validados!` com exit code

0.

- [x] **Step 7: Commit das atualizações de integração**

```bash
git add plugin.json .claude-plugin/ .gemini-plugin/ .codex-plugin/ .grok-plugin/ AGENTS.md CLAUDE.md GEMINI.md README.md scripts/validate-plugin.*
git commit -m "feat(agent): register clean-code, design-patterns, and solid-principles across all AI manifests and validation scripts"
```

---

### Task 5: Validação Final End-to-End e Verificação de Links Cruzados

**Files:**

- Modify: `docs/superpowers/plans/2026-09-22-align-clean-code-patterns-solid.md` (Checklists de progresso)

**Interfaces:**

- Consumes: Todo o repositório integrado.
- Produces: Garantia de 0 links quebrados, scripts executáveis e sincronismo entre documentações.

- [x] **Step 1: Testar resolução de todos os links relativos citados entre as skills**

Executar script PowerShell de verificação de links cruzados:

```powershell
$skillsToCheck = @("skills/clean-code/SKILL.md", "skills/design-patterns/SKILL.md", "skills/solid-principles/SKILL.md")
foreach ($s in $skillsToCheck) {
    $dir = Split-Path $s
    $content = Get-Content $s -Raw
    $matches = [regex]::Matches($content, '\[.*?\]\(((\.\./[^)]+)|(\./[^)]+))\)')
    foreach ($m in $matches) {
        $relPath = $m.Groups[1].Value.Split('#')[0]
        $target = Resolve-Path (Join-Path $dir $relPath) -ErrorAction SilentlyContinue
        if ($target -and (Test-Path $target)) {
            Write-Output "Link OK em $s: $relPath"
        } else {
            Write-Error "Link quebrado em $s: $relPath"
        }
    }
}
```

Expected: Todas as referências marcadas como `Link OK` sem erros.

- [x] **Step 2: Executar varredura rápida de segurança das novas skills**

Executar:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File skills\java-kotlin-security-audit\scripts\quick_scan.ps1 skills -FailOn nunca
```

Expected: Exit code 0, 0 candidatos de falha.

- [x] **Step 3: Executar validação do plugin**

Executar:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\validate-plugin.ps1
```

Expected: `==> SUCESSO: Todos os componentes do agente foram validados!`

- [x] **Step 4: Commit de fechamento e registro**

```bash
git add docs/superpowers/plans/
git commit -m "docs: complete modernization and cross-referencing plan for clean-code, design-patterns, and solid-principles"
```

---

## Self-Review Checklist

- **Spec Coverage:** As 3 skills pedidas pelo usuário (`clean-code`, `design-patterns`, `solid-principles`) são
  individualmente modernizadas para Java 25 LTS, Kotlin 2.4+ e Spring Boot 4.1.1+, preservando suas missões essenciais.
  A malha de referências cruzadas ("o que uma não cobrir referencia a outra") está estabelecida e testada na Task 5.
- **No Placeholders:** Todos os comandos, snippets de configuração JSON, regex e estruturas de verificação contêm código
  exato.
- **Type/Path Consistency:** Todas as referências apontam para `skills/clean-code/`, `skills/design-patterns/`,
  `skills/solid-principles/`, `skills/java-kotlin-security-audit/` e `skills/concurrency-java21-review/`.
- **Cross-Platform:** PowerShell e Bash contemplados.
