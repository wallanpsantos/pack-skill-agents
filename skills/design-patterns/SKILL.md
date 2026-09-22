---
name: design-patterns
description: Padrões de projeto GoF e padrões arquiteturais idiomáticos para Java 25 LTS, Kotlin 2.4+ e Spring Boot 4.1.1+. Use ao desenhar arquiteturas de classes, refatorar condicionais para polimorfismo, implementar factories/builders ou estruturar integrações desacopladas.
---

# Design Patterns Skill

Catálogo de padrões de projeto GoF (*Gang of Four*) e padrões arquiteturais modernos, implementados de forma idiomática para a plataforma JVM moderna com **Java 25 LTS**, **Kotlin 2.4+** e **Spring Boot 4.1.1+**.

---

## Quando Usar

- O usuário solicita: "implemente o padrão Factory", "use Strategy aqui", "como estruturar um Builder", "como desacoplar via Observer".
- Desenho de arquitetura de classes e limites de módulos desacoplados.
- Refatoração de estruturas condicionais extensas (`if`/`else` ou `switch` legados) para polimorfismo seguro.
- Eliminação de acoplamento direto com código legado ou APIs externas via adaptadores.
- Composição dinâmica de comportamentos sem explosão combinatória de subclasses.
- Revisão de código para identificar sobre-engenharia (*Patternitis*) ou violações de princípios SOLID.

---

## Matriz GoF vs Idiomas Modernos da JVM

As linguagens modernas da JVM transformaram a forma como os padrões clássicos do GoF são implementados. Recursos nativos de linguagem substituem grande parte da cerimônia e código boilerplate original:

| Padrão GoF | Abordagem Clássica (Java 8-) | Idioma Java 25 LTS | Idioma Kotlin 2.4+ |
|---|---|---|---|
| **Builder** | Classe interna estática com métodos fluentes e cópia de campos | Fluent Builder imutável ou `record` com canonical constructor | Argumentos nomeados com valores default; DSL Builder com `@DslMarker` |
| **Factory Method** | Hierarquia de classes criadoras abstratas e concretas | Static factories em `record`/interfaces com pattern matching `switch` | Companion object factory functions, top-level functions e SAM |
| **Singleton** | Instância estática com double-checked locking ou Enum | Spring `@Component` (DI) ou `enum` para lógica de negócio pura | Declaração nativa `object` (thread-safe, lazy na JVM) ou Spring Bean |
| **Strategy** | Interface com classes concretas implementando algoritmo | `sealed interface` com pattern matching ou `@FunctionalInterface` | First-class functions `(T) -> R`, `fun interface` ou `sealed class/interface` |
| **Observer** | Interface `Observer`/`Observable` legada manual | Spring `ApplicationEventPublisher` + `@EventListener` / `@TransactionalEventListener` | `Delegates.observable`, Spring Events idiomáticos ou Flow/Coroutines |
| **Template Method** | Superclasse abstrata com métodos hook protegidos | Classe abstrata com método template `final` e passos protegidos | Higher-Order Functions com trailing lambdas (composição sobre herança) |
| **Decorator** | Subclasses com delegação manual para instância encapsulada | Composição de interfaces com delegação explícita por construtor | Delegação de classes nativa via palavra-chave `by` (`class D(...) : I by delegate`) |
| **Adapter** | Wrapper clássico ou herança múltipla de interfaces | Wrapper clássico com injeção de dependência por construtor | Extension functions para mapeamento de dados ou object adapter via `by` |

---

## Como o SOLID Direciona os Design Patterns

Padrões de projeto não existem no vácuo; são soluções consagradas para violações dos princípios SOLID. Para um aprofundamento nos princípios fundamentais, consulte [solid-principles](../solid-principles/SKILL.md).

- **SRP (Single Responsibility Principle)**:
  - **Builder**: Separa a responsabilidade de construção e validação da representação dos dados de domínio.
  - **Strategy**: Isola cada algoritmo em sua própria unidade coesa, aliviando a classe de contexto de múltiplas razões para mudar.
  - **Observer**: Separa o processamento do caso de uso principal da execução de efeitos colaterais e notificações.
  - **Decorator**: Separa responsabilidades transversais (ex: métricas, auditoria, formatação) da lógica central.
- **OCP (Open/Closed Principle)**:
  - **Strategy**: Permite adicionar novos algoritmos criando novas classes ou lambdas sem alterar o contexto consumidor.
  - **Template Method**: Mantém o esqueleto do algoritmo fechado para modificação enquanto passos específicos estão abertos para extensão.
  - **Decorator**: Permite adicionar responsabilidades a um objeto em tempo de execução sem modificar seu código original.
- **LSP (Liskov Substitution Principle)**:
  - **Adapter**: Garante que o adaptador honre o contrato da interface alvo sem quebrar as expectativas do cliente.
  - **Strategy & Decorator**: Todas as variantes e decoradores compartilham a mesma abstração, sendo intercambiáveis com segurança.
- **ISP (Interface Segregation Principle)**:
  - **Adapter**: Expõe uma interface fina e focada no cliente, ocultando interfaces externas densas e poluídas.
- **DIP (Dependency Inversion Principle)**:
  - **Factory Method**: O cliente depende da abstração do produto, delegando a instanciação concreta ao mecanismo de fábrica.
  - **Strategy**: O contexto depende da interface abstrata da estratégia, recebendo-a via injeção de dependência.

---

## Regra Monetária Inviolável (Domínio Financeiro)

