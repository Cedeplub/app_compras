-- Enquanto NENHUMA linha de seed_sucessao estiver ATIVO='SIM', a sucessao tem
-- que ser IDENTICA ao pivot, linha a linha - a heranca so pode mudar valor
-- quando alguem ativar uma sucessao de verdade. Quando existir ATIVO='SIM'
-- este teste se desliga sozinho (o WHERE NOT EXISTS zera o resultado) porque
-- ai a divergencia passa a ser o comportamento CORRETO, nao um defeito.
--
-- ⚠️ No Oracle, MINUS e UNION ALL tem a MESMA precedencia e avaliam da
-- esquerda para a direita. Sem parenteses em CADA bloco, "P minus S union all
-- S minus P" nao e (P-S) union all (S-P): reduz para so "S-P", e o teste
-- passa a testar UMA direcao (sucessao perdendo linha do pivot passa
-- despercebido). Por isso os dois blocos abaixo vao entre parenteses
-- proprios, nao so um parenteses externo em volta de tudo.
--
-- Lista de colunas explicita (nao "select *"): int_venda_mensal_sucessao tem
-- uma coluna a mais que o pivot, vd_ant_3m (revisao etapa 3, impeditivo 2) -
-- nao tem equivalente no pivot (o pivot expoe q03/q04/q05 crus, nao a media),
-- entao nao entra nesta comparacao. Desde a MELHORIA D1 ela herda com os DOIS
-- pesos, como as colunas irmas - o que nao muda nada aqui, porque com
-- ATIVO='NAO' em todas as linhas nenhuma heranca e' aplicada. MINUS exige o MESMO NUMERO de colunas nos dois lados - "select
-- *" quebraria em erro de compilacao (numero de colunas incompativel), nao
-- em divergencia de dado.
with pivot as (
    select
        codigo_produto, q00, q01, q02, q03, q04, q05, q06, q07, q08, q09, q10, q11,
        v00, v01, v02, v03, v04, v05,
        qatual, vatual, cli_atac_atual, cli_var_atual, dias_sem_est_atual, fora_de_linha,
        tx_devolucao_3m, cli_atac_00, cli_var_00, dias_sem_est_00,
        med02, med03, med04, med06, med09, med12
      from {{ ref('int_venda_mensal_pivot') }}
),

sucessao as (
    select
        codigo_produto, q00, q01, q02, q03, q04, q05, q06, q07, q08, q09, q10, q11,
        v00, v01, v02, v03, v04, v05,
        qatual, vatual, cli_atac_atual, cli_var_atual, dias_sem_est_atual, fora_de_linha,
        tx_devolucao_3m, cli_atac_00, cli_var_00, dias_sem_est_00,
        med02, med03, med04, med06, med09, med12
      from {{ ref('int_venda_mensal_sucessao') }}
)

select * from (
    (
        select * from pivot
        minus
        select * from sucessao
    )
    union all
    (
        select * from sucessao
        minus
        select * from pivot
    )
)
where not exists (
    select 1 from {{ ref('seed_sucessao') }} where ATIVO = 'SIM'
)
