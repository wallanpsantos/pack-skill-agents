---
name: clean-code
description: Princípios de Clean Code (DRY, KISS, YAGNI), convenções de nomenclatura, design de funções e refatoração idiomática para Java 25 LTS e Kotlin 2.4+. Use quando o usuário solicitar "limpe este código", "refatore", "melhore a legibilidade", ou durante revisões de qualidade de código.
---

# Clean Code Skill

Escreva código legível, expressivo, manutenível e idiomático para a plataforma JVM moderna, abrangendo **Java 25 LTS** e
**Kotlin 2.4+**.

---

## Quando Usar

- Solicitações como: "limpe este código", "refatore este método", "melhore a legibilidade", "esta função está muito
  complexa".
- Revisões de código com foco em simplicidade, manutenibilidade e eliminação de code smells.
- Redução de complexidade ciclomática e aninhamentos desnecessários.
- Padronização de nomenclatura, imutabilidade e eliminação de Primitive Obsession.
- Transição de código legado ou verboso para os padrões idiomáticos do Java 25 e Kotlin 2.4.

---

## Princípios Fundamentais

| Princípio | Significado                | Sintoma de Violação                                          | Ação de Refatoração                                               |
|-----------|----------------------------|--------------------------------------------------------------|-------------------------------------------------------------------|
| **DRY**   | *Don't Repeat Yourself*    | Blocos de lógica duplicados ou regras de domínio espalhadas  | Encapsular regra única em Record/Value Class ou método utilitário |
| **KISS**  | *Keep It Simple, Stupid*   | Soluções super-engenheiradas, cadeias funcionais convolutas  | Simplificar fluxo, usar biblioteca padrão e construções diretas   |
| **YAGNI** | *You Aren't Gonna Need It* | Interfaces gigantes especulativas, parâmetros "just in case" | Deletar código morto, modelar apenas o necessário para o presente |

---

## DRY - Don't Repeat Yourself

> *"Toda peça de conhecimento deve ter uma representação única, não ambígua e autoritativa no sistema."*

DRY não é apenas sobre duplicação literal de linhas de texto; é sobre **duplicação de conhecimento e regras de
negócio**.

### Violação (Java & Kotlin)

Duplicação de regras de validação ou cálculo em múltiplos controladores, serviços ou endpoints:

```java
// ❌ BAD (Java): Validação repetida manualmente em múltiplos pontos
public class UserController {
    public void createUser(UserRequest request) {
        if (request.email() == null || request.email().isBlank()) {
            throw new ValidationException("Email is required");
        }
        if (!request.email().contains("@")) {
            throw new ValidationException("Invalid email format");
        }
        // ... criar usuário
    }

    public void updateUser(UserRequest request) {
        if (request.email() == null || request.email().isBlank()) {
            throw new ValidationException("Email is required");
        }
        if (!request.email().contains("@")) {
            throw new ValidationException("Invalid email format");
        }
        // ... atualizar usuário
    }
}
```

### Refatorado em Java 25

Encapsular a regra de negócio em um `record` imutável com **compact constructor** e **guard clauses**. O tipo passa a
ser auto-validável e a regra tem fonte única da verdade:

```java
// ✅ GOOD (Java 25): Record com compact constructor garante unicidade da regra
public record Email(String value) {
    public Email {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException("Email is required");
        }
        value = value.trim().toLowerCase();
        if (!value.contains("@") || value.startsWith("@") || value.endsWith("@")) {
            throw new IllegalArgumentException("Invalid email format: " + value);
        }
    }
}

public record UserRequest(String name, Email email) {}

public class UserController {
    public void createUser(UserRequest request) {
        // Regra validada na criação do record Email. Código enxuto e seguro.
        userService.create(request.name(), request.email());
    }

    public void updateUser(Long id, UserRequest request) {
        userService.update(id, request.name(), request.email());
    }
}
```

### Refatorado em Kotlin 2.4+

Usar `@JvmInline value class` para validação com **zero overhead** de alocação no heap, ou funções de extensão
dedicadas:

```kotlin
// ✅ GOOD (Kotlin 2.4): Value class imutável com validação fail-fast
@JvmInline
value class Email(val value: String) {
    init {
        require(value.isNotBlank()) { "Email is required" }
        require(value.contains("@") && !value.startsWith("@") && !value.endsWith("@")) {
            "Invalid email format: $value"
        }
    }

    val normalized: String get() = value.trim().lowercase()
}

data class UserRequest(val name: String, val email: Email)

class UserController(private val userService: UserService) {
    fun createUser(request: UserRequest) {
        userService.create(request.name, request.email)
    }

    fun updateUser(id: Long, request: UserRequest) {
        userService.update(id, request.name, request.email)
    }
}
```

### Exceções ao DRY: Duplicação Acidental vs Duplicação Real

Evite a armadilha da "abstração prematura". Se dois trechos de código possuem estrutura similar hoje, mas mudam por
razões de negócio distintas, **não os unifique**:

```java
// Duplicação aparente, mas com motivações de mudança distintas - MANTENHA SEPARADO:
public BigDecimal calculateShippingTax(Order order) {
    return order.totalWeight().multiply(SHIPPING_TAX_RATE);
}

public BigDecimal calculateInsuranceFee(Order order) {
    return order.declaredValue().multiply(INSURANCE_FEE_RATE);
}
// Unificar ambos em "calculateRate(amount, rate)" cria acoplamento artificial perigoso.
```

---

## KISS - Keep It Simple, Stupid

> *"A solução mais simples que resolve o problema com clareza é a melhor."*

Evite complexidade desnecessária gerada por excesso de abstração, construções funcionais labirínticas ou cadeias
obscuras de escopo.

### Violação (Java & Kotlin)

```java
// ❌ BAD (Java): Over-engineering para checagem simples de String
public class StringUtils {
    public boolean isBlank(String str) {
        return Optional.ofNullable(str)
                .map(String::trim)
                .map(String::isEmpty)
                .orElseGet(() -> Boolean.TRUE);
    }
}
```

```kotlin
// ❌ BAD (Kotlin): Cadeia convoluta de scope functions onde um simples if ou extensão nativa resolve
fun processUser(user: User?): String {
    return user?.let { u ->
        u.address?.run {
            city.takeIf { it.isNotBlank() }?.let { "City: $it" }
        }
    } ?: "Unknown"
}
```

### Refatorado em Java 25

```java
// ✅ GOOD (Java 25): Simples, direto e legível com métodos da JDK padrão
public final class TextUtils {
    private TextUtils() {}

    public static boolean isBlank(String str) {
        return str == null || str.isBlank();
    }
}
```

### Refatorado em Kotlin 2.4+

```kotlin
// ✅ GOOD (Kotlin 2.4): Uso direto da biblioteca padrão e safe-call idiomático
fun processUser(user: User?): String {
    val city = user?.address?.city
    return if (!city.isNullOrBlank()) "City: $city" else "Unknown"
}
```

### Checklist KISS

- [ ] Um desenvolvedor júnior compreende o fluxo em 30 segundos?
- [ ] Existe um método na standard library do Java 25 (`String.isBlank()`, `Objects.requireNonNull()`, `List.copyOf()`)
  ou Kotlin (`isNullOrBlank()`, `orEmpty()`) que elimina essa lógica personalizada?
- [ ] Estou adicionando uma camada genérica para um caso de uso que só existe uma vez?

---

## YAGNI - You Aren't Gonna Need It

> *"Não implemente funcionalidades, parâmetros ou abstrações até que elas sejam realmente necessárias."*

### Violação

```java
// ❌ BAD: Repositório com 15 métodos genéricos "para o caso de precisarmos no futuro"
public interface UserRepository {
    Optional<User> findById(Long id);
    User save(User user);
    // Métodos especulativos nunca chamados pela aplicação:
    List<User> findByAgeBetweenAndCountryOrderByScoreDesc(int min, int max, String country);
    void bulkArchiveInactiveUsers(Instant before);
    CompletableFuture<Void> exportAllToXmlAsync();
}
```

