---
name: design-patterns
description: Common design patterns with Java 25 examples (Factory, Builder, Strategy, Observer, Decorator, etc.). Use when user asks "implement pattern", "use factory", "strategy pattern", or when designing extensible components.
---

# Design Patterns Skill

Practical design patterns reference for Java 25 and Spring Boot >= 4.0.5.

## When to Use

- User asks to implement a specific pattern
- Designing extensible/flexible components
- Refactoring rigid code structures
- Code review suggests pattern usage

---

## Quick Reference: When to Use What

| Problem                                 | Pattern             |
|-----------------------------------------|---------------------|
| Complex object construction             | **Builder**         |
| Create objects without specifying class | **Factory**         |
| Multiple algorithms, swap at runtime    | **Strategy**        |
| Add behavior without changing class     | **Decorator**       |
| Notify multiple objects of changes      | **Observer**        |
| Ensure single instance                  | **Singleton**       |
| Convert incompatible interfaces         | **Adapter**         |
| Define algorithm skeleton               | **Template Method** |

---

## How SOLID Drives Design Patterns

Design patterns are concrete, time-tested templates used to resolve violations of SOLID principles. When designing your
application structure, map SOLID violations to the appropriate patterns:

- **SRP (Single Responsibility)**: When a class has multiple reasons to change (e.g., orchestrating flow + processing
  data), use **Strategy** (encapsulating algorithms), **Observer** (decoupling event handling), or **Decorator**
  (separating cross-cutting concerns).
- **OCP (Open/Closed)**: Instead of modifying classes using long `if`/`switch` blocks for new types, use **Strategy**
  (pluggable behaviors via `sealed interface`), **Template Method** (extensible steps), or **Abstract Factory**
  (extensible object families).
- **LSP (Liskov Substitution)**: To prevent inheritance issues (like throwing `UnsupportedOperationException` in
  subclasses), favor **Composition over Inheritance** or use the **Adapter** pattern to map incompatible models cleanly.
- **ISP (Interface Segregation)**: Rather than exposing a fat interface to clients, use the **Adapter** pattern to
  present a thin, segregated interface specialized for that client's role.
- **DIP (Dependency Inversion)**: To avoid hardcoding concrete dependencies with `new`, delegate object construction to
  **Factory Method**, **Abstract Factory**, or **Builder**, and inject them via constructor Dependency Injection.

---

## Monetary Values: Mandatory Rule

Every example in this skill that touches money follows one rule without exception: use `BigDecimal` with an explicit
`RoundingMode` and a fixed **scale of 6 decimal places**, via `setScale(6, RoundingMode.HALF_EVEN)`.

Do **not** use `MathContext(precision, RoundingMode)` for monetary arithmetic. `MathContext` controls **significant
digits**, not decimal places — `new MathContext(6, RoundingMode.HALF_EVEN)` on `2.000000` can silently truncate to
`2.50000` (5 decimals) instead of the required 6, which is a real precision bug, not a style preference. Always call
`.setScale(6, RoundingMode.HALF_EVEN)` after each arithmetic operation (`add`, `subtract`, `multiply`, `divide`)
instead.

```java
// ❌ WRONG — MathContext controls significant digits, not decimal places.
// 2.000000 + 0.500000 with MathContext(6, HALF_EVEN) rounds to 2.50000 (5 decimals),
// silently violating the 6-decimal-place rule.
BigDecimal wrong = coffee.cost().add(MILK_PRICE, new MathContext(6, RoundingMode.HALF_EVEN));

// ✅ CORRECT — explicit scale, always 6 decimal places, no ambiguity.
BigDecimal correct = coffee.cost().add(MILK_PRICE).setScale(6, RoundingMode.HALF_EVEN);
```

Additionally, encapsulate every monetary value in an immutable `record` combining `BigDecimal` and `Currency`, with
fail-fast validation in the canonical constructor:

```java
public record Money(BigDecimal amount, Currency currency) {

    public Money {
        Objects.requireNonNull(amount, "amount must not be null");
        Objects.requireNonNull(currency, "currency must not be null");
        if (amount.scale() != 6) {
            amount = amount.setScale(6, RoundingMode.HALF_EVEN);
        }
        if (amount.signum() < 0) {
            throw new IllegalArgumentException("amount must not be negative: " + amount);
        }
    }

    public Money add(Money other) {
        requireSameCurrency(other);
        return new Money(amount.add(other.amount).setScale(6, RoundingMode.HALF_EVEN), currency);
    }

    private void requireSameCurrency(Money other) {
        if (!currency.equals(other.currency)) {
            throw new IllegalArgumentException(
                    "Cannot combine different currencies: " + currency + " vs " + other.currency);
        }
    }
}
```

    When a `Money`-typed field represents persisted account/order balance and is subject to concurrent updates, add `@Version` on the owning entity and handle `OptimisticLockException` with a bounded retry (e.g., Resilience4j `Retry` with backoff + jitter) at the service layer — never at the repository/adapter layer.

