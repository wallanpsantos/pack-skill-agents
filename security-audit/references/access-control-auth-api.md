# Controle de Acesso, Autenticação e API Security (A01/A07:2025)

Cobre CSRF, autenticação/autorização (senhas, BOLA/IDOR, JWT, rate limiting) e boas práticas de exposição de API REST.
Válido para Spring Boot, Quarkus, Jakarta EE e Java puro.

## Conteúdo
- CSRF Protection
  - Spring Security
  - Quarkus
  - CORS vs CSRF: Common Misconceptions
- Authentication & Authorization
  - Password Storage
  - Authorization — Proteção contra BOLA/IDOR
  - Spring Security Annotations
  - JWT Security — OAuth2 Resource Server
  - Rate Limiting & Brute Force Protection
- API Security (REST)
  - OpenAPI/Swagger — Não Expor Schemas Sensíveis
  - Proteção BOLA/IDOR
  - Validação de JWT com Resource Server

---

## CSRF Protection

### Spring Security

```java

@Bean
public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
    http
            // REST APIs com JWT (stateless) — pode desabilitar
            .csrf(csrf -> csrf.disable())

            // Browser apps com sessão — manter CSRF habilitado
            .csrf(csrf -> csrf
                    .csrfTokenRepository(CookieCsrfTokenRepository.withHttpOnlyFalse())
            );
    return http.build();
}
```

> Warning: Only disable CSRF if the API is 100% stateless (no session cookies) and authentication is performed via
> `Authorization: Bearer`. If there is any cookie-based workflow, keep CSRF enabled.

### Quarkus

```properties
quarkus.http.csrf.enabled=true
quarkus.http.csrf.cookie-name=XSRF-TOKEN
```

### CORS vs CSRF: Common Misconceptions (A02/A01:2025)

| Mecanismo | Lado      | Protege contra                          | Observação                              |
|-----------|-----------|-----------------------------------------|-----------------------------------------|
| CORS      | Navegador | Leitura cross-origin de respostas       | Não é proteção server-side de segurança |
| CSRF      | Servidor  | Requisições forjadas em nome do usuário | Requer token ou SameSite cookies        |

> [!IMPORTANT]
> Configurar `Access-Control-Allow-Origin: *` com `Access-Control-Allow-Credentials: true` é crítico — permite que
qualquer origem leia dados autenticados do usuário. Sempre especifique domínios explícitos.

---

## Authentication & Authorization (A07:2025)

### Password Storage

```java
// ✅ GOOD: DelegatingPasswordEncoder (Spring Security — recomendado)
PasswordEncoder encoder = PasswordEncoderFactories.createDelegatingPasswordEncoder();
String hash = encoder.encode(rawPassword);

// Argon2 direto (para novos projetos)
PasswordEncoder encoder = new Argon2PasswordEncoder(16, 32, 1, 65536, 10);

// ❌ BAD: MD5, SHA1, SHA256 sem salt — NUNCA para senhas!
```

### Authorization — Proteção contra BOLA/IDOR

```java
// ✅ GOOD: Verificação de ownership no service layer (protege contra BOLA/IDOR)
@Service
public class DocumentService {

    public Document getDocument(Long documentId, User currentUser) {
        Document doc = documentRepository.findById(documentId)
                .orElseThrow(() -> new NotFoundException("Document not found"));

        // Checa se o recurso pertence ao usuário autenticado
        if (!doc.getOwnerId().equals(currentUser.getId()) &&
                !currentUser.hasRole("ADMIN")) {
            throw new AccessDeniedException("Not authorized");
        }
        return doc;
    }
}

// ❌ BAD: Apenas verificação no controller — confia no ID do usuário
@GetMapping("/documents/{id}")
public Document getDocument(@PathVariable Long id) {
    return documentRepository.findById(id).orElseThrow(); // Sem auth check!
}
```

### Spring Security Annotations

```java

@PreAuthorize("hasRole('ADMIN')")
public void adminOnly() {
}

@PreAuthorize("hasRole('USER') and #userId == authentication.principal.id")
public void ownDataOnly(Long userId) {
}

// Quarkus
@RolesAllowed("ADMIN")
public void adminOnly() {
}

@RolesAllowed({"USER", "MODERATOR"})
public void restrictedOp() {
}
```

### JWT Security — OAuth2 Resource Server (Spring Boot 4.1+)

