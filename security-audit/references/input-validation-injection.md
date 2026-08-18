# Validação de Entrada e Prevenção de Injeção (A05:2025)

Cobre os pontos de fronteira onde entrada não confiável entra na aplicação: validação de campos, sanitização de HTML,
XXE, upload de arquivos, SQL Injection e XSS. Válido para Spring Boot, Quarkus, Jakarta EE e Java puro.

## Conteúdo
- Input Validation (All Frameworks)
  - Bean Validation (JSR 380)
  - Custom HTML Sanitization Validator
  - Allowlist vs Blocklist
  - XML External Entity (XXE) Prevention
  - File Uploads: Path Traversal & Zip Slip Prevention
- SQL Injection Prevention
  - JPA/Hibernate (All Frameworks)
  - JDBC (Plain Java)
- XSS Prevention
  - Output Encoding
  - Content Security Policy

---

## Input Validation (All Frameworks)

### Bean Validation (JSR 380)

Works in Spring Boot 4.1+, Quarkus, Jakarta EE, and standalone.

```java
// ✅ GOOD: Validate at boundary
public class CreateUserRequest {

    @NotNull(message = "Username is required")
    @Size(min = 3, max = 50, message = "Username must be 3-50 characters")
    @Pattern(regexp = "^[a-zA-Z0-9_]+$", message = "Username can only contain letters, numbers, underscore")
    private String username;

    @NotNull
    @Email(message = "Invalid email format")
    private String email;

    @NotNull
    @Size(min = 8, max = 100)
    @Pattern(regexp = "^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).*$",
            message = "Password must contain uppercase, lowercase, and number")
    private String password;

    @Min(value = 0, message = "Age cannot be negative")
    @Max(value = 150, message = "Invalid age")
    private Integer age;
}

// Controller/Resource - trigger validation
public Response createUser(@Valid CreateUserRequest request) {
    // request is already validated
}
```

### Custom HTML Sanitization Validator

Never try to validate or sanitize HTML using custom regular expression blocklists. Attackers can easily bypass regex
patterns with SVG tags, event handlers (e.g., `onerror`), or encoding variations. Use the **OWASP Java HTML Sanitizer**
library.

**Dependency:**

```xml

<properties>
    <owasp.html.sanitizer.version>20260313.1</owasp.html.sanitizer.version>
</properties>

<dependency>
<groupId>com.googlecode.owasp-java-html-sanitizer</groupId>
<artifactId>owasp-java-html-sanitizer</artifactId>
<version>${owasp.html.sanitizer.version}</version>
</dependency>
```