---

## Creational Patterns

### Builder

**Use when:** Object has many parameters, some optional.

```java
// ❌ Telescoping constructor antipattern
public class User {
    public User(String name) {
    }

    public User(String name, String email) {
    }

    public User(String name, String email, int age) {
    }

    public User(String name, String email, int age, String phone) {
    }
    // ... explosion of constructors
}

// ✅ Builder pattern (immutable result)
public final class User {
    private final String name;      // required
    private final String email;     // required
    private final int age;          // optional
    private final String phone;     // optional
    private final String address;   // optional

    private User(Builder builder) {
        this.name = builder.name;
        this.email = builder.email;
        this.age = builder.age;
        this.phone = builder.phone;
        this.address = builder.address;
    }

    public static Builder builder(String name, String email) {
        return new Builder(name, email);
    }

    public static class Builder {
        private final String name;
        private final String email;
        private int age = 0;
        private String phone = "";
        private String address = "";

        private Builder(String name, String email) {
            this.name = Objects.requireNonNull(name, "name must not be null");
            this.email = Objects.requireNonNull(email, "email must not be null");
        }

        public Builder age(int age) {
            if (age < 0) {
                throw new IllegalArgumentException("age must not be negative: " + age);
            }
            this.age = age;
            return this;
        }

        public Builder phone(String phone) {
            this.phone = phone;
            return this;
        }

        public Builder address(String address) {
            this.address = address;
            return this;
        }

        public User build() {
            return new User(this);
        }
    }
}

// Usage
User user = User.builder("John", "john@example.com")
        .age(30)
        .phone("+1234567890")
        .build();
```

> For plain data holders with only required fields, prefer a `record` with a validating canonical constructor instead of
> a full Builder — introduce the Builder only when there are genuinely optional fields or multi-step construction. Avoid
> Lombok's `@Builder`: it hides the canonical constructor and encourages skipping fail-fast validation, which conflicts
> with the immutability and validation rules for domain objects.

---

### Factory Method

**Use when:** Need to create objects without specifying the exact class.

```java
// ✅ Java 25: Factory Method using Sealed Types + Pattern Matching for switch
public sealed interface NotificationConfig permits EmailConfig, SmsConfig, PushConfig {
}

public record EmailConfig(String address) implements NotificationConfig {
}

public record SmsConfig(String phoneNumber) implements NotificationConfig {
}

public record PushConfig(String deviceToken) implements NotificationConfig {
}

public interface Notification {
    void send(String message);
}

public class EmailNotification implements Notification {
    private final String address;

    public EmailNotification(String address) {
        this.address = address;
    }

    @Override
    public void send(String message) { /* deliver via email provider */ }
}

public class SmsNotification implements Notification {
    private final String phoneNumber;

    public SmsNotification(String phoneNumber) {
        this.phoneNumber = phoneNumber;
    }

    @Override
    public void send(String message) { /* deliver via SMS gateway */ }
}

public class PushNotification implements Notification {
    private final String deviceToken;

    public PushNotification(String deviceToken) {
        this.deviceToken = deviceToken;
    }

    @Override
    public void send(String message) { /* deliver via push provider */ }
}

public class NotificationFactory {
    public static Notification create(NotificationConfig config) {
        return switch (config) {
            case EmailConfig ec -> new EmailNotification(ec.address());
            case SmsConfig sc -> new SmsNotification(sc.phoneNumber());
            case PushConfig pc -> new PushNotification(pc.deviceToken());
        }; // Exhaustiveness is compiler-enforced, no 'default' needed
    }
}

// Usage
Notification notification = NotificationFactory.create(new EmailConfig("user@example.com"));
notification.

send("Hello!");
```

> Modeling the factory input as a `sealed interface` instead of a raw `String` type tag removes an entire class of
> runtime `IllegalArgumentException` — invalid configurations become unrepresentable at compile time, which is strictly
> better than the old `String`-switch factory.

**With Spring Boot >= 4.0.5 (preferred for DI-managed senders):**

