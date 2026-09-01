-- ─────────────────────────────────────────────────────────────────────────────
-- int_produto_fiscal — colunas BH a BS, mais BZ, CA, CB e DR da aba `pedido`.
--
-- Gabarito: docs/gabarito_pedido_formulas.txt. Mapa coluna a coluna:
--   BH VL_ENT_UNIT         dCadastroTI!$AA, vazio -> 0   (ja vem UNITARIO)
--   BI CUSTO_ULT_ENT       dCadastroTI!$Z,  vazio -> 0
--   BJ COD_ICMS            dCadastroTI!$N,  VAZIO -> Parametros!$B$13
--   BK COD_PISCOF          dCadastroTI!$Q,  VAZIO -> Parametros!$B$14
--   BL MODALIDADE          dICMS!$D por $BJ2, sem linha -> ""
--   BM MVA                 dICMS!$E por $BJ2, sem linha -> ""
--   BN UF_ORIGEM           dCadastroTI!$K,  vazio -> '?'
--   BO CRED_TOTAL          dCredito!$E por "$F2|$BJ2", sem linha -> empirico
--   BP ALIQ_ICMS_ORIGEM    dICMS_Origem!$B por $BN2, sem linha -> 0
--   BQ CRED_ICMS           por MODALIDADE (ver secao propria)
--   BR CRED_PISCOF         MAX(0,(1-$BQ2)*Parametros!$B$2), 0 se $BZ2 = 0
--   BS CHECK_IMPORTADO     credito real abaixo de X% do esperado pela UF
--   BZ PISCOF_EF           dPISCOFINS!$D por $BK2, sem linha -> ""
--   CA ICMS_SAIDA_EF       dICMS!$H (ICMS_EF_SAIDA)        por $BJ2, -> ""
--   CB ICMS_SEM_RED        dICMS!$J (ICMS_EF_SEM_REDUCAO)  por $BJ2, -> ""
--   DR CRED_TOTAL_EMPIRICO MAX(0, 1 - $BI2/$BH2), "" se BH ou BI for 0
-- (o mapa das letras de dCadastroTI sai de docs/gabarito_powerquery.m, passo
-- `Selecionado`: $K=UF_ORIGEM, $N=COD_TRIBUTACAO, $Q=CODTRIBPISCOFINS,
-- $Z=CUSTO_ULT_ENT, $AA=VL_ULT_ENT.)
--
-- Grao: 1 linha por SKU. Espinha = int_produto_base (o cadastro inteiro).
--
-- POR QUE BZ/CA/CB MORAM AQUI, e nao no model de margem: sao lookups da MESMA
-- linha de dICMS/dPISCOFINS que ja e' lida para BL/BM, pela MESMA chave
-- ($BJ2/$BK2). Separa-las por letra da coluna obrigaria a repetir o join e
-- abriria a chance de dois models buscarem a aliquota com chaves diferentes -
-- que e' exatamente o defeito que muda preco de venda real. A letra de origem
-- de cada uma esta no mapa acima e no schema.yml.
--
-- ── BJ/BK | o fallback vale para VAZIO, e ZERO NAO E VAZIO ──────────────────
-- A formula e IFERROR(IF(<lookup>="",<padrao>,<lookup>),<padrao>): o codigo
-- padrao entra quando a celula esta VAZIA (produto ainda sem linha de
-- tributacao). CONTEXTO.md 6.2, armadilha medida: 5 linhas de PCTABTRIB (BA,
-- filial 2) tem `codst = 0`. Zero NAO e vazio - nao cai no padrao, vai para o
-- MATCH em dICMS e NAO ACHA. Resultado, de proposito: MODALIDADE, MVA,
-- ICMS_SAIDA_EF e ICMS_SEM_RED em branco nesses 5 SKUs, e as margens deles
-- saindo vazias la na frente. `nvl(x, padrao)` reproduz isso exatamente: nvl
-- so' age sobre NULL (a celula vazia), nunca sobre 0.
-- Medido nesta base: 19 SKUs sem linha de tributacao (caem no padrao 26/1) e
-- 5 SKUs com codigo 0 (nao caem - ficam sem modalidade).
--
-- ── BM | "celula vazia" e "nao achou" sao coisas DIFERENTES ────────────────
-- IFERROR(INDEX(dICMS!$E:$E,MATCH($BJ2,...)),""). Sao dois vazios distintos,
-- e o Excel os devolve com valores distintos:
--   * MATCH FALHA (COD_ICMS sem linha em dICMS - os 5 SKUs com codigo 0) -> o
--     INDEX propaga #N/A, o IFERROR devolve "" -> aqui, NULL;
--   * MATCH ACHA e a CELULA da MVA esta VAZIA (todo NORMAL e todo
--     ST_RECOLHIDO do seed: codigos 3, 5, 7, 8, 20, 24, 25 - 4.040 SKUs) ->
--     INDEX sobre celula vazia devolve ZERO, nao "" -> aqui, 0.
-- Um `select i.MVA` daria NULL nos dois casos e divergiria da planilha em 4.040
-- celulas de BM. A prova esta no proprio gabarito: a linha de amostra (CODIGO
-- 1036, COD_ICMS 24, cuja celula de MVA no seed esta VAZIA) traz `V=0`, nao
-- vazio. O mesmo vale, em tese, para qualquer outro INDEX deste model - so' que
-- em dICMS_Origem, dPISCOFINS, dCredito e nas colunas H/J de dICMS nao existe
-- celula vazia hoje, entao MVA e' o unico caso vivo.
-- Efeito no calculo: NENHUM, e de proposito. BT/BU so' leem MVA depois de
-- confirmar MODALIDADE = 'ST_SUBSTITUTO', e todo ST_SUBSTITUTO tem MVA
-- preenchida (tests/compras_icms_st_exige_mva.sql). A diferenca e' de
-- FIDELIDADE da coluna exibida, e o aceite e' celula a celula.
--
-- ── BO | CRED_TOTAL e a grafia CAR 80 ──────────────────────────────────────
-- A chave e' o texto "$F2&"|"&$BJ2" - FORNECEDOR (que e' o texto do
-- DEPARTAMENTO, CONTEXTO.md regra 7) concatenado com o codigo de ICMS.
-- ⚠ DIVERGENCIA DELIBERADA DO ARQUIVO EM referencia/, decidida pelo Diretor
-- de Compras em 21/08/2026 (PENDENCIAS_DIRETORIA.md item 3; CONTEXTO.md 6.4).
-- O seed trazia `CAR80` e o departamento na base e' `CAR 80`, COM ESPACO: a
-- busca falhava NA PROPRIA PLANILHA e esses SKUs caiam no credito empirico.
-- O Diretor decidiu corrigir a GRAFIA DO SEED para bater com a base, e nao
-- manter o erro - `seeds/seed_credito.csv` agora tem `CAR 80`. Os 41 SKUs
-- passam a usar o credito TABELADO (0,156 no COD_ICMS 24; 0,0925 no 26).
-- Medido apos a correcao: os 12 fornecedores do seed casam.
-- ⚠ ALCANCE REAL DA MUDANCA, medido no banco em 21/08/2026 - menor do que a
-- nota do Diretor previa ("muda credito, ICMS-ST e preco desses 41"):
--   BO (CRED_TOTAL) muda em 39 dos 41 - nos outros 2 o empirico ja calhava de
--     dar exatamente o valor tabelado (COD_ICMS 26, 0,0925);
--   BT/BU (ICMS-ST), BV/BW/BY (custo), as margens e os precos NAO mudam em
--     nenhum dos 41, e ALERTA tambem nao.
-- A razao esta duas secoes abaixo, em BQ: CRED_ICMS le $DR2 (o credito
-- EMPIRICO), nao $BO2. Ou seja, BO nao entra na cadeia de custo - seu unico
-- consumidor e' BS (CHECK_IMPORTADO), e nos 41 o limiar nao virou de lado.
-- Isso NAO e' motivo para reverter a correcao: a grafia certa e' a grafia
-- certa, e no dia em que a decisao do item 2 (usar dCredito de verdade, com a
-- tributacao por item que a TI ainda vai expor - PDF secao 14) for revista,
-- BO passa a valer preco e a correcao ja estara feita. E' motivo para NAO
-- prometer ao Diretor um efeito em preco que o dado nao mostra.
-- O upper() do join reproduz o MATCH do Excel, que ignora CAIXA mas nao ignora
-- espaco - hoje nao muda nenhuma linha (os 12 nomes ja estao em maiuscula),
-- esta ali para nao divergir do Excel se um cadastro mudar de caixa amanha.
-- O espaco continua SIGNIFICATIVO: nada de trim() aqui. A correcao foi na
-- grafia do dado do seed, nao na regra de comparacao.
--
-- ── BQ | CRED_ICMS le DR (o empirico), NAO BO ──────────────────────────────
-- IF($BL2="ST_RECOLHIDO",0, IF($BL2="NORMAL",$BP2, IF(OR($DR2="",$DR2<=$BZ2),
-- 0, $DR2-$BZ2))).
-- O terceiro ramo (ST_SUBSTITUTO, e tambem MODALIDADE em branco) usa $DR2 =
-- CRED_TOTAL_EMPIRICO, e NAO $BO2 = CRED_TOTAL. A diferenca so' aparece nos
-- SKUs cujo par FORNECEDOR|COD_ICMS existe em dCredito: para eles BO e' a
-- tabela e DR e' a conta 1 - custo/valor. Trocar um pelo outro muda a base do
-- ICMS-ST (BT/BU) e o imposto recolhido. Esta escrito assim na planilha; foi
-- conferido caractere a caractere no gabarito.
-- O ramo ST_RECOLHIDO = 0 tem razao de negocio (PDF 8.1): o ICMS-ST daquele
-- item ja foi recolhido pelo fornecedor, entao nao ha credito a apropriar aqui.
--
-- Duas armadilhas de tradutor nessa formula, as duas por causa do "" do Excel:
--   1) `$BL2="ST_RECOLHIDO"` com BL em branco e' FALSO, e `<>` e' VERDADEIRO.
--      Em SQL, `modalidade = 'X'` com NULL da UNKNOWN, que nao e' o mesmo que
--      FALSO em toda construcao - por isso os testes de NULL vem explicitos.
--   2) `$DR2<=$BZ2` com BZ em branco e' VERDADEIRO no Excel (texto > numero,
--      sempre), o que zera o credito. Em SQL, `x <= null` da UNKNOWN e cairia
--      no ELSE, devolvendo NULL. O `when piscof_ef is null then 0` reproduz o
--      Excel. Hoje isso nao dispara (todo COD_PISCOF resolve para 1, 2 ou 4, e
--      os tres estao no seed), mas passa a valer sozinho se aparecer um codigo
--      de PIS/COFINS novo no cadastro - que e' justamente quando um NULL
--      silencioso apagaria a cadeia de preco inteira.
--
-- ── BR | CRED_PISCOF: o credito e' sobre a NF sem IPI, menos o ICMS ─────────
-- PDF 8.3 e CONTEXTO.md regra 4. `IF($BZ2=0,0,...)`: produto monofasico ou de
-- excecao (aliquota efetiva 0) nao gera credito de PIS/COFINS. Com BZ em
-- branco, ""=0 e' FALSO no Excel e a conta ACONTECE - `piscof_ef = 0` com NULL
-- da UNKNOWN e cai no ELSE, mesmo caminho. Nao e' coincidencia feliz, foi
-- conferido.
--
-- ── BS | CHECK_IMPORTADO ────────────────────────────────────────────────────
-- IF(AND($BO2<>"",$BO2<$BP2*0.6),...). O 0,6 sai do parametro
-- CRED_IMPORTADO_LIMIAR - constante fiscal dentro de SQL e' defeito neste
-- projeto. Importado costuma vir com 4% de ICMS na origem; credito real muito
-- abaixo do esperado pela UF e' o sintoma. E' a UNICA coluna CHECK_* desta leva
-- (as demais - CC, CD, CE, CL, DB - ficam para a leva de alertas, que le estas
-- colunas por ref()).
-- ─────────────────────────────────────────────────────────────────────────────

