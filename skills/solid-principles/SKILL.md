---
name: solid-principles
description: SOLID principles checklist with Java 25 and Kotlin examples. Use when reviewing classes, refactoring code, or when user asks about Single Responsibility, Open/Closed, Liskov, Interface Segregation, or Dependency Inversion.
---

# SOLID Principles Skill

Review and application of SOLID principles in Java 25 and Kotlin, focusing on financial rigor, immutability, and safe concurrency
where applicable.

## When to Use

- User mentions "check SOLID" / "SOLID review" / "does this class do too much?"
- Class design review
- Refactoring large classes
- Design-focused code review

---

## Quick Reference

| Letter | Principle             | Summary                                              |
|--------|-----------------------|------------------------------------------------------|
| **S**  | Single Responsibility | A class = one reason to change                       |
| **O**  | Open/Closed           | Open for extension, closed for modification          |
| **L**  | Liskov Substitution   | Subtypes must be substitutable for their base types  |
| **I**  | Interface Segregation | Many specific interfaces > one general interface     |
| **D**  | Dependency Inversion  | Depend on abstractions, not concrete implementations |

In Java 25, `record`, `sealed interface`, and `pattern matching` typically simplify OCP and LSP implementation,
eliminating dispatch based on `String`/`instanceof` without introducing unnecessary inheritance.

---

## SOLID in Practice

- **S (Single Responsibility)**: Each class/method should have only one reason to change. Separate validation,
  persistence, and HTTP mapping into distinct components.
- **O (Open/Closed)**: Extend behavior using new classes, composition, or `sealed interface` + pattern matching, never
  by modifying existing code. Avoid `if`/`switch` chains based on `String`.
- **L (Liskov Substitution)**: Subtypes must be fully substitutable for their base type. Never override a method to
  throw `UnsupportedOperationException` or do nothing — this violates the parent type's contract.
- **I (Interface Segregation)**: Prefer small, role-specific interfaces (`role interfaces`) over large, generic ones. A
  client should never depend on methods it does not use.
- **D (Dependency Inversion)**: Depend on abstractions (interfaces), never on concrete implementations. Inject
  dependencies via constructors; never instantiate with `new` outside of factories, configurations, or DI containers.

---

## S - Single Responsibility Principle (SRP)

> "A class should have only one reason to change."

### Violation

```java
// ❌ BAD: UserService does too much
public class UserService {

    public User createUser(String name, String email) {
        // validation
        if (email == null || !email.contains("@")) {
            throw new IllegalArgumentException("Invalid email");
        }

        // persistence
        User user = new User(name, email);
        entityManager.persist(user);

        // notification
        String subject = "Welcome!";
        String body = "Hello " + name;
        emailClient.send(email, subject, body);

        // audit
        auditLog.log("User created: " + email);

        return user;
    }
}
```

**Problems:**

- Validation changes? UserService needs to be modified.
- Email template changes? UserService needs to be modified.
- Audit format changes? UserService needs to be modified.
- Hard to test each responsibility in isolation.

### Refactored (Java 25 — immutable record + constructor injection)

```java
// ✅ GOOD: each class with a single responsibility
public record User(String name, String email) {
    public User {
        if (email == null || !email.contains("@")) {
            throw new IllegalArgumentException("Invalid email format");
        }
    }
}

public class UserRepository {
    private final EntityManager entityManager;

    public UserRepository(EntityManager entityManager) {
        this.entityManager = entityManager;
    }

    public User save(User user) {
        entityManager.persist(user);
        return user;
    }
}

public class WelcomeEmailSender {
    private final EmailClient emailClient;

    public WelcomeEmailSender(EmailClient emailClient) {
        this.emailClient = emailClient;
    }

    public void sendWelcome(User user) {
        emailClient.send(user.email(), "Welcome!", "Hello " + user.name());
    }
}

public class UserAuditLogger {
    private final AuditLog auditLog;

    public UserAuditLogger(AuditLog auditLog) {
        this.auditLog = auditLog;
    }

    public void logCreation(User user) {
        auditLog.log("User created: " + user.email());
    }
}

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

    public User createUser(String name, String email) {
        // validation is now fail-fast in the canonical constructor of the User record
        User user = repository.save(new User(name, email));
        emailSender.sendWelcome(user);
        auditLogger.logCreation(user);
        return user;
    }
}
```

> Note: moving validation into the canonical constructor of the `record` eliminates the need for an isolated
> `UserValidator` class when the rule is just a construction invariant. If validation depends on external state (e.g.,
> querying the database for a duplicate email), keep a separate `UserValidator` — that is still a distinct
> responsibility.

### How to Detect SRP Violations

