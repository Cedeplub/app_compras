-- ─────────────────────────────────────────────────────────────────────────────
-- int_produto_custo — colunas BT a BY da aba `pedido`. ICMS-ST e custo total.
--
-- Gabarito: docs/gabarito_pedido_formulas.txt. Mapa coluna a coluna:
--   BT ICMS_ST_s/VALOR         MAX(0, $BH2*(1+MVA)*aliq_interna - $BH2*$BQ2)
--   BU ICMS_ST_s/CUSTO         MAX(0, $BI2*(1+MVA)*aliq_interna - $BH2*$BQ2)
--   BV CUSTO_TOT_s/VALOR       $BI2 + $BT2
--   BW CUSTO_TOT_OFICIAL       $BI2 + $BU2
--   BX CUSTO_ADICIONAL_IMAGEM  so' INGRAX: $BH2*(1/%NF-1)*(1-$BZ2)
--   BY CUSTO_TOT_GERENCIAL     $BW2 + $BX2
--
-- Grao: 1 linha por SKU. Espinha = int_produto_fiscal (que ja e' o cadastro
-- inteiro), porque toda coluna daqui depende de MODALIDADE, MVA, CRED_ICMS e
-- PISCOF_EF.
--
-- ⚠ BY (CUSTO_TOT_GERENCIAL) e' uma das colunas com exigencia de ZERO
-- divergencia no aceite - junto de CLASSE e MODALIDADE. Ela e' a base de custo
-- de CI, CJ, CQ, CS, CX, CZ, DG: um erro aqui nao "aparece num relatorio", ele
-- muda preco de venda enviado para a equipe comercial.
--
-- ── ICMS-ST so' existe para MODALIDADE = 'ST_SUBSTITUTO' ───────────────────
-- PDF 8.1: a CEDEP e' credenciada como substituta tributaria (Art. 7o-B do
-- Decreto 7.799/00) - o fornecedor NAO retem o ICMS-ST na compra (fica
-- suspenso) e a propria CEDEP calcula e recolhe no momento da venda. Por isso
-- as tres modalidades tem tratamentos diferentes e NAO intercambiaveis:
--   * ST_SUBSTITUTO — a CEDEP recolhe: calcula base por MVA e aliquota interna;
--   * ST_RECOLHIDO  — ja foi recolhido antes na cadeia: nao ha nada a recolher
--                     aqui, o valor e' 0 (e nao "vazio", nao "nulo");
--   * NORMAL        — regime normal, sem ST: 0.
-- E o quarto caso, que o Excel produz sem dizer: MODALIDADE em BRANCO (os 5
-- SKUs com codst = 0 - CONTEXTO.md 6.2). `""<>"ST_SUBSTITUTO"` e' VERDADEIRO
-- no Excel, entao esses tambem saem com ICMS-ST = 0, e BV/BW/BY continuam
-- preenchidos. O que apaga a margem deles la na frente e' ICMS_SAIDA_EF /
-- ICMS_SEM_RED em branco, nao esta coluna. Em SQL, `modalidade <>
-- 'ST_SUBSTITUTO'` com NULL da UNKNOWN e cairia no ELSE (calculando ST com MVA
-- nula = NULL) - por isso o `modalidade is null` vem explicito no primeiro
-- when.
--
-- ── BT x BU: o que muda e' SO' o primeiro termo ─────────────────────────────
-- BT usa $BH2 (VL_ENT_UNIT, o valor da nota) e BU usa $BI2 (CUSTO_ULT_ENT, o
-- custo contabil) na base. O termo de credito e' IDENTICO nos dois: $BH2*$BQ2,
-- sempre sobre o VALOR DA NOTA. E o guarda-corpo das duas e' `OR($BM2="",
-- $BH2=0)` - tambem sobre BH nas DUAS, inclusive em BU, que nem usa BH na base.
-- Isso nao e' engano de transcricao: esta assim no gabarito e foi conferido.
-- Efeito pratico: um SKU com custo contabil preenchido e nota zerada sai com
-- BU (e portanto BW, BY e toda a cadeia de preco) em BRANCO, nao com o custo
-- puro. Reproduzido de proposito.
--
-- ── BX | o ajuste Ingrax (80/20) — a regra que NAO pode escorregar ──────────
-- PDF 8.4 e CONTEXTO.md regra 2. Para quase todo fornecedor, custo oficial e
-- custo gerencial sao o mesmo numero. A excecao e' a INGRAX: 80% do valor do
-- produto vem em nota fiscal normal (fluxo fiscal padrao) e os outros 20% vem
-- numa nota separada de "cessao de direito de imagem" (aluguel de marca), que
-- nao entra no sistema como custo do produto mas E' custo real do negocio.
--   BX = $BH2 * (1/0,8 - 1) * (1 - PISCOF_EF)
--        \_____/   \_______/   \___________/
--         valor    a parcela   liquido do credito de PIS/COFINS que a
--         da NF    que falta   parcela NAO gera (ela nao passa pela NF normal)
-- O 0,8 sai do parametro PERC_NF_NORMAL_INGRAX. O teste $F2="INGRAX" e' sobre
-- FORNECEDOR, que e' o texto do DEPARTAMENTO (CONTEXTO.md regra 7) - 230 SKUs
-- hoje. O upper() reproduz o `=` do Excel, que ignora caixa.
--
-- ⚠ ONDE ESSE AJUSTE ENTRA, E ONDE NUNCA ENTRA:
--   ENTRA em BY (CUSTO_TOT_GERENCIAL) e, por ele, em toda margem e todo preco
--     sugerido - atacado e varejo;
--   ENTRA tambem, SOMADO A PARTE, no cenario "ST s/Valor" (CH/CY/CO/DE fazem
--     `$BV2+$BX2`) - porque BV parte de BW sem o ajuste;
--   NUNCA entra na base de ICMS-ST (BT/BU), que usa so' o custo OFICIAL puro.
-- Confundir os dois erra o IMPOSTO RECOLHIDO, nao so' o relatorio gerencial.
-- E' por isso que BX e' coluna propria e nao um termo embutido em BW: assim a
-- base fiscal e a base gerencial nao tem como se misturar por descuido, e
-- `tests/compras_custo_gerencial_coerente.sql` cobra a identidade
-- BY = BW + BX a cada build.
--
-- ── O "" do Excel virando NULL ─────────────────────────────────────────────
-- BV/BW/BY sao `IF(<anterior>="","",<soma>)`: uma vez que BT/BU saem em
-- branco, o branco se propaga por toda a cadeia de custo. Em Oracle, NULL + x
-- ja e' NULL - o `case when ... is null then null` esta escrito assim mesmo
-- assim, para o leitor ver a regra em vez de deduzi-la do comportamento do
-- operador.
-- BX nao tem IFERROR na planilha: se PISCOF_EF estivesse em branco num SKU
-- INGRAX, o Excel devolveria #VALOR! e aqui devolve NULL. Nao acontece hoje
-- (todo COD_PISCOF resolve para 1, 2 ou 4) e esta registrado no relatorio da
-- etapa como divergencia POTENCIAL, nao atual.
-- ─────────────────────────────────────────────────────────────────────────────

with fiscal as (
    select * from {{ ref('int_produto_fiscal') }}
),

base as (
    select * from {{ ref('int_produto_base') }}
),

parametro as (
    select * from {{ ref('int_parametro') }}
),

-- BT e BU. A aliquota interna da BA (Parametros!$B$16) vem do int_parametro -
-- nenhum 0,205 escrito dentro do SQL.
imposto as (
    select
        f.codigo,
        b.fornecedor,
        f.vl_ent_unit,
        f.custo_ult_ent,
        f.modalidade,
        f.mva,
        f.cred_icms,
        f.piscof_ef,
        -- BT: base sobre o VALOR DA NOTA
        case when f.modalidade is null or f.modalidade <> 'ST_SUBSTITUTO'
             then 0
             when f.mva is null or f.vl_ent_unit = 0
             then null   -- o "" do Excel: sem MVA ou sem nota, nao ha base
             else greatest(0,   f.vl_ent_unit * (1 + f.mva) * par.aliq_icms_interna_ba
                              - f.vl_ent_unit * nvl(f.cred_icms, 0))
        end                                                as icms_st_s_valor,
        -- BU: base sobre o CUSTO CONTABIL; o guarda-corpo continua sendo $BH2
        case when f.modalidade is null or f.modalidade <> 'ST_SUBSTITUTO'
             then 0
             when f.mva is null or f.vl_ent_unit = 0
             then null
             else greatest(0,   f.custo_ult_ent * (1 + f.mva) * par.aliq_icms_interna_ba
                              - f.vl_ent_unit  * nvl(f.cred_icms, 0))
        end                                                as icms_st_s_custo,
        -- BX: o ajuste gerencial da Ingrax, calculado aqui porque nao depende
        -- de BT/BU - so' do valor da nota e do PIS/COFINS efetivo.
        case when upper(b.fornecedor) = 'INGRAX'
             then f.vl_ent_unit
                  * (1 / par.perc_nf_normal_ingrax - 1)
                  * (1 - f.piscof_ef)
             else 0
        end                                                as custo_adicional_imagem
      from fiscal f
      join base b
        on b.codigo = f.codigo
     cross join parametro par
),

final as (
    select
        i.codigo,
        i.icms_st_s_valor,
        i.icms_st_s_custo,
        -- BV: custo contabil + o ST calculado sobre o VALOR da nota
        case when i.icms_st_s_valor is not null
             then i.custo_ult_ent + i.icms_st_s_valor
        end                                                as custo_tot_s_valor,
        -- BW: o custo OFICIAL - o unico que a apuracao fiscal enxerga
        case when i.icms_st_s_custo is not null
             then i.custo_ult_ent + i.icms_st_s_custo
        end                                                as custo_tot_oficial,
        i.custo_adicional_imagem,
        -- BY: o custo GERENCIAL - a base de toda margem e todo preco sugerido.
        -- O ajuste de imagem entra AQUI e so' aqui (PDF 8.4).
        case when i.icms_st_s_custo is not null
             then i.custo_ult_ent + i.icms_st_s_custo + i.custo_adicional_imagem
        end                                                as custo_tot_gerencial
      from imposto i
)

select * from final
