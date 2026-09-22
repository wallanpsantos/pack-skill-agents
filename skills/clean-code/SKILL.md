---
name: clean-code
description: Clean Code principles (DRY, KISS, YAGNI), naming conventions, function design, and refactoring. Use when user says "clean this code", "refactor", "improve readability", or when reviewing code quality.
---

# Clean Code Skill

Write readable, maintainable code following Clean Code principles.

## When to Use

- User says "clean this code" / "refactor" / "improve readability"
- Code review focusing on maintainability
- Reducing complexity
- Improving naming

---

## Core Principles

| Principle | Meaning                  | Violation Sign            |
|-----------|--------------------------|---------------------------|
| **DRY**   | Don't Repeat Yourself    | Copy-pasted code blocks   |
| **KISS**  | Keep It Simple, Stupid   | Over-engineered solutions |
| **YAGNI** | You Aren't Gonna Need It | Features "just in case"   |

---

## DRY - Don't Repeat Yourself

> "Every piece of knowledge must have a single, unambiguous representation in the system."

### Violation

```java
// ❌ BAD: Same validation logic repeated
public class UserController {

    public void createUser(UserRequest request) {
        if (request.getEmail() == null || request.getEmail().isBlank()) {
            throw new ValidationException("Email is required");
        }
        if (!request.getEmail().contains("@")) {
            throw new ValidationException("Invalid email format");
        }
        // ... create user
    }

    public void updateUser(UserRequest request) {
        if (request.getEmail() == null || request.getEmail().isBlank()) {
            throw new ValidationException("Email is required");
        }
        if (!request.getEmail().contains("@")) {
            throw new ValidationException("Invalid email format");
        }
        // ... update user
    }
}
```

### Refactored

```java
// ✅ GOOD: Single source of truth
public class EmailValidator {

    public void validate(String email) {
        if (email == null || email.isBlank()) {
            throw new ValidationException("Email is required");
        }
        if (!email.contains("@")) {
            throw new ValidationException("Invalid email format");
        }
    }
}

public class UserController {
    private final EmailValidator emailValidator;

    public void createUser(UserRequest request) {
        emailValidator.validate(request.getEmail());
        // ... create user
    }

    public void updateUser(UserRequest request) {
        emailValidator.validate(request.getEmail());
        // ... update user
    }
}
```

### DRY Exceptions

Not all duplication is bad. Avoid premature abstraction:

```java
// These look similar but serve different purposes - OK to duplicate
public BigDecimal calculateShippingCost(Order order) {
    return order.getWeight().multiply(SHIPPING_RATE);
}

public BigDecimal calculateInsuranceCost(Order order) {
    return order.getValue().multiply(INSURANCE_RATE);
}
// Don't force these into one method - they'll evolve differently
```

---

## KISS - Keep It Simple

> "The simplest solution is usually the best."

### Violation

```java
// ❌ BAD: Over-engineered for simple task
public class StringUtils {

    public boolean isEmpty(String str) {
        return Optional.ofNullable(str)
                .map(String::trim)
                .map(String::isEmpty)
                .orElseGet(() -> Boolean.TRUE);
    }
}
```

### Refactored

```java
// ✅ GOOD: Simple and clear
public class StringUtils {

    public boolean isEmpty(String str) {
        return str == null || str.trim().isEmpty();
    }

    // Or use existing library
    // return StringUtils.isBlank(str);  // Apache Commons
    // return str == null || str.isBlank();  // Java 11+
}
```

### KISS Checklist

- Can a junior developer understand this in 30 seconds?
- Is there a simpler way using standard libraries?
- Am I adding complexity for edge cases that may never happen?

---

## YAGNI - You Aren't Gonna Need It

> "Don't add functionality until it's necessary."

### Violation

```java
// ❌ BAD: Building for hypothetical future
public interface Repository<T, ID> {
    T findById(ID id);

    List<T> findAll();

    List<T> findAll(Pageable pageable);

    List<T> findAll(Sort sort);

    List<T> findAllById(Iterable<ID> ids);

    T save(T entity);

    List<T> saveAll(Iterable<T> entities);

    void delete(T entity);

    void deleteById(ID id);

    void deleteAll(Iterable<T> entities);

    void deleteAll();

    boolean existsById(ID id);

    long count();
    // ... 20 more methods "just in case"
}

// Current usage: only findById and save
```

