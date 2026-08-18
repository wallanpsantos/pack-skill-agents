# Criptografia Pós-Quântica e Resistência a Computação Quântica

Relevante para sistemas com dados de retenção longa ou alto valor de ameaça — bancos, meios de pagamento,
seguradoras, prontuários médicos e sistemas hospitalares. Não é um item do OWASP Top 10:2025 (a OWASP ainda não
publicou uma categoria dedicada a isso); trate como extensão setorial, no mesmo espírito da seção AI/ML Security do
SKILL.md.

## Conteúdo
- Por que isso importa agora (Harvest Now, Decrypt Later)
- O que quebra e o que não quebra
- Padrões NIST (FIPS 203/204/205)
- Suporte em Java: JDK nativo vs Bouncy Castle
- Key Encapsulation para dados em repouso (código)
- Assinatura digital com ML-DSA (código)
- TLS em trânsito — hybrid key exchange
- Tamanho de chave/assinatura — impacto prático (JWT, mensageria financeira)
- Priorização por risco — o que migrar primeiro
- Panorama regulatório por setor
- Crypto-agility como princípio arquitetural

---

## Por que Isso Importa Agora

Um computador quântico criptograficamente relevante (capaz de quebrar RSA/ECC em escala) ainda não existe. O risco
que existe **hoje** é **Harvest Now, Decrypt Later (HNDL)**: um adversário intercepta e armazena tráfego
criptografado ou backups hoje, e descriptografa quando um computador quântico capaz estiver disponível. Isso importa
especificamente para dados com retenção longa — prontuário médico, histórico de crédito, dados de apólice de
seguro, registros contábeis — porque a janela de exposição não é "quando o computador quântico existir", é
"desde o dia em que o dado foi capturado".

## O Que Quebra e o Que Não Quebra

Nem toda criptografia é afetada da mesma forma. Isso decide se o item da checklist é "aumentar o tamanho da chave"
(barato) ou "trocar de algoritmo" (migração real).

| Tipo                                   | Algoritmos Atuais         | Efeito da Computação Quântica                                  | Ação                          |
|------------------------------------------|----------------------------|------------------------------------------------------------------|--------------------------------|
| Assimétrica (troca de chave)             | RSA, ECDH, DH               | Shor's algorithm quebra por completo (não é questão de tamanho de chave) | Migrar para ML-KEM (ou híbrido) |
| Assimétrica (assinatura)                 | RSA, ECDSA, EdDSA            | Shor's algorithm quebra por completo                             | Migrar para ML-DSA (ou híbrido) |
| Simétrica (cifragem)                     | AES-128, AES-256             | Grover's algorithm dá apenas speedup quadrático (reduz a segurança pela metade em bits) | AES-256 já tem margem suficiente; evite AES-128 para dados de retenção longa |
| Hash                                     | SHA-256, SHA-384, SHA-512    | Efeito marginal em resistência a colisão                         | SHA-256 permanece adequado; SHA-384/512 dão margem extra (é o que a CNSA 2.0 exige) |

Ou seja: o item "Ban AES/ECB" e "AES-256" que já está em `references/ssrf-crypto-secrets.md` continua sendo a
orientação correta para criptografia simétrica — o problema quântico não está ali, está na troca de chave e na
assinatura assimétrica.

## Padrões NIST

Em agosto de 2024, o NIST finalizou os três padrões primários após um processo de padronização de oito anos:

| Padrão   | Algoritmo | Substitui                | Uso                      |
|----------|-----------|----------------------------|---------------------------|
| FIPS 203 | ML-KEM (ex-CRYSTALS-Kyber) | RSA/ECDH para troca de chave | Key Encapsulation Mechanism |
| FIPS 204 | ML-DSA (ex-CRYSTALS-Dilithium) | RSA/ECDSA para assinatura | Assinatura digital |
| FIPS 205 | SLH-DSA (ex-SPHINCS+) | — | Assinatura digital, fallback baseado em hash (fundamentação matemática diferente do ML-DSA, para diversidade criptográfica) |