Em conformidade com os padrões de engenharia bancária e de meios de pagamento, **qualquer representação monetária deve seguir rigorosamente as regras abaixo**:

1. **Nunca use `double` ou `float`**: A representação binária IEEE 754 introduz erros cumulativos de arredondamento inaceitáveis para dinheiro (ex: `0.1 + 0.2 != 0.3`).
2. **Sempre use `BigDecimal` com escala explícita de 6 casas decimais e `RoundingMode.HALF_EVEN`**:
   - Chame `.setScale(6, RoundingMode.HALF_EVEN)` em cada operação aritmética (`add`, `subtract`, `multiply`, `divide`).
   - O arredondamento bancário (`HALF_EVEN`) minimiza o viés estatístico de acumulação de sobras em grandes volumes de transações.
3. **Proibido o uso de `MathContext` para controle de casas decimais**:
   - `MathContext(precision, RoundingMode)` controla **dígitos significativos totais**, não casas decimais. Aplicar `new MathContext(6, RoundingMode.HALF_EVEN)` em `2.000000 + 0.500000` arredonda para `2.50000` (5 casas decimais), truncando silenciosamente a precisão exigida.
4. **Encapsulamento em Tipo de Valor Imutável**:
   - Combine o valor e a moeda em um tipo de valor imutável com validação fail-fast no construtor.
5. **Concorrência Segura em Saldo**:
   - Entidades que persistem saldos sujeitos a concorrência devem utilizar controle de concorrência otimista (`@Version`) e retentativas com backoff e jitter na camada de serviço. Para detalhes, consulte [concurrency-java21-review](../concurrency-java21-review/SKILL.md).

### Implementação Canônica do Tipo `Money`

#### Java 25 (Record Imutável)

```java
package com.example.domain.money;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Currency;
import java.util.Objects;

public record Money(BigDecimal amount, Currency currency) {

    public static final int MONETARY_SCALE = 6;
    public static final RoundingMode FINANCIAL_ROUNDING = RoundingMode.HALF_EVEN;

    public Money {
        Objects.requireNonNull(amount, "amount must not be null");
        Objects.requireNonNull(currency, "currency must not be null");
        
        // Garante a escala fixa de 6 casas decimais com arredondamento bancário
        if (amount.scale() != MONETARY_SCALE) {
            amount = amount.setScale(MONETARY_SCALE, FINANCIAL_ROUNDING);
        }
        if (amount.signum() < 0) {
            throw new IllegalArgumentException("amount must not be negative: " + amount);
        }
    }

    public static Money of(String amount, String currencyCode) {
        return new Money(new BigDecimal(amount), Currency.getInstance(currencyCode));
    }

    public static Money zero(Currency currency) {
        return new Money(BigDecimal.ZERO.setScale(MONETARY_SCALE, FINANCIAL_ROUNDING), currency);
    }

    public Money add(Money other) {
        requireSameCurrency(other);
        BigDecimal newAmount = this.amount.add(other.amount).setScale(MONETARY_SCALE, FINANCIAL_ROUNDING);
        return new Money(newAmount, this.currency);
    }

    public Money subtract(Money other) {
        requireSameCurrency(other);
        BigDecimal newAmount = this.amount.subtract(other.amount).setScale(MONETARY_SCALE, FINANCIAL_ROUNDING);
        return new Money(newAmount, this.currency);
    }

    public Money multiply(BigDecimal factor) {
        Objects.requireNonNull(factor, "factor must not be null");
        BigDecimal newAmount = this.amount.multiply(factor).setScale(MONETARY_SCALE, FINANCIAL_ROUNDING);
        return new Money(newAmount, this.currency);
    }

    private void requireSameCurrency(Money other) {
        Objects.requireNonNull(other, "other money must not be null");
        if (!this.currency.equals(other.currency)) {
            throw new IllegalArgumentException(
                "Cannot operate across currencies: " + this.currency + " vs " + other.currency
            );
        }
    }
}
```

#### Kotlin 2.4+ (Data Class com Operadores Sobrecarregados)

```kotlin
package com.example.domain.money

import java.math.BigDecimal
import java.math.RoundingMode
import java.util.Currency

data class Money(
    val amount: BigDecimal,
    val currency: Currency
) : Comparable<Money> {

    init {
        require(amount.signum() >= 0) { "amount must not be negative: $amount" }
        require(amount.scale() == MONETARY_SCALE) {
            "amount scale must be exactly $MONETARY_SCALE, but was ${amount.scale()}"
        }
    }

    companion object {
        const val MONETARY_SCALE = 6
        val FINANCIAL_ROUNDING: RoundingMode = RoundingMode.HALF_EVEN

        fun of(amountStr: String, currencyCode: String): Money {
            val normalized = BigDecimal(amountStr).setScale(MONETARY_SCALE, FINANCIAL_ROUNDING)
            return Money(normalized, Currency.getInstance(currencyCode))
        }

        fun zero(currency: Currency): Money =
            Money(BigDecimal.ZERO.setScale(MONETARY_SCALE, FINANCIAL_ROUNDING), currency)
    }

    operator fun plus(other: Money): Money {
        requireSameCurrency(other)
        val newAmount = amount.add(other.amount).setScale(MONETARY_SCALE, FINANCIAL_ROUNDING)
        return Money(newAmount, currency)
    }

    operator fun minus(other: Money): Money {
        requireSameCurrency(other)
        val newAmount = amount.subtract(other.amount).setScale(MONETARY_SCALE, FINANCIAL_ROUNDING)
        return Money(newAmount, currency)
    }

    operator fun times(factor: BigDecimal): Money {
        val newAmount = amount.multiply(factor).setScale(MONETARY_SCALE, FINANCIAL_ROUNDING)
        return Money(newAmount, currency)
    }

    override fun compareTo(other: Money): Int {
        requireSameCurrency(other)
        return this.amount.compareTo(other.amount)
    }

    private fun requireSameCurrency(other: Money) {
        require(this.currency == other.currency) {
            "Cannot operate across currencies: ${this.currency} vs ${other.currency}"
        }
    }
}
```

