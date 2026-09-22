# Segurança em Kotlin 2.4+ no Servidor JVM

Este documento detalha armadilhas, vulnerabilidades e padrões de mitigação específicos para aplicações backend
desenvolvidas em **Kotlin 2.4+** rodando sobre a **JVM** (com Spring Boot 4.1.1+, Spring MVC, Spring WebFlux, Ktor ou
Micronaut).

> [!IMPORTANT]
> **Escopo:** Exclusivo para backends JVM (serviços de API, workers, jobs e consumidores de mensageria).
> **Fora de escopo:** Android, Kotlin Multiplatform (KMP), Kotlin/Native, Kotlin/JS e Kotlin/Wasm.

---

## 1. Nulidade e Platform Types na Fronteira Java-Kotlin

Kotlin possui segurança de tipos nulos estrita em tempo de compilação. No entanto, quando interage com bibliotecas Java
(incluindo o próprio ecossistema Spring Framework e JDBC), os tipos retornados são **Platform Types** (notados
internamente como `T!`).

### O Risco

Se uma chamada Java retorna `null` para uma variável tipada em Kotlin como não-nula, o compilador insere uma asserção
intrínseca (`Intrinsics.checkNotNull`). Se a asserção falhar em runtime, um `NullPointerException` é lançado
abruptamente. Em manipuladores de segurança ou decisões de autorização, isso pode causar negação de serviço (DoS) ou
comportamento de "fail-open" se exceções forem tratadas de forma frouxa.

### Mitigação

- Trate qualquer retorno de API Java como potencialmente nulo na fronteira de entrada.
- Utilize anotações de anotação de nulidade estrita (`@NonNull`, `@Nullable` do Jakarta ou JSpecify).
- Ative o flag de compilação `-Xjsr305=strict` nas opções do compilador Kotlin.

```kotlin
// ❌ BAD: Confiança cega em retorno Java (lança NPE abrupto se ausente)
fun processOrder(orderId: String) {
    val order = javaOrderRepository.findOrder(orderId) // Tipo retornado: Order!
    // Se order for null, a linha abaixo explode em tempo de execução
    val total = order.amount
}

// ✅ GOOD: Tratar como anulável na fronteira ou usar operador seguro
fun processOrderSafe(orderId: String) {
    val order: Order? = javaOrderRepository.findOrder(orderId)
    if (order == null) {
        throw ResourceNotFoundException("Pedido $orderId não encontrado")
    }
    val total = order.amount
}
```

Configuração no `build.gradle.kts`:

```kotlin
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions {
        freeCompilerArgs.addAll("-Xjsr305=strict", "-all-warnings-as-errors")
    }
}
```

---

## 2. Alvos de Anotação (Annotation Use-Site Targets) e Bean Validation

Ao aplicar Bean Validation (Jakarta Validation / JSR 380) em classes Kotlin, uma propriedade declarada no construtor
primário gera múltiplos elementos bytecode: um parâmetro de construtor, um campo (*field*) e um método getter.

### O Risco

Se você anotar a propriedade sem especificar o alvo (`use-site target`), o compilador Kotlin anota o **parâmetro do
construtor**, mas os frameworks de validação (como Hibernate Validator no Spring Boot) inspecionam o **getter** ou o
**campo**. Como resultado, **a validação é silenciosamente ignorada**.

```kotlin
// ❌ BAD: A anotação vai para o construtor; o Spring NÃO valida no controller!
data class CreateUserRequest(
    @NotNull
    @Size(min = 3, max = 50)
    val username: String,

    @Email
    val email: String
)

// ✅ GOOD: Uso explícito do alvo @field: ou @get:
data class CreateUserRequest(
    @field:NotBlank(message = "Username é obrigatório")
    @field:Size(min = 3, max = 50, message = "Username deve ter entre 3 e 50 caracteres")
    @field:Pattern(regexp = "^[a-zA-Z0-9_]+$", message = "Username contém caracteres inválidos")
    val username: String,

    @field:NotBlank(message = "Email é obrigatório")
    @field:Email(message = "Email em formato inválido")
    val email: String
)
```

---

## 3. Data Classes, Records, `copy()` e Exposição em Logs

### Vazamento de Dados Sensíveis no `toString()`