Cada algoritmo tem parâmetros de nível de segurança crescente (ex.: ML-KEM-512/768/1024, ML-DSA-44/65/87). Para a
maioria das aplicações comerciais, **ML-KEM-768** e **ML-DSA-65** são o ponto de partida recomendado — equivalem
aproximadamente a AES-192 em força de segurança. Sistemas com exigência regulatória mais alta (ex.: CNSA 2.0, ver
seção de panorama regulatório) usam ML-KEM-1024/ML-DSA-87.

Em março de 2025 o NIST selecionou HQC como um quinto algoritmo (KEM alternativo, baseado em códigos, backup não
lattice-based para o ML-KEM), com padronização final ainda em andamento. Trate ML-KEM/ML-DSA como a resposta atual,
não a definitiva — a escolha de algoritmo deve ficar isolada atrás de uma interface (ver Crypto-Agility, ao final).

## Suporte em Java: JDK Nativo vs Bouncy Castle

| Caminho                  | Requisito         | Cobre                                              | Não cobre                          |
|---------------------------|--------------------|------------------------------------------------------|--------------------------------------|
| JDK nativo (JEP 496/497)  | JDK 24+            | `KeyPairGenerator`, `KEM`, `KeyFactory` (ML-KEM); `KeyPairGenerator`, `Signature`, `KeyFactory` (ML-DSA) | TLS (`javax.net.ssl`) até o JDK 26 — ver seção de TLS |
| Bouncy Castle (`BC`)      | Java 21+           | Mesma API JCA (`KeyPairGenerator.getInstance("ML-KEM", "BC")`), mais TLS via provider `BCJSSE` | — |

A partir do `bcprov-jdk18on` 1.79+, o Bouncy Castle alinhou os nomes de algoritmo ao padrão JCA definido pelas
JEPs — ou seja, o mesmo código funciona com o provider `SUN`/`SunJCE` nativo do JDK 24+ ou com o provider `BC`,
trocando apenas o nome do provider. Isso é o que viabiliza portar o mesmo código entre Java 21 (produção hoje, via
BC) e Java 25+ LTS (nativo, quando a organização migrar).

```xml
<dependency>
    <groupId>org.bouncycastle</groupId>
    <artifactId>bcprov-jdk18on</artifactId>
    <version>1.84</version>
</dependency>
```

**Nota de versão:** confirme a versão atual do `bcprov-jdk18on` no momento da implementação — cripto pós-quântica é
uma área ativa, e travar a auditoria numa versão específica sem revalidar é, por si só, um risco.

## Key Encapsulation para Dados em Repouso

O padrão prático mais imediato para a maioria dos serviços backend não é reescrever TLS — é envelope encryption:
usar ML-KEM para encapsular a chave simétrica (AES) que efetivamente cifra o dado. O dado grande continua sendo
cifrado com AES-256/GCM (que já é seguro pós-quântico); o ML-KEM protege apenas a troca da chave AES.

