# Validação de Entrada e Prevenção de Injeção (A05:2025)

Este documento detalha o tratamento seguro de entradas de dados e a prevenção contra todas as formas de injeção em
aplicações **Java 25 LTS** e **Kotlin 2.4+** no ecossistema Spring Boot 4.1.1+, Quarkus e Jakarta EE.

---

## Índice

1. [Bean Validation em Java e Kotlin (Jakarta Validation 3.1)](#1-bean-validation-em-java-e-kotlin)
2. [Injeção de SQL, JPQL e HQL](#2-injeção-de-sql-jpql-e-hql)
3. [Injeção em Bancos NoSQL (MongoDB)](#3-injeção-em-bancos-nosql-mongodb)
4. [Injeção de Comandos do Sistema Operacional](#4-injeção-de-comandos-do-sistema-operacional)
5. [Injeção de SpEL (Spring Expression Language)](#5-injeção-de-spel-spring-expression-language)
6. [XML External Entity (XXE) e Parsers XML](#6-xml-external-entity-xxe-e-parsers-xml)
7. [Injeção em Arquivos YAML (SnakeYAML e Jackson)](#7-injeção-em-arquivos-yaml-snakeyaml-e-jackson)
8. [Upload de Arquivos, Path Traversal e Zip Slip](#8-upload-de-arquivos-path-traversal-e-zip-slip)
9. [ReDoS (Regular Expression Denial of Service)](#9-redos-regular-expression-denial-of-service)
10. [Reflexão Dinâmica e Carregamento Inseguro de Classes](#10-reflexão-dinâmica-e-carregamento-inseguro-de-classes)

---

## 1. Bean Validation em Java e Kotlin

Toda requisição externa que cruzar a fronteira da aplicação (Controllers, Consumidores Kafka/RabbitMQ, Webhooks) deve
ser validada antes de qualquer processamento de negócio.

### Validação em Java 25 (Records)

```java
// ✅ GOOD: Record com validações de fronteira em Java 25
public record CreateAccountRequest(
    @NotBlank(message = "Documento é obrigatório")
    @Pattern(regexp = "\\d{11}|\\d{14}", message = "Documento deve conter 11 dígitos (CPF) ou 14 (CNPJ)")
    String documentNumber,

    @NotBlank
    @Size(min = 3, max = 100)
    String customerName,

    @NotNull
    @DecimalMin(value = "0.01", message = "O limite inicial deve ser positivo")
    BigDecimal initialCreditLimit,

    @Size(max = 10, message = "Máximo de 10 chaves Pix iniciais")
    List<@NotBlank @Size(max = 77) String> initialPixKeys
) {}
```

### Validação em Kotlin 2.4 (Data Classes com Use-Site Targets)

Em Kotlin, lembre-se sempre de utilizar o prefixo `@field:` ou `@get:` para que a anotação seja inspecionada pelo
validador:

```kotlin
// ✅ GOOD: Data class Kotlin com alvos de anotação explícitos
data class TransferRequest(
    @field:NotBlank(message = "ID de destino obrigatório")
    @field:UUID(message = "ID de destino deve ser um UUID válido")
    val destinationAccountId: String,

    @field:NotNull
    @field:Positive(message = "Valor da transferência deve ser positivo")
    val amountCents: Long,

    @field:Size(max = 140, message = "Descrição não pode exceder 140 caracteres")
    val description: String?
)
```

---

## 2. Injeção de SQL, JPQL e HQL

Consultas dinâmicas construídas por concatenação de strings ou interpolação de texto representam risco crítico de
injeção de SQL.

### Armadilha de Interpolação no Kotlin

```kotlin
// ❌ VULNERABLE: Interpolação de string Kotlin em consulta nativa
val query = entityManager.createNativeQuery(
    "SELECT * FROM accounts WHERE status = 'ACTIVE' AND account_number = '$accountNumber'"
)

// ✅ SECURE: Parâmetros vinculados (Binding Parameters)
val query = entityManager.createNativeQuery(
    "SELECT * FROM accounts WHERE status = 'ACTIVE' AND account_number = :accountNumber",
    Account::class.java
).setParameter("accountNumber", accountNumber)
```

### Spring Data JPA e `JdbcClient` (Spring Boot 4.1 / Spring 7)

```java
// ✅ GOOD: Spring Data JPA com binding explícito
@Query("SELECT a FROM Account a WHERE a.customer.id = :customerId AND a.currency = :currency")
List<Account> findAccountsByCustomer(
    @Param("customerId") String customerId,
    @Param("currency") String currency
);

// ✅ GOOD: JdbcClient moderno (Spring Framework 7)
public Optional<AccountRecord> findAccountById(String id) {
    return jdbcClient.sql("SELECT id, balance, status FROM accounts WHERE id = :id")
        .param("id", id)
        .query(AccountRecord.class)
        .optional();
}
```

---

## 3. Injeção em Bancos NoSQL (MongoDB)

Em MongoDB e Spring Data MongoDB, entradas não confiáveis passadas diretamente em consultas JSON ou expressões SpEL
podem resultar em injeção de NoSQL ou bypass de autenticação (ex.: envio de objetos como `{"$gt": ""}`).

```java
// ❌ VULNERABLE: String JSON concatenada em consulta MongoDB
String jsonQuery = "{ 'username': '" + userInput + "', 'status': 'ACTIVE' }";
BasicQuery query = new BasicQuery(jsonQuery);
List<UserDocument> users = mongoTemplate.find(query, UserDocument.class);

// ✅ GOOD: Uso de Criteria API tipada e segura do Spring Data MongoDB
Query query = new Query();
query.addCriteria(Criteria.where("username").is(userInput).and("status").is("ACTIVE"));
List<UserDocument> users = mongoTemplate.find(query, UserDocument.class);
```

---

## 4. Injeção de Comandos do Sistema Operacional

Nunca execute comandos do sistema operacional interpolando entrada do usuário em shells como `/bin/sh` ou `cmd.exe`.

```java
// ❌ VULNERABLE: Shell command injection
Runtime.getRuntime().exec("/bin/sh -c generate_report.sh " + userInput);

// ✅ GOOD: ProcessBuilder com argumentos separados em array (sem invocação de shell)
public void generateReport(String safeFilename) throws IOException {
    // Valida previamente o nome contra allowlist rigorosa
    if (!safeFilename.matches("^[a-zA-Z0-9_-]{1,64}\\.pdf$")) {
        throw new IllegalArgumentException("Nome de arquivo inválido");
    }

    ProcessBuilder pb = new ProcessBuilder("/usr/local/bin/report_generator", "--file", safeFilename);
    pb.directory(new File("/var/reports"));
    pb.redirectErrorStream(true);
    Process process = pb.start();
    // Tratamento de timeouts e término de processo...
}
```

---

## 5. Injeção de SpEL (Spring Expression Language)

O SpEL avalia expressões dinâmicas que podem invocar métodos arbitrários e executar comandos no sistema
(`T(java.lang.Runtime).getRuntime().exec(...)`) se utilizado com `StandardEvaluationContext`.

```java
// ❌ CRITICAL: Avaliação de SpEL não confiável com contexto padrão
ExpressionParser parser = new SpelExpressionParser();
Expression exp = parser.parseExpression(untrustedSpelInput);
Object result = exp.getValue(new StandardEvaluationContext()); // RCE garantido!

// ✅ GOOD: SimpleEvaluationContext (Modo restrito, apenas leitura de propriedades)
ExpressionParser parser = new SpelExpressionParser();
EvaluationContext context = SimpleEvaluationContext.forReadOnlyDataBinding().build();
Object result = parser.parseExpression(safeExpression).getValue(context, targetObject);
```

---

## 6. XML External Entity (XXE) e Parsers XML

Parsers XML na JVM (`DocumentBuilderFactory`, `SAXParserFactory`, `XMLInputFactory`, `TransformerFactory`) são
vulneráveis a XXE se external entities e DTDs não forem explicitamente desabilitados.

```java
// ✅ GOOD: DocumentBuilderFactory protegido contra XXE
public Document parseXmlSafely(InputStream inputStream) throws Exception {
    DocumentBuilderFactory dbf = DocumentBuilderFactory.newInstance();
    
    // Desabilita declarações DTD por completo
    dbf.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
    
    // Desabilita entidades externas gerais e de parâmetro
    dbf.setFeature("http://xml.org/sax/features/external-general-entities", false);
    dbf.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
    dbf.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false);
    
    dbf.setXIncludeAware(false);
    dbf.setExpandEntityReferences(false);
    
    DocumentBuilder db = dbf.newDocumentBuilder();
    return db.parse(inputStream);
}
```

---

## 7. Injeção em Arquivos YAML (SnakeYAML e Jackson)

Bibliotecas de parsing de YAML podem instanciar classes arbitrárias se configuradas com construtores permissivos.

```java
// ❌ VULNERABLE: SnakeYAML padrão permite instanciar classes arbitrárias
Yaml yaml = new Yaml();
Object data = yaml.load(untrustedYamlString);

// ✅ GOOD: SnakeYAML com SafeConstructor (permite apenas tipos padrão como List, Map, String)
LoaderOptions options = new LoaderOptions();
options.setMaxAliasesForCollections(50); // Prevenção contra YAML bomb / billion laughs
Yaml safeYaml = new Yaml(new SafeConstructor(options));
Object safeData = safeYaml.load(untrustedYamlString);
```

---

## 8. Upload de Arquivos, Path Traversal e Zip Slip

Ao manipular uploads de arquivos ou extrações de `.zip`:

1. **Nunca confie no nome original fornecido pelo cliente (`file.getOriginalFilename()`).**
2. Gere um UUID físico aleatório para o armazenamento no disco ou bucket.
3. Valide o caminho resolvido usando `.normalize()` e verifique se o destino inicia com o diretório raiz esperado
   (`startsWith`).

```java
// ✅ GOOD: Upload seguro com renomeação por UUID e validação de Path Traversal
public Path saveUploadedFile(MultipartFile file, Path baseStorageDir) throws IOException {
    String originalFilename = file.getOriginalFilename();
    if (originalFilename == null || originalFilename.isBlank()) {
        throw new IllegalArgumentException("Nome de arquivo ausente");
    }

    // Extrai extensão permitida
    String extension = extractAllowedExtension(originalFilename); // ex: .pdf, .jpg, .png
    String safePhysicalFilename = UUID.randomUUID() + extension;

    Path destinationPath = baseStorageDir.resolve(safePhysicalFilename).normalize();

    // Defesa em profundidade contra Path Traversal
    if (!destinationPath.startsWith(baseStorageDir.toAbsolutePath().normalize())) {
        throw new SecurityException("Tentativa de Path Traversal detectada");
    }

    Files.copy(file.getInputStream(), destinationPath, StandardCopyOption.REPLACE_EXISTING);
    return destinationPath;
}

// ✅ GOOD: Prevenção contra Zip Slip durante descompactação
public void unzipSafely(File zipArchive, Path outputDir) throws IOException {
    Path canonicalOutputDir = outputDir.toAbsolutePath().normalize();

    try (ZipInputStream zis = new ZipInputStream(new FileInputStream(zipArchive))) {
        ZipEntry entry;
        long totalBytesExtracted = 0;
        int totalEntries = 0;

        while ((entry = zis.getNextEntry()) != null) {
            totalEntries++;
            if (totalEntries > 1000) { // Prevenção contra Zip Bomb (limite de entradas)
                throw new SecurityException("Arquivo compactado excede o número máximo de arquivos");
            }

            Path resolvedPath = canonicalOutputDir.resolve(entry.getName()).normalize();

            // Verificação estrita de fronteira de diretório
            if (!resolvedPath.startsWith(canonicalOutputDir)) {
                throw new SecurityException("Tentativa de Zip Slip detectada: " + entry.getName());
            }

            if (entry.isDirectory()) {
                Files.createDirectories(resolvedPath);
            } else {
                Files.createDirectories(resolvedPath.getParent());
                try (OutputStream os = Files.newOutputStream(resolvedPath)) {
                    byte[] buffer = new byte[8192];
                    int len;
                    while ((len = zis.read(buffer)) > 0) {
                        totalBytesExtracted += len;
                        if (totalBytesExtracted > 100 * 1024 * 1024) { // Limite de 100MB
                            throw new SecurityException("Arquivo compactado excede o limite de tamanho (Zip Bomb)");
                        }
                        os.write(buffer, 0, len);
                    }
                }
            }
        }
    }
}
```

---

## 9. ReDoS (Regular Expression Denial of Service)

Expressões regulares mal construídas com agrupamentos recursivos ou operadores repetitivos ambíguos (ex.: `(a+)+$`)
sofrem de **Catastrophic Backtracking**, levando a CPU a 100% com payloads curtos.

### Diretrizes de Auditoria

- Audite regexes que processam entradas livres de usuários.
- Em Java, considere a passagem de limites de tempo ou o uso de bibliotecas de autômatos lineares como **Google RE2/J**.

```java
// ✅ GOOD: Uso de RE2/J para regex em tempo linear O(n) garantido contra ReDoS
import com.google.re2j.Pattern;
import com.google.re2j.Matcher;

public class LinearRegexValidator {
    private static final Pattern SAFE_PATTERN = Pattern.compile("^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\\.[a-zA-Z0-9-.]+$");

    public boolean isValid(String email) {
        return SAFE_PATTERN.matcher(email).matches();
    }
}
```

---

## 10. Reflexão Dinâmica e Carregamento Inseguro de Classes

O carregamento dinâmico de classes através de `Class.forName(userInput)` permite que um atacante requisite a
instanciação de classes presentes no classpath que possuam construtores perigosos ou efeitos colaterais estáticos.

```java
// ❌ BAD: Carregamento de classe arbitrário via parâmetro
Class<?> clazz = Class.forName(classNameFromUser);

// ✅ GOOD: Allowlist explícita de classes permitidas
private static final Map<String, Class<? extends Processor>> ALLOWED_PROCESSORS = Map.of(
    "invoice", InvoiceProcessor.class,
    "receipt", ReceiptProcessor.class
);

public Processor getProcessor(String type) {
    Class<? extends Processor> clazz = ALLOWED_PROCESSORS.get(type);
    if (clazz == null) {
        throw new IllegalArgumentException("Processador inválido: " + type);
    }
    return applicationContext.getBean(clazz);
}
```
