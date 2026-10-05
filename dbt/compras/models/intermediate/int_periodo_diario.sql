-- ─────────────────────────────────────────────────────────────────────────────
-- int_periodo_diario — a janela de int_faturamento_diario, int_devolucao_diaria
-- e int_venda_diaria (v2 Etapa 10, tela Monitoramento). Mesmo motivo de
-- int_periodo_mensal existir: se cada um dos três models reavaliasse
-- `trunc(sysdate)` por conta própria, um `dbt run --select int_venda_diaria`
-- isolado, rodado do outro lado da meia-noite de um `dbt run` anterior,
-- deixaria a espinha de dias mais larga que int_faturamento_diario/
-- int_devolucao_diaria - dia novo entrando com quantidade/valor ZERADOS sem
-- erro nenhum. Aqui a janela é calculada UMA VEZ; os dois models de
-- faturamento/devolução leem por ref(), e int_venda_diaria herda a janela deles
-- (não lê este model direto — não precisa, porque não tem espinha de dias
-- própria, ao contrário de int_venda_mensal, que TEM e por isso precisa).
--
-- ── ⚠ A JANELA MUDOU EM 05/10/2026: de 400 DIAS para 96 MESES ───────────────
-- Era `trunc(sysdate) - var('compras_monitoramento_dias_historico', 400) + 1`,
-- justificado assim: "granularidade de Dia/Semana só precisa alcançar UM
-- ano-anterior completo; comparação de Mês/Ano usa COMPRAS_VENDA_MENSAL - não
-- este model".
--
-- A premissa estava ERRADA, e o defeito era visível na tela: o backend
-- (`app/servicos/monitoramento.py`) recebe `de`/`ate` prontos da tela e soma
-- COMPRAS_MONITORAMENTO para TODAS as granularidades — Ano inclusive. Nunca
-- existiu caminho que lesse COMPRAS_VENDA_MENSAL; aquela tabela não tem leitor
-- nenhum, e nem teria como servir esta tela, porque não tem as colunas de
-- PESO/LITRAGEM que as métricas do Monitoramento usam. Com 400 dias, portanto,
-- escolher "Ano" e voltar um período devolvia tela vazia — não por falta de
-- dado (o CEDEP tem histórico desde 06/2013), mas por falta de janela.
--
-- Agora são `var('compras_monitoramento_meses_historico', 96)` meses, o MESMO
-- valor de compras_meses_historico, e ALINHADOS PELO MÊS (add_months sobre
-- trunc(sysdate,'MM')), não por dia corrido. O alinhamento não é cosmético: faz
-- a janela diária e a mensal começarem no mesmo mês, que é o que o teste
-- compras_venda_diaria_bate_mensal já assume ao reconciliar os dois grãos
-- apenas em meses completos.
--
-- Custo medido: COMPRAS_MONITORAMENTO passa de ~339 mil para ~2,0 milhões de
-- linhas. O build cresce pouco (o peso é a varredura do PCMOV, que acontece com
-- qualquer janela); quem degradaria de verdade eram três consultas de LISTA DE
-- FILTRO sem recorte de data em monitoramento.py — por isso elas ganharam
-- `DIAS_LISTA_FILTROS` lá, mantendo o alcance que já tinham.
--
-- Grão: 1 linha só.
-- ─────────────────────────────────────────────────────────────────────────────

with periodo as (
    select
        add_months(trunc(sysdate, 'MM'),
                   -({{ var('compras_monitoramento_meses_historico', 96) }} - 1)) as data_inicio,
        -- Fim continua no DIA seguinte a hoje, não no fim do mês: o mês corrente
        -- é parcial de propósito, e DATA_REFERENCIA (compras_parametro) depende
        -- de `max(dia)` ser o último dia COM DADO, para a comparação
        -- parcial-contra-parcial do ano anterior ser honesta.
        trunc(sysdate) + 1                                                        as data_fim,
        {{ var('compras_monitoramento_meses_historico', 96) }}                    as qtd_meses
      from dual
),

final as (
    select * from periodo
)

select * from final
