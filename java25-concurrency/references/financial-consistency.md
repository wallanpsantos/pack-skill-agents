# Financial State Under Concurrency

Load when reviewing balances, ledgers, monetary arithmetic, or concurrency control on financial state.

## Rules (non-negotiable)

1. Never `double` / `float` for money.
2. **`MathContext` is significant digits, not decimal places.** Using it as a scale limiter corrupts large values.
   - Add/subtract are exact: **do not** pass a `MathContext` or a `RoundingMode`.
   - Divide (and multiply when you must round) uses **explicit scale**:
     `amount.divide(divisor, 6, RoundingMode.HALF_EVEN)`.
   - `MathContext` only when the domain genuinely asks for significant-digit precision, with justification.
3. Default intermediate precision: scale 6, unless the domain says otherwise.
4. Concurrent balance/state mutations MUST use explicit concurrency control:
   - **Default**: `@Version` (optimistic locking) + bounded retry with backoff, **outside the transaction**.
   - **Accepted alternatives with explicit justification**: conditional atomic update, pessimistic lock
     (`SELECT ... FOR UPDATE`), serializable transaction.
   - The requirement is concurrency control on financial state — the mechanism may vary, it MUST NOT be absent.
5. Encapsulate amount + currency in an immutable `record` with fail-fast validation and normalized scale.
6. In-memory concurrent structures (`LongAdder`, `AtomicLong`, `ConcurrentHashMap`) are never the source of truth for a
   balance.

---

## 1. The `MathContext` trap (most expensive bug in this file)

```java
BigDecimal balance = new BigDecimal("1500000.00");
BigDecimal debit   = new BigDecimal("25.50");

// ❌ MathContext(6) = 6 SIGNIFICANT DIGITS → 1500000  (the debit silently vanishes)
balance.subtract(debit, new MathContext(6, RoundingMode.HALF_EVEN));

// ✅ subtraction is exact — no rounding argument at all
balance.subtract(debit);                                  // 1499974.50

// ✅ when you must divide, fix the SCALE
BigDecimal rate = amount.divide(divisor, 6, RoundingMode.HALF_EVEN);
```

---

## 2. Optimistic locking (default)

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
```

### Retry must sit OUTSIDE the transaction

The version conflict is detected at **commit**, after the `@Transactional` method returns. A `@Retryable` on the same
method (or inside the same transactional proxy) never sees it. And with Spring Data the exception is translated: the
observable type is `ObjectOptimisticLockingFailureException` (a `OptimisticLockingFailureException`), not
`jakarta.persistence.OptimisticLockException`. Matching the wrong type gives a retry that never fires.

```java
// ❌ retry inside the transactional boundary, wrong exception type
@Transactional
@Retryable(retryFor = OptimisticLockException.class)
public void debit(Long id, BigDecimal amount) { ... }

// ✅ facade (non-transactional) retries; the transactional method is a separate bean
@Service
public class AccountFacade {

    private final AccountService accountService; // separate bean → proxy applies

    @Retryable(
            retryFor = OptimisticLockingFailureException.class,
            maxAttempts = 3,
            backoff = @Backoff(delay = 100, multiplier = 2, random = true)) // jitter
    public void debit(Long accountId, BigDecimal amount) {
        accountService.debitInTransaction(accountId, amount); // commit happens inside this call
    }
}

@Service
public class AccountService {

