# Design Patterns (Padrões de Projeto) - Java 25 LTS & Kotlin 2.4+

**Carregar**: `view skills/design-patterns/SKILL.md`

---

## Descrição

Catálogo de Padrões de Projeto GoF (*Gang of Four*) e padrões arquiteturais modernos, otimizados para a plataforma JVM
contemporânea (**Java 25 LTS**, **Kotlin 2.4+** e **Spring Boot 4.1.1+**).

Foco em código idiomático, seguro, imutável, compatível com Virtual Threads (Project Loom) e em conformidade estrita com
as regras de precisão monetária (`BigDecimal` com escala de 6 casas decimais e `RoundingMode.HALF_EVEN`).

---

## Casos de Uso

- "Como implementar o padrão Strategy com sealed interfaces ou funções lambdas?"
- "Preciso de um Builder em Kotlin ou argumentos nomeados resolvem meu caso?"
- "Como estruturar um DSL Builder tipado em Kotlin com `@DslMarker`?"
- "Qual a forma idiomática de Factory Method usando pattern matching em Java 25?"
- "Como usar o padrão Decorator sem boilerplate no Kotlin com a palavra-chave `by`?"
- "Como desacoplar efeitos colaterais de persistência usando o padrão Observer com Spring Events?"
- "Quando usar Template Method vs funções de alta ordem (Higher-Order Functions)?"
- "Como criar um Adapter seguro para isolar SDKs legados mantendo o domínio tipado?"

---

## Exemplos de Interação

```
> "Preciso processar pagamentos via Pix, Cartão e Boleto com regras de gateway distintas."
→ Recomenda Strategy com sealed interface (Java 25) ou sealed class/hierarquia com lambdas (Kotlin 2.4), garantindo tratamento exaustivo, controle de timeout e chaves de idempotência.

> "Nosso construtor de pedidos tem 12 parâmetros opcionais e itens aninhados."
→ Sugere argumentos nomeados para casos simples ou DSL Builder tipado (@DslMarker) em Kotlin 2.4; em Java 25, implementa Fluent Builder imutável com validação no build().

> "Preciso adicionar medição de métricas e taxas extras em um serviço de transferência bancária."
→ Sugere Decorator via composição de interface (Java 25) ou delegação de classes nativa 'by delegate' (Kotlin 2.4), promovendo OCP sem herança rígida.
```

---

## Matriz GoF vs Idiomas Modernos da JVM

| Padrão GoF          | Categoria      | Abordagem Java 25 LTS                                                   | Abordagem Kotlin 2.4+                                                      | Princípio SOLID Promovido     |
|---------------------|----------------|-------------------------------------------------------------------------|----------------------------------------------------------------------------|-------------------------------|
| **Builder**         | Criacional     | Fluent Builder imutável ou `record` com canonical constructor           | Argumentos nomeados com defaults; DSL Builder (`@DslMarker`)               | **SRP**, **DIP**              |
| **Factory Method**  | Criacional     | Static factory em `record`/interfaces com pattern matching `switch`     | Companion object factory functions, top-level functions e SAM              | **DIP**, **SRP**, **OCP**     |
| **Singleton**       | Criacional     | Spring Bean (`@Service`/`@Component`) ou `enum` para lógica sem estado  | Declaração nativa `object` (thread-safe na JVM) ou Spring Bean             | **SRP** (usar com parcimônia) |
| **Strategy**        | Comportamental | `sealed interface` com pattern matching ou `@FunctionalInterface`       | First-class functions `(T) -> R`, `fun interface` ou `sealed interface`    | **OCP**, **SRP**              |
| **Observer**        | Comportamental | Spring Boot `ApplicationEventPublisher` + `@TransactionalEventListener` | `Delegates.observable` (memória) ou Spring Events idiomáticos              | **OCP**, **SRP**, **DIP**     |
| **Template Method** | Comportamental | Classe abstrata com método template `final` e hooks protegidos          | Higher-Order Functions com trailing lambdas (composição sobre herança)     | **OCP**, **DIP**              |
| **Decorator**       | Estrutural     | Composição de interface com injeção de delegado por construtor          | Class delegation nativa via palavra-chave `by` (`class D : I by delegate`) | **OCP**, **SRP**              |
| **Adapter**         | Estrutural     | Wrapper adapter com injeção de dependência por construtor               | Extension functions para mapeamento de dados ou object adapter via `by`    | **LSP**, **ISP**, **DIP**     |