- Class has many `import` statements from different domains.
- Class name frequently contains "And", "Manager", or "Handler".
- Methods operate on unrelated data.
- Changes in one area require touching unrelated methods.
- Difficult to name the class concisely.

### Quick Questions

1. Can you describe the purpose of the class in a single sentence without using "and"?
2. Would different stakeholders request changes to this class?
3. Are there methods that do not use most of the class fields?

---

## O - Open/Closed Principle (OCP)

> "Software entities should be open for extension, but closed for modification."

### Violation

```java
// ❌ BAD: needs to modify the class to add a new discount type
public class DiscountCalculator {

    public BigDecimal calculate(Order order, String discountType) {
        if (discountType.equals("PERCENTAGE")) {
            return order.total().multiply(new BigDecimal("0.10"));
        } else if (discountType.equals("FIXED")) {
            return new BigDecimal("50.00");
        } else if (discountType.equals("LOYALTY")) {
            return order.total().multiply(order.customer().loyaltyRate());
        }
        // Each new discount type = modifying this class
        return BigDecimal.ZERO;
    }
}
```

### Refactored (Java 25 — sealed interface + pattern matching, without String dispatch)

```java
// ✅ GOOD: new discounts without modifying existing code
// Financial rule: BigDecimal with explicit scale and RoundingMode, never double/float.

public sealed interface Discount permits PercentageDiscount, FixedDiscount, LoyaltyDiscount, SeasonalDiscount {
    BigDecimal apply(Order order);
}

public record PercentageDiscount(BigDecimal rate) implements Discount {
    @Override
    public BigDecimal apply(Order order) {
        return order.total().multiply(rate, new MathContext(6, RoundingMode.HALF_EVEN));
    }
}

public record FixedDiscount(BigDecimal amount) implements Discount {
    @Override
    public BigDecimal apply(Order order) {
        return amount.setScale(6, RoundingMode.HALF_EVEN);
    }
}

public record LoyaltyDiscount(BigDecimal loyaltyRate) implements Discount {
    @Override
    public BigDecimal apply(Order order) {
        return order.total().multiply(loyaltyRate, new MathContext(6, RoundingMode.HALF_EVEN));
    }
}

// New discount? Just add a new record — no existing class is modified.
public record SeasonalDiscount(BigDecimal rate) implements Discount {
    @Override
    public BigDecimal apply(Order order) {
        return order.total().multiply(rate, new MathContext(6, RoundingMode.HALF_EVEN));
    }
}

public class DiscountCalculator {
    public BigDecimal calculate(Order order, Discount discount) {
        return discount.apply(order);
    }
}
```

> The `sealed interface` locks down the set of known variants at compile time — if an exhaustive `switch` over
> `Discount` is needed elsewhere, the compiler forces you to handle all cases, making it easier to detect OCP broken by
> omission.

### How to Detect OCP Violations

- `if/else` or `switch` statements over type/status based on a `String` that grows over time.
- Dispatching by an enum with frequently added new values.
- Changes require modifying core classes.

### Common OCP Patterns

| Pattern                         | When to Use                                          |
|---------------------------------|------------------------------------------------------|
| Strategy (via sealed interface) | Multiple algorithms for the same operation           |
| Template Method                 | Same structure, different steps                      |
| Decorator                       | Dynamically add behavior                             |
| Factory                         | Create objects without specifying the concrete class |

---

## L - Liskov Substitution Principle (LSP)

> "Subtypes must be substitutable for their base types."

### Violation

```java
// ❌ BAD: Square violates Rectangle's contract
public class Rectangle {
    protected int width;
    protected int height;

    public void setWidth(int width) {
        this.width = width;
    }

    public void setHeight(int height) {
        this.height = height;
    }

    public int getArea() {
        return width * height;
    }
}

public class Square extends Rectangle {
    @Override
    public void setWidth(int width) {
        this.width = width;
        this.height = width; // Violates the expected behavior!
    }

    @Override
    public void setHeight(int height) {
        this.width = height; // Violates the expected behavior!
        this.height = height;
    }
}
```

### Refactored (Java 25 — sealed interface + immutable records)

```java
// ✅ GOOD: separate abstractions, without mutable state inheritance

public sealed interface Shape permits Rectangle, Square {
    int area();
}

public record Rectangle(int width, int height) implements Shape {
    @Override
    public int area() {
        return width * height;
    }
}

public record Square(int side) implements Shape {
    @Override
    public int area() {
        return side * side;
    }
}
```

### Real-World Violation in Java Enterprise: UnsupportedOperationException