    @Transactional
    public void debitInTransaction(Long accountId, BigDecimal amount) {
        Account account = accountRepository.findById(accountId)
                .orElseThrow(() -> new AccountNotFoundException(accountId));

        BigDecimal newBalance = account.getBalance().subtract(amount); // exact, no rounding

        if (newBalance.signum() < 0) {
            throw new InsufficientFundsException(accountId); // business failure — must NOT be retried
        }
        account.setBalance(newBalance);
    }
}
```

Notes:

- Document max attempts and backoff; use jitter so retries do not synchronize.
- Never swallow the optimistic-lock failure, and never retry business failures such as insufficient funds.
- Spring Retry is an external dependency — justify it, or write the bounded retry loop by hand around the transactional
  call.
- Under predictably high contention, optimistic retries become retry storms: monitor DB contention and switch to atomic
  updates or pessimistic locks (Evans et al., Ch. 12; Rahman, Ch. 5).

---

## 3. Alternative: conditional atomic update

```java
// ✅ When optimistic locking overhead is not justified — requires explicit justification in review
@Modifying(flushAutomatically = true, clearAutomatically = true) // JPQL bypasses the persistence context
@Query("UPDATE Account a SET a.balance = a.balance - :amount, a.version = a.version + 1 "
     + "WHERE a.id = :id AND a.balance >= :amount")
int debitAtomic(@Param("id") Long id, @Param("amount") BigDecimal amount);

// Caller MUST check the affected row count
@Transactional
public void debit(Long accountId, BigDecimal amount) {
    int updated = accountRepository.debitAtomic(accountId, amount);
    if (updated == 0) {
        throw new InsufficientFundsException(accountId); // no row matched the balance predicate
    }
}
```

The bulk update does not synchronize the persistence context and does not increment `@Version` on its own — hence
`flushAutomatically`/`clearAutomatically` and the explicit version bump. Entities loaded before the update are stale.

---

## 4. Money value object

```java
public record Money(BigDecimal amount, Currency currency) {

    private static final int SCALE = 6;

    public Money {
        Objects.requireNonNull(amount, "amount");
        Objects.requireNonNull(currency, "currency");
        if (amount.scale() > SCALE) {
            throw new IllegalArgumentException("scale must be <= " + SCALE);
        }
        // BigDecimal.equals compares scale: 1.50 != 1.5. Normalize so record equality behaves.
        amount = amount.setScale(SCALE, RoundingMode.UNNECESSARY);
    }

    public Money add(Money other) {
        requireSameCurrency(other);
        return new Money(amount.add(other.amount), currency);       // exact
    }

    public Money subtract(Money other) {
        requireSameCurrency(other);
        return new Money(amount.subtract(other.amount), currency);  // exact
    }

    public Money divide(BigDecimal divisor) {
        return new Money(amount.divide(divisor, SCALE, RoundingMode.HALF_EVEN), currency); // scale, not MathContext
    }

    private void requireSameCurrency(Money other) {
        if (!currency.equals(other.currency)) {
            throw new IllegalArgumentException("currency mismatch");
        }
    }
}
```

`setScale(..., UNNECESSARY)` is safe here because the constructor already rejects a larger scale; it only pads.

---

## 5. External operations with financial effect

Idempotency key, timeout, safe retry policy (only for idempotent operations), and a reconciliation path. A timeout is
not a failure: the operation may have succeeded downstream. Never resolve that ambiguity with a blind retry.

---

## 6. Flags

- Balance mutation without concurrency control under concurrent writers
- `MathContext` used as a decimal-place limiter; `divide` without scale + `RoundingMode`
- Rounding applied to addition/subtraction
- Optimistic-lock retry placed inside the transaction, or matching `OptimisticLockException` under Spring Data
- Business exceptions (insufficient funds) inside the retry set
- `double`/`float` money fields
- `record` money without scale normalization (equality surprises)
- Bulk JPQL update without `clearAutomatically` / version bump / row-count check
- Financial gates on `ConcurrentHashMap.size()` / estimated counts
- Alternative concurrency control without explicit justification in review
- External financial call without idempotency key or reconciliation path

---

## 7. References & Literature

- Rahman, A.N.M. Bazlur. *Modern Concurrency in Java*. O'Reilly Media, 2026. (Ch. 3, Ch. 5).
- Evans, Benjamin J., James Gough, and Chris Newland. *Optimizing Cloud Native Java*. O'Reilly Media, 2024. (Ch. 8,
  Ch. 12).