```java
// ✅ GOOD: Envelope encryption com ML-KEM protegendo a chave AES (Bouncy Castle, Java 21+).
import org.bouncycastle.jcajce.spec.MLKEMParameterSpec;
import org.bouncycastle.jce.provider.BouncyCastleProvider;
import javax.crypto.KEM;
import javax.crypto.SecretKey;
import javax.crypto.spec.KTSParameterSpec;
import java.security.*;

public class EnvelopeEncryption {

    static { Security.addProvider(new BouncyCastleProvider()); }

    // Gerado uma vez por titular da chave (ex.: por tenant, por cofre de chaves).
    // Em produção, a chave privada fica em KMS/HSM — nunca em memória de aplicação sem proteção.
    public KeyPair gerarParDeChaves() throws Exception {
        KeyPairGenerator kpg = KeyPairGenerator.getInstance("ML-KEM", "BC");
        kpg.initialize(MLKEMParameterSpec.ml_kem_768, new SecureRandom()); // nível de segurança padrão recomendado
        return kpg.generateKeyPair();
    }

    // Lado que cifra: encapsula uma chave AES-256 usando a chave pública do titular.
    public ChaveComEncapsulacao cifrarChaveDeSessao(PublicKey chavePublicaTitular) throws Exception {
        KEM kem = KEM.getInstance("ML-KEM", "BC");
        KTSParameterSpec params = new KTSParameterSpec.Builder("AES", 256).build();
        KEM.Encapsulator encapsulator = kem.newEncapsulator(chavePublicaTitular, params, null);
        KEM.Encapsulated encapsulado = encapsulator.encapsulate();
        // encapsulado.encapsulation() vai junto com o dado cifrado (não é segredo).
        // encapsulado.key() é a chave AES-256 real — use-a para cifrar o payload com AES/GCM.
        return new ChaveComEncapsulacao(encapsulado.key(), encapsulado.encapsulation());
    }

    // Lado que decifra: recupera a mesma chave AES-256 a partir da chave privada do titular.
    public SecretKey decapsularChaveDeSessao(PrivateKey chavePrivadaTitular, byte[] encapsulacao) throws Exception {
        KEM kem = KEM.getInstance("ML-KEM", "BC");
        KTSParameterSpec params = new KTSParameterSpec.Builder("AES", 256).build();
        KEM.Decapsulator decapsulator = kem.newDecapsulator(chavePrivadaTitular, params);
        return decapsulator.decapsulate(encapsulacao);
    }

    public record ChaveComEncapsulacao(SecretKey chaveAes, byte[] encapsulacao) {}
}
```

No JDK 24+ nativo, a única mudança é a fonte do parameter spec e a remoção do argumento de provider — o resto da
API (`KeyPairGenerator`, `KEM`, `KTSParameterSpec`) é o mesmo:

```java
// Diferença ao usar o provider nativo do JDK 24+ em vez de Bouncy Castle:
import java.security.spec.NamedParameterSpec;

KeyPairGenerator kpg = KeyPairGenerator.getInstance("ML-KEM"); // sem provider — usa o SunJCE nativo
kpg.initialize(NamedParameterSpec.ML_KEM_768);
KEM kem = KEM.getInstance("ML-KEM"); // idem
```

```java
// ❌ BAD: Continuar usando apenas RSA-2048/ECDH para proteger a chave de sessão em dado com retenção
// longa (ex.: backup médico com retenção de 20 anos). Não é sobre o tamanho da chave RSA — Shor's
// algorithm quebra RSA independentemente do tamanho assim que houver hardware quântico suficiente.
KeyPairGenerator kpg = KeyPairGenerator.getInstance("RSA");
kpg.initialize(4096); // maior não ajuda contra Shor's algorithm
```

## Assinatura Digital com ML-DSA

Para assinar artefatos que precisam permanecer verificáveis por muito tempo — documentos médicos, contratos,
artefatos de build, comprovantes de transação:

```java
// ✅ GOOD: Assinar com ML-DSA (Bouncy Castle, Java 21+).
import org.bouncycastle.jcajce.spec.MLDSAParameterSpec;
import org.bouncycastle.jce.provider.BouncyCastleProvider;
import java.security.*;

public class AssinaturaDocumento {

    static { Security.addProvider(new BouncyCastleProvider()); }

    public KeyPair gerarParDeChaves() throws Exception {
        KeyPairGenerator kpg = KeyPairGenerator.getInstance("ML-DSA", "BC");
        kpg.initialize(MLDSAParameterSpec.ml_dsa_65, new SecureRandom()); // nível de segurança padrão recomendado
        return kpg.generateKeyPair();
    }

    public byte[] assinar(PrivateKey chavePrivada, byte[] documento) throws Exception {
        Signature assinatura = Signature.getInstance("ML-DSA", "BC");
        assinatura.initSign(chavePrivada);
        assinatura.update(documento);
        return assinatura.sign();
    }

    public boolean verificar(PublicKey chavePublica, byte[] documento, byte[] assinaturaBytes) throws Exception {
        Signature assinatura = Signature.getInstance("ML-DSA", "BC");
        assinatura.initVerify(chavePublica);
        assinatura.update(documento);
        return assinatura.verify(assinaturaBytes);
    }
}
```

