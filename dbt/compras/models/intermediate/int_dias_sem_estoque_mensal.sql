-- ─────────────────────────────────────────────────────────────────────────────
-- Origem: CTE `dias_sem_estoque_mensal`, relatorios_compras/query_mensal.py
-- (conferido também contra app_relatorios/relatorios/compras_mensal.py).
--
-- Grão: mês × produto. Equivalente ao QT_DIAS_SEM_ESTOQUE da rotina 2080: dias
-- em que PCHISTEST.QTESTGER = 0, restrito à filial de estoque
-- (var('compras_filial_estoque', '2')).
--
-- É a ÚNICA coluna do relatório mensal específica de filial - faturamento e
-- devolução (int_faturamento_mensal / int_devolucao_mensal) são consolidados
-- em todas as filiais. Não estenda esse filtro para os outros models.
--
-- stg_historico_estoque tem 117 milhões de linhas: o filtro de filial e o
-- filtro de data (semiaberto, >= inicio AND < fim) precisam vir cedo.
--
-- Os limites de data vêm de int_periodo_mensal (ref, uma linha), não mais da
-- macro expandida direto aqui - ver o cabeçalho de int_periodo_mensal para o
-- porquê (janela dessincronizada em build parcial).
-- ─────────────────────────────────────────────────────────────────────────────

with periodo as (
    select * from {{ ref('int_periodo_mensal') }}
),

historico_estoque as (
    select h.*
      from {{ ref('stg_historico_estoque') }} h
     cross join periodo pe
     where h.id_filial = '{{ var("compras_filial_estoque", "2") }}'
       and h.quantidade_gerencial = 0
       and h.data >= pe.data_inicio
       and h.data <  pe.data_fim
),

final as (
    select
        trunc(h.data, 'MM') as mes,
        h.id_produto,
        count(distinct h.data) as dias_sem_estoque
      from historico_estoque h
     group by trunc(h.data, 'MM'), h.id_produto
)

select * from final
