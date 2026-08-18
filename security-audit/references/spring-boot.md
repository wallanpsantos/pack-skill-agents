# Spring Boot 4.1+ — Segurança Específica do Framework

Mudanças e recursos de segurança introduzidos no Spring Boot 4.1.x com impacto direto em AppSec. Consulte este arquivo
quando o código em revisão usar Spring Boot (`SecurityFilterChain`, `RestClient`/`WebClient`, Actuator).

## Conteúdo
- SecurityFilterChain — DSL moderna
- SSRF — Mitigação nativa com InetAddressFilter
- Actuator Hardening
- Observability + Security (OpenTelemetry)

---

## Spring Boot 4.1+ Specific Security

This section covers security-relevant changes and new features introduced in Spring Boot 4.1.x that directly impact
AppSec practices.

### SecurityFilterChain — Modern DSL

```java
// ✅ GOOD: Spring Boot 4.1+ modern SecurityFilterChain
@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers("/actuator/health", "/actuator/info").permitAll()
                        .requestMatchers("/actuator/**").hasRole("OPS")  // Actuator hardening
                        .anyRequest().authenticated()
                )
                .oauth2ResourceServer(oauth2 -> oauth2
                        .jwt(jwt -> jwt.jwtAuthenticationConverter(jwtAuthConverter()))
                )
                .sessionManagement(session -> session
                        .sessionCreationPolicy(SessionCreationPolicy.STATELESS)
                )
                .csrf(csrf -> csrf.disable()) // Stateless JWT — safe to disable
                .headers(headers -> headers
                        .contentSecurityPolicy(csp -> csp.policyDirectives("default-src 'self'"))
                        .frameOptions(frame -> frame.deny())
                        .httpStrictTransportSecurity(hsts -> hsts.maxAgeInSeconds(31536000))
                        .contentTypeOptions(Customizer.withDefaults())
                );
        return http.build();
    }
}
```

### SSRF Mitigation Nativa — InetAddressFilter (Spring Boot 4.1+)

Spring Boot 4.1 introduziu `InetAddressFilter` para bloquear requisições HTTP para endereços internos diretamente nos
clients gerenciados (RestClient, WebClient):

```java
// ✅ GOOD: RestClient com InetAddressFilter (Spring Boot 4.1+)
@Bean
public RestClient secureRestClient(RestClient.Builder builder) {
    return builder
            .requestInterceptor(new InetAddressFilter())  // Bloqueia loopback/private/link-local
            .build();
}

// InetAddressFilter bloqueia automaticamente:
// - 127.x.x.x (loopback)
// - 10.x.x.x / 192.168.x.x / 172.16-31.x.x (private)
// - 169.254.x.x (link-local / cloud metadata AWS, GCP, Azure)
```

### Actuator Hardening

```yaml
# application.yml — expor apenas o necessário
management:
  endpoints:
    web:
      exposure:
        include: health, info, metrics, prometheus
      # Nunca: include: "*"
  endpoint:
    health:
      show-details: when_authorized
  server:
    port: 8081  # Porta separada para actuator (isolar do tráfego público)
```

### Observability + Security (OpenTelemetry)

```java
// ✅ Propagar contexto de segurança em traces
@Component
public class SecurityObservabilityFilter extends OncePerRequestFilter {

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain) throws IOException, ServletException {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth != null) {
            Span.current()
                    .setAttribute("enduser.id", auth.getName())
                    .setAttribute("enduser.role", auth.getAuthorities().toString());
        }
        chain.doFilter(request, response);
    }
}
```