### Refatorado

```java
// ✅ GOOD: Apenas o contrato demandado pelo caso de uso atual
public interface UserRepository {
    Optional<User> findById(Long id);
    User save(User user);
}
```

### Sinais de Violação YAGNI

- Comentários: *"Podemos precisar disso na Fase 2"*.
- Flags booleanas de configuração que nunca foram alteradas em produção.
- Interfaces com apenas uma implementação onde o polimorfismo nunca será necessário.
- DTOs com dezenas de campos nulos carregados preventivamente.

---

## Naming Conventions (Convenções de Nomenclatura)

### Tabela Canônica de Nomenclatura (JVM)

| Elemento                   | Convenção                           | Java 25                            | Kotlin 2.4+                            |
|----------------------------|-------------------------------------|------------------------------------|----------------------------------------|
| **Classe / Interface**     | `PascalCase`, substantivo/adjetivo  | `OrderService`, `Auditable`        | `OrderService`, `Auditable`            |
| **Record / Data Class**    | `PascalCase`, substantivo imutável  | `record CustomerProfile(...)`      | `data class CustomerProfile(...)`      |
| **Value Class**            | `PascalCase`, tipo de domínio       | N/A (`record` no Java)             | `value class AccountId(val id: UUID)`  |
| **Método / Função**        | `camelCase`, verbo + substantivo    | `processPayment()`, `findActive()` | `processPayment()`, `findActive()`     |
| **Variável / Propriedade** | `camelCase`, substantivo específico | `orderAmount`, `timeoutSeconds`    | `orderAmount`, `timeoutSeconds`        |
| **Constante / Enum**       | `UPPER_SNAKE_CASE`                  | `MAX_RETRY_ATTEMPTS`               | `const val MAX_RETRY_ATTEMPTS = 3`     |
| **Enum Type**              | `PascalCase` singular               | `enum PaymentStatus { PENDING }`   | `enum class PaymentStatus { PENDING }` |
| **Pacote (Package)**       | `lowercase` unificado               | `com.example.billing.domain`       | `com.example.billing.domain`           |

### Booleans: Nomes Afirmativos e Intencionais

Evite prefixos negativos que causam duplas negativas confusas como `!isNotActive`:

```java
// ❌ BAD: Negações e ambiguidades
boolean check;
boolean status;
boolean isNotReady;
if (!isNotReady) { ... } // Dupla negativa confusa

// ✅ GOOD: Afirmativos com prefixos is/has/can/should
boolean isActive;
boolean hasPermission;
boolean canExecute;
boolean shouldRetry;
if (isActive) { ... }
```

### Métodos: Revele a Intenção

```java
// ❌ BAD: Nomes vagos que escondem o comportamento
void handle();
void doStuff();
Data get();

// ✅ GOOD: Verbo + Substantivo descritivo
void cancelSubscription();
void applyDiscountCode(String code);
User findByTaxId(TaxId taxId);
```

---

## Funções e Métodos de Alta Qualidade

### 1. Funções Pequenas e Focadas (Max ~15-20 linhas)

Funções devem fazer apenas uma coisa e fazê-la bem. Se uma função possui seções comentadas para separar etapas, cada
seção deve se tornar um método privado.

### 2. SLAP - Single Level of Abstraction Principle

Todos os passos dentro de um método devem estar no **mesmo nível de abstração**. Não misture orquestração de alto nível
com loops de baixo nível ou manipulação de strings.

```java
// ❌ BAD: Mistura orquestração com cálculo aritmético de baixo nível
public void checkout(Order order) {
    validateOrder(order); // Alto nível

    // Baixo nível intrusivo
    BigDecimal total = BigDecimal.ZERO;
    for (OrderItem item : order.items()) {
        total = total.add(item.unitPrice().multiply(BigDecimal.valueOf(item.quantity())));
    }

    paymentGateway.charge(order.customerId(), total); // Alto nível
}

// ✅ GOOD: Nível uniforme de abstração
public void checkout(Order order) {
    validateOrder(order);
    BigDecimal total = calculateTotal(order);
    processPayment(order.customerId(), total);
}

private BigDecimal calculateTotal(Order order) {
    return order.items().stream()
            .map(item -> item.unitPrice().multiply(BigDecimal.valueOf(item.quantity())))
            .reduce(BigDecimal.ZERO, BigDecimal::add);
}
```