---

## Padrões Criacionais

### 1. Builder

- **Princípio SOLID Promovido**: **SRP** (isola a lógica de validação e construção da representação de domínio) e **DIP** (o cliente não se acopla a construtores com muitos parâmetros).
- **Quando usar**: Construção de objetos com múltiplos campos opcionais, objetos compostos ou validações complexas consolidadas entre múltiplos campos. Para estruturas planas simples com parâmetros obrigatórios, prefira `record` com canonical constructor em Java ou `data class` em Kotlin.

#### Java 25 (Fluent Immutable Builder com Validação no `build()`)

```java
package com.example.patterns.builder;

import java.util.Objects;
import java.util.regex.Pattern;

public final class CustomerProfile {

    private static final Pattern EMAIL_PATTERN = Pattern.compile("^[^@]+@[^@]+\\.[^@]+$");

    private final String id;
    private final String fullName;
    private final String email;
    private final String phoneNumber;
    private final boolean marketingConsent;

    private CustomerProfile(Builder builder) {
        this.id = builder.id;
        this.fullName = builder.fullName;
        this.email = builder.email;
        this.phoneNumber = builder.phoneNumber;
        this.marketingConsent = builder.marketingConsent;
    }

    public static Builder builder(String id, String fullName, String email) {
        return new Builder(id, fullName, email);
    }

    public String id() { return id; }
    public String fullName() { return fullName; }
    public String email() { return email; }
    public String phoneNumber() { return phoneNumber; }
    public boolean marketingConsent() { return marketingConsent; }

    public static final class Builder {
        private final String id;
        private final String fullName;
        private final String email;
        private String phoneNumber = "";
        private boolean marketingConsent = false;

        private Builder(String id, String fullName, String email) {
            this.id = Objects.requireNonNull(id, "id must not be null");
            this.fullName = Objects.requireNonNull(fullName, "fullName must not be null");
            this.email = Objects.requireNonNull(email, "email must not be null");
        }

        public Builder phoneNumber(String phoneNumber) {
            this.phoneNumber = phoneNumber != null ? phoneNumber : "";
            return this;
        }

        public Builder marketingConsent(boolean consent) {
            this.marketingConsent = consent;
            return this;
        }

        public CustomerProfile build() {
            if (id.isBlank()) {
                throw new IllegalArgumentException("id must not be blank");
            }
            if (fullName.trim().length() < 2) {
                throw new IllegalArgumentException("fullName must have at least 2 characters");
            }
            if (!EMAIL_PATTERN.matcher(email).matches()) {
                throw new IllegalArgumentException("Invalid email format: " + email);
            }
            return new CustomerProfile(this);
        }
    }
}
```

#### Kotlin 2.4+ (Argumentos Nomeados vs DSL Builder com `@DslMarker`)

Para dados com parâmetros opcionais, Kotlin torna o padrão Builder clássico redundante através de **argumentos nomeados com valores padrão**:

```kotlin
// Abordagem direta para 90% dos casos de uso de dados
data class CustomerProfile(
    val id: String,
    val fullName: String,
    val email: String,
    val phoneNumber: String = "",
    val marketingConsent: Boolean = false
) {
    init {
        require(id.isNotBlank()) { "id must not be blank" }
        require(fullName.trim().length >= 2) { "fullName must have at least 2 characters" }
        require(email.contains("@")) { "Invalid email format: $email" }
    }
}

// Uso direto e limpo (sem necessidade de Builder GoF verboso)
val customer = CustomerProfile(
    id = "cust-101",
    fullName = "Maria Silva",
    email = "maria@example.com",
    marketingConsent = true
)
```

Quando se constrói uma **estrutura hierárquica aninhada complexa** (ex: montagem de pedido com itens, cupons e regras de entrega), utilizamos um **DSL Builder tipado** com `@DslMarker`:

```kotlin
package com.example.patterns.builder

import com.example.domain.money.Money

@DslMarker
annotation class OrderDsl

data class OrderItem(val sku: String, val quantity: Int, val unitPrice: Money)

data class Order(
    val customerId: String,
    val items: List<OrderItem>,
    val notes: String
)

@OrderDsl
class OrderItemBuilder {
    var sku: String = ""
    var quantity: Int = 1
    var unitPrice: Money = Money.of("0.000000", "BRL")

    fun build(): OrderItem {
        require(sku.isNotBlank()) { "sku must not be blank" }
        require(quantity > 0) { "quantity must be greater than zero" }
        return OrderItem(sku, quantity, unitPrice)
    }
}

@OrderDsl
class OrderBuilder {
    var customerId: String = ""
    var notes: String = ""
    private val items = mutableListOf<OrderItem>()

    fun item(block: OrderItemBuilder.() -> Unit) {
        items.add(OrderItemBuilder().apply(block).build())
    }

    fun build(): Order {
        require(customerId.isNotBlank()) { "customerId must not be blank" }
        require(items.isNotEmpty()) { "Order must contain at least one item" }
        return Order(customerId, items.toList(), notes)
    }
}

// Ponto de entrada fluente
fun order(block: OrderBuilder.() -> Unit): Order = OrderBuilder().apply(block).build()

// Uso da DSL hierárquica tipada
val newOrder = order {
    customerId = "cust-99"
    notes = "Entregar na recepção"
    item {
        sku = "PROD-A"
        quantity = 2
        unitPrice = Money.of("49.900000", "BRL")
    }
    item {
        sku = "PROD-B"
        quantity = 1
        unitPrice = Money.of("120.000000", "BRL")
    }
}
```

