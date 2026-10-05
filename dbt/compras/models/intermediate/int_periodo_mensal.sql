-- ─────────────────────────────────────────────────────────────────────────────
-- Por que este model existe: sem ele, compras_periodo_inicio()/compras_periodo_fim()
-- eram reavaliadas de forma INDEPENDENTE em quatro models materializados em
-- separado (int_faturamento_mensal, int_devolucao_mensal,
-- int_dias_sem_estoque_mensal e a espinha `meses` de int_venda_mensal). Cenário
-- real: build completo em 31/08; em 01/09 alguém roda
-- `dbt run --select int_venda_mensal` sozinho para iterar no model - a espinha
-- `meses` passa a incluir 09/2026 (SYSDATE mudou de mês) enquanto
-- int_faturamento_mensal ainda está parado em 08/2026. 09/2026 entra na saída
-- com quantidade e valor ZERADOS para todo SKU, via produtos_incluir - sem erro,
-- sem linha faltando, só número errado. Aqui a janela é calculada UMA VEZ e
-- gravada; os quatro models leem por ref() (cross join), o que amarra a
-- dependência no DAG: `--select +int_venda_mensal` reconstrói a cadeia inteira
-- e todos enxergam a MESMA janela; `--select int_venda_mensal` sozinho lê o
-- int_periodo_mensal já materializado (o mesmo que os outros três leram),
-- preservando a coerência mesmo sem reconstruir tudo.
--
-- ── ⚠ qtd_meses E data_inicio TÊM DE SAIR DA MESMA VAR ─────────────────────
-- Hoje saem: `data_inicio` por compras_periodo_inicio() e `qtd_meses` pelo
-- literal — os dois lendo `var('compras_meses_historico')`. Mantenha assim.
--
-- `qtd_meses` não é informativo: int_venda_mensal_pivot.sql e
-- int_venda_mensal_sucessao.sql derivam dele `n_fechados = qtd_meses - 1`, que
-- é a GUARDA de MED02..MED12 ("tenho meses fechados suficientes para esta
-- média?"). Se alguém trocar a janela por uma data fixa (ex.: `date
-- '2019-01-01'`) e deixar `qtd_meses` como literal antigo, nada quebra de
-- forma visível — mas basta o literal cair abaixo de 12 para MED12 virar NULL,
-- `MEDIA_JANELA` virar 0 (int_produto_demanda.sql) e a SUGESTÃO DE COMPRA
-- passar a pedir a menos, em silêncio, sem nenhum teste reprovar.
--
-- Com data fixa, `qtd_meses` TEM de passar a ser calculado:
--   months_between(data_fim, trunc(data_inicio, 'MM'))
-- Foi por isso que, em 05/10/2026, a ampliação para 96 meses foi feita como
-- janela MÓVEL (subindo a var) e não como piso fixo em 2019, que era o pedido
-- literal — ver o comentário da var em dbt_project.yml.
--
-- Grão: 1 linha só.
-- ─────────────────────────────────────────────────────────────────────────────

with periodo as (
    select
        {{ compras_periodo_inicio() }} as data_inicio,
        {{ compras_periodo_fim() }}    as data_fim,
        {{ var('compras_meses_historico', 96) }} as qtd_meses,
        trunc(sysdate, 'MM') as mes_corrente
      from dual
),

final as (
    select * from periodo
)

select * from final