### 3. Limite de Parâmetros (Max 3)

Se um método necessita de mais de 3 parâmetros, agrupe-os em um objeto contextual (`record` no Java 25, `data class` no
Kotlin 2.4).

```java
// ❌ BAD: Excesso de parâmetros primitivos suscetíveis à inversão
public void registerUser(String first, String last, String email, String phone, String street, String city, String zip) {}

// ✅ GOOD (Java 25): Parameter Object imutável via Record
public record Address(String street, String city, String zipCode) {}
public record UserRegistration(String firstName, String lastName, Email email, PhoneNumber phone, Address address) {}

public void registerUser(UserRegistration registration) {}
```

### 4. Evite Argumentos de Flag (Boolean Parameters)

Um parâmetro booleano indica quase invariavelmente que o método faz duas coisas distintas.

```java
// ❌ BAD: Flag boolean muda o fluxo interno
public void exportReport(Report report, boolean isPdf) {
    if (isPdf) {
        // gerar PDF
    } else {
        // gerar CSV
    }
}

// ✅ GOOD: Métodos explícitos e separados
public void exportPdfReport(Report report) {}
public void exportCsvReport(Report report) {}
```

---

## Injeção de Dependências Limpa (Spring Boot 4.1.1+)

### Proibição de Field Injection (`@Autowired` em Atributos)

A injeção em campos viola o encapsulamento, impede a criação de objetos imutáveis e dificulta testes unitários puros sem
subir o contexto do Spring.

### Java 25: Constructor Injection com Imutabilidade

No Spring Boot moderno, se a classe tiver apenas um construtor, a anotação `@Autowired` é redundante e deve ser omitida:

```java
// ❌ BAD: Field injection
@Service
public class OrderService {
    @Autowired
    private OrderRepository orderRepository;
    @Autowired
    private PaymentGateway paymentGateway;
}

// ✅ GOOD (Java 25): Injeção por construtor explícito com campos 'final' e verificação fail-fast
@Service
public class OrderService {
    private final OrderRepository orderRepository;
    private final PaymentGateway paymentGateway;

    public OrderService(OrderRepository orderRepository, PaymentGateway paymentGateway) {
        this.orderRepository = Objects.requireNonNull(orderRepository, "orderRepository must not be null");
        this.paymentGateway = Objects.requireNonNull(paymentGateway, "paymentGateway must not be null");
    }
}
```

### Kotlin 2.4+: Injeção por Construtor Primário

```kotlin
// ✅ GOOD (Kotlin 2.4): Construtor primário limpo, imutável e conciso
@Service
class OrderService(
    private val orderRepository: OrderRepository,
    private val paymentGateway: PaymentGateway
) {
    // Injeção limpa de dependência sem nenhuma anotação de framework
}
```

---

## Tratamento de Ausência de Valor e Null Safety

### Java 25: Disciplina no Uso de `Optional`

O `Optional` foi desenhado estritamente como **tipo de retorno para métodos onde o resultado pode estar ausente**.

- ❌ **NUNCA** use `Optional` como parâmetro de método (use sobrecarga ou trate null).
- ❌ **NUNCA** use `Optional` como atributo de classe ou campo de DTO/Record (não é serializável por padrão).
- ❌ **NUNCA** chame `.get()` sem verificação prévia (`.orElseThrow()`, `.map()`, `.ifPresent()`).

```java
// ❌ BAD: Chamada insegura e anti-pattern de Optional
Optional<User> optionalUser = userRepository.findById(id);
if (optionalUser.isPresent()) {
    return optionalUser.get().name();
}
return "Default";

// ✅ GOOD: Composição expressiva
return userRepository.findById(id)
        .map(User::name)
        .orElse("Default");

// ✅ GOOD: Falha rápida com exceção contextual
User user = userRepository.findById(id)
        .orElseThrow(() -> new EntityNotFoundException("User not found for id: " + id));
```

