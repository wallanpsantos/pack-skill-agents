# Deserialização Segura, Supply Chain e Container/Cloud (A03/A08:2025)

Cobre desserialização segura (Jackson), segurança da cadeia de suprimentos de build (SBOM, assinatura) e hardening de
containers/Kubernetes.

## Conteúdo
- Secure Deserialization
  - Evitar Java Serialization Nativa
  - Jackson2ObjectMapperBuilder — Configuração Segura
- Software Supply Chain Security
  - SBOM (Software Bill of Materials)
  - Assinatura e Verificação de Artefatos
  - Integração GitHub Security
- Container & Cloud Security
  - Dockerfile Hardening
  - Kubernetes Security Context
  - SBOM em Container Images
  - Zero Trust — mTLS entre Serviços

---

## Secure Deserialization (A08:2025)

### Evitar Java Serialization Nativa

```java
// ❌ DANGEROUS: ObjectInputStream — risco de RCE!
ObjectInputStream ois = new ObjectInputStream(untrustedInput);
Object obj = ois.readObject();

// ✅ GOOD: Jackson com allowlist explícita
PolymorphicTypeValidator ptv = BasicPolymorphicTypeValidator.builder()
        .allowIfBaseType("com.example.dto.")
        .allowIfSubType("com.example.dto.")
        .build();
mapper.

activateDefaultTyping(ptv, ObjectMapper.DefaultTyping.NON_FINAL);
```

### Jackson2ObjectMapperBuilder — Configuração Segura

```java

@Configuration
public class JacksonConfig {

    @Bean
    public ObjectMapper objectMapper() {
        return Jackson2ObjectMapperBuilder.json()
                .featuresToDisable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES)
                // Desativa default typing — previne gadget attacks
                .postConfigurer(mapper -> mapper.deactivateDefaultTyping())
                .build();
    }
}
```

---

## Software Supply Chain Security (A03:2025)

### SBOM (Software Bill of Materials)

```xml

<plugin>
    <groupId>org.cyclonedx</groupId>
    <artifactId>cyclonedx-maven-plugin</artifactId>
    <version>2.9.2</version>
    <executions>
        <execution>
            <phase>package</phase>
            <goals>
                <goal>makeAggregateBom</goal>
            </goals>
        </execution>
    </executions>
</plugin>
```

### Assinatura e Verificação de Artefatos

```bash
# Assinar com cosign (Sigstore)
cosign sign --key cosign.key meu-servico:1.2.3

# Verificar antes de deploy
cosign verify --key cosign.pub meu-servico:1.2.3
```

### Integração GitHub Security

```yaml
# .github/workflows/security.yml
- name: CodeQL Analysis
  uses: github/codeql-action/analyze@v3

- name: Dependency Review
  uses: actions/dependency-review-action@v4
  with:
    fail-on-severity: high

- name: OWASP Dependency Check
  run: mvn dependency-check:check
```

---

## Container & Cloud Security

### Dockerfile Hardening

```dockerfile
# ✅ GOOD: Distroless + non-root + read-only filesystem
FROM gcr.io/distroless/java21-debian12:nonroot AS runtime

COPY --chown=nonroot:nonroot --from=build /app/target/app.jar /app/app.jar

USER nonroot
WORKDIR /app

# Read-only filesystem (montar volumes apenas onde necessário)
# docker run --read-only --tmpfs /tmp ...

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### Kubernetes Security Context

```yaml
# ✅ GOOD: SecurityContext restritivo
spec:
  containers:
    - name: app
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        readOnlyRootFilesystem: true
        allowPrivilegeEscalation: false
        capabilities:
          drop: [ "ALL" ]
      # Secrets via Vault ou External Secrets Operator — nunca env hardcoded
```

### SBOM em Container Images

```bash
# Gerar SBOM da imagem com Syft
syft meu-servico:1.2.3 -o cyclonedx-json > sbom-image.json

# Assinar SBOM + imagem
cosign attest --predicate sbom-image.json --type cyclonedx meu-servico:1.2.3
```

### Zero Trust — mTLS entre Serviços

```yaml
# Istio — habilitar mTLS estrito em todo o namespace
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: STRICT
```

