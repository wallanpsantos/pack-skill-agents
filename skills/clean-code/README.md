# Clean Code (Código Limpo) - Java 25 LTS & Kotlin 2.4+

**Carregar**: `view skills/clean-code/SKILL.md`

---

## Descrição

Princípios de Código Limpo (Clean Code) aplicados à moderna plataforma JVM (Java 25 LTS e Kotlin 2.4+):
DRY, KISS, YAGNI, Boy Scout Rule, convenções de nomenclatura expressivas, design de funções com nível único de abstração (SLAP), erradicação de Primitive Obsession, detecção de code smells e técnicas sistemáticas de refatoração idiomática.

---

## Casos de Uso

- "Limpe este código" / "Clean this code"
- "Refatore este método" / "Refactor this method"
- "Melhore a legibilidade e manutenibilidade"
- "Esta função está muito longa ou complexa"
- "Elimine Primitive Obsession e argumentos do tipo flag"
- "Como estruturar injeção de dependências limpa no Spring Boot 4.1.1+?"
- "Qual padrão idiomático do Java 25 ou Kotlin 2.4 devo usar aqui?"

---

## Exemplos de Interação

```
> "Este método de checkout tem 80 linhas e muitos ifs aninhados, me ajude a refatorar."
→ Aplica Guard Clauses (Cláusulas de Guarda / Early Return), extrai métodos com nível único de abstração (SLAP) e agrupa parâmetros em Records (Java 25) ou Data Classes (Kotlin 2.4).

> "Temos validações manuais de e-mail e CPF espalhadas por três controllers."
→ Identifica violação de DRY e Primitive Obsession; encapsula regras em Record com compact constructor (Java 25) ou @JvmInline value class (Kotlin 2.4).
```

---

## Princípios Fundamentais

| Princípio | Pergunta-chave | Foco Principal |
|---|---|---|
| **DRY** | Esta lógica de negócio ou regra de validação está duplicada em outro ponto? | Fonte única da verdade para regras de domínio |
| **KISS** | Existe uma forma mais simples e direta usando a standard library moderna? | Clareza e eliminação de over-engineering |
| **YAGNI** | Precisamos dessa abstração/método/parâmetro hoje ou apenas "por precaução"? | Eliminação de código especulativo e morto |
| **Boy Scout Rule** | Deixei o arquivo mais legível e limpo do que quando o abri? | Melhoria contínua a cada alteração ou PR |
| **SLAP** | Todos os passos deste método estão no mesmo nível conceitual de abstração? | Separação entre orquestração e detalhes de baixo nível |

---

## Matriz de Conceitos e Padrões Modernos na JVM

| Conceito / Necessidade | Abordagem Java 25 LTS | Abordagem Kotlin 2.4+ |
|---|---|---|
| **Data Carriers Imutáveis** | `record` com acesso direto e sem getters legados | `data class` com propriedades `val` e método `copy()` |
| **Primitive Obsession** | `record` com compact constructor e validação fail-fast | `@JvmInline value class` com bloco `init` e zero heap overhead |
| **Controle de Fluxo / Padrões** | `switch` pattern matching com guard clauses (`when`) | `when` expression exaustivo com `sealed interface` |
| **Coleções Ordenadas** | Sequenced Collections (`getFirst()`, `getLast()`, `reversed()`) | Coleções nativas com `first()`, `last()`, `reversed()` |
| **Ausência de Valor** | `Optional<T>` estritamente em retorno de métodos | Tipagem anulável (`T?`), safe-call (`?.`) e Elvis (`?:`) |
| **Consultas / Strings Multilinha** | Text Blocks (`"""..."""`) com formatação preservada | Raw Strings (`"""..."""`) com `.trimIndent()` |
| **Injeção de Dependências** | Construtor explícito único sem `@Autowired` (Spring Boot) | Construtor primário conciso com `private val` |

---

## Tópicos Abordados na Skill

1. **Convenções de Nomenclatura**: Nomes reveladores de intenção, booleans afirmativos (eliminação de duplas negativas), enums top-level com mapeamento Jackson 3.
2. **Design de Funções e Métodos**: Funções pequenas (max ~15-20 linhas), limite de 3 parâmetros, eliminação de flags booleanas.
3. **Disciplina de Comentários**: Explicar o "PORQUÊ" (decisões, restrições externas), nunca o "O QUÊ" (código auto-documentado).
4. **Catálogo de Code Smells**: Magic numbers, primitive obsession, long parameter list, deep nesting, god classes, feature envy.
5. **Técnicas de Refatoração**: Guard clauses, extração de métodos, parameter objects, desconstrução funcional limpa.

---

## Habilidades Relacionadas

- **[Princípios SOLID](../solid-principles/SKILL.md)**: Aplique quando uma classe violar o SRP (Responsabilidade Única), tiver acoplamento excessivo ou necessitar de inversão de dependência (DIP).
- **[Design Patterns](../design-patterns/SKILL.md)**: Aplique quando lógicas condicionais complexas demandarem Strategy, Factory Method, State, ou criação fluente com Builder.
- **[Revisão de Concorrência](../concurrency-java21-review/SKILL.md)**: Aplique ao refatorar blocos `synchronized`, Virtual Threads, `CompletableFuture` ou contenção de locks concorrentes.
- **[Auditoria de Segurança Java/Kotlin](../java-kotlin-security-audit/SKILL.md)**: Aplique ao validar regras de segurança, sanitização contra injeção (SQLi/XSS/SSRF) e proteção de dados confidenciais (OWASP Top 10:2025).

---

## Recursos e Referências

- [Clean Code: A Handbook of Agile Software Craftsmanship (Robert C. Martin)](https://www.oreilly.com/library/view/clean-code-a/9780136083238/)
- [Refactoring: Improving the Design of Existing Code (Martin Fowler)](https://refactoring.com/)
- [Refactoring Guru - Code Smells Catalog](https://refactoring.guru/refactoring/smells)
- [Oracle Java 25 Documentation & JEPs](https://openjdk.org/projects/jdk/)
- [Kotlin Idiomatic Coding Conventions](https://kotlinlang.org/docs/coding-conventions.html)