```java
public interface NotificationSender {
    void send(String message);

    String getType();
}

@Component
public class EmailSender implements NotificationSender {
    @Override
    public void send(String message) { /* ... */ }

    @Override
    public String getType() {
        return "EMAIL";
    }
}

@Component
public class SmsSender implements NotificationSender {
    @Override
    public void send(String message) { /* ... */ }

    @Override
    public String getType() {
        return "SMS";
    }
}

@Component
public class NotificationFactory {
    private final Map<String, NotificationSender> senders;

    public NotificationFactory(List<NotificationSender> senderList) {
        this.senders = senderList.stream()
                .collect(Collectors.toMap(
                        NotificationSender::getType,
                        Function.identity()
                ));
    }

    public NotificationSender getSender(String type) {
        return Optional.ofNullable(senders.get(type))
                .orElseThrow(() -> new IllegalArgumentException("Unknown: " + type));
    }
}
```

> If `NotificationSender` implementations call an external gateway (SMTP, SMS provider, push service), wrap that I/O
> with an explicit timeout and a resilience policy (Resilience4j retry with backoff + jitter, circuit breaker). Never
> let
> the raw network/client exception leak past the adapter — map it to an integration-specific error type first.

---

### Singleton

**Use when:** Exactly one instance is needed (use sparingly!). Prefer Spring-managed singletons; avoid hand-rolled
singletons for anything that wraps I/O resources.

```java
// ✅ Acceptable use: enum-based singleton for stateless, side-effect-free logic
// (e.g., a currency-rounding policy or a stateless ID generator strategy)
public enum RoundingPolicy {
    FINANCIAL_DEFAULT;

    public BigDecimal apply(BigDecimal value) {
        return value.setScale(6, RoundingMode.HALF_EVEN);
    }
}
```

```java
// ❌ AVOID: enum-based singleton wrapping a single JDBC Connection.
// java.sql.Connection is not thread-safe. Sharing one instance across
// virtual threads causes corrupted state, lost updates, and defeats
// connection pooling, retry, and failover entirely.
public enum DatabaseConnection {
    INSTANCE;

    private Connection connection; // never do this

    public Connection getConnection() {
        return connection;
    }
}
```

**With Spring Boot >= 4.0.5 (preferred):**

```java
// Let Spring manage the DataSource lifecycle and pooling (HikariCP).
// Never hold a single shared Connection — always borrow one per operation
// via the DataSource or, more commonly, via Spring Data/JdbcClient.
@Component
public class OrderJdbcRepository {
    private final DataSource dataSource; // pooled, thread-safe to share

    public OrderJdbcRepository(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    public Optional<Order> findById(Long id) {
        try (Connection connection = dataSource.getConnection()) {
            // short-lived, per-call connection borrowed from the pool
            // ... query logic ...
            return Optional.empty();
        } catch (SQLException e) {
            throw new OrderPersistenceException("Failed to load order " + id, e);
        }
    }
}
```

**Warning:** Singletons can be problematic:

- Hard to test (global state)
- Hidden dependencies
- Never appropriate for non-thread-safe resources (JDBC `Connection`, `SimpleDateFormat`, mutable `Map`)
- Consider dependency injection instead

---

## Behavioral Patterns

### Strategy

**Use when:** Multiple algorithms for the same operation, need to swap at runtime.