### Kotlin 2.4+: Null Safety Nativo e Boas Práticas

- Tire proveito dos tipos `T` (não nulo) e `T?` (anulável) em tempo de compilação.
- ❌ **EVITE** o operador de asserção `!!` (*not-null assertion*). Trata-se de um code smell que reintroduz
  `NullPointerException`.
- Use o operador Elvis `?:` com `return` ou `throw` para guard clauses limpas.

```kotlin
// ❌ BAD: Forçando null assertion
fun getUserName(user: User?): String {
    return user!!.name
}

// ✅ GOOD: Safe-call com valor default ou fail-fast
fun getUserName(user: User?): String = user?.name ?: "Default"

fun requireActiveUser(user: User?): User {
    return user?.takeIf { it.isActive }
        ?: throw IllegalStateException("User must be active and non-null")
}
```

### Kotlin: Disciplina com Funções de Escopo (`let`, `apply`, `also`, `run`)

Use cada função para sua finalidade canônica e evite aninhamentos:

| Função  | Context Object | Retorno             | Quando Usar                                                           |
|---------|----------------|---------------------|-----------------------------------------------------------------------|
| `let`   | `it`           | Resultado do lambda | Executar operações em valores não nulos ou transformar escopo         |
| `apply` | `this`         | O próprio objeto    | Configuração e inicialização de instâncias                            |
| `also`  | `it`           | O próprio objeto    | Efeitos colaterais adicionais (logging, métricas) sem alterar o valor |
| `run`   | `this`         | Resultado do lambda | Computação que necessita de escopo específico do objeto               |

```kotlin
// ✅ GOOD: Uso idiomático das funções de escopo
val client = HttpClient().apply {
    connectTimeoutMs = 5000
    readTimeoutMs = 3000
}

val token = response.takeIf { it.isSuccessful }
    ?.body
    ?.token
    ?.also { logger.info { "Token successfully acquired" } }
```

---

## Comentários: Disciplina e Intencionalidade

> *"Não comente código ruim — refatore-o."*

### Comentários Ruins (Ruído e Desculpa para Código Obscuro)

```java
// ❌ BAD: Comentário óbvio que repete o código
// Incrementa o contador
counter++;

// ❌ BAD: Comentário explicando código confuso em vez de refatorar
// Verifica se o usuário é maior de idade, tem conta ativa e não possui restrição
if (u.getAge() >= 18 && u.getSt() == 1 && u.getFlags() != 4) { ... }
```

### Comentários Bons (Explicam o "PORQUÊ", Decisões e Restrições)

```java
// ✅ GOOD: Explicação de regras de negócio obscuras ou limitações de infraestrutura
// O gateway de pagamento parceiro rejeita requisições com mais de 3 casas decimais
// mesmo para moedas cripto (vide documentação do provedor v2.1, seção 4.2).
BigDecimal sanitizedAmount = amount.setScale(2, RoundingMode.HALF_UP);

// ✅ GOOD: Código auto-documentado elimina necessidade de comentários
if (user.isAdult() && user.hasActiveAccount() && !user.hasCreditRestriction()) {
    grantCredit(user);
}
```

---

## Code Smells Comuns e Técnicas de Refatoração