### Refactored

```java
// ✅ GOOD: Only what's needed now
public interface UserRepository {
    Optional<User> findById(Long id);

    User save(User user);
}

// Add methods when actually needed, not before
```

### YAGNI Signs

- "We might need this later"
- "Let's make it configurable just in case"
- "What if we need to support X in the future?"
- Abstract classes with one implementation

---

## Naming Conventions

### Variables

```java
// ❌ BAD
int d;                  // What is d?
String s;               // Meaningless
List<User> list;        // What kind of list?
Map<String, Object> m;  // What does it map?

// ✅ GOOD
int elapsedTimeInDays;
String customerName;
List<User> activeUsers;
Map<String, Object> sessionAttributes;
```

### Booleans

```java
// ❌ BAD
boolean flag;
boolean status;
boolean check;

// ✅ GOOD - Use is/has/can/should prefix
boolean isActive;
boolean hasPermission;
boolean canEdit;
boolean shouldNotify;
```

### Methods

```java
// ❌ BAD
void process();           // Process what?

void handle();            // Handle what?

void doIt();              // Do what?

User get();               // Get from where?

// ✅ GOOD - Verb + noun, descriptive
void processPayment();

void handleLoginRequest();

void sendWelcomeEmail();

User findByEmail(String email);

List<Order> fetchPendingOrders();
```

### Classes

```java
// ❌ BAD
class Data {
}           // Too vague

class Info {
}           // Too vague

class Manager {
}        // Often a god class

class Helper {
}         // Often a dumping ground

class Utils {
}          // Static method dumping ground

// ✅ GOOD - Noun, specific responsibility
class User {
}

class OrderProcessor {
}

class EmailValidator {
}

class PaymentGateway {
}

class ShippingCalculator {
}
```

### Naming Conventions Table

| Element   | Convention                    | Example              |
|-----------|-------------------------------|----------------------|
| Class     | PascalCase, noun              | `OrderService`       |
| Interface | PascalCase, adjective or noun | `Comparable`, `List` |
| Method    | camelCase, verb               | `calculateTotal()`   |
| Variable  | camelCase, noun               | `customerEmail`      |
| Constant  | UPPER_SNAKE                   | `MAX_RETRY_COUNT`    |
| Package   | lowercase                     | `com.example.orders` |

---

## Functions / Methods

### Keep Functions Small

```java
// ❌ BAD: 50+ line method doing multiple things
public void processOrder(Order order) {
    // validate order (10 lines)
    // calculate totals (15 lines)
    // apply discounts (10 lines)
    // update inventory (10 lines)
    // send notifications (10 lines)
    // ... and more
}

// ✅ GOOD: Small, focused methods
public void processOrder(Order order) {
    validateOrder(order);
    calculateTotals(order);
    applyDiscounts(order);
    updateInventory(order);
    sendNotifications(order);
}
```

### Single Level of Abstraction

```java
// ❌ BAD: Mixed abstraction levels
public void processOrder(Order order) {
    validateOrder(order);  // High level

    // Low level mixed in
    BigDecimal total = BigDecimal.ZERO;
    for (OrderItem item : order.getItems()) {
        total = total.add(item.getPrice().multiply(
                BigDecimal.valueOf(item.getQuantity())));
    }

    sendEmail(order);  // High level again
}

// ✅ GOOD: Consistent abstraction level
public void processOrder(Order order) {
    validateOrder(order);
    calculateTotal(order);
    sendConfirmation(order);
}

private BigDecimal calculateTotal(Order order) {
    return order.getItems().stream()
            .map(item -> item.getPrice().multiply(
                    BigDecimal.valueOf(item.getQuantity())))
            .reduce(BigDecimal.ZERO, BigDecimal::add);
}
```

### Limit Parameters