O compilador Kotlin gera automaticamente uma implementação de `toString()` para toda `data class`, incluindo todos os
campos declarados no construtor primário. Se a classe contiver credenciais, tokens, senhas ou PII, o simples envio do
objeto para um log (`logger.info("Processando: $user")`) vazará os dados em texto claro.

```kotlin
// ❌ BAD: toString() gerado automaticamente expõe senhas e PII
data class UserCredentials(
    val username: String,
    val passwordHash: String,
    val apiKey: String,
    val cpf: String
)

// ✅ GOOD: Sobrescrever toString() explicitamente ou ocultar campos sensíveis
data class UserCredentials(
    val username: String,
    val passwordHash: String,
    val apiKey: String,
    val cpf: String
) {
    override fun toString(): String =
        "UserCredentials(username='$username', passwordHash='[PROTECTED]', apiKey='[PROTECTED]', cpf='***')"
}
```

### Bypass de Validação via Método `copy()`

Data classes possuem o método `copy()`. Se você adicionou validações em blocos `init { ... }`, o método `copy()` do
Kotlin chama diretamente o construtor padrão e pode bypassar regras de negócio se construído incorretamente com
parâmetros alterados.
Para DTOs e Value Objects imutáveis críticos de segurança, considere classes normais com construtor privado e funções de
fábrica com validação garantida.

---

## 4. Serialização e Desserialização Segura

### Jackson 3 (`tools.jackson` / `com.fasterxml.jackson`)

No Spring Boot 4.1.1+, ao trabalhar com Kotlin, garanta que o módulo de serialização esteja configurado sem suporte a
default typing aberto:

```kotlin
@Configuration
class JacksonSecurityConfig {

    @Bean
    fun objectMapper(): ObjectMapper {
        return JsonMapper.builder()
            .disable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES)
            // Impede ataques de deserialização polimórfica (gadget chains)
            .deactivateDefaultTyping()
            .addModule(kotlinModule())
            .build()
    }
}
```

### kotlinx.serialization

Se o projeto utilizar `kotlinx.serialization`:

- A serialização em `kotlinx.serialization` é segura por design contra gadget chains desconhecidos porque os
  serializadores são gerados em tempo de compilação.
- No entanto, ao usar polimorfismo aberto, restrinja expressamente as subclasses registradas:

```kotlin
// ✅ GOOD: Serializadores polimórficos estritamente selados
@Serializable
sealed interface PaymentCommand {
    @Serializable
    @SerialName("credit_card")
    data class CreditCardPayment(val token: String, val amountCents: Long) : PaymentCommand

    @Serializable
    @SerialName("pix")
    data class PixPayment(val pixKey: String, val amountCents: Long) : PaymentCommand
}
```

---

## 5. Coroutines e Propagação de Contexto de Segurança

Em backends reativos (Spring WebFlux com coroutines e Ktor), as coroutines suspendem e retomam a execução em threads
diferentes da pool (`Dispatchers.Default` ou `Dispatchers.IO`).

### O Risco de Perda do SecurityContext

O Spring Security tradicionalmente armazena a autenticação em `ThreadLocal` via `SecurityContextHolder`. Quando uma
coroutine suspende (ex.: numa chamada assíncrona ou acesso a banco com R2DBC), o `ThreadLocal` da thread anterior **não
é transferido automaticamente** para a nova thread de execução.

Se o código subsequente consultar `SecurityContextHolder.getContext().authentication`, o retorno será **null** ou, pior,
a autenticação de outra requisição concorrente que utilizou a mesma thread!

### Mitigação

1. Utilize o módulo `spring-security-reactive` e integre o contexto reativo com as coroutines:

```kotlin
import kotlinx.coroutines.reactor.awaitSingle
import org.springframework.security.core.context.ReactiveSecurityContextHolder
import org.springframework.security.core.Authentication

// ✅ GOOD: Obter autenticação a partir do contexto reativo compatível com coroutines
suspend fun getCurrentUser(): Authentication {
    return ReactiveSecurityContextHolder.getContext()
        .map { it.authentication }
        .awaitSingle()
}
```

2. Se precisar propagar manualmente o contexto entre despachantes:

