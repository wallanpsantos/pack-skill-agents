# Resiliência, Tratamento de Exceções e Observabilidade Segura (A09/A10:2025)

Este documento detalha o princípio de **Fail-Closed**, o tratamento centralizado de erros com **`ProblemDetail` (RFC
9457)**, boas práticas para **Virtual Threads** e **Mensageria**, mascaramento de dados sensíveis (**PII Masking**) e
configuração de **Security Headers**.

---

## Índice

1. [Princípio Fail-Closed em Decisões de Segurança](#1-princípio-fail-closed-em-decisões-de-segurança)
2. [Tratamento Padronizado de Erros com ProblemDetail (RFC 9457)](#2-tratamento-padronizado-de-erros-com-problemdetail)
3. [Timeouts, Circuit Breaker, Retries com Jitter e Backpressure](#3-timeouts-circuit-breaker-retries-e-backpressure)
4. [Virtual Threads no Java 25 LTS: Cuidados de Concorrência e Segurança](#4-virtual-threads-no-java-25-lts)
5. [Mensageria Assíncrona Segura (Kafka, RabbitMQ, SQS)](#5-mensageria-assíncrona-segura)
6. [Logging Estruturado e Mascaramento de PII](#6-logging-estruturado-e-mascaramento-de-pii)
7. [Alertas Automatizados e Integração com SIEM](#7-alertas-automatizados-e-integração-com-siem)
8. [Cabeçalhos de Segurança HTTP (Security Headers)](#8-cabeçalhos-de-segurança-http)

---

## 1. Princípio Fail-Closed em Decisões de Segurança

O princípio **Fail-Closed** determina que, na ocorrência de qualquer falha inesperada (exceção em filtro, timeout em
serviço de autenticação ou queda de conexão com banco de dados), o sistema deve **negar o acesso ou abortar a
operação**, nunca liberar a requisição por padrão (*fail-open*).

```java
// ❌ VULNERABLE (Fail-Open): Exceção inesperada libera o acesso
public boolean isAuthorized(User user, Resource resource) {
    try {
        return authorizationClient.checkPermission(user.getId(), resource.getId());
    } catch (Exception e) {
        log.error("Falha ao consultar servidor de autorização", e);
        return true; // PERIGO: Concede acesso se o serviço de permissão cair!
    }
}

// ✅ GOOD (Fail-Closed): Nega o acesso e lança exceção controlada
public boolean isAuthorized(User user, Resource resource) {
    try {
        return authorizationClient.checkPermission(user.getId(), resource.getId());
    } catch (Exception e) {
        log.error("Falha de comunicação no serviço de autorização", e);
        return false; // Sempre nega em caso de anomalia
    }
}
```

---

## 2. Tratamento Padronizado de Erros com ProblemDetail

No **Spring Boot 4.1.1+** e **Spring Framework 7**, o formato padrão da indústria para erros HTTP é o **RFC 9457 (
`ProblemDetail`)**.
Nunca vaze stack traces, nomes de tabelas, queries SQL, IPs internos ou mensagens cruas de exceção para o cliente.

```java
// ✅ GOOD: Centralizador global de exceções sem vazamento de detalhes internos
@RestControllerAdvice
public class GlobalExceptionHandler extends ResponseEntityExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(AccessDeniedException.class)
    public ProblemDetail handleAccessDenied(AccessDeniedException ex, HttpServletRequest request) {
        log.warn("Acesso negado para a URI: {}", request.getRequestURI());
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
            HttpStatus.FORBIDDEN,
            "Você não possui permissão para acessar o recurso solicitado."
        );
        problem.setType(URI.create("https://api.empresa.com.br/errors/access-denied"));
        problem.setProperty("timestamp", Instant.now());
        return problem;
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ProblemDetail handleValidationException(MethodArgumentNotValidException ex) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
            HttpStatus.UNPROCESSABLE_ENTITY,
            "Dados de entrada inválidos."
        );
        problem.setType(URI.create("https://api.empresa.com.br/errors/validation-failed"));

        Map<String, String> fieldErrors = ex.getBindingResult().getFieldErrors().stream()
            .collect(Collectors.toMap(
                FieldError::getField,
                fe -> fe.getDefaultMessage() != null ? fe.getDefaultMessage() : "Inválido",
                (existing, replacement) -> existing
            ));

        problem.setProperty("invalidParams", fieldErrors);
        return problem;
    }

    @ExceptionHandler(Exception.class)
    public ProblemDetail handleUnexpectedException(Exception ex) {
        // Registra o erro completo com stack trace apenas no log seguro interno
        String errorId = UUID.randomUUID().toString();
        log.error("Erro interno não tratado [ErrorId: {}]", errorId, ex);

        // Retorna mensagem genérica opaca para o cliente externo
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
            HttpStatus.INTERNAL_SERVER_ERROR,
            "Ocorreu um erro interno. Entre em contato com o suporte informando o identificador: " + errorId
        );
        problem.setType(URI.create("https://api.empresa.com.br/errors/internal-error"));
        problem.setProperty("errorId", errorId);
        return problem;
    }
}
```

---

## 3. Timeouts, Circuit Breaker, Retries e Backpressure

A indisponibilidade ou lentidão de dependências externas pode esgotar pools de conexões e threads da aplicação, causando
negação de serviço em cascata.

### Diretrizes de Auditoria

- Toda chamada HTTP ou RPC deve ter **timeouts explícitos de conexão e leitura** (máximo 2 a 5 segundos para serviços
  síncronos).
- Retries devem utilizar **exponential backoff com jitter aleatório** para evitar o problema de *thundering herd*.
- Utilize **Resilience4j Circuit Breaker** para isolar dependências com falha contínua.

```yaml
# application.yml — Configuração segura do Resilience4j
resilience4j:
  circuitbreaker:
    instances:
      paymentGateway:
        slidingWindowSize: 20
        failureRateThreshold: 50
        waitDurationInOpenState: 10s
        permittedNumberOfCallsInHalfOpenState: 5
  timelimiter:
    instances:
      paymentGateway:
        timeoutDuration: 3s
```

---

## 4. Virtual Threads no Java 25 LTS

Com Virtual Threads (`spring.threads.virtual.enabled: true`):

### 1. Prevenção de Thread Pinning

Em Java 21, blocos `synchronized` contendo operações de I/O bloqueante "pinavam" a carrier thread nativa da JVM. Embora
o Java 24 e 25 tenham substancialmente reduzido o pinning na especificação do runtime, é boa prática arquitetural
utilizar `ReentrantLock` para sincronizações que envolvam I/O de rede ou disco.

### 2. Limite de Concorrência com Semáforos

Virtual Threads são tão baratas que um loop descontrolado pode criar 100.000 threads disparando requisições contra um
banco de dados ou API externa. **Nunca use pools de threads para limitar concorrência em Virtual Threads; utilize
`Semaphore`**:

```java
// ✅ GOOD: Limite de concorrência estrito com Semaphore para Virtual Threads
@Component
public class ExternalServiceBulkhead {

    private final Semaphore semaphore = new Semaphore(50); // Máximo 50 requisições simultâneas

    public <T> T execute(Supplier<T> task) throws InterruptedException {
        if (!semaphore.tryAcquire(2, TimeUnit.SECONDS)) {
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS, "Serviço sobrecarregado");
        }
        try {
            return task.get();
        } finally {
            semaphore.release();
        }
    }
}
```

---

## 5. Mensageria Assíncrona Segura

Consumidores de eventos (Kafka, RabbitMQ, AWS SQS) recebem dados externos e devem ser auditados com o mesmo rigor dos
controllers HTTP:

1. **Validação de Schema:** Valide todo payload recebido contra classes com Bean Validation (`@Valid`).
2. **Idempotência:** Garanta que a mensagem possui um ID único e verifique se já foi processada antes de executar
   efeitos colaterais.
3. **Dead Letter Queue (DLQ):** Mensagens venenosas (malformadas ou que causam erros de negócio) devem ser encaminhadas
   para uma DLQ após N tentativas para não travar a partição.
4. **Propagação de Contexto de Auditoria:** Extraia cabeçalhos de rastreamento (`traceparent`, `X-Tenant-ID`,
   `X-User-ID`) e registre nos logs de consumo.

---

## 6. Logging Estruturado e Mascaramento de PII

### Mascaramento de Dados Pessoais e Segredos

Dados como CPF, números de cartão de crédito (PAN), CVV, senhas e chaves privadas **nunca** devem aparecer em texto
claro nos arquivos de log.

Configuração de conversor de mascaramento para **Logback** (`logback-spring.xml`):

```java
public class PiiMaskingConverter extends ClassicConverter {

    private static final Pattern CPF_PATTERN = Pattern.compile("\\b\\d{3}\\.?\\d{3}\\.?\\d{3}-?\\d{2}\\b");
    private static final Pattern CARD_PATTERN = Pattern.compile("\\b(?:\\d[ -]?){13,16}\\b");
    private static final Pattern EMAIL_PATTERN = Pattern.compile("\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}\\b");

    @Override
    public String convert(ILoggingEvent event) {
        String msg = event.getFormattedMessage();
        msg = CPF_PATTERN.matcher(msg).replaceAll("***.***.***-**");
        msg = CARD_PATTERN.matcher(msg).replaceAll("****-****-****-****");
        msg = EMAIL_PATTERN.matcher(msg).replaceAll("***@***.***");
        return msg;
    }
}
```

---

## 7. Alertas Automatizados e Integração com SIEM

O requisito **A09:2025** enfatiza a falha em alertar (*Alerting Failures*). Apenas gravar em log não previne incidentes.

### Eventos que Devem Disparar Alertas Imediatos no SIEM:

- **Pico de Autenticações Falhas:** > 10 falhas por minuto para o mesmo usuário ou mesmo IP de origem (ataque de força
  bruta / credential stuffing).
- **Acessos Negados Repetidos (403 Forbidden):** > 5 tentativas por minuto pelo mesmo usuário (indício de BOLA ou
  enumeração de privilégios).
- **Erros de Validação em Volume Anômalo (422/400):** Varredura automatizada com scanners ou fuzzers de API.
- **Detecção de Anomalias 5xx:** Erros não tratados acima da linha de base de produção.

---

## 8. Cabeçalhos de Segurança HTTP

Os cabeçalhos HTTP endurecem as defesas do cliente contra ataques de Clickjacking, MIME-Sniffing e XSS.

```java
// ✅ GOOD: Headers de segurança centralizados na SecurityFilterChain
http.headers(headers -> headers
    .contentSecurityPolicy(csp -> csp
        .policyDirectives("default-src 'none'; frame-ancestors 'none'; sandbox")
    )
    .frameOptions(frame -> frame.deny())
    .httpStrictTransportSecurity(hsts -> hsts
        .maxAgeInSeconds(31536000)
        .includeSubDomains(true)
        .preload(true)
    )
    .contentTypeOptions(Customizer.withDefaults())
    .permissionsPolicy(permissions -> permissions
        .policy("geolocation=(), camera=(), microphone=(), payment=()")
    )
);
```