No JDK 24+ nativo: `KeyPairGenerator.getInstance("ML-DSA")` sem provider, e
`kpg.initialize(NamedParameterSpec.ML_DSA_65)` no lugar de `MLDSAParameterSpec.ml_dsa_65` — mesma observação da
seção anterior.

## TLS em Trânsito — Hybrid Key Exchange

Isto é o ponto mais fácil de confundir: ter `ML-KEM` disponível como primitiva criptográfica **não significa** que
o handshake TLS do seu serviço já está protegido.

- **JDK 24–26:** ML-KEM existe apenas como primitiva standalone (JEP 496). O stack TLS (`javax.net.ssl`) **não**
  expõe grupos nomeados pós-quânticos — uma chamada `HttpClient`/`RestClient` comum continua negociando TLS
  clássico (x25519/secp256r1), mesmo rodando em JDK 24+.
- **JDK 27+ (JEP 527):** adiciona hybrid key exchange nativo ao `SunJSSE` — `X25519MLKEM768` (habilitado por
  padrão, sem mudança de código), mais `SecP256r1MLKEM768` e `SecP384r1MLKEM1024` (opt-in via
  `jdk.tls.namedGroups` ou `SSLParameters::setNamedGroups`).
- **Java 21 e Java 25 LTS (as versões que a maioria dos bancos/hospitais roda em produção):** como o Java segue
  ciclo de LTS a cada dois anos, o JEP 527 só chega a uma LTS no JDK 29 (2027). Até lá, hybrid TLS nativo via JSSE
  não está disponível em LTS — a rota real é o provider **BCJSSE** do Bouncy Castle como ponte.

```java
// ✅ GOOD: Habilitar hybrid key exchange via Bouncy Castle JSSE em Java 21 LTS,
// sem esperar o JDK 29.
Security.addProvider(new org.bouncycastle.jce.provider.BouncyCastleProvider());
Security.addProvider(new org.bouncycastle.jsse.provider.BouncyCastleJsseProvider());

SSLContext context = SSLContext.getInstance("TLS", "BCJSSE");
context.init(null, null, null);
SSLParameters params = context.getDefaultSSLParameters();
params.setNamedGroups(new String[]{"X25519MLKEM768", "x25519", "secp256r1"});
```

```java
// ✅ GOOD: Em JDK 27+, nenhuma mudança de código é necessária — X25519MLKEM768
// já vem habilitado por padrão no javax.net.ssl. Só vale a pena checar se o
// código não está sobrescrevendo os named groups para uma lista sem PQC.
SSLParameters params = sslSocket.getSSLParameters();
params.setNamedGroups(new String[]{"SecP384r1MLKEM1024", "X25519MLKEM768", "secp384r1", "x25519"});
sslSocket.setSSLParameters(params);
```

Para APIs expostas atrás de um API Gateway, load balancer ou CDN, verifique também se a **terminação TLS** nesse
ponto suporta hybrid key exchange — muitos desses componentes (não Java) já suportam `X25519Kyber768`/
`X25519MLKEM768` hoje, independentemente da versão do JDK da aplicação por trás. Isso costuma ser o caminho mais
rápido para proteger tráfego externo antes mesmo de tocar no código da aplicação.

## Tamanho de Chave/Assinatura — Impacto Prático

Assinaturas e chaves pós-quânticas são ordens de magnitude maiores que RSA/ECDSA. Isso tem consequência prática
direta em sistemas financeiros e em qualquer lugar com limite de tamanho de mensagem/token:

| Algoritmo         | Tamanho aproximado                          |
|--------------------|------------------------------------------------|
| ECDSA (P-256)       | ~64–72 bytes (assinatura)                      |
| ML-DSA-65           | ~3.3 KB (assinatura)                           |
| SLH-DSA             | ~8–50 KB (assinatura) — evite em caminhos de latência crítica |
| ML-KEM-768          | ~1.1–1.2 KB (chave pública + ciphertext)        |