```kotlin
import kotlinx.coroutines.withContext
import org.springframework.security.core.context.SecurityContextHolder

suspend fun <T> withSecurityContext(block: suspend () -> T): T {
    val securityContext = SecurityContextHolder.getContext()
    return withContext(Dispatchers.IO) {
        val previous = SecurityContextHolder.getContext()
        try {
            SecurityContextHolder.setContext(securityContext)
            block()
        } finally {
            SecurityContextHolder.setContext(previous)
        }
    }
}
```

### Anti-Patterns Críticos em Coroutines

1. **`GlobalScope.launch` no Handler HTTP:** Quebra o ciclo de vida da requisição, escapa dos limites de timeout e
   continua executando mesmo se o cliente desconectar (potencial DoS e exaustão de conexões).
2. **Engolir `CancellationException`:**
   ```kotlin
   // ❌ CRITICAL: Destrói o mecanismo de cancelamento de coroutines!
   try {
       callExternalService()
   } catch (e: Exception) { // Captura CancellationException e ignora
       logger.error("Falha", e)
   }

   // ✅ GOOD: Repropagar CancellationException imediatamente
   try {
       callExternalService()
   } catch (e: CancellationException) {
       throw e // Obrigatório para liberação de recursos
   } catch (e: Exception) {
       logger.error("Falha de negócio", e)
   }
   ```

---

## 6. Proxies, Spring AOP e o Plugin `kotlin-spring`

Em Kotlin, **todas as classes e métodos são `final` por padrão**.
O Spring Framework utiliza proxies CGLIB para aplicar aspectos fundamentais de segurança e transação:

- `@PreAuthorize`, `@PostAuthorize`, `@Secured`, `@RolesAllowed`
- `@Transactional`
- `@Cacheable`

### O Risco

Se o plugin `kotlin-spring` (ou o plugin `allopen`) não estiver aplicado no build do projeto:

1. O Spring não consegue criar o proxy da classe ou sobrescrever o método anotado.
2. O método protegido por `@PreAuthorize("hasRole('ADMIN')")` é executado **sem nenhuma checagem de autorização**,
   permitindo bypass completo de controle de acesso (BFLA)!

### Mitigação

Verifique obrigatoriamente se o plugin `kotlin-spring` está configurado no `build.gradle.kts` ou `pom.xml`:

```kotlin
// build.gradle.kts
plugins {
    kotlin("jvm") version "2.4.20"
    kotlin("plugin.spring") version "2.4.20" // Abre classes e métodos automaticamente para AOP
}
```

Para Maven:

```xml
<plugin>
    <groupId>org.jetbrains.kotlin</groupId>
    <artifactId>kotlin-maven-plugin</artifactId>
    <configuration>
        <compilerPlugins>
            <plugin>spring</plugin>
        </compilerPlugins>
    </configuration>
    <dependencies>
        <dependency>
            <groupId>org.jetbrains.kotlin</groupId>
            <artifactId>kotlin-maven-allopen</artifactId>
            <version>${kotlin.version}</version>
        </dependency>
    </dependencies>
</plugin>
```

### Armadilha de Auto-Invocação Interna (*Self-Invocation*)

Mesmo com a classe aberta, se um método do serviço chamar outro método da mesma classe diretamente
(`this.metodoProtegido()`), o proxy de segurança do Spring **não intercepta** a chamada.

```kotlin
@Service
class AccountService {

    // Chamada externa passa pelo proxy
    fun transfer(id: String) {
        // ...
        // ❌ BAD: Auto-invocação interna bypassa o @PreAuthorize de auditTransfer!
        auditTransfer(id)
    }

    @PreAuthorize("hasRole('COMPLIANCE')")
    fun auditTransfer(id: String) {
        // Checagem de segurança não é executada se chamada por transfer() internamente!
    }
}
```

---

## 7. Versionamento e Baseline Tecnológico

O Spring Boot 4.1.x gerencia por padrão dependências da linha Kotlin 2.3.x.
Em projetos adotando o baseline **Kotlin 2.4+**, é obrigatório sobrescrever a versão gerenciada:

No Gradle Kotlin DSL (`build.gradle.kts`):

```kotlin
plugins {
    id("org.springframework.boot") version "4.1.1"
    id("io.spring.dependency-management") version "1.1.7" // Se aplicável
    kotlin("jvm") version "2.4.20"
    kotlin("plugin.spring") version "2.4.20"
}
```

No Maven (`pom.xml`):

```xml
<properties>
    <kotlin.version>2.4.20</kotlin.version>
</properties>
```