```java
// ❌ BAD: ReadOnlyRepository violates CrudRepository's contract
public interface CrudRepository<T> {
    T save(T entity);

    Optional<T> findById(Long id);
}

public class ReadOnlyRepository<T> implements CrudRepository<T> {
    @Override
    public T save(T entity) {
        // Violates LSP! Clients calling save() on a CrudRepository reference
        // expect persistence, not a runtime exception.
        throw new UnsupportedOperationException("Write operations are not supported");
    }

    @Override
    public Optional<T> findById(Long id) {
        // read logic...
        return Optional.empty();
    }
}

// ✅ GOOD: segregate interfaces (ISP) to ensure LSP compliance
public interface ReadRepository<T> {
    Optional<T> findById(Long id);
}

public interface WriteRepository<T> {
    T save(T entity);
}

public class ReadOnlyRepository<T> implements ReadRepository<T> {
    @Override
    public Optional<T> findById(Long id) {
        // read logic...
        return Optional.empty();
    }
}
```

### LSP Rules

| Rule            | Meaning                                             |
|-----------------|-----------------------------------------------------|
| Pre-conditions  | Subclass cannot require more (strengthen)           |
| Post-conditions | Subclass cannot promise less (weaken)               |
| Invariants      | Subclass must maintain the parent's invariants      |
| History         | Subclass cannot modify inherited state unexpectedly |

### How to Detect LSP Violations

- Subclass throws an exception that the parent does not throw.
- Subclass returns `null` where the parent returns an object.
- Subclass ignores or overrides the parent's behavior unexpectedly.
- `instanceof` checks before calling methods.
- Empty implementations or methods that throw exceptions in interface implementations.

### Quick Check

```java
// If you see this, LSP might be violated
if(bird instanceof Penguin){
        // do not call fly()
        }else{
        bird.

fly();
}
```

> In Java 25, prefer `switch` with pattern matching over `sealed interface` instead of chained `instanceof` — the
> compiler guarantees exhaustiveness and the logic remains declarative.

---

## I - Interface Segregation Principle (ISP)

> "Clients should not be forced to depend on interfaces they do not use."

### Violation

```java
// ❌ BAD: fat interface forces unnecessary implementations
public interface Worker {
    void work();

    void eat();

    void sleep();

    void attendMeeting();

    void writeReport();
}

// Robot does not eat or sleep!
public class Robot implements Worker {
    @Override
    public void work() { /* OK */ }

    @Override
    public void eat() { /* Cannot eat! */ }

    @Override
    public void sleep() { /* Cannot sleep! */ }

    @Override
    public void attendMeeting() { /* OK */ }

    @Override
    public void writeReport() { /* Maybe */ }
}
```

### Refactored

```java
// ✅ GOOD: segregated interfaces

public interface Workable {
    void work();
}

public interface Feedable {
    void eat();

    void sleep();
}

public interface Manageable {
    void attendMeeting();

    void writeReport();
}

// Combine only what you need
public class Employee implements Workable, Feedable, Manageable {
    @Override
    public void work() { /* ... */ }

    @Override
    public void eat() { /* ... */ }

    @Override
    public void sleep() { /* ... */ }

    @Override
    public void attendMeeting() { /* ... */ }

    @Override
    public void writeReport() { /* ... */ }
}

public class Robot implements Workable {
    @Override
    public void work() { /* ... */ }
    // No unnecessary methods!
}

public class Intern implements Workable, Feedable {
    @Override
    public void work() { /* ... */ }

    @Override
    public void eat() { /* ... */ }

    @Override
    public void sleep() { /* ... */ }
    // No meeting/report methods!
}
```

### How to Detect ISP Violations

- Implementations with empty methods or `throw new UnsupportedOperationException()`.
- Interface with 10+ methods.
- Different clients use completely distinct subsets of methods.
- Changes in the interface affect unrelated implementations.

### Repositories: Fat vs. Segregated Interface

```java
// ❌ Interface too fat for most use cases
public interface Repository<T> {
    T findById(Long id);

    List<T> findAll();

    T save(T entity);

    void delete(T entity);

    void deleteById(Long id);

    Page<T> findAll(Pageable pageable);

    long count();

    boolean existsById(Long id);
    // ... 15 more methods
}

// ✅ Better: split by use case
public interface ReadRepository<T> {
    Optional<T> findById(Long id);

    List<T> findAll();
}

public interface WriteRepository<T> {
    T save(T entity);

    void delete(T entity);
}
```

---

## D - Dependency Inversion Principle (DIP)

> "High-level modules should not depend on low-level modules. Both should depend on abstractions."

### Violation

