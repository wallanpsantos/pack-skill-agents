# SSRF, Criptografia Simétrica e Gestão de Segredos (A01/A04:2025)

Cobre validação de requisições de saída (SSRF), uso correto de criptografia simétrica e como lidar com segredos
(chaves, senhas de banco, tokens). Válido para Spring Boot, Quarkus, Jakarta EE e Java puro.

## Conteúdo
- SSRF (Server-Side Request Forgery) Prevention
- Symmetric Cryptography
  - Ban AES/ECB (Electronic Codebook)
  - Secure Randomness & IV Generation
  - Spring Security Crypto — Dados em Repouso
  - Google Tink — Para Casos Complexos
- Secrets Management
  - Nunca Hardcode Secrets
  - Gerenciadores de Secrets (Recomendados)
  - .gitignore

---

## SSRF (Server-Side Request Forgery) Prevention (A01:2025)

SSRF ocorre quando a aplicação aceita uma URL do cliente e a busca sem validação, permitindo varredura de rede interna,
acesso a loopback (`localhost`) ou leitura de endpoints de metadata de cloud (`169.254.169.254`).

```java
// ❌ VULNERABLE: Fetches user-provided URL directly, opening internal network scanning
public byte[] fetchExternalAsset(String urlString) throws Exception {
    URL url = new URI(urlString).toURL();
    return url.openStream().readAllBytes(); // Sem validação de protocolo, host ou IP!
}

// ✅ GOOD: Spring Boot 4.1+ — Use InetAddressFilter (Nativo) para bloqueio automático
@Bean
public RestClient secureRestClient(RestClient.Builder builder) {
    return builder
            .requestInterceptor(new InetAddressFilter()) // Bloqueia IPs privados, loopback e link-local
            .build();
}

// ✅ SECURE: Validar protocolo, resolver IP, verificar allowlist (Validação Manual)
public byte[] fetchExternalAssetSecure(String urlString) throws Exception {
    URL url = new URI(urlString).toURL();

    if (!"https".equalsIgnoreCase(url.getProtocol())) {
        throw new SecurityException("Only HTTPS connections are permitted");
    }

    InetAddress address = InetAddress.getByName(url.getHost());
    if (address.isLoopbackAddress() || address.isSiteLocalAddress() || address.isLinkLocalAddress()) {
        throw new SecurityException("Access to internal networks is forbidden");
    }

    Set<String> allowedDomains = Set.of("trusted-partner.com", "assets.trusted.com");
    if (!allowedDomains.contains(url.getHost())) {
        throw new SecurityException("Target domain is not allowlisted");
    }

    HttpURLConnection conn = (HttpURLConnection) url.openConnection();
    conn.setConnectTimeout(5000);
    conn.setReadTimeout(5000);
    return conn.getInputStream().readAllBytes();
}
```

---

## Symmetric Cryptography (A04:2025)

### 1. Ban AES/ECB (Electronic Codebook)

ECB mode encrypts identical plaintext blocks into identical ciphertext blocks, preserving visual or structural patterns
in data. Always use an authenticated encryption mode (AEAD) like **AES/GCM** (Galois/Counter Mode).

### 2. Secure Randomness & IV Generation

Never use `java.util.Random` for security-sensitive tasks (keys, IVs, salts) as it is predictable. Always use
`java.security.SecureRandom`. An Initialization Vector (IV) for GCM mode must be **exactly 12 bytes** and generated
randomly for every encryption operation.