with base as (
    select * from {{ ref('int_produto_base') }}
),

cadastro as (
    select * from {{ ref('int_cadastro_estoque') }}
),

parametro as (
    select * from {{ ref('int_parametro') }}
),

icms as (
    select * from {{ ref('seed_icms') }}
),

icms_origem as (
    select * from {{ ref('seed_icms_origem') }}
),

piscofins as (
    select * from {{ ref('seed_piscofins') }}
),

-- A chave de dCredito e' a coluna G da aba: FORNECEDOR & "|" & COD_ICMS.
-- Montada aqui, uma vez, para o join ficar por igualdade simples.
-- `tests/compras_credito_chave_unica.sql` garante que a chave nao duplica.
credito as (
    select
        upper(FORNECEDOR) || '|' || to_char(COD_ICMS) as chave_credito,
        CREDITO                                       as credito
      from {{ ref('seed_credito') }}
),

-- BH, BI, BJ, BK, BN — o que vem do cadastro, ja com o fallback aplicado.
entrada as (
    select
        b.codigo,
        b.fornecedor,
        -- BH: VL_ULT_ENT nunca e' dividido pela embalagem de compra
        -- (CONTEXTO.md regra 8) - ja vem unitario da origem.
        nvl(c.vl_ult_ent, 0)                                as vl_ent_unit,
        nvl(c.custo_ult_ent, 0)                             as custo_ult_ent,
        -- BJ/BK: nvl age so' sobre NULL (a celula VAZIA). codigo 0 passa
        -- direto e vai falhar no MATCH - ver cabecalho.
        nvl(c.cod_tributacao,   par.cod_trib_icms_padrao)   as cod_icms,
        nvl(c.codtribpiscofins, par.cod_trib_piscofins_padrao) as cod_piscof,
        nvl(c.uf_origem, '?')                               as uf_origem
      from base b
      join cadastro c
        on c.codprod = b.codigo
     cross join parametro par
),