```java
// ❌ BAD: high-level directly depends on low-level
public class OrderService {
    private PostgresOrderRepository repository; // Concrete class!
    private SmtpEmailSender emailSender;        // Concrete class!

    public OrderService() {
        this.repository = new PostgresOrderRepository(); // tight coupling
        this.emailSender = new SmtpEmailSender();         // tight coupling
    }

    public void createOrder(Order order) {
        repository.save(order);
        emailSender.send(order.customerEmail(), "Order confirmed");
    }
}
```

**Problems:**

- Impossible to test without a real Postgres instance.
- Impossible to swap the email provider.
- OrderService knows Postgres and SMTP implementation details.

### Refactored

```java
// ✅ GOOD: depending on abstractions

public interface OrderRepository {
    void save(Order order);

    Optional<Order> findById(Long id);
}

public interface NotificationSender {
    void send(String recipient, String message);
}

// High-level module depends on abstractions
public class OrderService {
    private final OrderRepository repository;
    private final NotificationSender notificationSender;

    // Dependencies injected via constructor
    public OrderService(OrderRepository repository,
                        NotificationSender notificationSender) {
        this.repository = repository;
        this.notificationSender = notificationSender;
    }

    public void createOrder(Order order) {
        repository.save(order);
        notificationSender.send(order.customerEmail(), "Order confirmed");
    }
}

// Low-level modules implement the abstractions
public class PostgresOrderRepository implements OrderRepository {
    @Override
    public void save(Order order) { /* Postgres-specific */ }

    @Override
    public Optional<Order> findById(Long id) { /* Postgres-specific */
        return Optional.empty();
    }
}

public class SmtpEmailSender implements NotificationSender {
    @Override
    public void send(String recipient, String message) { /* SMTP-specific */ }
}

// Easy to test with fakes!
public class InMemoryOrderRepository implements OrderRepository {
    private final Map<Long, Order> orders = new HashMap<>();

    @Override
    public void save(Order order) {
        orders.put(order.id(), order);
    }

    @Override
    public Optional<Order> findById(Long id) {
        return Optional.ofNullable(orders.get(id));
    }
}
```

### DIP with Spring Boot (>= 4.0.5)

```java
// Spring manages dependency injection automatically.
// Transactional boundary belongs to the Service (Use Case layer), never to the adapter/controller.

@Service
public class OrderService {
    private final OrderRepository repository;
    private final NotificationSender notificationSender;

    public OrderService(OrderRepository repository,
                        NotificationSender notificationSender) {
        this.repository = repository;
        this.notificationSender = notificationSender;
    }

    @Transactional
    public void createOrder(Order order) {
        repository.save(order);
        notificationSender.send(order.customerEmail(), "Order confirmed");
    }
}

@Repository
public class JpaOrderRepository implements OrderRepository { /* Spring Data implementation */
}

@Component
@Profile("production")
public class SmtpEmailSender implements NotificationSender {
}

@Component
@Profile("test")
public class FakeEmailSender implements NotificationSender {
}
```

> If `NotificationSender` makes a network call (external SMTP), handle timeouts and failures in the implementation
> (adapter). Never let infrastructure exceptions leak as-is to `OrderService` — wrap them in a custom integration error
> type before propagating them up the stack.

### How to Detect DIP Violations

- `new ConcreteClass()` instantiated inside business logic.
- Imports include implementation packages (e.g., `org.postgresql`, `org.apache.http`).
- Cannot swap implementations easily.
- Tests require real infrastructure (database, network).

---

## SOLID Review Checklist

When reviewing code, check:

| Principle | Question                                                           |
|-----------|--------------------------------------------------------------------|
| **SRP**   | Does this class have more than one reason to change?               |
| **OCP**   | Will adding a new type/functionality require modifying this class? |
| **LSP**   | Can subclasses be used anywhere the parent is expected?            |
| **ISP**   | Are there empty implementations or methods that throw exceptions?  |
| **DIP**   | Does high-level code depend on concrete implementations?           |

---

## Common Refactoring Patterns

| Violation                      | Refactoring                                            |
|--------------------------------|--------------------------------------------------------|
| SRP - God class                | Extract Class, Move Method                             |
| OCP - Type switching by String | Sealed Interface + Pattern Matching, Strategy, Factory |
| LSP - Broken inheritance       | Composition over Inheritance, Extract Interface        |
| ISP - Fat interface            | Split Interface, Role Interface                        |
| DIP - Rigid dependencies       | Dependency Injection, Abstract Factory                 |

---

## Related Skills

- `design-patterns` - Implementation patterns (Factory, Strategy, Observer, etc.)
- `clean-code` - Code-level principles (DRY, KISS, naming)
- `java-code-review` - Comprehensive review checklist