---

### 2. Factory Method

- **Princípio SOLID Promovido**: **DIP** (o cliente depende da interface abstrata ou sealed interface, nunca das classes concretas), **SRP** (centraliza o conhecimento de instanciação) e **OCP** (novos tipos de produto são adicionados sem alterar a interface pública).
- **Quando usar**: Criação polimórfica de objetos onde o tipo exato a ser instanciado depende de configurações, parâmetros ou regras de negócio.

#### Java 25 (Static Factories em `record`/`sealed interface` com Switch Pattern Matching)

```java
package com.example.patterns.factory;

import java.net.URI;
import java.util.Objects;

public sealed interface NotificationChannel permits EmailChannel, SmsChannel, PushChannel {
    void dispatch(String recipient, String message);
}

public record EmailChannel(String smtpHost, int port) implements NotificationChannel {
    @Override
    public void dispatch(String recipient, String message) {
        // Envio via cliente SMTP com timeout explícito
    }
}

public record SmsChannel(String providerApiKey, URI gatewayUri) implements NotificationChannel {
    @Override
    public void dispatch(String recipient, String message) {
        // Envio via gateway SMS com retentativa e backoff
    }
}

public record PushChannel(String firebaseAppId) implements NotificationChannel {
    @Override
    public void dispatch(String recipient, String message) {
        // Envio via serviço Push Notification
    }
}

// Configurações tipadas via Sealed Interface
public sealed interface ChannelConfig permits EmailConfig, SmsConfig, PushConfig {}
public record EmailConfig(String smtpHost, int port) implements ChannelConfig {}
public record SmsConfig(String providerApiKey, URI gatewayUri) implements ChannelConfig {}
public record PushConfig(String firebaseAppId) implements ChannelConfig {}

public final class NotificationChannelFactory {

    private NotificationChannelFactory() {}

    // Factory method com exaustividade garantida pelo compilador via Pattern Matching
    public static NotificationChannel create(ChannelConfig config) {
        Objects.requireNonNull(config, "config must not be null");
        return switch (config) {
            case EmailConfig(var host, var port) -> new EmailChannel(host, port);
            case SmsConfig(var key, var uri)     -> new SmsChannel(key, uri);
            case PushConfig(var appId)           -> new PushChannel(appId);
        };
    }
}
```

#### Kotlin 2.4+ (Companion Object Factory Functions e Top-Level Factories)

```kotlin
package com.example.patterns.factory

import java.net.URI

sealed interface NotificationChannel {
    fun dispatch(recipient: String, message: String)

    companion object {
        // Factory method idiomático no companion object
        fun create(config: ChannelConfig): NotificationChannel = when (config) {
            is ChannelConfig.Email -> EmailChannel(config.smtpHost, config.port)
            is ChannelConfig.Sms -> SmsChannel(config.providerApiKey, config.gatewayUri)
            is ChannelConfig.Push -> PushChannel(config.firebaseAppId)
        }
    }
}

sealed interface ChannelConfig {
    data class Email(val smtpHost: String, val port: Int) : ChannelConfig
    data class Sms(val providerApiKey: String, val gatewayUri: URI) : ChannelConfig
    data class Push(val firebaseAppId: String) : ChannelConfig
}

data class EmailChannel(val smtpHost: String, val port: Int) : NotificationChannel {
    override fun dispatch(recipient: String, message: String) { /* Envio via SMTP */ }
}

data class SmsChannel(val providerApiKey: String, val gatewayUri: URI) : NotificationChannel {
    override fun dispatch(recipient: String, message: String) { /* Envio via SMS Gateway */ }
}

data class PushChannel(val firebaseAppId: String) : NotificationChannel {
    override fun dispatch(recipient: String, message: String) { /* Envio via Push */ }
}
```

#### Integração no Spring Boot 4.1.1+ (Injeção de Mapa de Beans)

No Spring Boot, o Factory Method é frequentemente implementado por injeção automática de um mapa de componentes gerenciados (`Map<String, T>`):

```java
@Component
public class PaymentGatewayFactory {

    private final Map<String, PaymentGateway> gateways;

    public PaymentGatewayFactory(List<PaymentGateway> gatewayList) {
        this.gateways = gatewayList.stream()
            .collect(Collectors.toUnmodifiableMap(
                gw -> gw.getProviderName().toUpperCase(Locale.ROOT),
                Function.identity()
            ));
    }

    public PaymentGateway getGateway(String provider) {
        return Optional.ofNullable(gateways.get(provider.toUpperCase(Locale.ROOT)))
            .orElseThrow(() -> new IllegalArgumentException("Unknown payment provider: " + provider));
    }
}
```

Equivalente em Kotlin 2.4+:

```kotlin
@Component
class PaymentGatewayFactory(gatewayList: List<PaymentGateway>) {

    private val gateways: Map<String, PaymentGateway> =
        gatewayList.associateBy { it.providerName.uppercase() }

    fun getGateway(provider: String): PaymentGateway =
        gateways[provider.uppercase()]
            ?: throw IllegalArgumentException("Unknown payment provider: $provider")
}
```

