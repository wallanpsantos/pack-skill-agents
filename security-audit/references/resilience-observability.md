# Tratamento de Erros, Logging, Dependências e Headers (A09/A10:2025)

Cobre tratamento explícito de exceções (sem vazar stack trace), logging/alerting seguro com mascaramento de PII,
auditoria de dependências e headers de segurança HTTP.

## Conteúdo
- Mishandling of Exceptional Conditions
  - ProblemDetail — Padrão RFC 9457 (Spring Boot 3+)
  - Quarkus — Exception Mapper
- Logging & Alerting
  - Log de Eventos de Segurança
  - PII Masking — MaskingConverter (Logback)
  - Alerting (Não Só Logging)
- Dependency Security
  - OWASP Dependency Check
  - Keep Dependencies Updated
  - Pipeline CI/CD — Etapas Obrigatórias
- Security Headers

---

## Mishandling of Exceptional Conditions (A10:2025)

### ProblemDetail — Padrão RFC 9457 (Spring Boot 3+)

```java
// ✅ GOOD: @ControllerAdvice global com ProblemDetail (RFC 9457)
@RestControllerAdvice
public class GlobalExceptionHandler extends ResponseEntityExceptionHandler {

    @ExceptionHandler(AccessDeniedException.class)
    public ProblemDetail handleAccessDenied(AccessDeniedException ex, HttpServletRequest request) {
        log.warn("Access denied", kv("path", request.getRequestURI()), kv("reason", ex.getMessage()));
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.FORBIDDEN, "Access denied");
        problem.setType(URI.create("https://errors.mycompany.com/access-denied"));
        return problem;
    }

    @ExceptionHandler(PaymentValidationException.class)
    public ProblemDetail handlePaymentError(PaymentValidationException ex) {
        log.warn("Payment validation failed", kv("reason", ex.getReason()), kv("orderId", ex.getOrderId()));
        return ProblemDetail.forStatusAndDetail(HttpStatus.UNPROCESSABLE_ENTITY,
                "Payment could not be processed");
    }

    // ❌ BAD: nunca expor detalhes internos
    // return ResponseEntity.status(500).body(e.toString()); // Stack trace leak!
}
```

### Quarkus — Exception Mapper

```java
// Quarkus equivalente
@Provider
public class GlobalExceptionMapper implements ExceptionMapper<Exception> {

    @Override
    public Response toResponse(Exception exception) {
        log.error("Unhandled exception", exception);
        return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                .entity(new ErrorResponse("An error occurred"))
                .build();
    }
}
```

---

## Logging & Alerting (A09:2025)

### Log de Eventos de Segurança

```java
// ✅ Logar eventos relevantes de segurança
log.info("User login successful",kv("userId", userId),kv("ip",clientIp));
        log.

warn("Failed login attempt",kv("username", username),kv("ip",clientIp),

kv("attempt",attemptCount));
        log.

warn("Access denied",kv("userId", userId),kv("resource",resourceId));
        log.

error("Authentication failure",kv("reason", reason),kv("ip",clientIp));

// ❌ NEVER log sensitive data
        log.

info("Login: user={}, password={}",username, password);  // NUNCA!
```

### PII Masking — MaskingConverter (Logback)

```java
// ✅ GOOD: Custom MaskingConverter para Logback
public class SensitiveDataMaskingConverter extends ClassicConverter {

    private static final Pattern CPF_PATTERN = Pattern.compile("\\d{3}\\.\\d{3}\\.\\d{3}-\\d{2}");
    private static final Pattern EMAIL_PATTERN = Pattern.compile("[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}");
    private static final Pattern CARD_PATTERN = Pattern.compile("\\b(?:\\d[ -]?){13,16}\\b");

    @Override
    public String convert(ILoggingEvent event) {
        String message = event.getFormattedMessage();
        message = CPF_PATTERN.matcher(message).replaceAll("***.***.***-**");
        message = EMAIL_PATTERN.matcher(message).replaceAll("***@***.***");
        message = CARD_PATTERN.matcher(message).replaceAll("****-****-****-****");
        return message;
    }
}
```

```xml
<!-- logback-spring.xml -->
<conversionRule conversionWord="mask" converterClass="com.example.SensitiveDataMaskingConverter"/>
<pattern>%d{HH:mm:ss} [%thread] %-5level %logger{36} - %mask%n</pattern>
```

### Alerting (Não Só Logging)

A09:2025 é "Logging **& Alerting** Failures" — registrar o log não basta se ninguém é notificado. Configure alertas
automáticos para:

| Evento                 | Threshold      | Destino                         |
|------------------------|----------------|---------------------------------|
| Login failures         | > 5/min por IP | SIEM / PagerDuty                |
| 5xx errors             | > baseline     | Prometheus Alertmanager         |
| Privilege escalation   | Qualquer       | SIEM (ELK + Wazuh / OpenSearch) |
| Dependency CVE crítico | CVSS ≥ 9       | Slack / email                   |

---

## Dependency Security

### OWASP Dependency Check

```xml

<plugin>
    <groupId>org.owasp</groupId>
    <artifactId>dependency-check-maven</artifactId>
    <version>12.2.2</version>
    <executions>
        <execution>
            <goals>
                <goal>check</goal>
            </goals>
        </execution>
    </executions>
    <configuration>
        <failBuildOnCVSS>7</failBuildOnCVSS>
    </configuration>
</plugin>
```

```bash
mvn dependency-check:check
# Report: target/dependency-check-report.html
```

### Keep Dependencies Updated

```bash
mvn versions:display-dependency-updates
mvn versions:use-latest-releases
```

### Pipeline CI/CD — Etapas Obrigatórias

```yaml
# Todas as etapas abaixo devem FALHAR o build se encontrarem problemas críticos
stages:
  - sast          # Semgrep, SpotBugs + FindSecBugs
  - sca           # OWASP Dependency Check (CVSS > 7 falha o build)
  - sbom          # CycloneDX generation
  - sign          # Cosign artifact signing
  - dast          # OWASP ZAP / Nuclei (ambiente de staging)
  - codeql        # GitHub CodeQL
```

---

## Security Headers

| Header                      | Valor Recomendado                     | Protege contra    |
|-----------------------------|---------------------------------------|-------------------|
| `Content-Security-Policy`   | `default-src 'self'`                  | XSS               |
| `X-Content-Type-Options`    | `nosniff`                             | MIME sniffing     |
| `X-Frame-Options`           | `DENY`                                | Clickjacking      |
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` | Downgrade HTTPS   |
| `X-XSS-Protection`          | `1; mode=block`                       | Legacy XSS filter |
| `Permissions-Policy`        | `geolocation=(), microphone=()`       | Feature abuse     |

```java

@Bean
public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
    http.headers(headers -> headers
            .contentSecurityPolicy(csp -> csp.policyDirectives("default-src 'self'"))
            .frameOptions(frame -> frame.deny())
            .httpStrictTransportSecurity(hsts -> hsts
                    .maxAgeInSeconds(31536000)
                    .includeSubDomains(true))
            .contentTypeOptions(Customizer.withDefaults())
            .permissionsPolicy(policy -> policy.policy("geolocation=(), microphone=()"))
    );
    return http.build();
}
```