```java
// Gateway contract: every implementation must enforce an explicit timeout
// and accept an idempotency key derived from the order/transaction id,
// so retries never trigger a duplicate charge.
public interface PaymentGatewayClient {
    PaymentResult chargeCard(String cardToken, BigDecimal amount, String idempotencyKey, Duration timeout);

    PaymentResult chargeWallet(String walletToken, BigDecimal amount, String idempotencyKey, Duration timeout);

    PaymentResult chargeCrypto(String walletAddress, BigDecimal amount, String idempotencyKey, Duration timeout);
}

public record PaymentResult(boolean success, String reference) {
}

// ✅ Strategy pattern — monetary rule: BigDecimal with explicit scale(6) and RoundingMode.
// Sensitive identifiers (card token, wallet email) are never raw PAN/PII:
// they are opaque tokens issued by the gateway/vault, safe to hold in a record.
public sealed interface PaymentStrategy permits CreditCardPayment, PayPalPayment, CryptoPayment {
    PaymentResult pay(BigDecimal amount, String idempotencyKey);
}

public record CreditCardPayment(String cardToken, PaymentGatewayClient gatewayClient) implements PaymentStrategy {
    private static final Duration GATEWAY_TIMEOUT = Duration.ofSeconds(5);

    @Override
    public PaymentResult pay(BigDecimal amount, String idempotencyKey) {
        BigDecimal normalized = amount.setScale(6, RoundingMode.HALF_EVEN);
        return gatewayClient.chargeCard(cardToken, normalized, idempotencyKey, GATEWAY_TIMEOUT);
    }

    // Never log or print cardToken's underlying PAN. If this record is logged
    // as-is, only the opaque token (not the real card number) is exposed —
    // the token must be non-reversible outside the payment provider's vault.
}

public record PayPalPayment(String walletToken, PaymentGatewayClient gatewayClient) implements PaymentStrategy {
    private static final Duration GATEWAY_TIMEOUT = Duration.ofSeconds(5);

    @Override
    public PaymentResult pay(BigDecimal amount, String idempotencyKey) {
        BigDecimal normalized = amount.setScale(6, RoundingMode.HALF_EVEN);
        return gatewayClient.chargeWallet(walletToken, normalized, idempotencyKey, GATEWAY_TIMEOUT);
    }
}

public record CryptoPayment(String walletAddress, PaymentGatewayClient gatewayClient) implements PaymentStrategy {
    private static final Duration GATEWAY_TIMEOUT = Duration.ofSeconds(5);

    @Override
    public PaymentResult pay(BigDecimal amount, String idempotencyKey) {
        BigDecimal normalized = amount.setScale(6, RoundingMode.HALF_EVEN);
        return gatewayClient.chargeCrypto(walletAddress, normalized, idempotencyKey, GATEWAY_TIMEOUT);
    }
}

// Context
public class ShoppingCart {
    private PaymentStrategy paymentStrategy;

    public void setPaymentStrategy(PaymentStrategy strategy) {
        this.paymentStrategy = strategy;
    }

    public PaymentResult checkout(BigDecimal total, String orderId) {
        // idempotencyKey is derived from a stable business id (the order),
        // never generated fresh per call — otherwise retries would not be idempotent.
        return paymentStrategy.pay(total, "order:" + orderId);
    }
}
```