---

### 3. Singleton

- **Princípio SOLID Promovido**: **SRP** (alerta: singletons clássicos facilmente acumulam responsabilidades e se tornam "God Objects". Use com parcimônia).
- **Quando usar**: Coordenação de acesso a recursos sem estado (ex: políticas de cálculo imutáveis) ou componentes de infraestrutura gerenciados pelo container IoC.
- **Atenção Crítica**: **Nunca** use singleton para encapsular conexões de banco de dados (`java.sql.Connection`) ou estados mutáveis compartilhados. Em ambientes com Java 25 Virtual Threads, singletons compartilhados com blocos `synchronized` causam *thread pinning* no carrier thread do Loom. Consulte [concurrency-java21-review](../concurrency-java21-review/SKILL.md).

#### Java 25 (Spring Managed Singleton vs Enum Thread-Safe)

```java
// ✅ Caso 1: Lógica de negócio imutável e sem estado -> Enum Singleton
public enum FinancialRoundingPolicy {
    INSTANCE;

    private static final int SCALE = 6;
    private static final RoundingMode ROUNDING = RoundingMode.HALF_EVEN;

    public BigDecimal apply(BigDecimal amount) {
        Objects.requireNonNull(amount, "amount must not be null");
        return amount.setScale(SCALE, ROUNDING);
    }
}

// ✅ Caso 2: Serviços com dependências e I/O -> Spring Managed Singleton Bean (padrão)
@Service
public class AccountBalanceQueryService {

    private final DataSource dataSource; // Pool HikariCP gerenciado, thread-safe

    public AccountBalanceQueryService(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    public Optional<Money> getBalance(String accountId) {
        // Obtém conexão temporária e fecha em try-with-resources
        try (Connection conn = dataSource.getConnection()) {
            // Consulta de saldo...
            return Optional.of(Money.of("1500.000000", "BRL"));
        } catch (SQLException e) {
            throw new PersistenceException("Failed to query account balance", e);
        }
    }
}
```

#### Kotlin 2.4+ (`object` Nativo da JVM vs Spring Component)

```kotlin
package com.example.patterns.singleton

import java.math.BigDecimal
import java.math.RoundingMode
import java.util.Objects

// ✅ Declaração nativa 'object': thread-safe, inicialização lazy garantida pelo ClassLoader da JVM
object FinancialPolicy {
    private const val SCALE = 6
    private val ROUNDING = RoundingMode.HALF_EVEN

    fun round(value: BigDecimal): BigDecimal {
        Objects.requireNonNull(value, "value must not be null")
        return value.setScale(SCALE, ROUNDING)
    }
}

// ✅ Para componentes de aplicação com injeção de dependências: Spring @Service
@Service
class AccountBalanceQueryService(private val dataSource: DataSource) {
    fun getBalance(accountId: String): Money? {
        dataSource.connection.use { conn ->
            // Leitura de saldo com liberação garantida da conexão
            return Money.of("1500.000000", "BRL")
        }
    }
}
```

---

## Padrões Comportamentais

### 4. Strategy

- **Princípio SOLID Promovido**: **OCP** (novos comportamentos são adicionados como novas estratégias sem tocar no código cliente) e **SRP** (cada algoritmo fica restrito à sua própria classe ou função).
- **Quando usar**: Seleção de algoritmos intercambiáveis em tempo de execução (métodos de pagamento, políticas de frete, estratégias de precificação/desconto).

#### Java 25 (`sealed interface` com Injeção de Contexto ou `@FunctionalInterface`)

Para regras com operações de rede, timeouts e idempotência, utilize `sealed interface` com registros dedicados. Para algoritmos de cálculo puros, use `@FunctionalInterface`:

```java
package com.example.patterns.strategy;

import com.example.domain.money.Money;
import java.time.Duration;
import java.util.Objects;

public record PaymentResult(boolean approved, String transactionId, String message) {}

// Contrato formal com suporte a idempotência e tolerância a falhas
public sealed interface PaymentStrategy permits PixPaymentStrategy, CreditCardPaymentStrategy {
    PaymentResult execute(Money amount, String idempotencyKey, Duration timeout);
}

public record PixPaymentStrategy(String pixKey, PixGatewayClient client) implements PaymentStrategy {
    @Override
    public PaymentResult execute(Money amount, String idempotencyKey, Duration timeout) {
        Objects.requireNonNull(amount, "amount must not be null");
        return client.chargePix(pixKey, amount, idempotencyKey, timeout);
    }
}

public record CreditCardPaymentStrategy(String cardToken, CardGatewayClient client) implements PaymentStrategy {
    @Override
    public PaymentResult execute(Money amount, String idempotencyKey, Duration timeout) {
        Objects.requireNonNull(amount, "amount must not be null");
        return client.chargeToken(cardToken, amount, idempotencyKey, timeout);
    }
}

// Classe de contexto consumidora
public class CheckoutService {

    public PaymentResult processPayment(PaymentStrategy strategy, Money total, String orderId) {
        Objects.requireNonNull(strategy, "strategy must not be null");
        String idempotencyKey = "order:" + orderId;
        Duration timeout = Duration.ofSeconds(5);
        return strategy.execute(total, idempotencyKey, timeout);
    }
}
```

#### Kotlin 2.4+ (First-Class Functions, `fun interface` e Sealed Hierarchies)

Em Kotlin, estratégias simples podem ser passadas como **funções de primeira classe**:

