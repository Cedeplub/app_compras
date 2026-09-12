-- ─────────────────────────────────────────────────────────────────────────────
-- int_periodo_diario — a janela de int_faturamento_diario, int_devolucao_diaria
-- e int_venda_diaria (v2 Etapa 10, tela Monitoramento). Mesmo motivo de
-- int_periodo_mensal existir: se cada um dos três models reavaliasse
-- `trunc(sysdate)` por conta própria, um `dbt run --select int_venda_diaria`
-- isolado, rodado do outro lado da meia-noite de um `dbt run` anterior,
-- deixaria a espinha de dias mais larga que int_faturamento_diario/
-- int_devolucao_diaria - dia novo entrando com quantidade/valor ZERADOS sem
-- erro nenhum. Aqui a janela é calculada UMA VEZ; os três leem por ref().
--
-- {{ var('compras_monitoramento_dias_historico', 400) }} dias corridos
-- (~13 meses), DELIBERADAMENTE menor que os 24 meses de
-- compras_meses_historico/int_periodo_mensal: granularidade de Dia/Semana só
-- precisa alcançar UM ano-anterior completo, com folga para alinhamento de
-- semana (400 dias > 371 = 53 semanas). Comparação de Mês/Ano usa
-- COMPRAS_VENDA_MENSAL (24 meses, já existente) - não este model. Trazer 24
-- meses em grão DIÁRIO multiplicaria por ~30 o volume de int_venda_mensal sem
-- necessidade: nenhuma tela pede "Dia" ou "Semana" há dois anos.
--
-- Grão: 1 linha só.
-- ─────────────────────────────────────────────────────────────────────────────

with periodo as (
    select
        trunc(sysdate) - {{ var('compras_monitoramento_dias_historico', 400) }} + 1 as data_inicio,
        trunc(sysdate) + 1                                                          as data_fim,
        {{ var('compras_monitoramento_dias_historico', 400) }}                      as qtd_dias
      from dual
),

final as (
    select * from periodo
)

select * from final
