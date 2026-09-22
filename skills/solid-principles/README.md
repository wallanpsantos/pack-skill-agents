# Princípios SOLID

**Carregar**: `view .claude/skills/solid-principles/SKILL.md`

---

## Descrição

Checklist dos princípios SOLID com exemplos detalhados em Java. Cada princípio inclui exemplos de violação, soluções
refatoradas e padrões de detecção.

---

## Casos de Uso

- "Verifique se esta classe possui violações de SOLID"
- "Esta classe está fazendo coisas demais?" (SRP)
- "Como adiciono novos tipos sem modificar o código?" (OCP)
- "Por que Quadrado não deve estender Retângulo?" (LSP)
- "Esta interface é grande demais" (ISP)
- "Como tornar isso testável?" (DIP)

---

## Exemplos

```
> view .claude/skills/solid-principles/SKILL.md
> "Revise este UserService quanto aos princípios SOLID"
→ Identifica a violação do SRP, sugere a extração de validação e notificação
```

---

## Princípios Abordados

| Princípio                 | Pergunta-chave                                                 |
|---------------------------|----------------------------------------------------------------|
| **S**ingle Responsibility | Ela possui apenas um motivo para mudar?                        |
| **O**pen/Closed           | Posso estender sem modificar?                                  |
| **L**iskov Substitution   | Os subtipos podem substituir os tipos base?                    |
| **I**nterface Segregation | Os clientes são forçados a implementar métodos não utilizados? |
| **D**ependency Inversion  | Depende de abstrações?                                         |

---

## Habilidades Relacionadas

- `design-patterns` - Padrões de implementação
- `clean-code` - DRY, KISS, YAGNI
- `java-code-review` - Checklist completo de revisão

---

## Recursos

- [SOLID (Wikipedia)](https://en.wikipedia.org/wiki/SOLID)
- [Clean Code por Robert C. Martin](https://www.oreilly.com/library/view/clean-code-a/9780136083238/)
- [SOLID Principles in Java (Baeldung)](https://www.baeldung.com/solid-principles)
