# Controle de Acesso, Autenticação e Segurança de APIs (A01/A07:2025, API Top 10:2023)

Este guia cobre a configuração estrita de controle de acesso, autenticação e mitigação de vulnerabilidades de API em
**Java 25 LTS** e **Kotlin 2.4+** com **Spring Boot 4.1.1+** (Spring Framework 7 e Spring Security 7.1), além de
princípios válidos para Quarkus e Jakarta EE.

---

## Índice

1. [Configuração de Cadeias de Filtro (SecurityFilterChain e SecurityWebFilterChain)](#1-configuração-de-cadeias-de-filtro)
2. [Autorização em Múltiplas Camadas (URL, Método, Objeto e Propriedade)](#2-autorização-em-múltiplas-camadas)
3. [Prevenção contra BOLA / IDOR e Multi-Tenancy](#3-prevenção-contra-bola--idor-e-multi-tenancy)
4. [Tokens, JWT, OAuth2 e OIDC (Resource Server)](#4-tokens-jwt-oauth2-e-oidc-resource-server)
5. [Armazenamento de Senhas e Credenciais](#5-armazenamento-de-senhas-e-credenciais)
6. [CSRF, CORS, Sessões e Cookies Seguros](#6-csrf-cors-sessões-e-cookies-seguros)
7. [Prevenção de Open Redirects](#7-prevenção-de-open-redirects)
8. [Rate Limiting, Idempotência e Abuso de Fluxo de Negócio](#8-rate-limiting-idempotência-e-abuso-de-fluxo-de-negócio)
9. [Inventário de APIs e Proteção contra Shadow APIs](#9-inventário-de-apis-e-proteção-contra-shadow-apis)

---

## 1. Configuração de Cadeias de Filtro

No Spring Security 7.1+, a configuração de segurança é declarada através de beans `SecurityFilterChain` (Spring MVC) ou
`SecurityWebFilterChain` (Spring WebFlux).

### Princípio do Deny-by-Default

Toda cadeia de segurança deve adotar o princípio do menor privilégio: **bloquear ou exigir autenticação por padrão para
qualquer requisição que não esteja explicitamente liberada**.

```java
// ✅ GOOD: Spring MVC com Spring Security 7.1 — Deny-by-default estrito
@Configuration
@EnableWebSecurity
@EnableMethodSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        return http
            .securityMatcher("/**")
            .authorizeHttpRequests(auth -> auth
                // Rotas estritamente públicas (expostas propositalmente)
                .requestMatchers(HttpMethod.GET, "/actuator/health/liveness", "/actuator/health/readiness").permitAll()
                .requestMatchers(HttpMethod.POST, "/v1/auth/login", "/v1/auth/refresh").permitAll()
                .requestMatchers(HttpMethod.POST, "/v1/webhooks/payments").permitAll() // Validado por assinatura HMAC
                // Rotas administrativas exigindo role específica
                .requestMatchers("/admin/**", "/actuator/**").hasRole("ADMIN")
                // Qualquer outra requisição exige autenticação obrigatória
                .anyRequest().authenticated()
            )
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt.jwtAuthenticationConverter(customJwtAuthenticationConverter()))
            )
            .sessionManagement(session -> session
                .sessionCreationPolicy(SessionCreationPolicy.STATELESS)
            )
            // CSRF desabilitado apenas porque a API é 100% stateless via Bearer Token (sem cookies)
            .csrf(csrf -> csrf.disable())
            .headers(headers -> headers
                .contentSecurityPolicy(csp -> csp.policyDirectives("default-src 'self'"))
                .frameOptions(frame -> frame.deny())
                .httpStrictTransportSecurity(hsts -> hsts.maxAgeInSeconds(31536000).includeSubDomains(true))
                .contentTypeOptions(Customizer.withDefaults())
            )
            .build();
    }
}
```

Para **Spring WebFlux (reativo com coroutines)**:

```kotlin
// ✅ GOOD: WebFlux SecurityWebFilterChain
@Configuration
@EnableWebFluxSecurity
@EnableReactiveMethodSecurity
class ReactiveSecurityConfig {

    @Bean
    fun springSecurityFilterChain(http: ServerHttpSecurity): SecurityWebFilterChain {
        return http
            .authorizeExchange { exchanges ->
                exchanges
                    .pathMatchers(HttpMethod.GET, "/health").permitAll()
                    .pathMatchers("/admin/**").hasAuthority("ROLE_ADMIN")
                    .anyExchange().authenticated()
            }
            .oauth2ResourceServer { it.jwt(Customizer.withDefaults()) }
            .csrf { it.disable() }
            .build()
    }
}
```

---

## 2. Autorização em Múltiplas Camadas

A autorização não pode depender apenas de regras na URL. Ataques do tipo **BFLA (Broken Function Level Authorization)**
e **BOPLA (Broken Object Property Level Authorization)** exploram a falta de verificações em camadas internas.

### Nível de Método (`@PreAuthorize` e `@Secured`)

Ative `@EnableMethodSecurity` e utilize SpEL rigoroso:

```java
// ✅ GOOD: Autorização por método com checagem de perfil e contexto
@Service
public class PayoutService {

    @PreAuthorize("hasRole('FINANCE_OPERATOR') and hasAuthority('SCOPE_payout:write')")
    public PayoutResult executePayout(PayoutCommand command) {
        // ...
    }

    @PreAuthorize("hasRole('ADMIN') or #tenantId == authentication.principal.claims['tenant_id']")
    public List<AuditRecord> listTenantAuditLogs(String tenantId) {
        // ...
    }
}
```

### Nível de Propriedade (Prevenção de Mass Assignment)

Nunca exponha a entidade JPA diretamente como parâmetro de entrada (`@RequestBody`) de um controller. Um atacante pode
enviar campos administrativos (`role`, `verified`, `balance`, `tenantId`) e sobrescrevê-los se o binding for automático.

```java
// ❌ BAD: Mass Assignment — entidade JPA exposta diretamente
@PostMapping("/users")
public User createUser(@RequestBody User user) {
    return userRepository.save(user); // Atacante pode enviar "role": "ADMIN" no payload!
}

// ✅ GOOD: DTO estrito de entrada sem campos de controle
public record CreateUserRequest(
    @NotBlank String fullName,
    @Email String email,
    @NotBlank String password
) {}

@PostMapping("/users")
public UserResponse createUser(@Valid @RequestBody CreateUserRequest request) {
    User user = new User(request.fullName(), request.email(), hashPassword(request.password()));
    user.setRole(Role.USER); // Força perfil padrão no código
    return UserResponse.from(userRepository.save(user));
}
```

---

## 3. Prevenção contra BOLA / IDOR e Multi-Tenancy

**BOLA (Broken Object Level Authorization)** ocorre quando um usuário legítimo acessa recursos de outro usuário
simplesmente alterando o identificador numérico ou UUID na rota (`/accounts/102` → `/accounts/103`).

### Regra Fundamental

Toda consulta a objeto privado **deve filtrar pelo identificador do usuário ou tenant autenticado no próprio SQL/JPQL**.

```java
// ❌ BAD: BOLA/IDOR — consulta busca apenas pelo ID recebido do cliente
@GetMapping("/contracts/{contractId}")
public Contract getContract(@PathVariable String contractId) {
    return contractRepository.findById(contractId)
        .orElseThrow(() -> new NotFoundException("Contrato não encontrado"));
}

// ✅ GOOD: Consulta garante propriedade através do principal autenticado
@GetMapping("/contracts/{contractId}")
public ContractResponse getContract(
    @PathVariable String contractId,
    @AuthenticationPrincipal Jwt principal
) {
    String currentUserId = principal.getSubject();
    String tenantId = principal.getClaimAsString("tenant_id");

    return contractService.getContractForUser(contractId, currentUserId, tenantId);
}

// No Repository:
public interface ContractRepository extends JpaRepository<Contract, String> {
    @Query("SELECT c FROM Contract c WHERE c.id = :id AND c.ownerId = :ownerId AND c.tenantId = :tenantId")
    Optional<Contract> findByIdAndOwnerAndTenant(
        @Param("id") String id,
        @Param("ownerId") String ownerId,
        @Param("tenantId") String tenantId
    );
}
```

---

## 4. Tokens, JWT, OAuth2 e OIDC (Resource Server)

Ao utilizar o `spring-boot-starter-oauth2-resource-server`, evite parsers manuais caseiros com bibliotecas genéricas de
JWT (como `jjwt` ou `nimbus`).

### Configuração Recomendada via `application.yml`

```yaml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: https://auth.empresa.com.br/oauth2/v1
          audiences: https://api.empresa.com.br
          jwk-set-uri: https://auth.empresa.com.br/oauth2/v1/jwks
```

### Validações Obrigatórias de Tokens

1. **Emissor (`iss`) e Audiência (`aud`):** Rejeite qualquer token cuja audiência não inclua o identificador deste
   serviço.
2. **Expiração (`exp`):** Exija claim de expiração obrigatória (`setAllowEmptyExpiryClaim(false)`).
3. **Algoritmo de Assinatura Fixo:** Fixe os algoritmos aceitos (ex.: `RS256`, `ES256`). Rejeite explicitamente tokens
   com algoritmo `none` ou chaves simétricas incompatíveis.
4. **Clock Skew Mínimo:** Defina a tolerância de clock skew para no máximo 30 a 60 segundos (o padrão do Spring é 60
   segundos).

```java
// ✅ GOOD: Customização de JwtDecoder com validações estritas
@Bean
public JwtDecoder jwtDecoder(OAuth2ResourceServerProperties properties) {
    NimbusJwtDecoder jwtDecoder = NimbusJwtDecoder.withJwkSetUri(properties.getJwt().getJwkSetUri())
        .jwsAlgorithms(algorithms -> {
            algorithms.add(SignatureAlgorithm.RS256);
            algorithms.add(SignatureAlgorithm.ES256);
        })
        .build();

    OAuth2TokenValidator<Jwt> defaultValidators = JwtValidators.createDefaultWithIssuer(properties.getJwt().getIssuerUri());
    OAuth2TokenValidator<Jwt> audienceValidator = new JwtClaimValidator<List<String>>(
        JwtClaimNames.AUD,
        aud -> aud != null && aud.contains("https://api.empresa.com.br")
    );

    DelegatingOAuth2TokenValidator<Jwt> combinedValidator =
        new DelegatingOAuth2TokenValidator<>(defaultValidators, audienceValidator);

    jwtDecoder.setJwtValidator(combinedValidator);
    return jwtDecoder;
}
```

---

## 5. Armazenamento de Senhas e Credenciais

Nunca utilize MD5, SHA-1, SHA-256 ou qualquer algoritmo de hash rápido para armazenar senhas. Esses algoritmos foram
projetados para integridade, não para proteção contra ataques de força bruta com GPUs.

```java
// ✅ GOOD: Argon2id via Spring Security (Recomendado para novos sistemas)
@Bean
public PasswordEncoder passwordEncoder() {
    // saltLength: 16 bytes, hashLength: 32 bytes, parallelism: 1, memory: 65536 KB, iterations: 3
    return new Argon2PasswordEncoder(16, 32, 1, 65536, 3);
}

// ✅ GOOD: DelegatingPasswordEncoder (Suporte a migração progressiva de hashes legados)
@Bean
public PasswordEncoder delegatingPasswordEncoder() {
    return PasswordEncoderFactories.createDelegatingPasswordEncoder();
}
```

---

## 6. CSRF, CORS, Sessões e Cookies Seguros

### CSRF (Cross-Site Request Forgery)

- **APIs REST Stateless:** Se a autenticação é realizada exclusivamente por cabeçalho HTTP
  `Authorization: Bearer <token>` e não utiliza cookies de sessão, desabilitar CSRF é aceitável
  (`http.csrf(csrf -> csrf.disable())`).
- **Aplicações com Cookies/Sessão:** Se a autenticação depender de cookies de sessão (`JSESSIONID`, tokens de sessão em
  cookies), **CSRF deve permanecer obrigatoriamente ativo**:
  ```java
  http.csrf(csrf -> csrf
      .csrfTokenRepository(CookieCsrfTokenRepository.withHttpOnlyFalse())
      .csrfTokenRequestHandler(new SpaCsrfTokenRequestHandler())
  );
  ```

### CORS (Cross-Origin Resource Sharing)

A configuração incorreta de CORS é uma das falhas mais frequentes em ambientes corporativos.

- **PROIBIDO:** `Access-Control-Allow-Origin: *` combinado com `Access-Control-Allow-Credentials: true`.
- Origens devem ser declaradas de forma explícita e restritiva:

```java
// ✅ GOOD: CORS com origens estritas
@Bean
public CorsConfigurationSource corsConfigurationSource() {
    CorsConfiguration configuration = new CorsConfiguration();
    configuration.setAllowedOrigins(List.of("https://app.empresa.com.br", "https://admin.empresa.com.br"));
    configuration.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "OPTIONS"));
    configuration.setAllowedHeaders(List.of("Authorization", "Content-Type", "Idempotency-Key"));
    configuration.setAllowCredentials(true);
    configuration.setMaxAge(3600L);

    UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/**", configuration);
    return source;
}
```

### Cookies Seguros

Em qualquer cookie de autenticação ou sessão:

- `Secure = true` (enviado exclusivamente por HTTPS).
- `HttpOnly = true` (inacessível para scripts JavaScript no browser, mitigando XSS).
- `SameSite = Strict` ou `Lax` (bloqueia envio em requisições cross-site de terceiros).

---

## 7. Prevenção de Open Redirects

Ao receber parâmetros de redirecionamento (como `returnUrl`, `redirect_uri` ou `target`), nunca faça o redirecionamento
cego para URLs informadas pelo cliente.

```java
// ❌ BAD: Open Redirect — redireciona para qualquer destino
@GetMapping("/login/callback")
public RedirectView redirectAfterLogin(@RequestParam String redirectUrl) {
    return new RedirectView(redirectUrl); // Atacante envia redirectUrl=https://phishing-site.com
}

// ✅ GOOD: Validação contra allowlist estrita de domínios confiáveis
private static final Set<String> ALLOWED_HOSTS = Set.of("app.empresa.com.br", "portal.empresa.com.br");

public RedirectView safeRedirect(String redirectUrl) {
    try {
        URI uri = new URI(redirectUrl).normalize();
        if (uri.getHost() == null || !ALLOWED_HOSTS.contains(uri.getHost().toLowerCase())) {
            return new RedirectView("/dashboard"); // Fallback seguro
        }
        return new RedirectView(uri.toString());
    } catch (URISyntaxException e) {
        return new RedirectView("/dashboard");
    }
}
```

---

## 8. Rate Limiting, Idempotência e Abuso de Fluxo de Negócio

### Rate Limiting por Usuário e IP

Endpoints de login, registro, geração de token, Pix, recuperação de senha e disparo de emails devem possuir limites de
taxa severos.

- No nível de API Gateway (Spring Cloud Gateway com Redis) ou via Bucket4j em microserviços.
- Extraia o IP real via cabeçalho `X-Forwarded-For` **apenas se a aplicação estiver atrás de um proxy reverso
  confiável**, ou use o `userId` em rotas autenticadas.

### Idempotência em Transações Críticas

Operações financeiras e de alteração de estado sensível devem exigir cabeçalho `Idempotency-Key` (UUIDv4) com
persistência atômica no Redis/banco para evitar reprocessamento acidental ou race conditions causadas por múltiplos
cliques/retries.

---

## 9. Inventário de APIs e Proteção contra Shadow APIs

A documentação OpenAPI (Swagger UI) exposta em ambientes de produção facilita a enumeração e o mapeamento de superfície
de ataque por agentes maliciosos.

```yaml
# application-prod.yml
springdoc:
  api-docs:
    enabled: false # Desabilita endpoint /v3/api-docs em produção
  swagger-ui:
    enabled: false # Desabilita UI /swagger-ui.html em produção
```

Se o Swagger precisar ser mantido acessível para desenvolvedores internos em ambientes externos, coloque a rota sob a
proteção obrigatória de `hasRole('DEVELOPER')` ou isole o acesso via VPN.