```kotlin
package com.example.patterns.strategy

import com.example.domain.money.Money
import java.math.BigDecimal
import java.time.Duration

// Abordagem 1: Estratégia pura como First-Class Function type alias
typealias DiscountPolicy = (Money) -> Money

val vipDiscount: DiscountPolicy = { original -> original * BigDecimal("0.850000") }
val regularDiscount: DiscountPolicy = { original -> original * BigDecimal("0.950000") }

class PricingCalculator {
    fun calculateFinalPrice(basePrice: Money, discount: DiscountPolicy): Money {
        return discount(basePrice)
    }
}

// Abordagem 2: Estratégias ricas com I/O modeladas com Sealed Interface
data class PaymentResult(val approved: Boolean, val transactionId: String)

sealed interface PaymentStrategy {
    fun execute(amount: Money, idempotencyKey: String, timeout: Duration): PaymentResult

    data class Pix(val pixKey: String, val client: PixGatewayClient) : PaymentStrategy {
        override fun execute(amount: Money, idempotencyKey: String, timeout: Duration): PaymentResult =
            client.chargePix(pixKey, amount, idempotencyKey, timeout)
    }

    data class Card(val cardToken: String, val client: CardGatewayClient) : PaymentStrategy {
        override fun execute(amount: Money, idempotencyKey: String, timeout: Duration): PaymentResult =
            client.chargeToken(cardToken, amount, idempotencyKey, timeout)
    }
}
```

---

### 5. Observer

- **Princípio SOLID Promovido**: **OCP** (novos observadores se conectam aos eventos sem alterar o publicador) e **SRP** (o fluxo principal não cuida do envio de emails, auditoria ou redução de estoque).
- **Quando usar**: Propagação de eventos de domínio e desacoplamento de efeitos colaterais pós-transação.

#### Java 25 (Spring Boot 4.1.1+ `ApplicationEventPublisher` e Transações)

Eventos de domínio devem ser publicados como `record` imutável. Para efeitos colaterais externos, use `@TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)` para evitar que falhas no listener causem rollback indevido da transação de negócio principal:

```java
package com.example.patterns.observer;

import com.example.domain.money.Money;
import org.slf4j.MDC;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;
import org.springframework.stereotype.Component;

// Evento imutável com correlação para observabilidade
public record OrderPlacedEvent(String orderId, Money total, String customerEmail, String correlationId) {}

@Service
public class OrderCheckoutService {

    private final ApplicationEventPublisher eventPublisher;

    public OrderCheckoutService(ApplicationEventPublisher eventPublisher) {
        this.eventPublisher = eventPublisher;
    }

    @Transactional
    public void completeOrder(String orderId, Money total, String email) {
        // 1. Persistir pedido na base de dados
        String correlationId = MDC.get("correlationId");
        
        // 2. Disparar evento desacoplado
        eventPublisher.publishEvent(new OrderPlacedEvent(orderId, total, email, correlationId));
    }
}

@Component
public class OrderNotificationListener {

    @Async
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onOrderPlacedAsync(OrderPlacedEvent event) {
        // Propaga MDC para a Virtual Thread de execução assíncrona
        try {
            if (event.correlationId() != null) {
                MDC.put("correlationId", event.correlationId());
            }
            // Envio de email de confirmação com tolerância a falhas
        } finally {
            MDC.clear();
        }
    }
}
```

#### Kotlin 2.4+ (`Delegates.observable` vs Spring Events)

Para observabilidade em memória de propriedades mutáveis de estado local, Kotlin oferece `Delegates.observable`:

```kotlin
package com.example.patterns.observer

import com.example.domain.money.Money
import kotlin.properties.Delegates

class Account(initialBalance: Money) {
    // Observer em nível de propriedade com delegação de atributos
    var balance: Money by Delegates.observable(initialBalance) { property, old, new ->
        println("Auditoria de saldo: ${property.name} alterado de $old para $new")
    }

    // Observer com capacidade de veto (interrupção de transição de estado inválida)
    var authorizedLimit: Money by Delegates.vetoable(initialBalance) { _, _, new ->
        new.amount.signum() >= 0 // Bloqueia atribuição de valores negativos
    }
}
```

Para eventos a nível de arquitetura de microsserviços e Spring Boot, Kotlin usa a infraestrutura de eventos do Spring de forma idiomática:

```kotlin
data class OrderPlacedEvent(
    val orderId: String,
    val total: Money,
    val customerEmail: String,
    val correlationId: String?
)

@Component
class OrderEventListener {

    @Async
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun handleOrderPlaced(event: OrderPlacedEvent) {
        // Efeito colateral seguro após commit
    }
}
```

---

### 6. Template Method

- **Princípio SOLID Promovido**: **OCP** (estrutura fixa com passos flexíveis) e **DIP** (inversão do controle de execução — *Hollywood Principle: "Don't call us, we'll call you"*).
- **Quando usar**: Processamentos com etapas fixas e ordenadas onde implementações específicas variam apenas detalhes de leitura, transformação ou persistência. Em linguagens modernas, **prefira composição via Higher-Order Functions sobre herança**.

#### Java 25 (Classe Abstrata com Método Template `final` e Hooks Protegidos)

