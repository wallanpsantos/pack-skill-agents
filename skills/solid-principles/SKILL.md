---
name: solid-principles
description: Princípios SOLID (SRP, OCP, LSP, ISP, DIP) aplicados de forma idiomática em Java 25 LTS e Kotlin 2.4+ no Spring Boot 4.1.1+. Use durante revisões de arquitetura de classes, refatoração de serviços monolíticos ou análise de acoplamento e extensibilidade.
---

# Princípios SOLID na JVM Moderna (Java 25 LTS & Kotlin 2.4+)

Guia definitivo e checklist prático dos princípios **SOLID** (*Single Responsibility, Open/Closed, Liskov Substitution,
Interface Segregation, Dependency Inversion*), aplicados com rigor arquitetural e de forma idiomática na plataforma JVM
moderna com **Java 25 LTS**, **Kotlin 2.4+** e **Spring Boot 4.1.1+**.

Foco em tipagem estática avançada (`sealed interface`, `record`, pattern matching, class delegation), imutabilidade,
isolamento de efeitos colaterais, concorrência segura com Virtual Threads e precisão financeira estrita com `BigDecimal`
e `RoundingMode.HALF_EVEN`.

---

## Quando Usar

- Durante revisões de Pull Requests e arquitetura de classes focadas em acoplamento, coesão e manutenibilidade.
- Ao refatorar classes infladas ("God Classes" ou serviços monolíticos) que misturam validação, persistência e
  orquestração.
- Ao substituir condicionais legadas (`if`/`else` ou `switch` baseados em `String`/enum) por polimorfismo seguro e
  extensível.
- Ao identificar violações de contratos de herança (`UnsupportedOperationException` ou pré/pós-condições quebradas).
- Ao decompor interfaces gigantes ("Fat Interfaces") em contratos enxutos focados no cliente ("Role Interfaces").
- Ao eliminar acoplamento rígido (instanciações diretas com `new` ou `@Autowired` em campos) em favor de injeção limpa
  por construtor e dependência de abstrações de domínio.

---

## Matriz Resumo dos Princípios SOLID

| Letra | Princípio                 | Resumo do Conceito                                                                                | Idioma Java 25 LTS                                                                                      | Idioma Kotlin 2.4+                                                                                           | Padrão GoF Relacionado                                             |
|-------|---------------------------|---------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------|
| **S** | **Single Responsibility** | Uma classe deve ter um, e apenas um, motivo para mudar.                                           | `record` imutável com validação compacta + serviços orquestradores desacoplados.                        | `data class` imutável com bloco `init` + serviços com injeção via construtor primário.                       | [Builder, Strategy, Observer](../design-patterns/SKILL.md)         |
| **O** | **Open/Closed**           | Aberto para extensão, fechado para modificação.                                                   | `sealed interface` com `permits` + pattern matching exaustivo no `switch`.                              | `sealed interface` / `sealed class` avaliado em `when` exaustivo ou `fun interface`.                         | [Strategy, Factory Method, Decorator](../design-patterns/SKILL.md) |
| **L** | **Liskov Substitution**   | Subtipos devem ser substituíveis por seus tipos base sem alterar a corretude.                     | `sealed interface` hierárquica imutável; composição sobre herança; sem `UnsupportedOperationException`. | Segregação de hierarquia via interfaces e classes de dados; contratos claros sem exceções em operações base. | [Adapter, Strategy](../design-patterns/SKILL.md)                   |
| **I** | **Interface Segregation** | Clientes não devem ser forçados a depender de métodos que não utilizam.                           | Role interfaces pequenas e funcionais (`@FunctionalInterface`).                                         | Interfaces segregadas combinadas elegantemente via delegação nativa de classes (`by`).                       | [Adapter](../design-patterns/SKILL.md)                             |
| **D** | **Dependency Inversion**  | Módulos de alto nível não devem depender de módulos de baixo nível; ambos dependem de abstrações. | Injeção estrita via construtor único sem `@Autowired`; dependência em interfaces de domínio puro.       | Construtor primário conciso (`val`); suporte a CGLIB via `kotlin-spring` (`all-open`); fakes de teste.       | [Factory Method, Strategy](../design-patterns/SKILL.md)            |

---

## S - Single Responsibility Principle (SRP)

> *"Uma classe deve ter apenas um motivo para mudar."* — Robert C. Martin

O SRP estabelece que um módulo ou classe deve ser responsável por um único ator ou contexto de negócio. Quando uma
classe acumula responsabilidades distintas — como validação de dados, persistência em banco, envio de e-mails e registro
de auditoria —, mudanças em regras de notificação forçam a alteração de código que lida com o ciclo de vida de
persistência, elevando drasticamente o risco de regressões.

### Sintomas de Violação

- Classes com múltiplos imports de domínios não relacionados (ex: `jakarta.persistence.*`, `jakarta.mail.*`,
  `org.slf4j.Logger`, regras de cálculo).
- Nomes de classes genéricos ou compostos: `UserManager`, `OrderProcessorAndNotifier`, `PaymentHandler`.
- Métodos longos que misturam orquestração com detalhes de infraestrutura e formatação de texto.
- Dificuldade em escrever testes unitários sem mockar dezenas de colaboradores.

---

### Violação (Java & Kotlin)