-- DR | CRED_TOTAL_EMPIRICO. Fica antes de BO e BQ porque os dois o consomem -
-- BO como FALLBACK da tabela, BQ como a fonte PRIMARIA do ramo ST.
empirico as (
    select
        e.*,
        case when e.vl_ent_unit = 0 or e.custo_ult_ent = 0
             then null   -- o "" do Excel: sem nota ou sem custo, nao ha o que medir
             else greatest(0, 1 - e.custo_ult_ent / e.vl_ent_unit)
        end                                                 as cred_total_empirico
      from entrada e
),

-- Os quatro lookups fiscais. Todos left join: "nao achou" tem significado de
-- negocio em cada um deles, e nenhum pode descartar a linha do SKU.
lookup as (
    select
        e.codigo,
        e.fornecedor,
        e.vl_ent_unit,
        e.custo_ult_ent,
        e.cod_icms,
        e.cod_piscof,
        e.uf_origem,
        e.cred_total_empirico,
        i.MODALIDADE                     as modalidade,          -- BL
        -- BM: INDEX sobre celula VAZIA devolve 0, nao "" - o "" so' aparece
        -- quando o MATCH FALHA. Ver secao propria no cabecalho.
        case when i.COD_TRIBUTACAO is not null
             then nvl(i.MVA, 0)
        end                              as mva,                 -- BM
        i.ICMS_EF_SAIDA                  as icms_saida_ef,       -- CA
        i.ICMS_EF_SEM_REDUCAO            as icms_sem_red,        -- CB
        pc.ALIQ_EFETIVA                  as piscof_ef,           -- BZ
        nvl(o.ALIQ_ICMS_COMPRA, 0)       as aliq_icms_origem,    -- BP
        cr.credito                       as credito_tabelado
      from empirico e
      left join icms i
        on i.COD_TRIBUTACAO = e.cod_icms
      left join piscofins pc
        on pc.CODTRIBPISCOFINS = e.cod_piscof
      left join icms_origem o
        on o.UF_ORIGEM = e.uf_origem
      left join credito cr
        on cr.chave_credito = upper(e.fornecedor) || '|' || to_char(e.cod_icms)
),