```java
package com.example.patterns.templatemethod;

import java.time.Duration;

public abstract class FinancialReportPipeline {

    // Método template final: protege os invariantes do algoritmo contra sobrescrita indevida
    public final void executePipeline() {
        validateEnvironment();
        var rawData = extractRecords();
        var processedData = transform(rawData);
        persist(processedData);
        if (requiresAuditNotification()) {
            sendAuditNotice();
        }
    }

    private void validateEnvironment() {
        // Verificação obrigatória de segurança e integridade
    }

    protected abstract String extractRecords();
    protected abstract String transform(String rawData);
    protected abstract void persist(String processedData);

    // Método hook opcional com comportamento default
    protected boolean requiresAuditNotification() {
        return true;
    }

    protected void sendAuditNotice() {
        // Notificação de conformidade default
    }
}

public final class DailyBankingReportPipeline extends FinancialReportPipeline {
    @Override
    protected String extractRecords() { return "Extracted banking records"; }

    @Override
    protected String transform(String rawData) { return "Transformed: " + rawData; }

    @Override
    protected void persist(String processedData) { /* Salva em storage seguro */ }
}
```

#### Kotlin 2.4+ (Higher-Order Functions: Preferindo Composição sobre Herança)

Em Kotlin, o padrão Template Method é substituído com elegância por **funções de ordem superior inline com trailing lambdas**, eliminando acoplamento estrutural de subclasses:

```kotlin
package com.example.patterns.templatemethod

inline fun <T, R> runPipeline(
    pipelineName: String,
    extract: () -> T,
    transform: (T) -> R,
    persist: (R) -> Unit,
    auditNotice: ((R) -> Unit)? = null
): R {
    println("Iniciando pipeline: $pipelineName")
    val raw = extract()
    val processed = transform(raw)
    persist(processed)
    auditNotice?.invoke(processed)
    println("Pipeline $pipelineName concluído com sucesso")
    return processed
}

// Uso expressivo via trailing lambdas com composição limpa
fun executeDailyJob() {
    runPipeline(
        pipelineName = "DailyReconciliation",
        extract = { "raw-records-from-s3" },
        transform = { data -> "processed-$data" },
        persist = { result -> println("Gravando $result no Postgres") },
        auditNotice = { result -> println("Notificando canal de auditoria sobre $result") }
    )
}
```

---

## Padrões Estruturais

### 7. Decorator

- **Princípio SOLID Promovido**: **OCP** (adiciona comportamentos dinamicamente sem alterar a classe decorada) e **SRP** (divide responsabilidades auxiliares em decoradores atômicos e independentes).
- **Quando usar**: Adição de camadas transversais como medição de latência, cálculo de taxas adicionais em preços, caching ou auditoria de operações.

#### Java 25 (Composição de Interfaces com Delegação Explícita)

```java
package com.example.patterns.decorator;

import com.example.domain.money.Money;
import java.util.Objects;

public interface TransferService {
    Money calculateTotalFee(Money baseAmount);
}

public class StandardTransferService implements TransferService {
    @Override
    public Money calculateTotalFee(Money baseAmount) {
        Objects.requireNonNull(baseAmount, "baseAmount must not be null");
        return Money.zero(baseAmount.currency());
    }
}

// Decorador base abstrato
public abstract class TransferDecorator implements TransferService {
    protected final TransferService delegate;

    protected TransferDecorator(TransferService delegate) {
        this.delegate = Objects.requireNonNull(delegate, "delegate must not be null");
    }
}

public class InternationalTransferDecorator extends TransferDecorator {
    private final Money exchangeFee;

    public InternationalTransferDecorator(TransferService delegate, Money exchangeFee) {
        super(delegate);
        this.exchangeFee = Objects.requireNonNull(exchangeFee, "exchangeFee must not be null");
    }

    @Override
    public Money calculateTotalFee(Money baseAmount) {
        Money previousFees = delegate.calculateTotalFee(baseAmount);
        return previousFees.add(exchangeFee);
    }
}
```

#### Kotlin 2.4+ (Class Delegation Nativa via Palavra-Chave `by`)

Kotlin oferece suporte de primeira classe ao padrão Decorator através da delegação de classes com a keyword `by`. O compilador gera automaticamente todo o código de repasse para a instância delegada, permitindo que a classe decoradora sobrescreva apenas os métodos necessários:

```kotlin
package com.example.patterns.decorator

import com.example.domain.money.Money

interface TransferService {
    fun calculateTotalFee(baseAmount: Money): Money
    fun supportsCurrency(currencyCode: String): Boolean
}

class StandardTransferService : TransferService {
    override fun calculateTotalFee(baseAmount: Money): Money = Money.zero(baseAmount.currency)
    override fun supportsCurrency(currencyCode: String): Boolean = true
}

// Decorador nativo: 'by delegate' repassa supportsCurrency() automaticamente!
class InternationalTransferDecorator(
    private val delegate: TransferService,
    private val exchangeFee: Money
) : TransferService by delegate {

    override fun calculateTotalFee(baseAmount: Money): Money {
        val currentFee = delegate.calculateTotalFee(baseAmount)
        return currentFee + exchangeFee
    }
}

// Uso e composição elegante
val service: TransferService = InternationalTransferDecorator(
    delegate = StandardTransferService(),
    exchangeFee = Money.of("15.500000", "BRL")
)
```

---

### 8. Adapter

- **Princípio SOLID Promovido**: **LSP** (o adaptador se faz passar pela interface esperada pelo consumidor sem efeitos colaterais), **ISP** (oferece apenas os métodos relevantes para o cliente) e **DIP** (o consumidor depende da interface alvo desacoplada de fornecedores terceiros).
- **Quando usar**: Integração entre interfaces incompatíveis, adaptação de SDKs legados ou tradução de modelos de transporte (DTOs externos) para o modelo de domínio interno.