```java
// ❌ BAD (Java): UserService acumula validação, persistência, notificação e auditoria
public class UserService {
    private final EntityManager entityManager;
    private final SmtpClient smtpClient;
    private final AuditDatabase auditDatabase;

    public UserService(EntityManager entityManager, SmtpClient smtpClient, AuditDatabase auditDatabase) {
        this.entityManager = entityManager;
        this.smtpClient = smtpClient;
        this.auditDatabase = auditDatabase;
    }

    public User registerUser(String name, String email) {
        // Responsabilidade 1: Validação de formato de entrada
        if (email == null || !email.contains("@") || email.isBlank()) {
            throw new IllegalArgumentException("Invalid email format");
        }
        if (name == null || name.isBlank()) {
            throw new IllegalArgumentException("Name cannot be empty");
        }

        // Responsabilidade 2: Persistência de entidade
        User user = new User(name, email);
        entityManager.persist(user);

        // Responsabilidade 3: Formatação e envio de e-mail
        String subject = "Bem-vindo à Plataforma!";
        String body = "<h1>Olá, " + name + "</h1><p>Sua conta foi ativada com sucesso.</p>";
        smtpClient.sendHtml(email, subject, body);

        // Responsabilidade 4: Auditoria de conformidade
        auditDatabase.insertLog("USER_REGISTERED", user.getId(), Instant.now());

        return user;
    }
}
```

---

### Refatoração Idiomática em Java 25 LTS

No Java 25, a validação de formato e integridade estrutural é encapsulada diretamente no construtor compacto de um
`record` imutável. Cada dependência de infraestrutura é isolada em seu próprio componente coeso, e o serviço atua
exclusivamente como orquestrador do caso de uso:

```java
// ✅ GOOD (Java 25): Invariantes no record e componentes com responsabilidades isoladas

// 1. Representação do domínio imutável com validação fail-fast compacta
public record User(String name, String email) {
    public User {
        if (name == null || name.isBlank()) {
            throw new IllegalArgumentException("Name cannot be empty");
        }
        if (email == null || !email.contains("@") || email.isBlank()) {
            throw new IllegalArgumentException("Invalid email format");
        }
    }
}

// 2. Responsabilidade única: Persistência do Usuário
public interface UserRepository {
    User save(User user);
}

public class JpaUserRepository implements UserRepository {
    private final EntityManager entityManager;

    public JpaUserRepository(EntityManager entityManager) {
        this.entityManager = entityManager;
    }

    @Override
    public User save(User user) {
        entityManager.persist(user);
        return user;
    }
}

// 3. Responsabilidade única: Notificação de Boas-Vindas
public interface WelcomeEmailSender {
    void sendWelcome(User user);
}

public class SmtpWelcomeEmailSender implements WelcomeEmailSender {
    private final SmtpClient smtpClient;

    public SmtpWelcomeEmailSender(SmtpClient smtpClient) {
        this.smtpClient = smtpClient;
    }

    @Override
    public void sendWelcome(User user) {
        String subject = "Bem-vindo à Plataforma!";
        String body = "<h1>Olá, " + user.name() + "</h1><p>Sua conta foi ativada com sucesso.</p>";
        smtpClient.sendHtml(user.email(), subject, body);
    }
}

// 4. Responsabilidade única: Auditoria de Operações
public interface UserAuditLogger {
    void logCreation(User user);
}

public class DatabaseUserAuditLogger implements UserAuditLogger {
    private final AuditDatabase auditDatabase;

    public DatabaseUserAuditLogger(AuditDatabase auditDatabase) {
        this.auditDatabase = auditDatabase;
    }

    @Override
    public void logCreation(User user) {
        auditDatabase.insertLog("USER_REGISTERED", user.email(), Instant.now());
    }
}

// 5. Orquestrador do Caso de Uso: Coeso e focado apenas no fluxo de registro
public class UserService {
    private final UserRepository repository;
    private final WelcomeEmailSender emailSender;
    private final UserAuditLogger auditLogger;

    public UserService(UserRepository repository,
                       WelcomeEmailSender emailSender,
                       UserAuditLogger auditLogger) {
        this.repository = repository;
        this.emailSender = emailSender;
        this.auditLogger = auditLogger;
    }

    public User registerUser(String name, String email) {
        // A validação sintática ocorre na instanciação do record User
        User newUser = new User(name, email);
        User savedUser = repository.save(newUser);
        emailSender.sendWelcome(savedUser);
        auditLogger.logCreation(savedUser);
        return savedUser;
    }
}
```

---

### Refatoração Idiomática em Kotlin 2.4+

Em Kotlin 2.4, utilizamos `data class` imutável com validação declarativa no bloco `init`, aliada a construtores
primários concisos:

```kotlin
// ✅ GOOD (Kotlin 2.4): Separação estrita com data class e injeção primária

// 1. Domínio imutável com validação de invariantes
data class User(val name: String, val email: String) {
    init {
        require(name.isNotBlank()) { "Name cannot be empty" }
        require(email.isNotBlank() && email.contains("@")) { "Invalid email format" }
    }
}

// 2. Contratos focados de responsabilidade única
interface UserRepository {
    fun save(user: User): User
}

interface WelcomeEmailSender {
    fun sendWelcome(user: User)
}

interface UserAuditLogger {
    fun logCreation(user: User)
}

// 3. Orquestrador do Caso de Uso
class UserService(
    private val repository: UserRepository,
    private val emailSender: WelcomeEmailSender,
    private val auditLogger: UserAuditLogger
) {
    fun registerUser(name: String, email: String): User {
        val user = User(name = name, email = email)
        val savedUser = repository.save(user)
        emailSender.sendWelcome(savedUser)
        auditLogger.logCreation(savedUser)
        return savedUser
    }
}
```