| Code Smell                  | Descrição                                                               | Sintoma                             | Solução Canônica                                 |
|-----------------------------|-------------------------------------------------------------------------|-------------------------------------|--------------------------------------------------|
| **Magic Numbers / Strings** | Literais literais espalhados no código                                  | `if (status == 3)`                  | Constantes nomeadas ou Enums tipados             |
| **Primitive Obsession**     | Uso excessivo de tipos primitivos para conceitos de domínio             | `String email, String cpf, Long id` | `record` (Java) ou `value class` (Kotlin)        |
| **Long Parameter List**     | Métodos com > 3 argumentos                                              | Métodos com 5+ parâmetros           | Parameter Object / Record                        |
| **Deep Nesting**            | Ninhos profundos de `if/else`                                           | Código em forma de seta (`>`)       | Guard Clauses (Retorno Antecipado)               |
| **God Class**               | Classes que orquestram centenas de linhas e múltiplas responsabilidades | Arquivos com 500+ linhas            | Extrair classes por responsabilidade única       |
| **Dead Code**               | Código comentado ou métodos privados inacessíveis                       | Linhas mortas acumuladas            | Deletar imediatamente (o Git mantém o histórico) |
| **Feature Envy**            | Método que acessa mais dados de outra classe do que da própria          | `other.getX(), other.getY()`        | Mover método para a classe que detém os dados    |

### Primitive Obsession: Solução Java 25 vs Kotlin 2.4+

```java
// ❌ BAD: Passagem acidental de parâmetros invertidos que compilam sem erro!
public void transferMoney(String sourceAccountId, String targetAccountId, BigDecimal amount) {}
transfer(targetAccountId, sourceAccountId, amount); // Erro catastrófico em runtime

// ✅ GOOD (Java 25): Records de domínio garantem segurança de tipos
public record AccountId(UUID value) {
    public AccountId {
        Objects.requireNonNull(value, "AccountId must not be null");
    }
}

public void transferMoney(AccountId source, AccountId target, Money amount) {
    // Impossível inverter source e target acidentalmente com outros tipos
}
```

```kotlin
// ✅ GOOD (Kotlin 2.4): Value classes sem alocação adicional no runtime
@JvmInline
value class AccountId(val value: UUID)

data class Money(val amount: BigDecimal, val currency: Currency) {
    init {
        require(amount >= BigDecimal.ZERO) { "Amount cannot be negative" }
    }
}

fun transferMoney(source: AccountId, target: AccountId, amount: Money) {
    // Tipo seguro e compilação de alta performance
}
```

### Guard Clauses (Cláusulas de Guarda / Early Return)

Elimine aninhamentos profundos validando condições de erro e exceção logo no início do método:

```java
// ❌ BAD: Estrutura piramidal com aninhamento excessivo
public void processOrder(Order order) {
    if (order != null) {
        if (order.isApproved()) {
            if (!order.items().isEmpty()) {
                // Lógica de negócio soterrada no 4º nível de indentação
                dispatch(order);
            } else {
                throw new IllegalStateException("Order has no items");
            }
        } else {
            throw new IllegalStateException("Order is not approved");
        }
    }
}

// ✅ GOOD: Guard clauses lineares e limpas
public void processOrder(Order order) {
    if (order == null) return;

    if (!order.isApproved()) {
        throw new IllegalStateException("Order is not approved");
    }
    if (order.items().isEmpty()) {
        throw new IllegalStateException("Order has no items");
    }

    // Fluxo feliz principal no nível zero de indentação
    dispatch(order);
}
```

### Top-Level Enums vs Nested/Inner Enums

Enums genéricos aninhados dentro de classes (e.g. `public enum Status`) geram poluição no namespace, dificultam a
reutilização e causam ambiguidades em imports. Prefira enums top-level com nomes expressivos e serialização resiliente
com Jackson 3:

```java
// ✅ GOOD (Java 25): Enum Top-Level com contrato explícito Jackson 3
public enum OrderStatus {
    PENDING("pending"),
    PROCESSING("processing"),
    COMPLETED("completed"),
    CANCELLED("cancelled");

    private final String wireValue;

    OrderStatus(String wireValue) {
        this.wireValue = wireValue;
    }

    @JsonValue
    public String wireValue() {
        return wireValue;
    }

    @JsonCreator
    public static OrderStatus fromWire(String value) {
        if (value == null || value.isBlank()) return PENDING;
        for (var status : values()) {
            if (status.wireValue.equalsIgnoreCase(value) || status.name().equalsIgnoreCase(value)) {
                return status;
            }
        }
        throw new IllegalArgumentException("Unknown order status: " + value);
    }
}
```

---

## Modern JVM Clean Code Patterns (Java 25 LTS & Kotlin 2.4)

