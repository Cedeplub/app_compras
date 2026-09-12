-- Testa que a janela mensal (mes) de int_faturamento_mensal, int_devolucao_mensal,
-- int_dias_sem_estoque_mensal e int_venda_mensal está coerente com a janela
-- registrada em int_periodo_mensal (a fonte única dos limites). Falha em rede de
-- segurança contra build parcial: se int_periodo_mensal for reconstruído sem que
-- toda a cadeia mensal acompanhe (ou vice-versa), o mês novo entra com
-- quantidade/valor ZERADOS em silêncio via produtos_incluir - é o cenário exato
-- que motivou a criação de int_periodo_mensal (ver seu cabeçalho).
--
-- Por que MIN/MAX e não "todo mês presente": int_devolucao_mensal e
-- int_dias_sem_estoque_mensal podem legitimamente não ter linha em um mês
-- (nenhuma devolução, nenhum dia de ruptura naquele mês) - isso NÃO é
-- incoerência, é dado real. O que indica janela dessincronizada é dado FORA da
-- janela declarada em int_periodo_mensal - antes do início ou depois do fim -
-- isso só acontece se o model foi construído lendo um int_periodo_mensal
-- diferente do que os demais leram. Por isso o teste sempre reprova dado fora
-- da janela (para os 4 models), e só cobra cobertura COMPLETA (mes_min = início
-- e mes_max = fim) de int_faturamento_mensal e int_venda_mensal: os dois têm,
-- por construção, garantia de pelo menos uma linha em cada mês do período -
-- int_venda_mensal por causa da espinha `meses` cruzada com `produtos_incluir`
-- (que não depende de ter havido movimento), e int_faturamento_mensal porque,
-- na prática comercial, não existe mês sem nenhuma venda faturada no catálogo
-- inteiro. Devolução e dia sem estoque não têm essa garantia estrutural.

with periodo as (
    select
        trunc(data_inicio, 'MM')             as mes_inicio,
        add_months(trunc(data_fim, 'MM'), -1) as mes_fim
      from {{ ref('int_periodo_mensal') }}
),

limites as (
    select 'int_faturamento_mensal' as origem, min(mes) as mes_min, max(mes) as mes_max
      from {{ ref('int_faturamento_mensal') }}
    union all
    select 'int_devolucao_mensal', min(mes), max(mes)
      from {{ ref('int_devolucao_mensal') }}
    union all
    select 'int_dias_sem_estoque_mensal', min(mes), max(mes)
      from {{ ref('int_dias_sem_estoque_mensal') }}
    union all
    select 'int_venda_mensal', min(mes), max(mes)
      from {{ ref('int_venda_mensal') }}
)

select
    l.origem,
    l.mes_min,
    l.mes_max,
    p.mes_inicio,
    p.mes_fim
  from limites l
 cross join periodo p
 where
    -- dado fora da janela declarada = sempre incoerencia, para qualquer model
    l.mes_min < p.mes_inicio
    or l.mes_max > p.mes_fim
    -- cobertura completa so e exigivel onde ha garantia estrutural
    or (
        l.origem in ('int_faturamento_mensal', 'int_venda_mensal')
        and (l.mes_min <> p.mes_inicio or l.mes_max <> p.mes_fim)
    )
