# Princípios SOLID (SOLID Principles) - Java 25 LTS & Kotlin 2.4+

**Carregar**: `view skills/solid-principles/SKILL.md`

---

## Descrição

Guia de referência e checklist prático dos princípios **SOLID** (*Single Responsibility, Open/Closed, Liskov
Substitution, Interface Segregation, Dependency Inversion*) aplicados com foco na plataforma JVM contemporânea (**Java
25 LTS**, **Kotlin 2.4+** e **Spring Boot 4.1.1+**).

O guia aborda a transição de práticas legadas para abordagens modernas:

- **SRP**: `record` imutável com validação compacta e `data class` com `init`, eliminando classes "God" e separando
  orquestração de efeitos colaterais.
- **OCP**: `sealed interface` com pattern matching exaustivo no `switch` (Java 25) e expressões `when` (Kotlin 2.4),
  garantindo precisão financeira estrita com `BigDecimal` e `RoundingMode.HALF_EVEN`.
- **LSP**: Eliminação de `UnsupportedOperationException`, garantia de invariantes de contratos e preferência por
  composição sobre herança.
- **ISP**: Decomposição de "Fat Interfaces" em Role Interfaces funcionais e composição elegante via delegação de classes
  nativa (`by`) em Kotlin.
- **DIP**: Injeção estrita via construtor único sem `@Autowired`, dependência de abstrações de domínio e configuração do
  plugin `kotlin-spring` (`all-open`) para proxies CGLIB.

---

## Casos de Uso

- "Verifique se esta classe possui violações de SOLID"
- "Esta classe está fazendo coisas demais? Como dividir o UserService?" (SRP)
- "Como adicionar novos tipos de cálculo ou desconto sem modificar a classe existente?" (OCP)
- "Por que implementar CrudRepository e lançar UnsupportedOperationException quebra o LSP?" (LSP)
- "Como decompor interfaces infladas sem gerar dezenas de métodos pass-through em Kotlin?" (ISP via `by`)
- "Como estruturar injeção de dependências sem `@Autowired` em campo no Spring Boot 4.1.1+?" (DIP)

---

## Exemplos de Interação

```
> "Revise este UserService que valida CPF, salva no Postgres e envia e-mail SMTP."
→ Identifica violação de SRP e DIP. Sugere extração de invariantes no record de domínio, repositório de dados dedicado, gateway de notificação e injeção por construtor único no serviço orquestrador.

> "Como calcular descontos dinâmicos sem encadear múltiplos if/else em String?"
→ Demonstra OCP com sealed interface Discount permits PercentageDiscount, FixedDiscount, etc., cálculo financeiro com BigDecimal.setScale(6, RoundingMode.HALF_EVEN) e avaliação exaustiva em switch/when.

> "Por que herdar Rectangle para criar Square causa falhas em testes unitários?"
→ Explica quebra de LSP e contratos de invariantes. Demonstra refatoração para sealed interface Shape com records imutáveis independentes.
```

---

## Matriz Resumo dos Princípios SOLID na JVM Moderna

| Princípio                     | Pergunta-Chave                                                               | Abordagem Java 25 LTS                                                          | Abordagem Kotlin 2.4+                                                        | Padrão GoF Associado                                               |
|-------------------------------|------------------------------------------------------------------------------|--------------------------------------------------------------------------------|------------------------------------------------------------------------------|--------------------------------------------------------------------|
| **S - Single Responsibility** | A classe possui apenas uma única razão para mudar?                           | `record` imutável com construtor compacto + serviços coesos.                   | `data class` com bloco `init` + serviços com injeção primária.               | [Builder, Strategy, Observer](../design-patterns/SKILL.md)         |
| **O - Open/Closed**           | É possível adicionar comportamentos sem modificar código existente?          | `sealed interface` com `permits` + pattern matching exaustivo no `switch`.     | `sealed interface` / `sealed class` avaliado em `when` sem `else`.           | [Strategy, Factory Method, Decorator](../design-patterns/SKILL.md) |
| **L - Liskov Substitution**   | Os subtipos podem substituir os tipos base sem quebras em tempo de execução? | Segregação de hierarquias; imutabilidade; sem `UnsupportedOperationException`. | `sealed interface` com `data class`; composição sobre herança.               | [Adapter, Strategy](../design-patterns/SKILL.md)                   |
| **I - Interface Segregation** | Os clientes dependem apenas dos métodos que efetivamente utilizam?           | Role Interfaces funcionais e contratos finos segregados.                       | Interfaces segregadas combinadas com delegação de classes nativa (`by`).     | [Adapter](../design-patterns/SKILL.md)                             |
| **D - Dependency Inversion**  | Módulos de negócio dependem exclusivamente de abstrações?                    | Injeção obrigatória por construtor único; sem `@Autowired`; tipos de domínio.  | Construtor primário conciso (`val`); suporte a `kotlin-spring` (`all-open`). | [Factory Method, Strategy](../design-patterns/SKILL.md)            |

---

## Prevenção de Armadilhas Comuns

1. **God Classes e Serviços Monolíticos**: Serviços com dezenas de métodos e dependências de múltiplos domínios ferem
   SRP e dificultam testes unitários puros.
2. **Despacho por String ou Enums Inflados**: Cadeias de `if ("TYPE".equals(str))` violam OCP. Prefira polimorfismo via
   `sealed interface`.
3. **`UnsupportedOperationException` em Subtipos**: Lançar exceções de operação não suportada viola o contrato LSP.
   Segregue as interfaces (ISP).
4. **Interfaces Inchadas (Fat Interfaces)**: Forçar clientes a implementar métodos que não utilizam viola ISP e polui a
   base de código.
5. **Injeção de Campo com `@Autowired`**: Prejudica a testabilidade, esconde dependências e impossibilita campos `final`
   imutáveis. Utilize injeção por construtor.
6. **Perda de Precisão Monetária**: Jamais use `double` ou `float` para cálculos de taxas ou descontos. Sempre aplique
   `BigDecimal` com escala e `RoundingMode.HALF_EVEN`.

---

## Habilidades Relacionadas

- **[Clean Code](../clean-code/SKILL.md)**: Funções pequenas, Boy Scout Rule, regras DRY, KISS e YAGNI.
- **[Design Patterns](../design-patterns/SKILL.md)**: Padrões GoF (Strategy, Factory Method, Adapter, Decorator,
  Builder) implementados na JVM moderna.
- **[Revisão de Concorrência Java 21/25](../concurrency-java21-review/SKILL.md)**: Concorrência com Virtual Threads,
  prevenção de locks em singletons e serviços stateless seguros.
- **[Auditoria de Segurança Java/Kotlin](../java-kotlin-security-audit/SKILL.md)**: Práticas de validação defensiva e
  integridade estrutural contra OWASP Top 10:2025.

---

## Recursos e Referências

- [Clean Architecture: A Craftsman's Guide to Software Structure and Design (Robert C. Martin)](https://www.oreilly.com/library/view/clean-architecture-a/9780134494272/)
- [JEP 440: Record Patterns (Java 21+)](https://openjdk.org/jeps/440)
- [JEP 441: Pattern Matching for switch (Java 21+)](https://openjdk.org/jeps/441)
- [Kotlin Class Delegation Reference](https://kotlinlang.org/docs/delegation.html)
- [Kotlin All-Open Compiler Plugin](https://kotlinlang.org/docs/all-open-plugin.html)
- [Spring Framework Core Technologies: Dependency Injection](https://docs.spring.io/spring-framework/reference/core/beans.html)
