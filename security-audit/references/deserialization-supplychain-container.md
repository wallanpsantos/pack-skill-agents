# Desserialização Segura, Supply Chain e Hardening de Runtime (A03/A08:2025)

Este documento detalha o tratamento seguro de desserialização (Java nativo, Jackson 3 e kotlinx.serialization), a
segurança da cadeia de suprimentos de software (Maven, Gradle, GitHub Actions, SBOM) e o hardening de contêineres Docker
e clusters Kubernetes.

---

## Índice

1. [Desserialização Java Nativa e ObjectInputFilter (JEP 290/415)](#1-desserialização-java-nativa-e-objectinputfilter)
2. [Jackson 3 e Desativação de Default Typing](#2-jackson-3-e-desativação-de-default-typing)
3. [kotlinx.serialization e Polimorfismo Fechado](#3-kotlinxserialization-e-polimorfismo-fechado)
4. [Segurança de Supply Chain em Maven e Gradle](#4-segurança-de-supply-chain-em-maven-e-gradle)
5. [Triagem de CVEs, Alcançabilidade e VEX](#5-triagem-de-cves-alcançabilidade-e-vex)
6. [SBOM (CycloneDX) e Assinatura de Artefatos (Sigstore/Cosign)](#6-sbom-cyclonedx-e-assinatura-de-artefatos)
7. [Hardening de GitHub Actions e Pipelines de CI/CD](#7-hardening-de-github-actions-e-pipelines-de-cicd)
8. [Dockerfile Hardening (Distroless e Non-Root)](#8-dockerfile-hardening)
9. [Hardening de Manifestos Kubernetes (Pod Security Standards Restricted)](#9-hardening-de-manifestos-kubernetes)

---

## 1. Desserialização Java Nativa e ObjectInputFilter

A desserialização nativa em Java (`ObjectInputStream.readObject()`) é inerentemente insegura quando alimentada com dados
recebidos de fontes externas. Se classes conhecidas como "gadgets" estiverem presentes no classpath (bibliotecas como
Commons Collections, Spring, Groovy), a leitura do fluxo pode resultar em Execução Remota de Código (RCE) antes mesmo
que a aplicação inspecione o objeto retornado.

### Regra

**Evite completamente `ObjectInputStream` em novas aplicações.** Se for estritamente necessário processar fluxos
serializados nativos legados, configure obrigatoriamente um filtro de desserialização (`ObjectInputFilter` - JEP 290 e
JEP 415):

```java
// ✅ GOOD: Filtro de serialização nativo restritivo (allowlist estrita)
public Object deserializeSafely(InputStream inputStream) throws IOException, ClassNotFoundException {
    try (ObjectInputStream ois = new ObjectInputStream(inputStream)) {
        ObjectInputFilter filter = ObjectInputFilter.Config.createFilter(
            "com.empresa.dto.*;!*" // Permite apenas DTOs específicos da empresa; rejeita tudo o mais
        );
        ois.setObjectInputFilter(filter);
        return ois.readObject();
    }
}
```

---

## 2. Jackson 3 e Desativação de Default Typing

No ecossistema moderno de **Jackson 3** (`tools.jackson.core:jackson-databind` ou
`com.fasterxml.jackson.core:jackson-databind`), a ativação de *Default Typing* irrestrito (`enableDefaultTyping()`)
reintroduz o risco de gadget attacks em JSON.

### Configuração Segura de Jackson

- Desative o Default Typing global.
- Se o polimorfismo for indispensável, utilize `@JsonTypeInfo` com nome lógico (`Id.NAME`) combinado com um
  `BasicPolymorphicTypeValidator` estrito.

```java
// ✅ GOOD: Jackson configurado com polimorfismo seguro por allowlist
@Configuration
public class JacksonConfig {

    @Bean
    public ObjectMapper objectMapper() {
        PolymorphicTypeValidator ptv = BasicPolymorphicTypeValidator.builder()
            .allowIfBaseType("com.empresa.model.event.")
            .allowIfSubType("com.empresa.model.event.")
            .build();

        return JsonMapper.builder()
            .disable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES)
            .deactivateDefaultTyping()
            .polymorphicTypeValidator(ptv)
            .build();
    }
}
```

```java
// ✅ GOOD: Mapeamento polimórfico explícito por nome lógico
@JsonTypeInfo(
    use = JsonTypeInfo.Id.NAME,
    include = JsonTypeInfo.As.PROPERTY,
    property = "type"
)
@JsonSubTypes({
    @JsonSubTypes.Type(value = CreditCardPayment.class, name = "CREDIT_CARD"),
    @JsonSubTypes.Type(value = PixPayment.class, name = "PIX")
})
public sealed interface PaymentMethod permits CreditCardPayment, PixPayment {}
```

---

## 3. kotlinx.serialization e Polimorfismo Fechado

Em projetos Kotlin, a biblioteca `kotlinx.serialization` compila os serializadores de forma determinística e tipada,
eliminando gadget attacks por reflexão arbitrária.
Ao trabalhar com interfaces polimórficas:

- Utilize hierarquias seladas (`sealed class` ou `sealed interface`).
- Evite deserializar para `Any` ou interfaces abertas sem controle de classes derivadas.

---

## 4. Segurança de Supply Chain em Maven e Gradle

### Gradle: Verificação de Metadados e Dependency Locking

No Gradle 8 e 9, ative a verificação estrita de somas de verificação (checksums) e assinaturas PGP de todas as
dependências baixadas:

```bash
# Habilita geração e conferência de checksums estritos
./gradlew --write-verification-metadata sha256 help
```

Arquivo gerado: `gradle/verification-metadata.xml`. No CI, adicione a verificação:

```bash
./gradlew build --dependency-verification=strict
```

### Maven: Enforcer Plugin e Checksums

No Maven, utilize o `maven-enforcer-plugin` para bloquear dependências duplicadas, forçar versões de bibliotecas e
proibir repositórios HTTP não criptografados:

```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-enforcer-plugin</artifactId>
    <version>3.5.0</version>
    <executions>
        <execution>
            <id>enforce-security</id>
            <goals><goal>enforce</goal></goals>
            <configuration>
                <rules>
                    <banDuplicatePomDependencyVersions/>
                    <requireReleaseDeps>
                        <onlyWhenRelease>true</onlyWhenRelease>
                    </requireReleaseDeps>
                </rules>
            </configuration>
        </execution>
    </executions>
</plugin>
```

---

## 5. Triagem de CVEs, Alcançabilidade e VEX

Nem todo CVE reportado por scanners (como Dependabot ou OWASP Dependency Check) é explorável no contexto da sua
aplicação.

### Critérios de Triagem e Priorização

1. **Alcançabilidade (*Reachability*):** O código vulnerável da dependência é realmente invocado ou configurado no fluxo
   de execução do seu microsserviço?
2. **CISA KEV (Known Exploited Vulnerabilities):** O CVE está sendo ativamente explorado na internet? Se sim, prioridade
   imediata.
3. **EPSS (Exploit Prediction Scoring System):** Score de probabilidade de exploração nos próximos 30 dias.
4. **Declarações VEX (Vulnerability Exploitability eXchange):** Documente explicitamente decisões de falso positivo ou
   não alcançabilidade via arquivos VEX (`vex.json`) para que os gates de CI não bloqueiem deploys por ruído.

---

## 6. SBOM (CycloneDX) e Assinatura de Artefatos

### Geração de SBOM no Build

Gere o Software Bill of Materials no formato padrão **CycloneDX** a cada build de release:

```xml
<!-- pom.xml -->
<plugin>
    <groupId>org.cyclonedx</groupId>
    <artifactId>cyclonedx-maven-plugin</artifactId>
    <version>2.9.2</version>
    <executions>
        <execution>
            <phase>package</phase>
            <goals><goal>makeAggregateBom</goal></goals>
        </execution>
    </executions>
</plugin>
```

### Assinatura com Cosign (Sigstore)

Assine o artefato JAR e a imagem OCI para assegurar a integridade e a procedência do binário em produção:

```bash
# Assina a imagem no registro utilizando OIDC no pipeline
cosign sign --yes registry.empresa.com.br/backend/servico:1.0.0
```

---

## 7. Hardening de GitHub Actions e Pipelines de CI/CD

Workflows do GitHub Actions são vetores frequentes de comprometimento de credenciais e supply chain poisoning.

### Checklist Obrigatório

- [ ] **Menor Privilégio em `permissions`:** Defina `permissions: read-all` ou `contents: read` no topo de todo
  workflow.
- [ ] **Fixação de Actions por Commit SHA Completo:** Nunca use tags mutáveis como `@v4` ou `@main`. Use o SHA de 40
  caracteres:
  ```yaml
  # ❌ BAD: Tag mutável pode ser sequestrada
  uses: actions/checkout@v4

  # ✅ GOOD: Fixado por commit SHA imutável
  uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
  ```
- [ ] **Prevenção de Script Injection em `run:`:** Nunca interpole expressões não confiáveis
  (`${{ github.event.issue.title }}`) diretamente no script shell. Passe-as via variáveis de ambiente:
  ```yaml
  # ❌ VULNERABLE: Injeção de comando shell no CI
  run: echo "PR: ${{ github.head_ref }}"

  # ✅ GOOD: Passagem segura via env var
  env:
    PR_HEAD: ${{ github.head_ref }}
  run: echo "PR: $PR_HEAD"
  ```
- [ ] **Autenticação OIDC:** Utilize federação de identidade OpenID Connect para comunicação com provedores de nuvem
  (AWS IAM Roles, GCP Workload Identity, Vault) em vez de credenciais estáticas de longa duração gravadas nos Secrets do
  repositório.

---

## 8. Dockerfile Hardening

Construa imagens seguras e imutáveis com **Distroless** e usuários não privilegiados:

```dockerfile
# Multi-stage build com base Java 25 LTS
FROM eclipse-temurin:25-jdk-noble AS build
WORKDIR /app
COPY . .
RUN ./gradlew bootJar --no-daemon

# Imagem final de runtime: Google Distroless (sem shell, sem package manager)
FROM gcr.io/distroless/java25-debian12:nonroot AS runtime

WORKDIR /app
COPY --from=build --chown=nonroot:nonroot /app/build/libs/app.jar /app/app.jar

# Roda com usuário não privilegiado predefinido no distroless (UID 65532)
USER nonroot

EXPOSE 8080
ENTRYPOINT ["java", "-XX:+UseZGC", "-jar", "app.jar"]
```

---

## 9. Hardening de Manifestos Kubernetes

Os pods devem aderir ao perfil **Restricted** do Kubernetes Pod Security Standards:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ms-sdui-composer
  namespace: production
spec:
  template:
    spec:
      automountServiceAccountToken: false # Desabilita injeção do token do K8s se não for cliente da API K8s
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        runAsGroup: 65532
        fsGroup: 65532
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: app
          image: registry.empresa.com.br/ms-sdui-composer@sha256:7f3b...
          securityContext:
            readOnlyRootFilesystem: true # Filesystem imutável
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL # Remove todas as capabilities do Linux
          resources:
            limits:
              cpu: "2"
              memory: "2Gi"
            requests:
              cpu: "500m"
              memory: "1Gi"
```
