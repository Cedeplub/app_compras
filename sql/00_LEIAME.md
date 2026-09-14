# sql/ — DDL do schema COMPRAS, na ordem de execução

Repositório novo (Etapa 14, Fase D). Sobe o schema `COMPRAS` do zero numa base
limpa. Cada script é idempotente (checa `USER_TABLES`/`USER_INDEXES` antes de
criar) e pode rodar de novo sem derrubar dado. Rodar na ordem abaixo.

**O que este `sql/` NÃO faz:** não toca no `CEDEP` (só concede `SELECT` nele, no
script 01), não recria nenhuma `COMPRAS_*`, `DIM_*`, `INT_*`, `STG_*` ou
`FAT_*` — essas são do dbt e nascem de `dbt seed` + `dbt run`.

| Ordem | Arquivo | O que faz | Rodar como |
|---|---|---|---|
| 1 | `01_usuario_compras.sql` | Cria o usuário `COMPRAS` (se não existir), privilégios de sistema, `GRANT SELECT` nominal nas 19 tabelas do `CEDEP` usadas pelo plano dbt. | SYSTEM ou DBA nominal |
| 2 | `02_tabelas_auth.sql` | `APP_USUARIO`, `APP_SESSAO`, `APP_AUDITORIA` — contas, sessões e trilha de auditoria do dashboard. | COMPRAS |
| 3 | `03_tabelas_decisao.sql` | `APP_DECISAO_PRECO` (+ `APP_DECISAO_PRECO_HIST`) — decisão vigente de margem/preço por produto e o histórico de valores anteriores. | COMPRAS |
| 4 | `04_tabelas_pedido.sql` | `APP_PEDIDO`, `APP_PEDIDO_ITEM`, `APP_PEDIDO_STATUS_HIST` — o pedido de compra da v2 (cabeçalho, itens, máquina de estados). | COMPRAS |
| 5 | `05_tabelas_lote_preco.sql` | `APP_LOTE_PRECO`, `APP_LOTE_PRECO_ITEM`, `APP_LOTE_PRECO_STATUS_HIST` — o lote de preços que sai da diretoria em direção a quem digita no Winthor. | COMPRAS |
| 6 | `06_tabela_atualizacao.sql` | `APP_ATUALIZACAO` — uma linha por execução do dbt (manual ou agendada), usada para carimbar o cabeçalho da tela. | COMPRAS |
| 98 | `98_limpar_dados.sql` | `DELETE` (não `TRUNCATE`, não `DROP`) em todas as `APP_*`, na ordem das FKs. Não comita sozinho — quem roda decide `COMMIT`/`ROLLBACK`. | COMPRAS |
| 99 | `99_revogar.sql` | Desfaz o que `01` concedeu (revoga `SELECT` no `CEDEP` e privilégios de sistema); tem, comentado, o caminho para apagar as `APP_*` e o próprio usuário. | SYSTEM ou DBA nominal |

## O que mudou nesta renumeração (Etapa 14)

- **`APP_DECISAO_PEDIDO` deixou de existir.** A única escritora era a tela v1,
  que não foi para este repositório (parada desde 25/08/2026). A v2 grava em
  `APP_PEDIDO`/`APP_PEDIDO_ITEM` desde a Etapa 9. `dbt/compras`'s
  `stg_decisao_pedido` passou a ler `APP_PEDIDO_ITEM` (mudança do `dbt-regras`,
  fora deste `sql/`).
- **Nenhuma outra tabela mudou de forma.** Só a numeração dos arquivos e o
  agrupamento por assunto mudaram; `CREATE TABLE`, `CONSTRAINT`, `COMMENT ON`
  de toda tabela que sobrevive são os mesmos de antes da Etapa 14.
- Os arquivos antigos eram: `01_usuario_compras.sql` (igual),
  `02_tabelas_app.sql` (virou `02_tabelas_auth.sql` + `03_tabelas_decisao.sql`,
  perdendo a seção de `APP_DECISAO_PEDIDO`), `03_tabelas_pedido.sql` (virou
  `04_tabelas_pedido.sql`), `04_tabela_atualizacao.sql` (virou
  `06_tabela_atualizacao.sql`), `05_tabelas_lote_preco.sql` (manteve o nome e
  o número), `99_revogar.sql` (atualizado para a lista de tabelas atual).

## Senha

Nenhum script tem senha em texto. `01_usuario_compras.sql` usa `&senha`
(SQL*Plus `ACCEPT ... HIDE`), preenchida interativamente na hora da execução —
nunca na linha de comando.
