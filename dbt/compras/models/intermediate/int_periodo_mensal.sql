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
-- Grão: 1 linha só.
-- ─────────────────────────────────────────────────────────────────────────────

with periodo as (
    select
        {{ compras_periodo_inicio() }} as data_inicio,
        {{ compras_periodo_fim() }}    as data_fim,
        {{ var('compras_meses_historico', 24) }} as qtd_meses,
        trunc(sysdate, 'MM') as mes_corrente
      from dual
),

final as (
    select * from periodo
)

select * from final
