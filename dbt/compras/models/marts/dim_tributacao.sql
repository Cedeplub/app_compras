-- ─────────────────────────────────────────────────────────────────────────────
-- dim_tributacao — a aba `dICMS` da planilha v10, com o alcance real de cada
-- código medido no catálogo. Grão: 1 linha por COD_TRIBUTACAO (ICMS).
--
-- Qual coluna Excel reproduz: nenhuma da aba `pedido` diretamente. É a tabela
-- de apoio que BJ (COD_ICMS) busca e de onde saem BL (MODALIDADE), BM (MVA),
-- CA (ICMS_SAIDA_EF) e CB (ICMS_SEM_RED).
--
-- ── Por que o grão é o código de ICMS, e o PIS/COFINS fica de fora ─────────
-- São dois espaços de código INDEPENDENTES: `dICMS` (COD_TRIBUTACAO, 15
-- linhas) e `dPISCOFINS` (CODTRIBPISCOFINS, 3 linhas). O produto carrega um de
-- cada, mas os dois não formam par - não existe "a tributação 26/1" como
-- entidade, existe um produto que tem ICMS 26 e PIS/COFINS 1. Uma dimensão com
-- grão (cod_icms, cod_piscof) inventaria 45 combinações, das quais só um punhado
-- existe, e cada linha inventada mostraria uma alíquota de ICMS ao lado de uma
-- de PIS/COFINS como se as duas se aplicassem juntas a alguma coisa. Por isso o
-- PIS/COFINS NÃO entra: ele é `seed_piscofins`, três linhas, pequeno o bastante
-- para ser lido direto, e a alíquota efetiva de cada SKU já viaja em
-- `fat_pedido.piscof_ef` (BZ).
--
-- ── ⚠ ICMS-ST só existe para MODALIDADE = 'ST_SUBSTITUTO' ─────────────────
-- É a regra que decide imposto recolhido: 'ST_RECOLHIDO' vale 0 (já foi
-- recolhido antes na cadeia) e 'NORMAL' vale 0. Só o substituto tem MVA e só
-- ele gera ICMS-ST em BT/BU. `exige_mva` deixa isso explícito na dimensão em
-- vez de obrigar quem lê a saber a regra de cor - e é a mesma invariante que
-- `tests/compras_icms_st_so_substituto.sql` protege no cálculo.
--
-- ── ⚠ A REDUÇÃO DE BASE vale só para as filiais de atacado ────────────────
-- CONTEXTO.md regra 3 e PDF §8.2. Por isso o seed traz DUAS alíquotas efetivas
-- para o mesmo código: ICMS_EF_SAIDA (com redução, atacado) e
-- ICMS_EF_SEM_REDUCAO (cheia, varejo). Elas não são "a certa e a antiga" - são
-- dois regimes, e usar a reduzida no varejo mostra margem melhor do que a real.
-- Ver PENDENCIAS_DIRETORIA.md item 1: a coluna CY da planilha faz exatamente
-- isso, em 5.613 SKUs, e está reproduzida assim aguardando o Diretor.
--
-- ── Os códigos que o catálogo usa e a tabela não tem ──────────────────────
-- `qtd_sku` mede o alcance de cada linha do seed, mas NÃO mostra o caso
-- inverso, que é o perigoso: os 5 SKUs de PCTABTRIB com codst = 0
-- (CONTEXTO.md §6.2), cujo código está preenchido e não existe aqui. Eles saem
-- sem modalidade, sem alíquota, com margem em branco - e sem alerta, porque
-- CHECK_TRIB testa "vazio", não "não encontrado" (PENDENCIAS_DIRETORIA.md item
-- 4). Como esta dimensão tem grão no seed, esses códigos não aparecem como
-- linha, e não devem aparecer: inventar linha para código inexistente seria
-- criar uma tributação que não há. Quem precisa deles olha
-- `fat_pedido where modalidade is null`.
-- ─────────────────────────────────────────────────────────────────────────────

with seed as (
    select * from {{ ref('seed_icms') }}
),

fiscal as (
    select * from {{ ref('int_produto_fiscal') }}
),

-- O alcance real de cada codigo, medido no catalogo de hoje.
uso as (
    select
        cod_icms,
        count(*) as qtd_sku
      from fiscal
     group by cod_icms
),

final as (
    select
        s.COD_TRIBUTACAO                                   as cod_tributacao,
        s.DESCRICAO                                        as descricao,
        s.MODALIDADE                                       as modalidade,          -- BL
        s.MVA                                              as mva,                 -- BM
        s.ALIQ_ICMS_SAIDA                                  as aliq_icms_saida,
        s.REDUCAO_BASE                                     as reducao_base,
        -- CA: alíquota efetiva COM redução - atacado (filiais 02 e 09)
        s.ICMS_EF_SAIDA                                    as icms_saida_ef,       -- CA
        -- CB: alíquota CHEIA - varejo, sempre
        s.ICMS_EF_SEM_REDUCAO                              as icms_sem_red,        -- CB
        -- só o substituto tem MVA a cobrar - ver cabeçalho
        case when s.MODALIDADE = 'ST_SUBSTITUTO' then 'S' else 'N' end as exige_mva,
        nvl(u.qtd_sku, 0)                                  as qtd_sku
      from seed s
      left join uso u
        on u.cod_icms = s.COD_TRIBUTACAO
)

select * from final