> [!TIP]
> **Concorrência e Virtual Threads**: Componentes com responsabilidade única que operam sobre records/data classes
imutáveis e não mantêm estado mutável interno são naturalmente *thread-safe*. No Spring Boot 4.1.1+ sobre Java 25 com
Virtual Threads ativadas (`spring.threads.virtual.enabled: true`), esses serviços escalam sem contenção de locks ou
pinning de carrier threads. Para diretrizes de concorrência,
consulte [concurrency-java21-review](../concurrency-java21-review/SKILL.md).

> [!NOTE]
> Para manter funções pequenas e aplicar a Boy Scout Rule durante a refatoração do SRP, consulte o guia
de [clean-code](../clean-code/SKILL.md).

---

## O - Open/Closed Principle (OCP)

> *"Entidades de software (classes, módulos, funções) devem estar abertas para extensão, mas fechadas para
modificação."* — Bertrand Meyer

O princípio estabelece que você deve ser capaz de adicionar novos comportamentos ao sistema sem alterar o código
existente que já está testado e operando em produção. Violações clássicas ocorrem quando novos requisitos (ex: um novo
tipo de desconto, meio de pagamento ou canal de notificação) exigem a adição de ramos `if`/`else` ou `case` em classes
centrais.

### Rigor de Precisão Financeira

