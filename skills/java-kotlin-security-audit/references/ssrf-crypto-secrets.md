# SSRF, Criptografia e Gestão de Segredos (A01/A04:2025, API7:2023)

Este guia cobre a prevenção rigorosa contra **Server-Side Request Forgery (SSRF)** e **DNS Rebinding**, a implementação
de **criptografia moderna** em Java 25 LTS e Kotlin 2.4+, e as melhores práticas para **gestão de segredos e
credenciais**.

---

## Índice

1. [SSRF e Prevenção Nativa com InetAddressFilter (Spring Boot 4.1+)](#1-ssrf-e-prevenção-nativa-com-inetaddressfilter)
2. [Validação Manual contra SSRF e DNS Rebinding](#2-validação-manual-contra-ssrf-e-dns-rebinding)
3. [Criptografia Simétrica Segura (AES-GCM e Proibição de ECB)](#3-criptografia-simétrica-segura)
4. [Derivação de Chaves com HKDF e JCA KDF (Java 25)](#4-derivação-de-chaves-com-hkdf-e-jca-kdf)
5. [Aleatoriedade Criptográfica e Comparação em Tempo Constante](#5-aleatoriedade-criptográfica-e-comparação-em-tempo-constante)
6. [TLS de Cliente e Verificação de Certificados](#6-tls-de-cliente-e-verificação-de-certificados)
7. [Gestão de Segredos e Prevenção de Hardcoding](#7-gestão-de-segredos-e-prevenção-de-hardcoding)

---

## 1. SSRF e Prevenção Nativa com InetAddressFilter

O **SSRF (Server-Side Request Forgery)** ocorre quando a aplicação efetua requisições HTTP para uma URL fornecida pelo
usuário sem a devida sanitização de destino. Em ambientes de nuvem (AWS, GCP, Azure, Kubernetes), o atacante pode
atingir serviços de metadados internos (`169.254.169.254`), portas de gestão do Kubernetes (`10.96.0.1`) ou serviços de
banco internos.

No **Spring Boot 4.1.1+**, os clientes HTTP gerenciados (`RestClient` e `WebClient`) suportam a mitigação nativa via
`InetAddressFilter`:

```java
// ✅ GOOD: RestClient configurado com InetAddressFilter no Spring Boot 4.1+
@Configuration
public class HttpClientConfig {

    @Bean
    public RestClient outboundRestClient(RestClient.Builder builder) {
        return builder
            .requestInterceptor(new InetAddressFilter()) // Bloqueia automaticamente loopback, private e link-local
            .build();
    }
}
```

O `InetAddressFilter` bloqueia automaticamente:

- Loopback: `127.0.0.0/8`, `::1`
- Redes privadas RFC 1918: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`
- Endereços Link-Local e Cloud Metadata: `169.254.0.0/16`, `fe80::/10`

---

## 2. Validação Manual contra SSRF e DNS Rebinding

Quando não for possível utilizar `InetAddressFilter` (ex.: bibliotecas de terceiros ou conexões socket brutas), a
validação manual deve considerar **DNS Rebinding**.
No ataque de DNS Rebinding, o atacante configura um servidor DNS com TTL de 0 segundos: a primeira resolução retorna um
IP público legítimo (bypassa o filtro), mas a conexão HTTP subsequente resolve para `127.0.0.1` ou `169.254.169.254`.

### Padrão Seguro de Conexão com Validação de IP Prévia

Para eliminar o risco de DNS Rebinding, resolva o IP uma única vez, valide-o contra a allowlist/blocklist e conecte
diretamente ao IP resolvido com o cabeçalho `Host` original:

```java
// ✅ GOOD: Resolução única e validação estrita contra SSRF e DNS Rebinding
public byte[] fetchUrlSafely(URI targetUri, Set<String> allowedDomains) throws IOException {
    String host = targetUri.getHost();
    if (host == null || !allowedDomains.contains(host.toLowerCase())) {
        throw new SecurityException("Domínio não autorizado na allowlist: " + host);
    }

    if (!"https".equalsIgnoreCase(targetUri.getProtocol())) {
        throw new SecurityException("Apenas HTTPS é permitido");
    }

    // Resolve todos os endereços associados ao host
    InetAddress[] addresses = InetAddress.getAllByName(host);
    for (InetAddress addr : addresses) {
        if (addr.isLoopbackAddress() || addr.isSiteLocalAddress() || addr.isLinkLocalAddress() || addr.isAnyLocalAddress()) {
            throw new SecurityException("Tentativa de SSRF bloqueada: " + addr.getHostAddress());
        }
        // Bloqueio explícito do range de metadados de nuvem 169.254.169.254
        byte[] raw = addr.getAddress();
        if (raw.length == 4 && (raw[0] & 0xFF) == 169 && (raw[1] & 0xFF) == 254) {
            throw new SecurityException("Acesso a metadados de nuvem proibido");
        }
    }

    // Executa chamada com timeouts estritos
    HttpURLConnection conn = (HttpURLConnection) targetUri.toURL().openConnection();
    conn.setConnectTimeout(3000);
    conn.setReadTimeout(5000);
    conn.setInstanceFollowRedirects(false); // NUNCA seguir redirects cegamente para não cair em rede interna!

    return conn.getInputStream().readAllBytes();
}
```

---

## 3. Criptografia Simétrica Segura

### Proibição Absoluta de AES/ECB

O modo **ECB (Electronic Codebook)** divide o texto em blocos independentes e cifra cada um com a mesma chave. Isso
preserva padrões visuais e estruturais dos dados originais.
O uso de `"AES"` sem especificação de modo (`Cipher.getInstance("AES")`) assume ECB em muitas implementações de
providers JCA legados e é terminantemente proibido.

### Padrão Ouro: AES-256-GCM

Sempre utilize **AES-GCM (Galois/Counter Mode)**, um algoritmo AEAD (Authenticated Encryption with Associated Data) que
garante confidencialidade e integridade simultâneas.

- **Tamanho do IV (Initialization Vector):** Exatamente **12 bytes** (96 bits).
- **Tamanho da Tag de Autenticação:** **128 bits**.
- **Regra de Ouro do GCM:** O IV deve ser gerado aleatoriamente através de `SecureRandom` **a cada operação de
  cifragem**. Nunca reutilize o mesmo par (Chave, IV).

```java
// ✅ GOOD: Cifra e decifra segura com AES-256-GCM em Java 25
public class CryptoService {

    private static final String ALGORITHM = "AES/GCM/NoPadding";
    private static final int TAG_LENGTH_BITS = 128;
    private static final int IV_LENGTH_BYTES = 12;

    public byte[] encrypt(byte[] plaintext, SecretKey key, byte[] associatedData) throws GeneralSecurityException {
        byte[] iv = new byte[IV_LENGTH_BYTES];
        SecureRandom.getInstanceStrong().nextBytes(iv);

        Cipher cipher = Cipher.getInstance(ALGORITHM);
        GCMParameterSpec parameterSpec = new GCMParameterSpec(TAG_LENGTH_BITS, iv);
        cipher.init(Cipher.ENCRYPT_MODE, key, parameterSpec);

        if (associatedData != null && associatedData.length > 0) {
            cipher.updateAAD(associatedData);
        }

        byte[] ciphertext = cipher.doFinal(plaintext);

        // Prepend do IV no payload final (IV não é segredo, apenas deve ser único)
        ByteBuffer byteBuffer = ByteBuffer.allocate(iv.length + ciphertext.length);
        byteBuffer.put(iv);
        byteBuffer.put(ciphertext);
        return byteBuffer.array();
    }

    public byte[] decrypt(byte[] encryptedPayload, SecretKey key, byte[] associatedData) throws GeneralSecurityException {
        if (encryptedPayload.length < IV_LENGTH_BYTES + (TAG_LENGTH_BITS / 8)) {
            throw new IllegalArgumentException("Payload cifrado corrompido ou incompleto");
        }

        ByteBuffer byteBuffer = ByteBuffer.wrap(encryptedPayload);
        byte[] iv = new byte[IV_LENGTH_BYTES];
        byteBuffer.get(iv);

        byte[] ciphertext = new byte[byteBuffer.remaining()];
        byteBuffer.get(ciphertext);

        Cipher cipher = Cipher.getInstance(ALGORITHM);
        GCMParameterSpec parameterSpec = new GCMParameterSpec(TAG_LENGTH_BITS, iv);
        cipher.init(Cipher.DECRYPT_MODE, key, parameterSpec);

        if (associatedData != null && associatedData.length > 0) {
            cipher.updateAAD(associatedData);
        }

        return cipher.doFinal(ciphertext);
    }
}
```

---

## 4. Derivação de Chaves com HKDF e JCA KDF

Ao derivar chaves simétricas a partir de segredos compartilhados, senhas mestras ou tokens de autorização, utilize a API
padronizada **`javax.crypto.KDF`** do Java moderno (baseada em RFC 5869 - HKDF).

```java
// ✅ GOOD: Derivação de chave segura com HKDF (HMAC-SHA256)
public SecretKey deriveKey(SecretKey masterKey, byte[] salt, byte[] info) throws GeneralSecurityException {
    KDF kdf = KDF.getInstance("HKDF-HMAC-SHA256");
    AlgorithmParameterSpec params = HKDFParameterSpec.ofExtractThenExpand(
        salt,
        masterKey.getEncoded(),
        info,
        32 // 256 bits para chave AES
    );
    return kdf.deriveKey("AES", params);
}
```

---

## 5. Aleatoriedade Criptográfica e Comparação em Tempo Constante

### `SecureRandom` vs `Random`

- **PROIBIDO:** `java.util.Random` para qualquer finalidade de segurança (geração de tokens, senhas temporárias, salts,
  IVs, códigos de verificação SMS/email). `Random` é baseado em um gerador congruencial linear previsível.
- **OBRIGATÓRIO:** `java.security.SecureRandom.getInstanceStrong()`.

### Prevenção contra Timing Attacks

Ao comparar hashes criptográficos, assinaturas HMAC ou tokens de autenticação, operadores de igualdade padrão
(`String.equals` ou `Arrays.equals`) realizam retorno antecipado no primeiro byte divergente. Isso permite que um
atacante deduza a chave medindo variações nanométricas no tempo de resposta HTTP.

```java
// ❌ VULNERABLE: Timing attack na comparação de assinatura HMAC
if (computedSignature.equals(headerSignature)) { ... }

// ✅ GOOD: Comparação em tempo constante (Constant-Time Comparison)
if (MessageDigest.isEqual(computedSignature.getBytes(StandardCharsets.UTF_8),
                          headerSignature.getBytes(StandardCharsets.UTF_8))) {
    // Válido
}
```

---

## 6. TLS de Cliente e Verificação de Certificados

Ao consumir APIs externas via HTTP, gRPC ou JDBC com SSL/TLS:

- **PROIBIDO:** Criar `TrustManager` que aceita qualquer certificado (`TrustAllCerts`) ou desabilitar verificação de
  hostname (`NoopHostnameVerifier`).
- Em ambientes corporativos com CA interna, importe o certificado raiz confiável no `cacerts` do JRE ou configure um
  `KeyStore` customizado no `SSLContext`.

```java
// ❌ CRITICAL: Desabilita toda a segurança de tráfego TLS
SSLContext sslContext = SSLContext.getInstance("TLS");
sslContext.init(null, new TrustManager[]{ new X509TrustManager() {
    public void checkClientTrusted(X509Certificate[] certs, String authType) {}
    public void checkServerTrusted(X509Certificate[] certs, String authType) {}
    public X509Certificate[] getAcceptedIssuers() { return null; }
}}, new SecureRandom());
```

---

## 7. Gestão de Segredos e Prevenção de Hardcoding

### Regra Zero-Hardcode

Nenhum segredo de produção (senhas de banco, chaves privadas, API keys, tokens de API de pagamento) pode residir em:

1. Código-fonte Java ou Kotlin (strings literais ou constantes).
2. Arquivos de propriedades sob versionamento Git (`application.yml`, `pom.xml`, `.env`).
3. Camadas de imagem Docker (`ENV SECRET_KEY=...` ou `RUN echo ...`).

### Soluções Recomendadas em Produção

- **HashiCorp Vault / AWS Secrets Manager / Azure Key Vault / GCP Secret Manager.**
- **Kubernetes External Secrets Operator (ESO)** injetando segredos diretamente na memória do Pod.
- Em desenvolvimento local, utilize perfis isolados (`application-local.yml`) que estejam explicitamente no
  `.gitignore`.
