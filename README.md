# App Compras CEDEP

Versão online do modelo de compras e precificação da diretoria de Compras — hoje uma
planilha Excel de 8.772 SKUs e ~980 mil fórmulas. Dois entregáveis: um fluxo **dbt** que
reproduz a lógica em SQL, e um **dashboard** que lê o resultado.

**Comece por `STATUS.md`** — onde o projeto está, o que está no ar e quais decisões
seguem abertas. Depois **`CONTEXTO.md`**, que é o documento canônico: convenções,
fronteira de acesso ao banco e o índice das regras de negócio. O detalhe dessas regras,
com as armadilhas medidas e os critérios de aceite, está em **`REGRAS.md`** — separado
para que quem trabalha em `.bat`, DDL ou tela não precise carregar 460 linhas de regra
fiscal a cada tarefa.

## Estrutura

```
STATUS.md          onde estamos: etapas, o que está no ar, decisões abertas
CONTEXTO.md        documento canônico — todo agente lê antes de trabalhar
REGRAS.md          o detalhe das regras de negócio, fiscais e de validação
MELHORIAS.md       divergências deliberadas da planilha, com efeito medido
PENDENCIAS_DIRETORIA.md   as 5 divergências PDF x planilha (todas decididas)
.claude/agents/    os 9 agentes de desenvolvimento
docs/              gabaritos extraídos da planilha e do PDF
referencia/        a planilha e o PDF originais
sql/               DDL do schema Oracle COMPRAS
dbt/compras/       o projeto dbt
validar/           scripts que comparam o dbt com a planilha
```

## A regra estrutural

```
CEDEP (WinThor)  --SELECT-->  dbt  --cria/atualiza-->  schema COMPRAS  <--le/escreve--  dashboard
```

O dbt é o único que enxerga o CEDEP, e só com SELECT. O dashboard só enxerga o schema
`COMPRAS`. Prefixo define o dono: `stg_ int_ dim_ fat_ COMPRAS_` é do dbt, `APP_` é da
aplicação.

## Agentes

O desenvolvimento é feito por agentes especializados, um por função, cada um no modelo
adequado ao peso da tarefa — **haiku** para o repetitivo com gabarito, **sonnet** para
implementação, **opus** só para regra fiscal e revisão.

| Agente | Modelo | Função |
|---|---|---|
| `oracle-dba` | sonnet | schema, GRANTs, tabelas `APP_*` |
| `dbt-staging` | haiku | models `stg_*` e seeds |
| `dbt-relatorios` | sonnet | porte do SQL dos dois relatórios |
| `dbt-regras` | opus | fiscal, custo, margem, preço, ABC, alertas |
| `validador` | sonnet | comparação numérica contra a planilha |
| `backend-fastapi` | sonnet | rotas, auth, acesso ao schema |
| `frontend-htmx` | sonnet | telas Jinja2 + HTMX + Tailwind |
| `infra-windows` | haiku | `.bat`, NSSM, nginx, agendamento |
| `revisor` | opus | revisão de cada etapa, somente leitura |

Agente novo ou alterado só passa a valer depois de reiniciar o Claude Code — o registro
é carregado na inicialização da sessão.

## Etapas

A = agentes · 0 = infra Oracle · 1 = dbt staging+seeds · 2 = reprodução dos relatórios ·
3 = consolidação por SKU · 4 = aba `pedido` em SQL · 5 = camada de contrato ·
6 = dashboard · 7 = produção (nginx + NSSM) · 8 = acesso externo.

Nenhuma etapa começa antes de a anterior ser aprovada, e cada uma passa pelo `revisor`
antes de ir para aprovação.

## Critério de aceite final

`fat_pedido` comparado célula a célula com a aba `pedido`: 122 colunas × 8.772 linhas,
tolerância 0,01.