### Java 25 LTS: Recursos Idiomáticos Modernos

#### 1. Records para Modelos e DTOs Imutáveis

Elimine classes anêmicas com getters/setters e dependências de anotações externas de geração de código. Records possuem
semântica de valor imutável por padrão:

```java
public record CustomerResponse(
        UUID id,
        String fullName,
        Email email,
        Instant registeredAt
) {}
```

#### 2. Pattern Matching para `switch` com Guard Clauses (`when`)

Elimine cadeias de `instanceof` e casts manuais utilizando switch com padrões de tipo e guard clauses (`when`):

```java
public sealed interface PaymentMethod permits CreditCardPayment, PixPayment, BoletoPayment {}

public record CreditCardPayment(BigDecimal amount, String lastFourDigits) implements PaymentMethod {}
public record PixPayment(BigDecimal amount, String pixKey) implements PaymentMethod {}
public record BoletoPayment(BigDecimal amount, LocalDate expirationDate) implements PaymentMethod {}

public String describePayment(PaymentMethod payment) {
    return switch (payment) {
        case CreditCardPayment cc when cc.amount().compareTo(BigDecimal.valueOf(1000)) > 0 ->
                "High-value Credit Card (**** " + cc.lastFourDigits() + ")";
        case CreditCardPayment cc ->
                "Standard Credit Card (**** " + cc.lastFourDigits() + ")";
        case PixPayment pix ->
                "Instant PIX to " + pix.pixKey();
        case BoletoPayment boleto when boleto.expirationDate().isBefore(LocalDate.now()) ->
                "Expired Boleto due on " + boleto.expirationDate();
        case BoletoPayment boleto ->
                "Valid Boleto due on " + boleto.expirationDate();
    };
}
```

#### 3. Sequenced Collections (Java 21+)

Acesse extremidades e ordens reversas de coleções de forma direta e semântica, sem recorrer a cálculos de índice ou
iteradores manuais:

```java
List<Order> orders = fetchRecentOrders();

// ❌ Antigo / Frágil:
Order first = orders.get(0);
Order last = orders.get(orders.size() - 1);

// ✅ Modern Java 25 Sequenced Collections:
Order first = orders.getFirst();
Order last = orders.getLast();
List<Order> newestFirst = orders.reversed();
```

#### 4. Text Blocks (`"""`) para Consultas e Modelos Multilinha

Mantenha legibilidade em queries SQL, JSONs ou templates sem operadores de concatenação `+`:

```java
// ✅ GOOD: Text block limpo e alinhado
String query = """
        SELECT id, customer_id, total_amount, status
        FROM customer_orders
        WHERE status = 'PENDING_APPROVAL'
          AND created_at >= :cutoffDate
        ORDER BY created_at ASC
        """;
```

---

### Kotlin 2.4+: Recursos Idiomáticos Modernos

#### 1. Data Classes com Imutabilidade e Cópia

Use `val` em propriedades de `data class` para promover imutabilidade. Quando modificações forem necessárias, use a
função utilitária `copy()`:

```kotlin
data class Account(
    val id: UUID,
    val balance: BigDecimal,
    val isFrozen: Boolean = false
)

// Criação com imutabilidade estrita
val updatedAccount = account.copy(balance = account.balance + depositAmount)
```

#### 2. Sealed Interfaces para Modelagem de Domínio e Resultados

Exaustividade garantida em tempo de compilação sem necessidade de bloco `else`:

```kotlin
sealed interface DomainResult<out T> {
    data class Success<T>(val value: T) : DomainResult<T>
    data class Failure(val reason: String, val code: Int) : DomainResult<Nothing>
}

fun handleResult(result: DomainResult<Order>) = when (result) {
    is DomainResult.Success -> println("Order processed: ${result.value.id}")
    is DomainResult.Failure -> println("Failed [${result.code}]: ${result.reason}")
    // O compilador verifica exaustividade automaticamente!
}
```

#### 3. Funções de Extensão com Semântica Limpa