Implicações concretas:
- Um JWT assinado com ML-DSA fica dezenas de vezes maior que um assinado com ECDSA/RS256 — pode estourar limites de
  tamanho de header HTTP em proxies/gateways já configurados para tokens clássicos.
- Mensageria financeira com limite de payload fixo (ex.: formatos legados de mensagens interbancárias) pode não
  acomodar assinaturas ML-DSA sem mudança de formato.
- SLH-DSA, apesar de ser o fallback mais conservador do NIST, tem assinaturas grandes e verificação mais lenta —
  reserve para casos onde diversidade criptográfica importa mais que desempenho (ex.: âncora de confiança de longo
  prazo), não para todo caminho de assinatura.

## Priorização por Risco — O Que Migrar Primeiro

Migrar tudo para PQC de uma vez não é o conselho correto nem o que os próprios prazos regulatórios pedem (ver
próxima seção — os prazos são escalonados por categoria, não uma data única). Priorize por **quanto tempo o dado
precisa ficar confidencial**, não por "criticidade" genérica:

1. **Alta prioridade — dados/artefatos de vida longa:** backups e dados em repouso com retenção regulatória de anos
   (prontuário médico, registro contábil, apólice de seguro), chaves-raiz de PKI interna, assinatura de código/
   firmware.
2. **Média prioridade — tráfego em trânsito de longa exposição:** TLS para replicação entre datacenters, VPNs
   site-to-site, tráfego entre serviços que atravessa rede não totalmente confiável.
3. **Baixa prioridade — artefatos de vida curta:** JWT de acesso com TTL de minutos, nonces, tokens de sessão HTTP
   — o TTL curto já limita a janela de exposição ao HNDL; migrar aqui tem retorno menor e custo de tamanho de token
   maior (ver seção anterior).

## Panorama Regulatório por Setor

Nenhuma dessas normas exige literalmente "implemente ML-KEM até [data]" para todo mundo — elas exigem inventário
criptográfico documentado e plano de migração, o que ainda assim é um item de auditoria concreto e verificável.

| Norma/Guia                        | Setor                          | O que exige hoje                                                        |
|-------------------------------------|-----------------------------------|-----------------------------------------------------------------------------|
| PCI DSS 4.0, Requisito 12.3.3        | Meios de pagamento                 | Inventário criptográfico documentado e plano de migração para algoritmos obsoletos |
| HIPAA Security Rule, atualização recente | Saúde (ePHI)                    | Análise de risco contínua deve considerar a ameaça quântica, especialmente para dados de retenção longa |
| EU DORA, Artigo 9                    | Bancos/seguradoras na UE           | Gestão de risco de TIC deve considerar ameaças quânticas à criptografia do setor financeiro |
| Roteiro PQC coordenado da UE          | Infraestrutura crítica (inclui financeiro) | Início da transição até o fim de 2026; sistemas de alto risco protegidos com PQC até o fim de 2030 |
| NIST IR 8547                          | Referência civil (EUA)             | RSA/ECC descontinuados após 2030, não permitidos após 2035                  |
| NSA CNSA 2.0                          | Sistemas de segurança nacional dos EUA | Não vincula bancos/hospitais comerciais diretamente, mas é adotado como roteiro de referência de fato pelo setor — especifica ML-KEM-1024/ML-DSA-87, com transições escalonadas entre 2030–2033 |

Trate esta tabela como ponto de partida para uma auditoria de conformidade, não como texto legal — confirme a
versão vigente de cada norma com o time de compliance/jurídico antes de reportar um achado como não conformidade.

## Crypto-Agility Como Princípio Arquitetural

O ponto mais importante desta seção não é "use ML-KEM" — é que a escolha de algoritmo não deve estar espalhada
pelo código. Os próprios algoritmos recomendados aqui provavelmente não serão os finais (ver nota sobre HQC,
acima).