> [!TIP]
> Always use the latest stable version
from [Maven Central](https://central.sonatype.com/artifact/com.googlecode.owasp-java-html-sanitizer/owasp-java-html-sanitizer)
and manage it via the `<properties>` block to avoid version drift.

**Implementation:**

```java
import org.owasp.html.PolicyFactory;
import org.owasp.html.Sanitizers;

public class SafeHtmlValidator implements ConstraintValidator<SafeHtml, String> {

    private static final PolicyFactory POLICY = Sanitizers.FORMATTING.and(Sanitizers.LINKS);

    @Override
    public boolean isValid(String value, ConstraintValidatorContext context) {
        if (value == null) return true;
        String sanitized = POLICY.sanitize(value);
        return value.equals(sanitized);
    }
}
```

### Allowlist vs Blocklist

```java
// ❌ BAD: Blocklist (attackers find bypasses)
if(input.contains("<script>")){
        throw new

ValidationException("Invalid input");
}

// ✅ GOOD: Allowlist (only permit known-good)
private static final Pattern SAFE_NAME = Pattern.compile("^[a-zA-Z\\s'-]{1,100}$");

if(!SAFE_NAME.

matcher(input).

matches()){
        throw new

ValidationException("Invalid name format");
}
```

### XML External Entity (XXE) Prevention (A05:2025)

XML parsers in Java (like `DocumentBuilderFactory`, `SAXParserFactory`, and `XMLInputFactory`) are vulnerable to XXE by
default because they resolve external DTDs and entities. This can leak local files or trigger internal SSRF.

```java
// ❌ BAD: Vulnerable XML Parser (resolves external DTDs and entities)
public Document parseXmlInsecure(InputStream input) throws Exception {
    DocumentBuilderFactory dbf = DocumentBuilderFactory.newInstance();
    DocumentBuilder db = dbf.newDocumentBuilder();
    return db.parse(input); // Vulnerable to XXE!
}

// ✅ GOOD: Configure XML parser securely (disable DTDs and external entities)
DocumentBuilderFactory dbf = DocumentBuilderFactory.newInstance();
try{
        dbf.

setFeature("http://apache.org/xml/features/disallow-doctype-decl",true);
    dbf.

setFeature("http://xml.org/sax/features/external-general-entities",false);
    dbf.

setFeature("http://xml.org/sax/features/external-parameter-entities",false);
    dbf.

setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd",false);
    dbf.

setXIncludeAware(false);
    dbf.

setExpandEntityReferences(false);
}catch(
ParserConfigurationException e){
        log.

error("Secure XML parser configuration failed",e);
}
```

### File Uploads: Path Traversal & Zip Slip Prevention (A05/A08:2025)

When handling file uploads (e.g., via `MultipartFile` in Spring), relying directly on `file.getOriginalFilename()` to
save files to disk exposes the application to **Path Traversal** (e.g., uploading to `../../etc/passwd`). Extracting zip
files without path validation causes **Zip Slip**, allowing attackers to overwrite arbitrary files outside the target
directory.

```java
// ❌ BAD: Relying directly on getOriginalFilename() and unvalidated zip extraction
public void saveAndExtractInsecure(MultipartFile file, Path targetDirectory) throws Exception {
    // Path Traversal Vulnerability
    File targetFile = new File(targetDirectory.toFile(), file.getOriginalFilename());
    file.transferTo(targetFile);

    // Zip Slip Vulnerability
    try (ZipInputStream zis = new ZipInputStream(new FileInputStream(targetFile))) {
        ZipEntry entry;
        while ((entry = zis.getNextEntry()) != null) {
            // No path validation check - files can be written anywhere!
            File resolvedFile = new File(targetDirectory.toFile(), entry.getName());
            resolvedFile.getParentFile().mkdirs();
            Files.copy(zis, resolvedFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
        }
    }
}

// ✅ GOOD: UUID-based safe filename + boundary check
public Path saveUploadedFile(MultipartFile file, Path targetDirectory) throws IOException {
    String originalFilename = file.getOriginalFilename();
    if (originalFilename == null || originalFilename.isEmpty()) {
        throw new IllegalArgumentException("Invalid filename");
    }
    String fileExtension = getFileExtension(originalFilename);
    String safePhysicalName = UUID.randomUUID().toString() + fileExtension;
    Path targetPath = targetDirectory.resolve(safePhysicalName).normalize();

    if (!targetPath.startsWith(targetDirectory.toAbsolutePath().normalize())) {
        throw new SecurityException("Directory traversal attempt detected");
    }
    Files.copy(file.getInputStream(), targetPath, StandardCopyOption.REPLACE_EXISTING);
    return targetPath;
}

// ✅ GOOD: Zip Slip Prevention during extraction
public void extractZipSafely(File zipFile, File targetDir) throws IOException {
    String targetDirPath = targetDir.getCanonicalPath();
    try (ZipInputStream zis = new ZipInputStream(new FileInputStream(zipFile))) {
        ZipEntry entry;
        while ((entry = zis.getNextEntry()) != null) {
            File resolvedFile = new File(targetDir, entry.getName());
            String resolvedFilePath = resolvedFile.getCanonicalPath();

            if (!resolvedFilePath.startsWith(targetDirPath + File.separator)) {
                throw new SecurityException("Zip Slip directory traversal attempt: " + entry.getName());
            }
            if (entry.isDirectory()) {
                resolvedFile.mkdirs();
            } else {
                resolvedFile.getParentFile().mkdirs();
                Files.copy(zis, resolvedFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
            }
        }
    }
}
```

---

## SQL Injection Prevention (A05:2025)

### JPA/Hibernate (All Frameworks)

```java
// ❌ BAD: String concatenation in JPQL (Vulnerable!)
String jpql = "SELECT u FROM User u WHERE u.email = '" + email + "'";
TypedQuery<User> query = entityManager.createQuery(jpql, User.class);

// ❌ BAD: String concatenation in Native Queries (Vulnerable!)
String sql = "SELECT * FROM users WHERE email = '" + email + "'";
Query query = entityManager.createNativeQuery(sql);

// ✅ GOOD: Parameterized queries in Spring Data JPA
@Query("SELECT u FROM User u WHERE u.email = :email")
Optional<User> findByEmail(@Param("email") String email);

// ✅ GOOD: Parameterized native query
@Query(value = "SELECT * FROM users WHERE email = ?1", nativeQuery = true)
User findByEmailNative(String email);

// ✅ GOOD: Criteria API (Inherently Safe)
CriteriaBuilder cb = entityManager.getCriteriaBuilder();
CriteriaQuery<User> query = cb.createQuery(User.class);
Root<User> user = query.from(User.class);
query.

where(cb.equal(user.get("email"),email));
```

### JDBC (Plain Java)

```java
// ❌ BAD: Statement with concatenation (Vulnerable!)
String sql = "SELECT * FROM users WHERE email = '" + email + "'";
Statement stmt = connection.createStatement();
ResultSet rs = stmt.executeQuery(sql);

// ✅ GOOD: PreparedStatement
String sql = "SELECT * FROM users WHERE email = ? AND status = ?";
try(
PreparedStatement stmt = connection.prepareStatement(sql)){
        stmt.

setString(1,email);
    stmt.

setString(2,status);

ResultSet rs = stmt.executeQuery();
}
```

---

## XSS Prevention (A05:2025)

### Output Encoding

```java
// ✅ GOOD: Use OWASP Encoder

import org.owasp.encoder.Encode;

String safe = Encode.forHtml(userInput);
String safeJs = Encode.forJavaScript(userInput);
String safeUrl = Encode.forUriComponent(userInput);
```

```xml

<dependency>
    <groupId>org.owasp.encoder</groupId>
    <artifactId>encoder</artifactId>
    <version>1.2.3</version>
</dependency>
```

### Content Security Policy

```java
// Spring Boot 4.1+
@Bean
public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
    http.headers(headers -> headers
            .contentSecurityPolicy(csp -> csp
                    .policyDirectives("default-src 'self'; script-src 'self'; style-src 'self'")
            )
    );
    return http.build();
}
```