Em cálculos fiscais, de taxas ou descontos, **nunca utilize `double` ou `float`**. O uso de tipos de ponto flutuante
binário causa imprecisões catastróficas de arredondamento. Sempre utilize `BigDecimal` com escala explícita (ex: 6 casas
decimais para cálculo intermediário, 2 para liquidação final) e modo de arredondamento financeiro padrão **
`RoundingMode.HALF_EVEN`** (*Banker's Rounding*).

---

### Violação (Java & Kotlin)

```java
// ❌ BAD (Java): Modificação obrigatória a cada novo tipo de desconto
public class DiscountCalculator {

    public BigDecimal calculateDiscount(Order order, String discountType) {
        if ("PERCENTAGE".equalsIgnoreCase(discountType)) {
            return order.total()
                    .multiply(new BigDecimal("0.10"))
                    .setScale(6, RoundingMode.HALF_EVEN);
        } else if ("FIXED".equalsIgnoreCase(discountType)) {
            return new BigDecimal("50.000000");
        } else if ("LOYALTY".equalsIgnoreCase(discountType)) {
            return order.total()
                    .multiply(order.customerLoyaltyRate())
                    .setScale(6, RoundingMode.HALF_EVEN);
        }
        // Para adicionar "SEASONAL", "BLACK_FRIDAY" ou "COUPON", esta classe precisa ser alterada!
        return BigDecimal.ZERO.setScale(6, RoundingMode.HALF_EVEN);
    }
}
```

---

### Refatoração Idiomática em Java 25 LTS

No Java 25, o OCP atinge seu ápice idiomático combinando **`sealed interface`** com records imutáveis e **Pattern
Matching for switch** (JEP 441/440). Novos descontos são adicionados como novos records. O compilador garante
exaustividade estrita em tempo de compilação sem necessidade de cláusulas `default`:

```java
// ✅ GOOD (Java 25): Extensão segura com sealed interface e pattern matching

public sealed interface Discount permits PercentageDiscount, FixedDiscount, LoyaltyDiscount, SeasonalDiscount {
    BigDecimal apply(Order order);
}

public record PercentageDiscount(BigDecimal rate) implements Discount {
    public PercentageDiscount {
        if (rate == null || rate.compareTo(BigDecimal.ZERO) < 0) {
            throw new IllegalArgumentException("Discount rate must be non-negative");
        }
    }

    @Override
    public BigDecimal apply(Order order) {
        return order.total()
                .multiply(rate)
                .setScale(6, RoundingMode.HALF_EVEN);
    }
}

public record FixedDiscount(BigDecimal amount) implements Discount {
    public FixedDiscount {
        if (amount == null || amount.compareTo(BigDecimal.ZERO) < 0) {
            throw new IllegalArgumentException("Discount amount must be non-negative");
        }
    }

    @Override
    public BigDecimal apply(Order order) {
        return amount.setScale(6, RoundingMode.HALF_EVEN);
    }
}

public record LoyaltyDiscount(BigDecimal loyaltyRate) implements Discount {
    @Override
    public BigDecimal apply(Order order) {
        return order.total()
                .multiply(loyaltyRate)
                .setScale(6, RoundingMode.HALF_EVEN);
    }
}

// Novo tipo de desconto: basta adicionar este record sem alterar nenhuma linha dos descontos existentes!
public record SeasonalDiscount(BigDecimal rate, BigDecimal cap) implements Discount {
    @Override
    public BigDecimal apply(Order order) {
        BigDecimal calculated = order.total().multiply(rate).setScale(6, RoundingMode.HALF_EVEN);
        return calculated.min(cap.setScale(6, RoundingMode.HALF_EVEN));
    }
}

// Abordagem Funcional / Pattern Matching Exaustivo:
public class DiscountService {

    public BigDecimal calculate(Order order, Discount discount) {
        // Polimorfismo direto:
        return discount.apply(order);
    }

    // Alternativa quando a lógica de orquestração externa inspeciona a variante:
    public BigDecimal inspectAndCalculate(Order order, Discount discount) {
        return switch (discount) {
            case PercentageDiscount p -> order.total().multiply(p.rate()).setScale(6, RoundingMode.HALF_EVEN);
            case FixedDiscount f      -> f.amount().setScale(6, RoundingMode.HALF_EVEN);
            case LoyaltyDiscount l    -> order.total().multiply(l.loyaltyRate()).setScale(6, RoundingMode.HALF_EVEN);
            case SeasonalDiscount s   -> order.total().multiply(s.rate()).setScale(6, RoundingMode.HALF_EVEN).min(s.cap());
        }; // Compilador valida exaustividade estrita sem 'default'
    }
}
```

---

### Refatoração Idiomática em Kotlin 2.4+

Em Kotlin 2.4, utilizamos `sealed interface` com `data class` avaliadas em expressões `when` exaustivas ou interfaces
funcionais com lambdas:

```kotlin
// ✅ GOOD (Kotlin 2.4): Sealed interface, avaliação exaustiva em when e precisão financeira
import java.math.BigDecimal
import java.math.RoundingMode

sealed interface Discount {
    fun apply(order: Order): BigDecimal
}

data class PercentageDiscount(val rate: BigDecimal) : Discount {
    init {
        require(rate >= BigDecimal.ZERO) { "Rate must be non-negative" }
    }

    override fun apply(order: Order): BigDecimal =
        order.total.multiply(rate).setScale(6, RoundingMode.HALF_EVEN)
}

data class FixedDiscount(val amount: BigDecimal) : Discount {
    init {
        require(amount >= BigDecimal.ZERO) { "Amount must be non-negative" }
    }

    override fun apply(order: Order): BigDecimal =
        amount.setScale(6, RoundingMode.HALF_EVEN)
}

data class LoyaltyDiscount(val loyaltyRate: BigDecimal) : Discount {
    override fun apply(order: Order): BigDecimal =
        order.total.multiply(loyaltyRate).setScale(6, RoundingMode.HALF_EVEN)
}

// Extensão limpa: adição sem modificar código anterior
data class SeasonalDiscount(val rate: BigDecimal, val cap: BigDecimal) : Discount {
    override fun apply(order: Order): BigDecimal {
        val calculated = order.total.multiply(rate).setScale(6, RoundingMode.HALF_EVEN)
        return calculated.min(cap.setScale(6, RoundingMode.HALF_EVEN))
    }
}

class DiscountService {
    // Avaliação exaustiva via when (o compilador Kotlin dispensa branch else)
    fun calculate(order: Order, discount: Discount): BigDecimal = when (discount) {
        is PercentageDiscount -> order.total.multiply(discount.rate).setScale(6, RoundingMode.HALF_EVEN)
        is FixedDiscount      -> discount.amount.setScale(6, RoundingMode.HALF_EVEN)
        is LoyaltyDiscount    -> order.total.multiply(discount.loyaltyRate).setScale(6, RoundingMode.HALF_EVEN)
        is SeasonalDiscount   -> order.total.multiply(discount.rate).setScale(6, RoundingMode.HALF_EVEN).min(discount.cap)
    }
}
```

> [!TIP]
> Para aprofundar a implementação de regras extensíveis com os padrões **Strategy**, **Factory Method** e **Decorator**,
consulte [design-patterns](../design-patterns/SKILL.md).

---

## L - Liskov Substitution Principle (LSP)

> *"Se $q (x)$ é uma propriedade demonstrável dos objetos $x$ de tipo $T$, então $q (y)$ deve ser verdadeiro para
objetos $y$ de tipo $S$, onde $S$ é um subtipo de $T$."* — Barbara Liskov

Em termos práticos de engenharia de software na JVM: **qualquer subclasse ou implementação de interface deve poder ser
utilizada no lugar de sua classe/interface base sem que o cliente precise saber a diferença ou sofra falhas inesperadas
de execução.**

### As Quatro Regras Formais do Contrato de Subtipagem

1. **Pré-condições não podem ser fortalecidas**: O subtipo não pode exigir mais do que o tipo base exigia (ex: não pode
   proibir parâmetros que a interface base aceita).
2. **Pós-condições não podem ser enfraquecidas**: O subtipo não pode entregar menos do que o tipo base garantia (ex: não
   pode retornar `null` onde a interface base garante `Optional` presente ou valor preenchido).
3. **Invariantes devem ser mantidos**: Todas as regras de integridade do tipo base devem permanecer válidas no subtipo.
4. **Regra de Histórico (Imutabilidade)**: O subtipo não pode permitir mutações de estado se a superclasse garantia
   imutabilidade.

### Violações Típicas no Mundo JVM Real

- **Lançar `UnsupportedOperationException`**: Implementar uma interface ampla e lançar exceção em métodos indesejados.
- **Checagens defensivas com `instanceof` / `is`**: Código cliente que precisa verificar o tipo concreto antes de
  invocar um método por medo do comportamento do subtipo.
- **O Dilema Retângulo x Quadrado**: Sobrescrever setters de forma que alterar a largura altere implicitamente a altura,
  violando invariantes de retângulos matemáticos.

---

### Violação 1: UnsupportedOperationException em Repositórios (Java)

```java
// ❌ BAD: ReadOnlyRepository viola o contrato de CrudRepository
public interface CrudRepository<T> {
    T save(T entity);
    Optional<T> findById(Long id);
    void deleteById(Long id);
}

public class ReadOnlyAuditRepository implements CrudRepository<AuditRecord> {
    @Override
    public AuditRecord save(AuditRecord entity) {
        // Violação grave de LSP! O cliente espera persistência, mas recebe uma exceção de runtime.
        throw new UnsupportedOperationException("Audit records are immutable and cannot be saved via this repository");
    }

    @Override
    public Optional<AuditRecord> findById(Long id) {
        // leitura permitida...
        return Optional.empty();
    }

    @Override
    public void deleteById(Long id) {
        throw new UnsupportedOperationException("Deletion not supported");
    }
}
```

---

### Violação 2: Quebra de Invariantes em Hierarquia de Formas (Java)

```java
// ❌ BAD: Quadrado viola os invariantes de Retângulo
public class Rectangle {
    private int width;
    private int height;

    public void setWidth(int width) { this.width = width; }
    public void setHeight(int height) { this.height = height; }
    public int getWidth() { return width; }
    public int getHeight() { return height; }
    public int area() { return width * height; }
}

public class Square extends Rectangle {
    @Override
    public void setWidth(int width) {
        super.setWidth(width);
        super.setHeight(width); // Efeito colateral inesperado!
    }

    @Override
    public void setHeight(int height) {
        super.setWidth(height); // Efeito colateral inesperado!
        super.setHeight(height);
    }
}

// Código cliente com suposição válida que falha catastroficamente:
void resize(Rectangle rect) {
    rect.setWidth(5);
    rect.setHeight(10);
    // Para Rectangle normal: área = 50.
    // Para Square: área = 100 (a largura foi sobrescrita para 10 no setHeight)!
    assert rect.area() == 50 : "Quebra de LSP detectada!";
}
```

---

### Refatoração Idiomática em Java 25 LTS

Substituímos a herança incorreta por **`sealed interface`** e **records imutáveis**. Repositórios são segregados em
interfaces de leitura e escrita:

```java
// ✅ GOOD (Java 25): Segregação estrita sem exceções de operação não suportada

// 1. Resolução para Repositórios: Segregação de interfaces (ISP garante LSP)
public interface ReadRepository<T> {
    Optional<T> findById(Long id);
}

public interface WriteRepository<T> {
    T save(T entity);
    void deleteById(Long id);
}

// ReadOnlyAuditRepository implementa APENAS o que de fato suporta
public class ReadOnlyAuditRepository implements ReadRepository<AuditRecord> {
    private final EntityManager entityManager;

    public ReadOnlyAuditRepository(EntityManager entityManager) {
        this.entityManager = entityManager;
    }

    @Override
    public Optional<AuditRecord> findById(Long id) {
        return Optional.ofNullable(entityManager.find(AuditRecord.class, id));
    }
}

// 2. Resolução para Hierarquias Geométricas: Imutabilidade e Sealed Interface
public sealed interface Shape permits Rectangle, Square {
    int area();
}

public record Rectangle(int width, int height) implements Shape {
    public Rectangle {
        if (width <= 0 || height <= 0) {
            throw new IllegalArgumentException("Dimensions must be positive");
        }
    }

    @Override
    public int area() {
        return width * height;
    }
}

public record Square(int side) implements Shape {
    public Square {
        if (side <= 0) {
            throw new IllegalArgumentException("Side must be positive");
        }
    }

    @Override
    public int area() {
        return side * side;
    }
}
```

---

### Refatoração Idiomática em Kotlin 2.4+

Em Kotlin 2.4, modelamos hierarquias puras e previsíveis sem efeitos colaterais:

```kotlin
// ✅ GOOD (Kotlin 2.4): Subtipagem segura sem métodos que explodem em tempo de execução

// 1. Contratos segregados de persistência
interface ReadRepository<T> {
    fun findById(id: Long): T?
}

interface WriteRepository<T> {
    fun save(entity: T): T
    fun deleteById(id: Long)
}

// Subtipo plenamente substituível para o contrato que assume
class ReadOnlyAuditRepository(private val entityManager: EntityManager) : ReadRepository<AuditRecord> {
    override fun findById(id: Long): AuditRecord? = entityManager.find(AuditRecord::class.java, id)
}

// 2. Modelagem geométrica com sealed interface e data class imutável
sealed interface Shape {
    val area: Int
}

data class Rectangle(val width: Int, val height: Int) : Shape {
    init {
        require(width > 0 && height > 0) { "Dimensions must be positive" }
    }
    override val area: Int get() = width * height
}

data class Square(val side: Int) : Shape {
    init {
        require(side > 0) { "Side must be positive" }
    }
    override val area: Int get() = side * side
}
```

---

## I - Interface Segregation Principle (ISP)

> *"Clientes não devem ser forçados a depender de métodos que não utilizam."* — Robert C. Martin

Interfaces inchadas ("Fat Interfaces") acoplam módulos a métodos irrelevantes para suas necessidades. Quando uma
interface possui 15 ou 20 métodos misturando leitura, escrita, relatórios, auditoria e controle de ciclo de vida,
qualquer alteração na assinatura de um método de relatório força a recompilação e reimplantação de componentes que
apenas realizavam leitura simples.

### Sintomas de Violação

- Implementações de interfaces contendo métodos vazios (`{ /* no-op */ }`) ou que lançam
  `UnsupportedOperationException`.
- Clientes que utilizam apenas 1 ou 2 métodos de uma interface com dezenas de operações.
- Dificuldade para criar stubs ou fakes em testes unitários devido ao excesso de métodos a implementar.

---

### Violação (Java & Kotlin)

```java
// ❌ BAD (Java): Interface 'Worker' força comportamentos não aplicáveis a todos os clientes
public interface Worker {
    void work();
    void eat();
    void sleep();
    void attendMeeting();
    void writeDailyReport();
}

// Um Robô automatizado não come, não dorme e não participa de reuniões!
public class RobotWorker implements Worker {
    @Override
    public void work() {
        System.out.println("Processing manufacturing queue...");
    }

    @Override
    public void eat() {
        // Não faz sentido para robôs!
        throw new UnsupportedOperationException("Robots do not eat");
    }

    @Override
    public void sleep() {
        // Não faz sentido para robôs!
        throw new UnsupportedOperationException("Robots do not sleep");
    }

    @Override
    public void attendMeeting() {
        // Não aplicável
    }

    @Override
    public void writeDailyReport() {
        System.out.println("Generating telemetry payload...");
    }
}
```

---

### Refatoração Idiomática em Java 25 LTS

Segregamos a fat interface em **Role Interfaces** enxutas e coesas. Cada cliente depende estritamente do contrato que
consome:

```java
// ✅ GOOD (Java 25): Role Interfaces específicas por capacidade

@FunctionalInterface
public interface Workable {
    void work();
}

public interface Feedable {
    void eat();
    void sleep();
}

public interface Manageable {
    void attendMeeting();
    void writeDailyReport();
}

// Funcionário humano implementa todos os papéis relevantes
public class HumanWorker implements Workable, Feedable, Manageable {
    @Override public void work() { /* executa tarefas */ }
    @Override public void eat() { /* almoço */ }
    @Override public void sleep() { /* descanso */ }
    @Override public void attendMeeting() { /* alinhamento diário */ }
    @Override public void writeDailyReport() { /* resumo diário */ }
}

// Robô implementa exclusivamente o que executa
public class RobotWorker implements Workable {
    @Override
    public void work() {
        // processamento contínuo sem métodos artificiais
    }
}

// Serviço consumidor depende apenas da capacidade necessária
public class ProductionLine {
    private final List<Workable> workers;

    public ProductionLine(List<Workable> workers) {
        this.workers = List.copyOf(workers);
    }

    public void runShift() {
        workers.forEach(Workable::work);
    }
}
```

---

### Refatoração Idiomática em Kotlin 2.4+ (com Delegação de Classes `by`)

No Kotlin 2.4, a segregação de interfaces atinge máxima elegância através do suporte nativo à **Delegação de Classes**
com a palavra-chave **`by`**. Isso permite compor comportamentos a partir de implementações especializadas sem nenhum
código boilerplate de métodos pass-through:

```kotlin
// ✅ GOOD (Kotlin 2.4): Interfaces segregadas e composição via delegação nativa ('by')

fun interface Workable {
    fun work()
}

interface Feedable {
    fun eat()
    fun sleep()
}

interface Manageable {
    fun attendMeeting()
    fun writeDailyReport()
}

// Robô depende estritamente de Workable
class RobotWorker : Workable {
    override fun work() {
        // Operação contínua de linha de produção
    }
}

// Implementações especializadas para delegação
class StandardEatingHabits : Feedable {
    override fun eat() { /* refeição */ }
    override fun sleep() { /* descanso */ }
}

class StandardCorporateDuties : Manageable {
    override fun attendMeeting() { /* reunião diária */ }
    override fun writeDailyReport() { /* relatório diário */ }
}

// HumanWorker combina interfaces segregadas usando delegação nativa de classes ('by')
// Zero boilerplate: chamadas para Feedable e Manageable são delegadas automaticamente!
class HumanWorker(
    private val workableTask: () -> Unit,
    feedableDelegate: Feedable = StandardEatingHabits(),
    manageableDelegate: Manageable = StandardCorporateDuties()
) : Workable, Feedable by feedableDelegate, Manageable by manageableDelegate {
    override fun work() = workableTask()
}

class ProductionLine(private val workers: List<Workable>) {
    fun executeShift() {
        workers.forEach { it.work() }
    }
}
```

> [!TIP]
> Para integrar SDKs ou APIs externas legadas que possuem interfaces infladas com seu domínio segregado, consulte o
padrão **Adapter** em [design-patterns](../design-patterns/SKILL.md).

---

## D - Dependency Inversion Principle (DIP)

> *"Módulos de alto nível não devem depender de módulos de baixo nível. Ambos devem depender de abstrações. Abstrações
não devem depender de detalhes. Detalhes devem depender de abstrações."* — Robert C. Martin

O DIP inverte a árvore de dependências tradicional da programação procedural. Em vez de a lógica de negócio central
(caso de uso / serviço de aplicação) instanciar diretamente adaptadores de banco de dados, drivers JDBC ou clientes HTTP
de mensageria, ela declara **interfaces de domínio**. Os módulos de infraestrutura (Spring Data, mensageria, gateways de
pagamento) é que passam a depender dessas interfaces de domínio para implementá-las.

### Violações Típicas

- Instanciação de implementações concretas dentro de serviços (`new PostgresOrderRepository()`).
- Injeção em campo com anotação `@Autowired` (`@Autowired private OrderRepository repository;`). Isso impede a
  imutabilidade, oculta dependências reais e impede a execução de testes unitários sem levantar o container de injeção
  de dependências.
- Vazamento de exceções técnicas de infraestrutura (`SQLException`, `SocketTimeoutException`, `MongoException`)
  diretamente na camada de domínio.

---

### Violação (Java & Kotlin)

```java
// ❌ BAD (Java): Acoplamento rígido a implementações concretas e injeção de campo
@Service
public class OrderService {

    // Violação 1: Injeção por campo esconde dependências e quebra imutabilidade
    @Autowired
    private PostgresOrderRepository repository; 

    // Violação 2: Dependência direta de classe concreta de infraestrutura
    @Autowired
    private SmtpEmailClient emailClient; 

    public void processOrder(Order order) {
        // Violação 3: Se o banco de dados mudar ou falhar, detalhes de SQL vazam aqui
        repository.insertDirectSql(order);
        emailClient.sendRawSmtp(order.customerEmail(), "Pedido confirmado");
    }
}
```

---

### Refatoração Idiomática em Java 25 & Spring Boot 4.1.1+

No Spring Boot 4.1.1+ (Spring Framework 7.0), a injeção estrita é realizada via construtor único sem a necessidade de
anotações `@Autowired`. As dependências são imutáveis (`final`), as interfaces pertencem à camada de domínio, e os erros
de infraestrutura são encapsulados em tipos de domínio:

```java
// ✅ GOOD (Java 25 & Spring Boot 4.1.1+): Injeção por construtor e abstrações de domínio

// 1. Abstrações puras do Domínio (Hexagonal / Clean Architecture)
public interface OrderRepository {
    Order save(Order order);
    Optional<Order> findById(Long id);
}

public interface NotificationGateway {
    void notifyCustomer(String email, String message);
}

// 2. Serviço de Alto Nível: Depende EXCLUSIVAMENTE das abstrações
@Service
public class OrderService {
    private final OrderRepository repository;
    private final NotificationGateway notificationGateway;

    // Injeção obrigatória via construtor: sem @Autowired (Spring Boot 4.1.1+ auto-detecta)
    public OrderService(OrderRepository repository, NotificationGateway notificationGateway) {
        this.repository = repository;
        this.notificationGateway = notificationGateway;
    }

    @Transactional
    public Order processOrder(Order order) {
        Order savedOrder = repository.save(order);
        notificationGateway.notifyCustomer(savedOrder.customerEmail(), "Seu pedido foi confirmado!");
        return savedOrder;
    }
}

// 3. Módulos de Baixo Nível (Infraestrutura) implementam os contratos de domínio
@Repository
public class PostgresOrderRepository implements OrderRepository {
    private final EntityManager entityManager;

    public PostgresOrderRepository(EntityManager entityManager) {
        this.entityManager = entityManager;
    }

    @Override
    public Order save(Order order) {
        try {
            entityManager.persist(order);
            return order;
        } catch (PersistenceException ex) {
            // Detalhe de infraestrutura encapsulado em exceção de domínio
            throw new DomainPersistenceException("Failed to persist order: " + order.id(), ex);
        }
    }

    @Override
    public Optional<Order> findById(Long id) {
        return Optional.ofNullable(entityManager.find(Order.class, id));
    }
}

@Component
@Profile("production")
public class SmtpNotificationGateway implements NotificationGateway {
    private final SmtpClient smtpClient;

    public SmtpNotificationGateway(SmtpClient smtpClient) {
        this.smtpClient = smtpClient;
    }

    @Override
    public void notifyCustomer(String email, String message) {
        try {
            smtpClient.send(email, "Notificação de Pedido", message);
        } catch (Exception ex) {
            // Falhas de rede tratadas no adaptador
            throw new NotificationDispatchException("Failed to deliver notification to: " + email, ex);
        }
    }
}

// 4. Implementação Fake para Testes Unitários Ultrarrápidos (Zero Spring Context necessário!)
public class InMemoryOrderRepository implements OrderRepository {
    private final Map<Long, Order> storage = new ConcurrentHashMap<>();

    @Override
    public Order save(Order order) {
        storage.put(order.id(), order);
        return order;
    }

    @Override
    public Optional<Order> findById(Long id) {
        return Optional.ofNullable(storage.get(id));
    }
}
```

---

### Refatoração Idiomática em Kotlin 2.4 & Spring Boot 4.1.1+

Em Kotlin 2.4, a injeção via construtor primário é expressa de forma concisa. Note o suporte ao plugin `kotlin-spring`
(que aplica `all-open` automaticamente para classes `@Service` e métodos `@Transactional` para permitir proxies CGLIB do
Spring Framework 7):

```kotlin
// ✅ GOOD (Kotlin 2.4 & Spring Boot 4.1.1+): Construtor primário conciso com suporte a all-open
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.util.concurrent.ConcurrentHashMap

// 1. Contratos de domínio
interface OrderRepository {
    fun save(order: Order): Order
    fun findById(id: Long): Order?
}

interface NotificationGateway {
    fun notifyCustomer(email: String, message: String)
}

// 2. Serviço de Alto Nível
// Graças ao plugin 'kotlin-spring' / 'all-open', a classe e os métodos anotados
// são abertos para proxy CGLIB automaticamente no build Gradle.
@Service
class OrderService(
    private val repository: OrderRepository,
    private val notificationGateway: NotificationGateway
) {
    @Transactional
    fun processOrder(order: Order): Order {
        val savedOrder = repository.save(order)
        notificationGateway.notifyCustomer(savedOrder.customerEmail, "Seu pedido foi confirmado!")
        return savedOrder
    }
}

// 3. Fake em memória para testes unitários isolados
class InMemoryOrderRepository : OrderRepository {
    private val storage = ConcurrentHashMap<Long, Order>()

    override fun save(order: Order): Order {
        storage[order.id] = order
        return order
    }

    override fun findById(id: Long): Order? = storage[id]
}
```

> [!IMPORTANT]
> **Thread Safety em Serviços Singleton no Spring Boot**: Serviços injetados via DIP são instanciados como *Singletons*
no Spring Boot. Eles **nunca devem manter estado mutável em campos de instância**. Em ambientes corporativos modernos
rodando sobre Virtual Threads do Java 25 (`spring.threads.virtual.enabled: true`), centenas de requisições simultâneas
compartilham a mesma instância do serviço. Qualquer estado mutável deve residir no escopo local da chamada do método ou
em estruturas concorrentes com controle explícito.
Consulte [concurrency-java21-review](../concurrency-java21-review/SKILL.md).

---

## Checklist de Revisão de Código SOLID

Utilize este checklist prático durante auditorias de código e revisões de Pull Requests:

| Princípio | Pergunta de Verificação                                                              | Sinal de Alerta (Code Smell)                                                          | Ação de Correção Recomendada                                                      |
|-----------|--------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------|
| **SRP**   | Esta classe possui apenas uma única razão para mudar?                                | Nomes com "And", "Manager", mais de 7 colaboradores injetados, múltiplos domínios.    | Extrair classes especializadas para validação, persistência e efeitos colaterais. |
| **OCP**   | Para adicionar uma nova variação de negócio é necessário modificar código existente? | `switch` ou cadeias de `if/else` inspecionando `String` ou enum de tipo de negócio.   | Migrar para `sealed interface` com pattern matching ou padrão Strategy.           |
| **LSP**   | Qualquer subtipo pode substituir seu tipo base sem lançar exceções inesperadas?      | `throw new UnsupportedOperationException()`, métodos no-op ou `instanceof` defensivo. | Segregar interfaces hierárquicas e adotar composição sobre herança.               |
| **ISP**   | Algum cliente é forçado a implementar métodos que não utiliza?                       | Classes implementando interfaces com métodos vazios ou desnecessários para seu papel. | Decompor em Role Interfaces funcionais; em Kotlin, utilizar delegação `by`.       |
| **DIP**   | A regra de negócio depende exclusivamente de interfaces do domínio?                  | `new ConcreteClass()` no meio do serviço, injeção com `@Autowired` em campo.          | Injetar abstrações via construtor único sem anotações desnecessárias.             |

---

## Matriz de Cruzamento: SOLID x Design Patterns x Clean Code

| Violação SOLID               | Refatoração Recomendada                                | Padrão GoF Associado                                            | Diretriz Clean Code                                         |
|------------------------------|--------------------------------------------------------|-----------------------------------------------------------------|-------------------------------------------------------------|
| **SRP** (Serviço Monolítico) | Decomposição em serviços especializados e orquestrador | [Builder, Strategy, Observer](../design-patterns/SKILL.md)      | [Funções Pequenas, Boy Scout Rule](../clean-code/SKILL.md)  |
| **OCP** (Switch de Tipos)    | `sealed interface` + Pattern Matching                  | [Strategy, Factory Method](../design-patterns/SKILL.md)         | [Polimorfismo sobre Condicionais](../clean-code/SKILL.md)   |
| **LSP** (Herança Quebrada)   | Composição de interfaces imutáveis                     | [Adapter, Strategy](../design-patterns/SKILL.md)                | [Princípio do Menor Espanto (POLA)](../clean-code/SKILL.md) |
| **ISP** (Fat Interface)      | Role Interfaces enxutas e delegação nativa             | [Adapter, Decorator](../design-patterns/SKILL.md)               | [Interfaces Focadas e YAGNI](../clean-code/SKILL.md)        |
| **DIP** (Acoplamento Rígido) | Injeção de dependência por construtor                  | [Factory Method, Abstract Factory](../design-patterns/SKILL.md) | [Separação de Construção e Uso](../clean-code/SKILL.md)     |

---

## Prevenção de Anti-Patterns e Sobre-Engenharia ("Patternitis")

> [!WARNING]
> **Alerta de Sobre-Engenharia**:
> 1. **Não crie interfaces prematuras ("Interfaceitis")**: Se uma classe possui apenas uma única implementação concreta
     previsível e não faz I/O externo ou integração que justifique dublê de testes, criar `IUserService` e
     `UserServiceImpl` viola o princípio **YAGNI** (*You Aren't Gonna Need It*). Crie interfaces onde há variação
     polimórfica ou fronteira arquitetural real.
> 2. **Composição sobre Herança**: Quase todas as violações de LSP decorrem de herança de código (`extends`) utilizada
     para mero reaproveitamento de código em vez de relação genuína "é um". Prefira sempre compor objetos por injeção.
> 3. **Imutabilidade Estrutural**: Sempre que possível, utilize `record` no Java 25 e `data class` no Kotlin 2.4.
     Objetos imutáveis eliminam dezenas de bugs sutis de concorrência e quebras de invariantes de estado.

---

## Habilidades Relacionadas

- **[Clean Code](../clean-code/SKILL.md)**: Diretrizes complementares para nomenclatura expressiva, funções de
  responsabilidade única, regras DRY, KISS, YAGNI e Boy Scout Rule.
- **[Design Patterns](../design-patterns/SKILL.md)**: Implementações canônicas dos padrões GoF (Strategy, Factory
  Method, Adapter, Decorator, Builder) que concretizam os princípios SOLID.
- **[Revisão de Concorrência Java 21/25](../concurrency-java21-review/SKILL.md)**: Regras essenciais para execução
  thread-safe de serviços singleton sob Virtual Threads (Project Loom), locks e eliminação de thread pinning.
- **[Auditoria de Segurança Java/Kotlin](../java-kotlin-security-audit/SKILL.md)**: Boas práticas de segurança aplicadas
  à validação de domínio e controle de acesso (OWASP Top 10:2025).

---

## Recursos e Referências

- [Clean Architecture: A Craftsman's Guide to Software Structure and Design (Robert C. Martin)](https://www.oreilly.com/library/view/clean-architecture-a/9780134494272/)
- [JEP 440: Record Patterns (Java 21+)](https://openjdk.org/jeps/440)
- [JEP 441: Pattern Matching for switch (Java 21+)](https://openjdk.org/jeps/441)
- [JEP 409: Sealed Classes (Java 17+)](https://openjdk.org/jeps/409)
- [Kotlin Delegation Pattern (Official Documentation)](https://kotlinlang.org/docs/delegation.html)
- [Kotlin All-Open Compiler Plugin for Spring](https://kotlinlang.org/docs/all-open-plugin.html)
- [Spring Framework 7.0 & Spring Boot 4.1 Dependency Injection Reference](https://docs.spring.io/spring-framework/reference/core/beans.html)