#### Java 25 (Wrapper Adapter Clássico com Injeção de Dependências)

```java
package com.example.patterns.adapter;

import com.example.domain.money.Money;
import java.util.Objects;

// Interface de domínio esperada pelo sistema
public interface PaymentProviderGateway {
    String processCharge(String accountId, Money amount);
}

// SDK ou biblioteca legada externa de terceiro
public class LegacyPaymentSdk {
    public int sendPayment(String acc, double rawValue, String curr) {
        // API antiga com tipos primitivos
        return 200; // Código de sucesso HTTP
    }
}

// Adaptador que isola o sistema da API legada
public class LegacySdkPaymentAdapter implements PaymentProviderGateway {

    private final LegacyPaymentSdk legacySdk;

    public LegacySdkPaymentAdapter(LegacyPaymentSdk legacySdk) {
        this.legacySdk = Objects.requireNonNull(legacySdk, "legacySdk must not be null");
    }

    @Override
    public String processCharge(String accountId, Money amount) {
        Objects.requireNonNull(accountId, "accountId must not be null");
        Objects.requireNonNull(amount, "amount must not be null");

        // Conversão controlada mantendo o domínio estritamente tipado
        double doubleValue = amount.amount().doubleValue();
        int status = legacySdk.sendPayment(accountId, doubleValue, amount.currency().getCurrencyCode());
        
        if (status != 200) {
            throw new IllegalStateException("Legacy gateway returned failure status: " + status);
        }
        return "SUCCESS_TX_" + System.currentTimeMillis();
    }
}
```

#### Kotlin 2.4+ (Extension Functions para Mapeamento e Object Adapter)

Em Kotlin, adaptações puramente estruturais de dados (como conversores de DTO para Domínio) são implementadas com **funções de extensão**:

```kotlin
package com.example.patterns.adapter

import com.example.domain.money.Money

data class LegacyCustomerPayload(
    val id_externo: String,
    val vl_saldo: String,
    val cd_moeda: String
)

data class DomainCustomer(
    val id: String,
    val balance: Money
)

// Extension function atua como um adaptador funcional de dados, limpo e sem classes intermediárias
fun LegacyCustomerPayload.toDomain(): DomainCustomer {
    return DomainCustomer(
        id = this.id_externo,
        balance = Money.of(this.vl_saldo, this.cd_moeda)
    )
}
```

Para adaptação de interfaces comportamentais, combinamos `by` com injeção:

```kotlin
interface ModernAuditLogger {
    fun logEvent(message: String)
}

class LegacySyslogService {
    fun writeSyslog(level: Int, payload: ByteArray) { /* ... */ }
}

class SyslogAdapter(private val legacySyslog: LegacySyslogService) : ModernAuditLogger {
    override fun logEvent(message: String) {
        legacySyslog.writeSyslog(level = 1, payload = message.toByteArray(Charsets.UTF_8))
    }
}
```

---

## Anti-Patterns e Cuidados ("Patternitis")

> [!WARNING]
> **Alerta de Patternitis (Sobre-engenharia)**: Não introduza padrões de projeto prematuramente. A arquitetura mais elegante é sempre a mais simples que atende aos requisitos atuais com clareza. Siga os princípios **KISS** (*Keep It Simple, Stupid*) e **YAGNI** (*You Aren't Gonna Need It*), documentados em [clean-code](../clean-code/SKILL.md).

| Anti-Pattern | Problema | Abordagem Recomendada |
|---|---|---|
| **Singleton Abuse** | Estado mutável global, dificuldade de testes unitários e acoplamento oculto | Injeção de dependências gerenciada pelo Spring Boot |
| **Singleton com `Connection` JDBC** | Conexão compartilhada corrompe estado em concorrência e quebra pools | Injetar `DataSource` com pool HikariCP; obter conexões sob demanda |
| **Factory Everywhere** | Criação de factories para classes que nunca terão variantes polimórficas | Uso direto do construtor ou `record` compacto se o tipo for único |
| **Deep Decorator Chains** | Dificuldade de rastreamento de stack traces e ordens de execução imprevisíveis | Limitar profundidade de decoradores; considerar pipeline explícito |
| **Strategy para Funções Triviais** | Criar classes de estratégia inteiras para uma simples linha de cálculo | Usar lambdas (`(T) -> R`) ou métodos puros estáticos |
| **Observer com Transação Mista** | Falha em listener secundário dispara rollback indevido no caso de uso | `@TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)` |
| **Thread Pinning com Virtual Threads** | Uso de `synchronized` em Singletons ou Decorators trava carrier threads | Substituir por `ReentrantLock` ou estruturas imutáveis e lock-free |
| **`MathContext` em Dinheiro** | Limita algarismos significativos e quebra casas decimais silenciosamente | `BigDecimal.setScale(6, RoundingMode.HALF_EVEN)` em toda operação |

Para orientações detalhadas sobre concorrência segura com Virtual Threads e prevenção de bloqueios na JVM, consulte [concurrency-java21-review](../concurrency-java21-review/SKILL.md).

---

## Habilidades Relacionadas

- [solid-principles](../solid-principles/SKILL.md) — Princípios de design orientado a objetos que os padrões materializam.
- [clean-code](../clean-code/SKILL.md) — Boas práticas de legibilidade, funções limpas e prevenção de sobre-engenharia.
- [concurrency-java21-review](../concurrency-java21-review/SKILL.md) — Concorrência segura, Virtual Threads (Project Loom) e prevenção de thread pinning em padrões de projeto.