```java
// ❌ BAD: Nome de algoritmo hardcoded em dezenas de call sites.
// Trocar de RSA para ML-KEM (ou de ML-KEM para o que vier depois) vira uma
// migração de código inteira, não uma troca de configuração.
KeyPairGenerator.getInstance("RSA");
```

```java
// ✅ GOOD: Algoritmo isolado atrás de uma abstração/configuração central,
// resolvido em um único ponto.
KeyPairGenerator.getInstance(cryptoConfig.getKeyExchangeAlgorithm());
```

Itens concretos de crypto-agility para revisar:
- O nome do algoritmo está centralizado em configuração (Spring `@ConfigurationProperties`, variável de ambiente),
  não espalhado como string literal?
- O formato de serialização de chave/certificado suporta os dois algoritmos durante a transição (esquemas híbridos
  clássico+PQC, ex.: certificados X.509 com `DeltaCertificateDescriptor` para migração gradual)?
- Existe um inventário criptográfico (Cryptographic Bill of Materials) atualizado — quais algoritmos, em quais
  serviços, protegendo quais dados?

## Ferramentas e Referências

| Ferramenta/Fonte                          | Uso                                                              |
|----------------------------------------------|---------------------------------------------------------------------|
| NIST CSRC — PQC Standardization               | Especificação oficial dos FIPS 203/204/205 e status do HQC          |
| OpenJDK JEP 496, 497, 527                     | Especificação exata da API Java nativa (ML-KEM, ML-DSA, TLS híbrido) |
| Bouncy Castle PQC Almanac (`downloads.bouncycastle.org`) | Referência de API para quem está em Java 21–23 ou precisa de TLS híbrido antes do JDK 29 |
| NSA CNSA 2.0 Guidance                         | Roteiro de referência de facto para prazos de migração             |

## Referências

- NIST — [Post-Quantum Cryptography Standardization Project](https://csrc.nist.gov/pqc-standardization)
- NIST — [FIPS 203: Module-Lattice-Based Key-Encapsulation Mechanism Standard (ML-KEM)](https://csrc.nist.gov/pubs/fips/203/final)
- NIST — [FIPS 204: Module-Lattice-Based Digital Signature Standard (ML-DSA)](https://csrc.nist.gov/pubs/fips/204/final)
- NIST — [FIPS 205: Stateless Hash-Based Digital Signature Standard (SLH-DSA)](https://csrc.nist.gov/pubs/fips/205/final)
- OpenJDK — [JEP 496: Quantum-Resistant Module-Lattice-Based Key Encapsulation Mechanism](https://openjdk.org/jeps/496)
- OpenJDK — [JEP 497: Quantum-Resistant Module-Lattice-Based Digital Signature Algorithm](https://openjdk.org/jeps/497)
- OpenJDK — [JEP 527: Hybrid Key Exchange in TLS 1.3](https://openjdk.org/jeps/527)
- NSA — [Announcing the Commercial National Security Algorithm Suite 2.0 (CNSA 2.0)](https://www.nsa.gov/Press-Room/News-Highlights/Article/Article/3148990/nsa-releases-future-quantum-resistant-qr-algorithm-requirements-for-national-se/)
- Bouncy Castle — [bouncycastle.org](https://www.bouncycastle.org/) (documentação de API e PQC Almanac)
- PCI Security Standards Council — [Document Library](https://www.pcisecuritystandards.org/document_library) (PCI DSS 4.0, Requisito 12.3.3)
- HHS — [HIPAA Security Rule](https://www.hhs.gov/hipaa/for-professionals/security/index.html)
- EUR-Lex — [Regulation (EU) 2022/2554 (DORA)](https://eur-lex.europa.eu/eli/reg/2022/2554/oj)

**Nota:** os links de FIPS 204/205, JEP 497 e o roteiro da UE seguem o mesmo padrão de URL confirmado para FIPS 203,
JEP 496 e CNSA 2.0 respectivamente, mas não foram individualmente verificados nesta revisão — confirme antes de citar
em um relatório de compliance formal. Esta é uma área regulatória em movimento; revalide os links periodicamente.