---

## Guia Rápido de Seleção

| Cenário / Necessidade                                                  | Padrão Recomendado  | Benefício Principal                                            |
|------------------------------------------------------------------------|---------------------|----------------------------------------------------------------|
| Construção de objetos complexos com múltiplos opcionais ou hierarquias | **Builder**         | Imutabilidade e validação fail-fast consolidada                |
| Criação de instâncias desacopladas da classe concreta de destino       | **Factory Method**  | Desacoplamento via DIP e exaustividade em tempo de compilação  |
| Ponto único de acesso para lógica sem estado ou pooling gerenciado     | **Singleton**       | Centralização de ciclo de vida (sempre via Spring ou Enum)     |
| Troca dinâmica de algoritmos de cálculo, integração ou precificação    | **Strategy**        | Aderência a OCP sem explosão de condicionais `if`/`switch`     |
| Reação desacoplada a eventos de domínio sem comprometer transações     | **Observer**        | Efeitos colaterais seguros isolados pós-commit                 |
| Pipeline com etapas fixas e passos customizáveis                       | **Template Method** | Reuso de orquestração; em Kotlin prefira funções de alta ordem |
| Adição de comportamentos transversais (taxas, métricas, logs)          | **Decorator**       | Extensibilidade transparente sem alterar o código original     |
| Integração com APIs externas ou modelos legados incompatíveis          | **Adapter**         | Proteção da integridade e pureza do modelo de domínio          |

---

## Prevenção de Anti-Patterns ("Patternitis")

> [!WARNING]
> **Alerta de Sobre-engenharia (Patternitis)**: Nunca introduza um padrão de projeto antes de haver uma necessidade real
e demonstrável. Se uma função pura ou um `record`/`data class` simples resolve o problema, não construa factories,
builders ou hierarquias de herança. Siga as diretrizes de **KISS** e **YAGNI** detalhadas
em [clean-code](../clean-code/SKILL.md).

Principais armadilhas a evitar:

1. **Singleton Abuse**: Nunca armazene estado mutável global ou recursos não thread-safe (como `java.sql.Connection`) em
   Singletons.
2. **Thread Pinning com Virtual Threads**: Evite blocos `synchronized` em Singletons ou Decorators compartilhados.
   Utilize `ReentrantLock` ou estruturas sem lock.
3. **Observer Bloqueante em Transação**: Nunca execute chamadas externas de I/O em `@EventListener` síncrono no mesmo
   contexto transacional. Utilize `@TransactionalEventListener(phase = AFTER_COMMIT)` com `@Async`.
4. **Violação de Precisão Monetária**: Jamais utilize `double`, `float` ou `MathContext` para dinheiro. Aplique
   `.setScale(6, RoundingMode.HALF_EVEN)`.

---

## Habilidades Relacionadas

- **[Princípios SOLID](../solid-principles/SKILL.md)**: Fundamentos teóricos e práticos de orientação a objetos que
  justificam o uso de cada padrão GoF.
- **[Clean Code](../clean-code/SKILL.md)**: Diretrizes de simplicidade (KISS, YAGNI, DRY), funções limpas e eliminação
  de sobre-engenharia.
- **[Concorrência e Paralelismo JVM](../java-kotlin-concurrency/SKILL.md)**: Virtual Threads (Java 25), Kotlin Coroutines (2.4+), carrier pinning, ScopedValue e concorrência estruturada sem anti-patterns.
- **[Auditoria de Segurança Java/Kotlin](../java-kotlin-security-audit/SKILL.md)**: Boas práticas de segurança em
  fábricas, adaptadores e proteção de dados confidenciais (OWASP Top 10:2025).

---

## Recursos e Referências

- [Design Patterns: Elements of Reusable Object-Oriented Software (Gang of Four)](https://www.oreilly.com/library/view/design-patterns-elements/0201633612/)
- [Refactoring Guru - Design Patterns Reference & Catalog](https://refactoring.guru/design-patterns)
- [Kotlin Delegation - Official Documentation](https://kotlinlang.org/docs/delegation.html)
- [Kotlin Type-Safe Builders & DSL Markers](https://kotlinlang.org/docs/type-safe-builders.html)
- [Spring Framework Event Publication & Handling](https://docs.spring.io/spring-framework/reference/core/beans/context-introduction.html#context-functionality-events)
- [JEP 441: Pattern Matching for switch (Java 21+)](https://openjdk.org/jeps/441)