Enriqueça tipos para legibilidade de negócio sem poluir o modelo original com dependências:

```kotlin
// Extensão clara e focada
fun BigDecimal.toCurrencyString(currency: Currency = Currency.getInstance("BRL")): String {
    return NumberFormat.getCurrencyInstance(Locale.of("pt", "BR")).apply {
        this.currency = currency
    }.format(this)
}

val formatted = BigDecimal("149.90").toCurrencyString() // "R$ 149,90"
```

---

## Boy Scout Rule & Manutenção Contínua

> *"Deixe a área de acampamento sempre mais limpa do que você a encontrou."*

Ao trabalhar em qualquer arquivo de código existente:

1. **Renomeie variáveis obscuras** que você teve dificuldade para entender.
2. **Elimine imports Fully Qualified Names (FQN)** no meio dos métodos — declare imports explícitos no topo do arquivo.
3. **Remova código morto e comentado** — o versionamento Git é o responsável por preservar o histórico.
4. **Substitua validações manuais repetidas** por records, value classes ou métodos utilitários existentes.
5. **Garanta testes unitários** para qualquer lógica refatorada antes de considerar o trabalho finalizado.

---

## Checklist de Revisão Clean Code

Utilize este checklist durante PR reviews e sessões de refatoração:

- [ ] **Scout Rule**: O código modificado está mais legível e limpo do que antes da alteração?
- [ ] **DRY**: Não há regras de domínio ou validações duplicadas entre métodos ou classes?
- [ ] **KISS**: A solução adotada é a mais simples e direta possível? As bibliotecas padrão foram preferidas?
- [ ] **YAGNI**: Não existem métodos, parâmetros, abstrações ou interfaces especulativas adicionadas "para o futuro"?
- [ ] **Nomenclatura**: Nomes revelam intenção? Booleans são afirmativos (`isActive`)? Métodos usam verbo + substantivo?
- [ ] **Tamanho de Funções**: Métodos são pequenos (máximo ~15-20 linhas) e possuem nível único de abstração (SLAP)?
- [ ] **Parâmetros**: Nenhum método possui mais de 3 parâmetros (usou-se Parameter Object / Record / Data Class)?
- [ ] **Sem Argumentos Flag**: Parâmetros booleanos que alteram comportamento interno foram divididos em métodos
  separados?
- [ ] **Injeção de Dependências**: Spring Boot usa injeção de construtor sem `@Autowired` em fields?
- [ ] **Null Safety**: Java usa `Optional` apenas em retorno de métodos? Kotlin evita operador de risco `!!`?
- [ ] **Guard Clauses**: Estruturas aninhadas de `if/else` foram substituídas por retorno antecipado?
- [ ] **Padrões Modernos**: Java 25 adota records e pattern matching? Kotlin 2.4 adota value classes e sealed
  interfaces?

---

## Skills Relacionadas

Se a sua refatoração ultrapassar o escopo de legibilidade de método e exigir mudanças estruturais, ative as seguintes
skills especializadas:

- **[Princípios SOLID](../solid-principles/SKILL.md)**: Ative quando uma classe/função violar o Princípio da
  Responsabilidade Única (SRP), possuir alto acoplamento, ou necessitar de Inversão de Dependência (DIP).
- **[Design Patterns](../design-patterns/SKILL.md)**: Ative quando blocos condicionais complexos exigirem substituição
  por Strategy, Factory Method, State, ou quando a construção de objetos complexos demandar Builder ou Fluent DSL.
- **[Revisão de Concorrência](../concurrency-java21-review/SKILL.md)**: Ative quando a refatoração envolver Virtual
  Threads, thread safety, migração de `synchronized` para `ReentrantLock`, `CompletableFuture` ou contenção de recursos
  assíncronos.
- **[Auditoria de Segurança Java/Kotlin](../java-kotlin-security-audit/SKILL.md)**: Ative quando o código envolver
  sanitização de entrada de usuários, prevenção contra SQLi/XSS/SSRF, criptografia ou manuseio de dados sensíveis e
  credenciais (OWASP Top 10:2025).
