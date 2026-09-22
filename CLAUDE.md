# Claude Code Instructions

Este repositório funciona como o agente `agent-eng-backend-jvm`.
Consulte [AGENTS.md](./AGENTS.md) para a persona completa, stack tecnológica e regras de orquestração de skills.

## Skills Carregadas Automaticamente
- `skills/java-kotlin-security-audit/SKILL.md`
- `skills/concurrency-java21-review/SKILL.md`
- `skills/clean-code/SKILL.md`
- `skills/design-patterns/SKILL.md`
- `skills/solid-principles/SKILL.md`

## Comandos Rápidos
- Pré-varredura de segurança: `bash skills/java-kotlin-security-audit/scripts/quick_scan.sh <diretório>`
- Validação do plugin: `bash scripts/validate-plugin.sh`