```java
// ❌ BAD: AES/ECB com criptografia estática, sem IV e geradores previsíveis
public class InsecureEncryption {
    private static final String ALGORITHM = "AES/ECB/PKCS5Padding";
    private static final byte[] HARDCODED_KEY = "mySuperSecretKey".getBytes(); // Chave hardcoded!

    public static byte[] encrypt(byte[] plaintext) throws Exception {
        SecretKeySpec key = new SecretKeySpec(HARDCODED_KEY, "AES");
        Cipher cipher = Cipher.getInstance(ALGORITHM);
        cipher.init(Cipher.ENCRYPT_MODE, key);
        return cipher.doFinal(plaintext); // ECB não utiliza IV, padrões são preservados!
    }
}

// ✅ GOOD: AES/GCM com IV aleatório por operação (SecureRandom)
public class EncryptionUtils {
    private static final String ALGORITHM = "AES/GCM/NoPadding";
    private static final int TAG_LENGTH_BIT = 128;
    private static final int IV_LENGTH_BYTE = 12;

    public static byte[] encrypt(byte[] plaintext, SecretKeySpec key) throws Exception {
        byte[] iv = new byte[IV_LENGTH_BYTE];
        SecureRandom.getInstanceStrong().nextBytes(iv); // Cryptographically secure random

        Cipher cipher = Cipher.getInstance(ALGORITHM);
        cipher.init(Cipher.ENCRYPT_MODE, key, new GCMParameterSpec(TAG_LENGTH_BIT, iv));
        byte[] ciphertext = cipher.doFinal(plaintext);

        byte[] encryptedMessage = new byte[iv.length + ciphertext.length];
        System.arraycopy(iv, 0, encryptedMessage, 0, iv.length);
        System.arraycopy(ciphertext, 0, encryptedMessage, iv.length, ciphertext.length);
        return encryptedMessage;
    }
}
```

### Spring Security Crypto — Dados em Repouso

```java
// ✅ GOOD: BytesEncryptor para dados em repouso

import org.springframework.security.crypto.encrypt.Encryptors;
import org.springframework.security.crypto.encrypt.BytesEncryptor;

BytesEncryptor encryptor = Encryptors.stronger(password, salt);
byte[] encrypted = encryptor.encrypt(sensitiveData);
byte[] decrypted = encryptor.decrypt(encrypted);
```

### Google Tink — Para Casos Complexos

Para operações criptográficas avançadas (envelope encryption, key rotation gerenciada), prefira **Google Tink** que
oferece APIs seguras por design:

```xml

<dependency>
    <groupId>com.google.crypto.tink</groupId>
    <artifactId>tink</artifactId>
    <version>1.15.0</version>
</dependency>
```

```java
// ✅ GOOD: Tink AEAD com key rotation automática
KeysetHandle keysetHandle = KeysetHandle.generateNew(KeyTemplates.get("AES128_GCM"));
Aead aead = keysetHandle.getPrimitive(Aead.class);
byte[] ciphertext = aead.encrypt(plaintext, associatedData);
```

---

## Secrets Management (A04:2025)

### Nunca Hardcode Secrets

```java
// ❌ BAD: Hardcoded
private static final String API_KEY = "sk-1234567890abcdef";

// ✅ GOOD: Environment variable
String apiKey = System.getenv("API_KEY");

// ✅ GOOD: Spring @Value
@Value("${api.key}")
private String apiKey;
```

### Gerenciadores de Secrets (Recomendados)

| Opção                                   | Quando usar                                 |
|-----------------------------------------|---------------------------------------------|
| **HashiCorp Vault**                     | On-premise / hybrid cloud, rotação dinâmica |
| **AWS Secrets Manager**                 | Workloads AWS, rotação automática nativa    |
| **Spring Cloud Config + Encryption**    | Ambientes Spring Cloud, config centralizada |
| **Kubernetes Secrets + Sealed Secrets** | Clusters K8s com GitOps                     |

```yaml
# application.yml — HashiCorp Vault via Spring Cloud Vault
spring:
  cloud:
    vault:
      host: vault.mycompany.com
      port: 8200
      scheme: https
      authentication: KUBERNETES
  config:
    import: vault://
```

### .gitignore

```gitignore
.env
*.pem
*.key
*credentials*
*secret*
application-local.yml
```