```java
// ✅ GOOD: spring-boot-starter-oauth2-resource-server (recomendado)
// Configura validação de JWT automaticamente (iss, aud, exp, alg)

// application.yml
spring:
security:
oauth2:
resourceserver:
jwt:
issuer-uri:https://auth.mycompany.com
audiences:my-api

// ❌ BAD: Parser sem fixar algoritmo (aceita "none")
Jwts.

parserBuilder().

build().

parseClaimsJws(token);

// ✅ GOOD: Parser fixando algoritmo e claims obrigatórias
Jwts.

parserBuilder()
    .

setSigningKey(signingKey)
    .

requireIssuer("https://auth.mycompany.com")
    .

requireAudience("my-api")
    .

build()
    .

parseClaimsJws(token);
```

### Rate Limiting & Brute Force Protection

Além do Bucket4j (application-level), considere também:

- **Spring Cloud Gateway Rate Limiter** — para cenários de API Gateway
- **Resilience4j RateLimiter** — integrado com Spring Boot Actuator e observability

```xml

<properties>
    <bucket4j.version>8.19.0</bucket4j.version>
</properties>

<dependency>
<groupId>com.bucket4j</groupId>
<artifactId>bucket4j_jdk17-core</artifactId>
<version>${bucket4j.version}</version>
</dependency>
```

```java

@Component
public class RateLimitingFilter extends OncePerRequestFilter {

    private final Map<String, Bucket> cache = new ConcurrentHashMap<>();

    private Bucket createNewBucket() {
        return Bucket.builder()
                .addLimit(Bandwidth.classic(100, Refill.intervally(100, Duration.ofMinutes(1))))
                .build();
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        var clientIp = request.getRemoteAddr();
        var bucket = cache.computeIfAbsent(clientIp, k -> createNewBucket());

        if (bucket.tryConsume(1)) {
            filterChain.doFilter(request, response);
        } else {
            response.setStatus(HttpStatus.TOO_MANY_REQUESTS.value());
            response.setContentType(MediaType.APPLICATION_JSON_VALUE);
            response.setHeader("Retry-After", "60");
            response.getWriter().write("""
                    {
                        "status": 429,
                        "error": "Too Many Requests",
                        "message": "Rate limit exceeded. Try again in 60 seconds."
                    }
                    """);
        }
    }
}
```

> [!WARNING]
> No componente `RateLimitingFilter`, a instrução `var clientIp = request.getRemoteAddr();` assume que a aplicação
recebe tráfego direto do cliente. Em ambientes reais de Cloud/Kubernetes, o `getRemoteAddr()` frequentemente retornará o
IP do Load Balancer, Ingress Controller ou Proxy Reverso, correndo o risco de bloquear todo o tráfego legítimo em caso
de ataque.
>
> **Recomendação para Produção:**
> 1. Extraia o IP real do cliente a partir do cabeçalho HTTP `X-Forwarded-For` (garantindo que sua aplicação esteja
     configurada para aceitar apenas proxies confiáveis, evitando spoofing desse header).
> 2. Se a rota for autenticada, utilize o identificador exclusivo do usuário extraído do próprio token JWT (ex: `sub` ou
     `username`) como chave no cache do limitador.


---

## API Security (REST)

### OpenAPI/Swagger — Não Expor Schemas Sensíveis

```java
// ✅ GOOD: Ocultar campos sensíveis no schema OpenAPI
public class UserResponse {

    public String username;

    @Schema(hidden = true) // Não expõe no Swagger UI
    public String internalId;

    @JsonProperty(access = JsonProperty.Access.WRITE_ONLY) // Aceita na entrada, nunca serializa na saída
    public String password;
}

// ✅ GOOD: Desabilitar Swagger em produção
@ConditionalOnExpression("${springdoc.swagger-ui.enabled:false}")
@Configuration
public class OpenApiConfig { ...
}
```

```yaml
# application-prod.yml
springdoc:
  swagger-ui:
    enabled: false
  api-docs:
    enabled: false
```

### Proteção BOLA/IDOR (Broken Object Level Authorization)

Além de `@PreAuthorize`, implemente verificação de ownership consistentemente. Ver seção Authentication & Authorization
acima.

### Validação de JWT com Resource Server

Use `spring-boot-starter-oauth2-resource-server` em vez de parsear JWT manualmente. Ver seção JWT acima.