```java
// ❌ BAD: Too many parameters
public User createUser(String firstName, String lastName,
                       String email, String phone,
                       String address, String city,
                       String country, String zipCode) {
    // ...
}

// ✅ GOOD: Use parameter object
public User createUser(CreateUserRequest request) {
    // ...
}

// Or builder
public User createUser(UserBuilder builder) {
    // ...
}
```

### Avoid Flag Arguments

```java
// ❌ BAD: Boolean flag changes behavior
public void sendMessage(String message, boolean isUrgent) {
    if (isUrgent) {
        // send immediately
    } else {
        // queue for later
    }
}

// ✅ GOOD: Separate methods
public void sendUrgentMessage(String message) {
    // send immediately
}

public void queueMessage(String message) {
    // queue for later
}
```

---

## Comments

### Avoid Obvious Comments

```java
// ❌ BAD: Noise comments
// Set the user's name
user.setName(name);

// Increment counter
counter++;

// Check if user is null
        if(user !=null){
        // ...
        }
```

### Good Comments

```java
// ✅ GOOD: Explain WHY, not WHAT

// Retry with exponential backoff to avoid overwhelming the server
// during high load periods (see incident #1234)
for(int attempt = 0;
attempt<MAX_RETRIES;attempt++){
        Thread.

sleep((long) Math.

pow(2,attempt) *1000);
        // ...
        }

// TODO: Replace with Redis cache after infrastructure upgrade (Q2 2026)
private Map<String, User> userCache = new ConcurrentHashMap<>();

// WARNING: Order matters! Discounts must be applied before tax calculation
applyDiscounts(order);

calculateTax(order);
```

### Let Code Speak

```java
// ❌ BAD: Comment explaining bad code
// Check if the user is an admin or has special permission
// and the action is allowed for their role
if((user.getRole() ==1||user.

getRole() ==2)&&
        (action ==3||action ==4||action ==7)){
        // ...
        }

// ✅ GOOD: Self-documenting code
        if(user.

hasAdminPrivileges() &&action.

isAllowedFor(user.getRole())){
        // ...
        }
```

---

## Common Code Smells

| Smell                   | Description                      | Refactoring          |
|-------------------------|----------------------------------|----------------------|
| **Long Method**         | Method > 20 lines                | Extract Method       |
| **Long Parameter List** | > 3 parameters                   | Parameter Object     |
| **Duplicate Code**      | Same code in multiple places     | Extract Method/Class |
| **Dead Code**           | Unused code                      | Delete it            |
| **Magic Numbers**       | Unexplained literals             | Named Constants      |
| **God Class**           | Class doing too much             | Extract Class        |
| **Feature Envy**        | Method uses another class's data | Move Method          |
| **Primitive Obsession** | Primitives instead of objects    | Value Objects        |

### Magic Numbers

```java
// ❌ BAD
if(user.getAge() >=18){}
        if(order.

getTotal() >100){}
        Thread.

sleep(86400000);

// ✅ GOOD
private static final int ADULT_AGE = 18;
private static final BigDecimal FREE_SHIPPING_THRESHOLD = new BigDecimal("100");
private static final long ONE_DAY_MS = TimeUnit.DAYS.toMillis(1);

if(user.

getAge() >=ADULT_AGE){}
        if(order.

getTotal().

compareTo(FREE_SHIPPING_THRESHOLD) >0){}
        Thread.

sleep(ONE_DAY_MS);
```

### Primitive Obsession

```java
// ❌ BAD: Primitives everywhere
public void createUser(String email, String phone, String zipCode) {
    // No validation, easy to mix up parameters
}

createUser("12345","john@email.com","555-1234");  // Wrong order, compiles!

// ✅ GOOD: Value objects
public record Email(String value) {
    public Email {
        if (!value.contains("@")) {
            throw new IllegalArgumentException("Invalid email");
        }
    }
}

public record PhoneNumber(String value) {
    // validation
}

public void createUser(Email email, PhoneNumber phone, ZipCode zipCode) {
    // Type-safe, self-validating
}
```

### Top-Level Enums vs Inner/Nested Enums