cred as (
    select
        l.codigo,
        l.vl_ent_unit,
        l.custo_ult_ent,
        l.cod_icms,
        l.cod_piscof,
        l.modalidade,
        l.mva,
        l.uf_origem,
        -- BO: a tabela ganha; sem linha na tabela, o empirico (que ja e' NULL
        -- quando BH ou BI e' zero, reproduzindo o "" do IF interno).
        nvl(l.credito_tabelado, l.cred_total_empirico)      as cred_total,
        l.aliq_icms_origem,
        -- BQ: le o EMPIRICO (DR), nao CRED_TOTAL (BO) - ver cabecalho.
        case when l.modalidade = 'ST_RECOLHIDO'      then 0
             when l.modalidade = 'NORMAL'            then l.aliq_icms_origem
             when l.cred_total_empirico is null      then 0
             -- Excel: numero <= "" e' VERDADEIRO, entao credito zerado
             when l.piscof_ef is null                then 0
             when l.cred_total_empirico <= l.piscof_ef then 0
             else l.cred_total_empirico - l.piscof_ef
        end                                                 as cred_icms,
        l.piscof_ef,
        l.icms_saida_ef,
        l.icms_sem_red,
        l.cred_total_empirico
      from lookup l
),

-- BR e BS dependem de BQ, que so' existe depois do CASE acima. Segunda passada
-- em vez de repetir a formula inteira - repetir seria mais uma chance de as
-- duas copias divergirem num ajuste futuro.
final as (
    select
        f.*,
        -- BR: PIS/COFINS sobre a NF sem IPI, descontado o credito de ICMS
        case when f.piscof_ef = 0
             then 0
             else greatest(0, (1 - f.cred_icms) * par.pis_cofins)
        end                                                 as cred_piscof,
        -- BS: limiar do parametro, nunca 0,6 chumbado
        case when f.cred_total is not null
              and f.cred_total < f.aliq_icms_origem * par.cred_importado_limiar
             then 'CREDITO REAL MUITO ABAIXO DO ESPERADO - CONFERIR SE E IMPORTADO (4%)'
        end                                                 as check_importado
      from cred f
     cross join parametro par
)

select * from final
