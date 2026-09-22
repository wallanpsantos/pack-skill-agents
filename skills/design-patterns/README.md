# Padrões de Projeto

**Carregar**: `view .claude/skills/design-patterns/SKILL.md`

---

## Descrição

Padrões de projeto comuns com exemplos práticos em Java. Cobre padrões de criação, comportamentais e estruturais com
sintaxe moderna do Java e integração com o Spring.

---

## Casos de Uso

- "Implementar padrão factory para notificações"
- "Usar builder para este objeto complexo"
- "Como adicionar funcionalidades sem modificar a classe?" (Decorator)
- "Múltiplos métodos de pagamento, trocar em tempo de execução" (Strategy)
- "Notificar múltiplos serviços quando um pedido for realizado" (Observer)

---

## Exemplos

```
> view .claude/skills/design-patterns/SKILL.md
> "Preciso criar tipos de relatórios diferentes (PDF, Excel, CSV)"
→ Sugere o padrão Factory com exemplo de implementação
```

---

## Padrões Cobertos

| Categoria          | Padrões                             |
|--------------------|-------------------------------------|
| **Criação**        | Builder, Factory Method, Singleton  |
| **Comportamental** | Strategy, Observer, Template Method |
| **Estrutural**     | Decorator, Adapter                  |

---

## Guia de Seleção Rápida

| Problema                               | Padrão    |
|----------------------------------------|-----------|
| Muitos parâmetros no construtor        | Builder   |
| Criar sem especificar a classe         | Factory   |
| Trocar algoritmos em tempo de execução | Strategy  |
| Adicionar comportamento dinamicamente  | Decorator |
| Notificar múltiplos objetos            | Observer  |
| Integrar código legado                 | Adapter   |

---

## Habilidades Relacionadas

- `solid-principles` - Princípios que os padrões implementam
- `clean-code` - Práticas a nível de código
- `spring-boot-patterns` - Implementações no Spring

---

## Recursos

- [Refactoring Guru - Padrões de Projeto](https://refactoring.guru/design-patterns)
- [Design Patterns por Gang of Four](https://www.oreilly.com/library/view/design-patterns-elements/0201633612/)
- [Java Design Patterns (java-design-patterns.com)](https://java-design-patterns.com/)
