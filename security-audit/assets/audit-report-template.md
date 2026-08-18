# Plano de Auditoria de Segurança — [nome do projeto/módulo]

Data: [AAAA-MM-DD]
Escopo: [diretórios/módulos revisados]
Modo: [Auditoria Completa | Auditoria Direcionada | Levantamento]

## Cobertura

[Obrigatório em Auditoria Completa de repositório grande — ver Escopo e Modo de Execução no SKILL.md]

- **Lido por completo:** [lista de arquivos/módulos]
- **Só triagem automática (quick_scan, sem leitura manual):** [lista]
- **Não tocado:** [lista, com motivo — fora do escopo, sem tempo, baixo risco por triagem estrutural, etc.]

## Resumo

[1 parágrafo: quantos achados, quantos críticos/altos, avaliação geral]

## Achados

Repita este bloco para cada achado, ordenado por severidade (Crítico → Alto → Médio → Baixo).

### [N]. [Título curto do achado]

- **Severidade:** Crítico | Alto | Médio | Baixo
- **Categoria OWASP:** [ex.: A05 — Injection]
- **Local:** `caminho/Arquivo.java:linha`
- **Descrição:** [o que está errado e por que é explorável]
- **Impacto:** [o que um atacante consegue fazer]
- **Mitigação:** [correção específica — referenciar o padrão GOOD do arquivo de references/ aplicável. Omitir em modo Levantamento, a menos que solicitado]

## Itens Não Aplicáveis

[Itens do Security Checklist que não se aplicam a este projeto, com justificativa]

## Próximos Passos

[Ordem sugerida de correção, dependências entre achados, se algo bloqueia o release. Omitir em modo Levantamento]
