# Financial State Under Concurrency

Load when reviewing balances, ledgers, monetary arithmetic, or concurrency control on financial state.

## Rules (non-negotiable)

1. Never `double` / `float` for money.
2. Every `BigDecimal` multiply/divide uses explicit `RoundingMode` (and scale/MathContext as needed).
3. Prefer 6 decimal places for intermediate precision unless domain says otherwise.
4. Concurrent balance/state mutations MUST use explicit concurrency control:
    - **Default**: `@Version` (optimistic locking) + retry with backoff on `OptimisticLockException`.
    - **Accepted alternatives with explicit justification**: atomic database update
      (`UPDATE ... SET balance = balance - ? WHERE balance >= ?`), pessimistic lock (`SELECT ... FOR UPDATE`),
      serializable transaction.
    - The requirement is concurrency control on financial state — the specific mechanism may vary, but it MUST NOT be
      absent.
5. Encapsulate amount + currency in an immutable `record` with fail-fast validation.

## Optimistic locking (default)

```java

@Entity
public class Account {
    @Id
    private Long id;

    @Column(nullable = false, precision = 19, scale = 6)
    private BigDecimal balance;

    @Version
    private Long version;
}

@Retryable(
        retryFor = OptimisticLockException.class,
        maxAttempts = 3,
        backoff = @Backoff(delay = 100, multiplier = 2)
)
public void debit(Long accountId, BigDecimal amount) {
    Account account = accountRepository.findById(accountId)
            .orElseThrow(() -> new AccountNotFoundException(accountId));

    BigDecimal newBalance = account.getBalance()
            .subtract(amount, new MathContext(6, RoundingMode.HALF_EVEN));

    if (newBalance.signum() < 0) {
        throw new InsufficientFundsException(accountId);
    }

    account.setBalance(newBalance);
    accountRepository.save(account);
}
```

Document max attempts and backoff. Do not swallow `OptimisticLockException`.

## Alternative: Atomic database update

```java
// ✅ When optimistic locking overhead is not justified
// Requires explicit justification in review
@Modifying
@Query("UPDATE Account a SET a.balance = a.balance - :amount " +
        "WHERE a.id = :id AND a.balance >= :amount")
int debitAtomic(@Param("id") Long id, @Param("amount") BigDecimal amount);

// Caller MUST check return value
int updated = accountRepository.debitAtomic(accountId, amount);
if(updated ==0){
        throw new

InsufficientFundsException(accountId);
}
```

## BigDecimal arithmetic

```java
// ❌
double total = price * taxRate;
BigDecimal r = dividend.divide(divisor); // may throw on non-terminating expansion

// ✅
BigDecimal r = dividend.divide(divisor, new MathContext(6, RoundingMode.HALF_EVEN));
```

Note: `MathContext` precision is **significant digits**, not scale after the decimal. For fixed scale use:

```java
amount.divide(divisor, 6,RoundingMode.HALF_EVEN);
```

## Money value object

```java
public record Money(BigDecimal amount, Currency currency) {
    public Money {
        Objects.requireNonNull(amount, "amount");
        Objects.requireNonNull(currency, "currency");
        if (amount.scale() > 6) {
            throw new IllegalArgumentException("scale must be <= 6");
        }
    }

    public Money add(Money other) {
        requireSameCurrency(other);
        return new Money(
                amount.add(other.amount, new MathContext(6, RoundingMode.HALF_EVEN)),
                currency
        );
    }

    private void requireSameCurrency(Money other) {
        if (!currency.equals(other.currency)) {
            throw new IllegalArgumentException("currency mismatch");
        }
    }
}
```

## Flags

- Balance mutation without concurrency control under concurrent writers
- No retry on `OptimisticLockException`
- `double`/`float` money fields
- `divide`/`multiply` without `RoundingMode`
- Financial gates on `ConcurrentHashMap.size()` / estimated counts
- Shared mutable `BigDecimal` field without sync or atomic replace (prefer reassign immutable results)
- Alternative concurrency control without explicit justification in review