Evite aninhar enums genéricos como `public enum Variant` ou `public enum Status` dentro de classes de dados ou records. Enums aninhados geram poluição visual, acoplamento desnecessário e colisões de importação em repositórios e serviços.

```java
// ❌ BAD: Enum aninhado genérico polui a classe e causa colisões de import
public record BannerComponent(String id, Variant variant) {
    public enum Variant { INFO, WARNING, SUCCESS, DANGER }
}

// ✅ GOOD: Enum Top-Level com semântica explícita e mapeamento JSON resiliente
public enum BannerVariant {
    INFO("info"),
    WARNING("warning"),
    SUCCESS("success"),
    DANGER("danger");

    private final String wireValue;

    BannerVariant(String wireValue) {
        this.wireValue = wireValue;
    }

    @JsonValue
    public String wireValue() {
        return wireValue;
    }

    @JsonCreator
    public static BannerVariant fromWire(String value) {
        if (value == null || value.isBlank()) return INFO;
        for (var v : values()) {
            if (v.wireValue.equalsIgnoreCase(value) || v.name().equalsIgnoreCase(value)) {
                return v;
            }
        }
        return INFO;
    }
}

public record BannerComponent(String id, BannerVariant variant) implements UIComponent { ... }
```

---

## Refactoring Quick Reference

| From                     | To                    | Technique                             |
|--------------------------|-----------------------|---------------------------------------|
| Long method              | Short methods         | Extract Method                        |
| Duplicate code           | Single method         | Extract Method                        |
| Complex conditional      | Polymorphism          | Replace Conditional with Polymorphism |
| Many parameters          | Object                | Introduce Parameter Object            |
| Temp variables           | Query method          | Replace Temp with Query               |
| Comments explaining code | Self-documenting code | Rename, Extract                       |
| Nested conditionals      | Early return          | Guard Clauses                         |

### Guard Clauses

```java
// ❌ BAD: Deeply nested
public void processOrder(Order order) {
    if (order != null) {
        if (order.isValid()) {
            if (order.hasItems()) {
                // actual logic buried here
            }
        }
    }
}

// ✅ GOOD: Guard clauses
public void processOrder(Order order) {
    if (order == null) return;
    if (!order.isValid()) return;
    if (!order.hasItems()) return;

    // actual logic at top level
}
```

---

## Modern Java Clean Code Patterns (Java 15+ / 16+)

Modern Java introduces features that simplify code structure and improve readability.

### Java Records for Data Carriers (Java 16+)

Use records instead of boilerplate-heavy POJOs for immutable data transport. Records automatically generate accessors
(without the legacy `get` prefix), `equals()`, `hashCode()`, and `toString()`.

```java
// ❌ Legacy DTO with boilerplate (or Lombok annotation dependency)
public class UserDto {
    private final String name;
    private final String email;

    public UserDto(String name, String email) {
        this.name = name;
        this.email = email;
    }

    public String getName() {
        return name;
    }

    public String getEmail() {
        return email;
    }
    // equals, hashCode, toString...
}

// ✅ Modern Java Record: Clean and concise
public record UserDto(String name, String email) {
}
```

### Pattern Matching for instanceof (Java 16+)

Eliminate redundant and unsafe manual casting checks.

```java
// ❌ Legacy casting
if(obj instanceof Order){
Order order = (Order) obj;

processOrder(order);
}

// ✅ Modern inline casting
        if(obj instanceof
Order order){

processOrder(order);
}
```

### Text Blocks (Java 15+)

Use text blocks to preserve formatting and eliminate string concatenation for multiline data like SQL, JSON, or HTML.

```java
// ❌ Cluttered concatenation
String query = "SELECT id, name FROM users "
                + "WHERE status = 'ACTIVE' "
                + "ORDER BY created_at DESC";

// ✅ Clean Text Block
String query = """
        SELECT id, name FROM users
        WHERE status = 'ACTIVE'
        ORDER BY created_at DESC
        """;
```

---

## Clean Code & Maintenance (Scout Rule)

The "Boy Scout Rule" states: *Always leave the campground cleaner than you found it.* When modifying code, apply these
clean code and maintenance principles:

- **DRY (Don't Repeat Yourself)**: Eliminate code duplication. When changing or adding code, identify similar existing
  logic and extract it into reusable methods or classes.
- **Names**: Actively improve readability. Rename poorly named variables, methods, or classes that you touch to match
  their actual intent.
- **Simplicity**: Favor simple, direct code over complex or over-engineered abstractions. Maintain smaller methods and a
  direct execution flow.
- **Maintainability**: Ensure code is highly readable, split responsibilities cleanly, remove dead/commented-out code,
  and write tests for any new or modified behavior.
- **Explicit Imports**: Avoid using Fully Qualified Names (FQN) inside the logic body (e.g., use `java.util.List` in the
  imports list rather than using `java.util.List` inline inside a method). Always use explicit `import` statements at
  the top of the file to keep the code body clean and readable.
- **Methods/Functions**: Keep methods small (ideally max ~20 lines) with a single, clear responsibility. Extract logic
  into helper methods with intention-revealing names.
- **Conditionals & Flow**: Avoid double negatives or negative boolean expressions (prefer `isActive` over
  `!isInactive`). Do not nest `if` statements deeply; use early returns and guard clauses to simplify the execution
  path.
- **Magic Values**: Do not hardcode magic numbers or strings inline. Extract them to named constants
  (`private static final`) or config properties.
- **Null Safety & Optional**: Never return or pass `null` values (not even to indicate a lack of validation errors or
  empty result). Use Java's `Optional` to represent the absence of a value and prevent `NullPointerException`. Enforce
  fail-fast parameters validation in constructors.

#### Example: FQN vs Explicit Imports

```java
// ❌ BAD: Fully Qualified Names cluttering the code body
public class OrderService {
    public void process(java.util.List<com.example.model.Order> orders) {
        java.time.LocalDateTime now = java.time.LocalDateTime.now();
        // ...
    }
}

// ✅ GOOD: Clean imports at the top
import java.util.List;
import java.time.LocalDateTime;
import com.example.model.Order;

public class OrderService {
    public void process(List<Order> orders) {
        LocalDateTime now = LocalDateTime.now();
        // ...
    }
}
```

#### Example: Fail-fast Constructors & Null Prevention

```java
// ❌ BAD: Allows null arguments, causing issues later
public class User {
    private String name;

    public User(String name) {
        this.name = name;
    }
}

// ✅ GOOD: Fail-fast constructor, prevents null/invalid state early
public class User {
    private final String name;

    public User(String name) {
        this.name = Objects.requireNonNull(name, "User name must not be null");
        if (name.isBlank()) {
            throw new IllegalArgumentException("User name must not be blank");
        }
    }
}
```

---

## Clean Code Checklist

When reviewing code, check:

- [ ] **Scout Rule**: Is the modified code cleaner than before? Did you rename bad names you touched?
- [ ] **DRY**: Is there any duplicated code? Have similar logic blocks been extracted?
- [ ] **Names**: Are names meaningful, pronounceable, and descriptive of their intent?
- [ ] **Simplicity**: Is the method size small (max ~20 lines) and the execution flow simple and direct? No
  over-engineering?
- [ ] **Maintainability**: Is the code readable, with split responsibilities, no dead/unused code, and tests included?
- [ ] **Imports**: Are all imports declared explicitly at the top? No Fully Qualified Names (FQN) cluttering the logic?
- [ ] **Conditionals**: Are there any double negatives or negative boolean checks (e.g., `!isInactive`)? Are nested ifs
  replaced by guard clauses/early returns?
- [ ] **Magic Values**: Are there any inline magic numbers or strings? Have they been extracted to named constants?
- [ ] **Null Safety**: Are there any returns or parameters passing `null`? Is `Optional` used to represent absence of
  value? Are constructors fail-fast?
- [ ] **Comments**: Are comments explaining "why", not "what"?
- [ ] **Abstraction**: Is the code at a consistent abstraction level?

---

## Related Skills

- `solid-principles` - Design principles for class structure
- `design-patterns` - Common solutions to recurring problems
- `java-code-review` - Comprehensive review checklist