> `chargeCard`/`chargeWallet`/`chargeCrypto` must be implemented with a Resilience4j retry (backoff + jitter) and
> circuit breaker around the actual HTTP/gRPC call to the payment provider, respecting the `timeout` parameter. A wallet
> address for crypto is not itself secret (it's meant to be public), but a card token and a PayPal wallet token are
> sensitive — even though they are not raw PAN, treat them as confidential and exclude them from `toString()`-based
> logging by never logging the full record; log only `reference` from `PaymentResult` and a masked identifier if
> traceability is required. Never model `PaymentStrategy` as a plain `@FunctionalInterface` lambda for real payment
> flows:
> doing so hides where the idempotency key, timeout, and gateway client are wired, and makes it easy to skip error
> handling in the chain.

---

### Observer

**Use when:** Objects need to be notified of changes in another object.

```java
// ✅ Observer pattern (interface-based, no framework)
// Each observer's failure is isolated so one broken observer does not
// prevent the others from running or propagate back into placeOrder.
public interface OrderObserver {
    void onOrderPlaced(Order order);
}

public class OrderService {
    private static final Logger log = LoggerFactory.getLogger(OrderService.class);
    private final List<OrderObserver> observers = new ArrayList<>();

    public void addObserver(OrderObserver observer) {
        observers.add(observer);
    }

    public void placeOrder(Order order) {
        saveOrder(order);
        for (OrderObserver observer : observers) {
            try {
                observer.onOrderPlaced(order);
            } catch (RuntimeException e) {
                log.error("Observer {} failed for order {}", observer.getClass(), order.id(), e);
            }
        }
    }
}
```

**With Spring Events (preferred, Spring Boot >= 4.0.5):**

```java
// Event — immutable record carrying the full state needed by listeners
public record OrderPlacedEvent(Order order, String correlationId) {
}

// Publisher
@Service
public class OrderService {
    private final ApplicationEventPublisher eventPublisher;

    public OrderService(ApplicationEventPublisher eventPublisher) {
        this.eventPublisher = eventPublisher;
    }

    @Transactional
    public void placeOrder(Order order) {
        saveOrder(order);
        String correlationId = MDC.get("correlationId");
        eventPublisher.publishEvent(new OrderPlacedEvent(order, correlationId));
    }
}

// Listeners (observers)
@Component
public class InventoryListener {

    // Runs only AFTER the placeOrder transaction commits successfully.
    // A plain @EventListener here would execute inside the same transaction
    // as placeOrder, so a failure in stock reduction could roll back the
    // entire order — rarely the intended behavior for a side effect.
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void handleOrderPlaced(OrderPlacedEvent event) {
        // Reduce inventory in its own transactional boundary.
        // If this fails, compensate (e.g., publish a StockReductionFailedEvent)
        // instead of relying on the original order transaction to roll back.
    }
}

@Component
public class EmailListener {

    @Async
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void handleOrderPlacedAsync(OrderPlacedEvent event) {
        // Runs on a different virtual thread than the publisher; MDC is
        // ThreadLocal-based and does not cross the async boundary automatically.
        // Set it explicitly from the event's correlationId and always clear it
        // in a finally block to avoid leaking state into a reused platform thread.
        try {
            MDC.put("correlationId", event.correlationId());
            sendConfirmationEmail(event.order().customerEmail(), event.order());
        } finally {
            MDC.clear();
        }
    }
}
```

> `@Async` methods run on a different thread than the publisher; any unhandled exception inside them is swallowed by
> default unless an `AsyncUncaughtExceptionHandler` is configured. Combining `@Async` with
> `@TransactionalEventListener(phase = AFTER_COMMIT)` decouples both the transactional boundary and the thread from the
> original request — treat each listener as its own unit of failure and add compensation logic where the side effect is
> not idempotent by nature.

---

### Template Method

**Use when:** Define an algorithm skeleton, let subclasses fill in the steps.

```java
// ✅ Template Method pattern
public abstract class DataProcessor {

    public final void process() {
        readData();
        processData();
        writeData();
        if (shouldNotify()) {
            notifyCompletion();
        }
    }

    protected abstract void readData();

    protected abstract void processData();

    protected abstract void writeData();

    protected boolean shouldNotify() {
        return true;
    }

    protected void notifyCompletion() {
        // default notification logic
    }
}

public class CsvDataProcessor extends DataProcessor {
    @Override
    protected void readData() { /* read CSV file with try-with-resources */ }

    @Override
    protected void processData() { /* transform rows */ }

    @Override
    protected void writeData() { /* persist to database */ }
}

public class ApiDataProcessor extends DataProcessor {
    @Override
    protected void readData() { /* fetch from external API with explicit timeout */ }

    @Override
    protected void processData() { /* transform API response */ }

    @Override
    protected void writeData() { /* write to cache */ }

    @Override
    protected boolean shouldNotify() {
        return false;
    }
}
```

> `ApiDataProcessor.readData()` performs external I/O. Any HTTP client call there must declare an explicit connect/read
> timeout and handle failure (`try`/`catch` or `.exceptionally()` if async) — never let a hanging external call block
> the
> whole template pipeline indefinitely.

---

## Structural Patterns

### Decorator

**Use when:** Add behavior dynamically without modifying existing classes.

```java
// ✅ Decorator pattern — monetary rule: setScale(6, RoundingMode.HALF_EVEN) on every
// BigDecimal operation. Do NOT use MathContext here: MathContext bounds significant
// digits, not decimal places, and would silently break the fixed 6-decimal-place rule.
public interface Coffee {
    String description();

    BigDecimal cost();
}

public record SimpleCoffee() implements Coffee {
    @Override
    public String description() {
        return "Coffee";
    }

    @Override
    public BigDecimal cost() {
        return new BigDecimal("2.000000");
    }
}

public abstract class CoffeeDecorator implements Coffee {
    protected final Coffee coffee;

    protected CoffeeDecorator(Coffee coffee) {
        this.coffee = coffee;
    }
}

public class MilkDecorator extends CoffeeDecorator {
    private static final BigDecimal MILK_PRICE = new BigDecimal("0.500000");

    public MilkDecorator(Coffee coffee) {
        super(coffee);
    }

    @Override
    public String description() {
        return coffee.description() + ", Milk";
    }

    @Override
    public BigDecimal cost() {
        return coffee.cost().add(MILK_PRICE).setScale(6, RoundingMode.HALF_EVEN);
    }
}

public class SugarDecorator extends CoffeeDecorator {
    private static final BigDecimal SUGAR_PRICE = new BigDecimal("0.200000");

    public SugarDecorator(Coffee coffee) {
        super(coffee);
    }

    @Override
    public String description() {
        return coffee.description() + ", Sugar";
    }

    @Override
    public BigDecimal cost() {
        return coffee.cost().add(SUGAR_PRICE).setScale(6, RoundingMode.HALF_EVEN);
    }
}

// Usage - compose decorators
Coffee coffee = new SugarDecorator(new MilkDecorator(new SimpleCoffee()));
String description = coffee.description(); // "Coffee, Milk, Sugar"
BigDecimal cost = coffee.cost();            // 2.700000
```

**Java I/O uses Decorator:**

```java
// Classic example from the JDK — always close with try-with-resources
try(BufferedReader reader = new BufferedReader(
        new InputStreamReader(
                new FileInputStream("file.txt")))){
        // read lines
        }
```

---

### Adapter

**Use when:** Make incompatible interfaces work together.

```java
// ✅ Adapter pattern

public interface MediaPlayer {
    void play(String filename);
}

public class LegacyAudioPlayer {
    public void playMp3(String filename) { /* ... */ }
}

public class AdvancedVideoPlayer {
    public void playMp4(String filename) { /* ... */ }

    public void playAvi(String filename) { /* ... */ }
}

public class Mp3PlayerAdapter implements MediaPlayer {
    private final LegacyAudioPlayer legacyPlayer;

    public Mp3PlayerAdapter(LegacyAudioPlayer legacyPlayer) {
        this.legacyPlayer = legacyPlayer;
    }

    @Override
    public void play(String filename) {
        legacyPlayer.playMp3(filename);
    }
}

public class VideoPlayerAdapter implements MediaPlayer {
    private final AdvancedVideoPlayer videoPlayer;

    public VideoPlayerAdapter(AdvancedVideoPlayer videoPlayer) {
        this.videoPlayer = videoPlayer;
    }

    @Override
    public void play(String filename) {
        if (filename.endsWith(".mp4")) {
            videoPlayer.playMp4(filename);
        } else if (filename.endsWith(".avi")) {
            videoPlayer.playAvi(filename);
        }
    }
}
```

> Dependencies are injected via constructor rather than instantiated with `new` inside the adapter — this keeps the
> adapter testable and follows DIP even for legacy integrations.

---

## Pattern Selection Guide

| Situation                                | Consider                                           |
|------------------------------------------|----------------------------------------------------|
| Object creation is complex               | Builder, Factory                                   |
| Need to add features dynamically         | Decorator                                          |
| Multiple implementations of an algorithm | Strategy                                           |
| React to state changes                   | Observer                                           |
| Integrate with legacy code               | Adapter                                            |
| Common algorithm, varying steps          | Template Method                                    |
| Need a single instance                   | Singleton (use sparingly, never for I/O resources) |

---

## Anti-Patterns to Avoid

| Anti-Pattern                                              | Problem                                                                                         | Better Approach                                                                           |
|-----------------------------------------------------------|-------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------|
| Singleton abuse                                           | Global state, hard to test                                                                      | Dependency Injection                                                                      |
| Singleton wrapping a JDBC `Connection`                    | Not thread-safe, defeats pooling/retry/failover                                                 | Inject a pooled `DataSource` (HikariCP)                                                   |
| Factory everywhere                                        | Over-engineering                                                                                | Simple `new` if the type is known                                                         |
| Deep decorator chains                                     | Hard to debug                                                                                   | Keep chains short, consider composition                                                   |
| Observer with many events                                 | Spaghetti notifications                                                                         | Event bus, clear event hierarchy                                                          |
| `@EventListener` for side effects on the same transaction | A side-effect failure rolls back the main use case                                              | `@TransactionalEventListener(phase = AFTER_COMMIT)`                                       |
| Functional-interface Strategy for money/I/O flows         | Hides timeout, idempotency, and error-handling wiring                                           | Explicit `sealed interface` implementations with injected clients                         |
| Raw PAN/secrets as record fields                          | Leaks via default `toString()`/logs                                                             | Store opaque provider tokens only, mask before logging                                    |
| `MathContext(precision, RoundingMode)` for money          | Bounds significant digits, not decimal places — silently truncates the required 6-decimal scale | `BigDecimal.setScale(6, RoundingMode.HALF_EVEN)` after every arithmetic operation         |
| No `@Version` on entities holding balance/financial state | Concurrent updates cause lost updates (last write wins)                                         | Optimistic Locking (`@Version`) with `OptimisticLockException` retry at the service layer |

---

## Related Skills

- `solid-principles` - Design principles that patterns help implement
- `clean-code` - Code-level best practices
- `java-code-review` - Systematic code review for Java
