# Spring Boot 4.1.1+ — Hardening e Recursos Específicos do Framework

Este documento detalha práticas de hardening exclusivas e novos recursos de segurança introduzidos no **Spring Boot
4.1.1+**, **Spring Framework 7** e **Spring Security 7.1**.

---

## Índice

1. [Diferenciação Estrita de Perfis (Default vs Dev vs Produção)](#1-diferenciação-estrita-de-perfis)
2. [Hardening Completo do Spring Boot Actuator](#2-hardening-completo-do-spring-boot-actuator)
3. [Clientes HTTP Modernos (RestClient e WebClient com SSRF Filter)](#3-clientes-http-modernos)
4. [Tratamento de Erros e Supressão de Diagnósticos Internos](#4-tratamento-de-erros-e-supressão-de-diagnósticos-internos)
5. [Observabilidade Segura com OpenTelemetry](#5-observabilidade-segura-com-opentelemetry)
6. [Testes Automatizados de Segurança](#6-testes-automatizados-de-segurança)

---

## 1. Diferenciação Estrita de Perfis

Configurações e utilitários convenientes durante o desenvolvimento local representam vulnerabilidades críticas se
carregados em produção.

### Itens Proibidos no Perfil de Produção:

1. **Spring Boot DevTools:** O DevTools (`spring-boot-devtools`) ativa live reload e desabilita caches de template.
   Garanta que seu escopo no build seja `developmentOnly` no Gradle ou `<optional>true</optional>` no Maven.
2. **H2 Console:** O console do banco H2 (`spring.h2.console.enabled=true`) permite execução arbitrária de comandos SQL
   no browser e bypassa autenticação.
3. **Endpoints de Debug ou Mocks de Autenticação:** Mock users, filtros de bypass de JWT ou endpoints `/test/**` devem
   existir estritamente sob `src/test/java`.

Configuração recomendada para `application-prod.yml`:

```yaml
spring:
  devtools:
    restart:
      enabled: false
  h2:
    console:
      enabled: false
server:
  error:
    include-message: never
    include-binding-errors: never
    include-stacktrace: never
    include-exception: false
```

---

## 2. Hardening Completo do Spring Boot Actuator

O Actuator expõe métricas e status operacional da aplicação. Se mal configurado, vaza variáveis de ambiente
(`/actuator/env`), senhas mascaradas, memória JVM (`/actuator/heapdump`), mapeamentos de rotas e conexões de rede.

### 4 Pilares de Hardening do Actuator em Produção:

1. **Porta Separada:** Isole o tráfego do Actuator em uma porta interna diferente da porta pública da API
   (`management.server.port`).
2. **Exposição Mínima:** Exponha estritamente o necessário (geralmente apenas `health`, `info`, `prometheus` e
   `metrics`). **Nunca use `include: "*"`**.
3. **Ocultação de Detalhes:** Configure `show-details: when_authorized` ou `never`.
4. **Proteção por Perfil/Role:** Exija perfil de administrador (`ROLE_OPS` ou `ROLE_ADMIN`).

```yaml
# application-prod.yml
management:
  server:
    port: 8081 # Porta isolada para tráfego de monitoramento interno
  endpoints:
    web:
      exposure:
        include: health, info, prometheus, metrics # Apenas endpoints operacionais
  endpoint:
    health:
      show-details: when_authorized
      probes:
        enabled: true
    env:
      enabled: false # Desabilita endpoint de variáveis de ambiente
    heapdump:
      enabled: false # Bloqueia dump de memória que conteria chaves e dados
    threaddump:
      enabled: false
```

Proteção na cadeia `SecurityFilterChain`:

```java
http.authorizeHttpRequests(auth -> auth
    // Probes do Kubernetes públicos apenas na porta de management
    .requestMatchers(EndpointRequest.to("health")).permitAll()
    // Métricas protegidas para o scraper do Prometheus
    .requestMatchers(EndpointRequest.to("prometheus", "metrics", "info")).hasRole("MONITORING")
    .requestMatchers(EndpointRequest.toAnyEndpoint()).hasRole("ADMIN")
);
```

---

## 3. Clientes HTTP Modernos

No Spring Boot 4.1.x, o `RestClient` é o cliente síncrono padrão recomendado em substituição ao clássico `RestTemplate`.
Para reatividade ou coroutines, utiliza-se `WebClient`.

### Mitigação Nativa de SSRF com `InetAddressFilter`

Configure o interceptor de segurança no builder global do `RestClient`:

```java
@Configuration
public class OutboundHttpConfig {

    @Bean
    public RestClient restClient(RestClient.Builder builder) {
        return builder
            .requestInterceptor(new InetAddressFilter()) // Bloqueia IPs privados, loopback e metadados AWS/GCP
            .build();
    }
}
```

---

## 4. Tratamento de Erros e Supressão de Diagnósticos Internos

Por padrão, em caso de erro 4xx ou 5xx sem interceptor customizado, o Spring Boot pode emitir a página "Whitelabel Error
Page".
Certifique-se de que a página padrão esteja desabilitada e que os erros sejam traduzidos exclusivamente pelo
`@RestControllerAdvice` formatando em `ProblemDetail` (RFC 9457):

```yaml
server:
  error:
    whitelabel:
      enabled: false
```

---

## 5. Observabilidade Segura com OpenTelemetry

Ao propagar dados para ferramentas de APM (Grafana, Jaeger, Datadog), garanta que atributos de segurança não contenham
segredos nem dados PII desprotegidos:

```java
@Component
public class SecuritySpanCustomizer implements OncePerRequestFilter {

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth != null && auth.isAuthenticated()) {
            Span currentSpan = Span.current();
            // Registra apenas o identificador anônimo do usuário
            currentSpan.setAttribute("enduser.id", auth.getName());
            currentSpan.setAttribute("enduser.role", auth.getAuthorities().toString());
            // NUNCA adicione tokens, emails ou CPFs como atributos de span!
        }
        filterChain.doFilter(request, response);
    }
}
```

---

## 6. Testes Automatizados de Segurança

Garanta que toda regra de segurança e controle de acesso possua testes automatizados unitários e de integração
(`@WebMvcTest` ou `@SpringBootTest`).

### Testando `@PreAuthorize` e Roles com MockMvc

```java
@WebMvcTest(TransferController.class)
class TransferControllerSecurityTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    @WithMockUser(username = "operador", roles = {"FINANCE_OPERATOR"})
    void shouldAllowTransferWhenUserHasRequiredRole() throws Exception {
        mockMvc.perform(post("/v1/transfers")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    { "destinationAccountId": "acc-123", "amountCents": 5000 }
                """))
            .andExpect(status().isOk());
    }

    @Test
    @WithMockUser(username = "comum", roles = {"USER"})
    void shouldDenyTransferWhenUserLacksRequiredRole() throws Exception {
        mockMvc.perform(post("/v1/transfers")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    { "destinationAccountId": "acc-123", "amountCents": 5000 }
                """))
            .andExpect(status().isForbidden()); // Garante que @PreAuthorize bloqueia
    }

    @Test
    void shouldReturnUnauthorizedWhenAnonymous() throws Exception {
        mockMvc.perform(post("/v1/transfers"))
            .andExpect(status().isUnauthorized()); // Garante deny-by-default
    }
}
```
