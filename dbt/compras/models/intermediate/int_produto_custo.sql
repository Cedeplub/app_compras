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
-- ── TRES COLUNAS SEM LETRA: o VALOR GERENCIAL (08/10/2026) ─────────────────
-- icms_st_bruto, valor_adicional_imagem e valor_tot_gerencial NAO vem do
-- gabarito - nao existem na planilha, nao tem letra de coluna e NAO entram em
-- fat_pedido/compras_pedido (que sao contrato de 122 colunas, conferido celula
-- a celula contra o Excel). Saem por COMPRAS_PRODUTO_CONTEXTO, que e' onde o
-- projeto poe derivado que a TELA precisa e a planilha nao tem - o mesmo lugar
-- de PRECO_ULT_ENT_SEM_FRETE.
--
-- Origem: documento "Valor Gerencial e Custo Gerencial" do Diretor de Compras,
-- 6a versao, validado por ele direto na tela de /precificacao em 29/09/2026
-- sobre 9 produtos cobrindo as 3 modalidades x 2 tratamentos de PIS/COFINS.
--
-- O QUE E': quanto o produto custou para entrar no estoque SEM DESCONTAR
-- NENHUM CREDITO de imposto. E' o espelho BRUTO do custo gerencial:
--     Custo Gerencial = CUSTO_ULT_ENT + ICMS-ST liquido + adicional LIQUIDO
--     Valor Gerencial = VL_ENT_UNIT   + ICMS-ST BRUTO   + adicional BRUTO
-- "Bruto" = sem o termo de credito. Compare com BT/BU, que subtraem
-- `vl_ent_unit * cred_icms`; o bruto nao subtrai nada. E o adicional bruto nao
-- multiplica por (1 - piscof_ef).
--
-- ⚠ POR QUE PARTE DO VALOR, E NAO DO CUSTO - a armadilha que ja' custou caro.
-- Ate 25/09/2026 a tela mostrava um "Valor NF" PROJETADO, reconstruido PARA
-- TRAS a partir do custo: valor = custo / ((1-cred_icms)*(1-cred_piscof)).
-- Foi retirado porque divergia da nota real - R$ 435,15 contra R$ 325,42 no
-- SKU 1654, 34% - ja' que CUSTO_TOT_GERENCIAL embute ST e ajustes que nao sao
-- daquela entrada (docs/VALOR_NF_PROJETADO.md, e o bloco que sobrou em
-- web/src/precificacao.js no lugar de `valorAntesDoCredito`). A formula daqui
-- vai para FRENTE a partir de VL_ENT_UNIT, o valor REAL da nota: nao tem como
-- divergir dela, porque comeca nela. NAO reintroduzir a reconstrucao.
--
-- ⚠ O ADICIONAL DA INGRAX NAO DEPENDE DA MODALIDADE - medido, nao suposto.
-- A Sec 2.1 do documento diz "Normal/Mono/ST Recolhido: Valor Gerencial =
-- Valor da ultima entrada", sem ressalva; a Sec 4 diz que o 80/20 e' "como a
-- Ingrax fatura QUALQUER item da linha", nao caracteristica de produto. Os
-- dados decidem: 33 dos 230 SKUs INGRAX sao modalidade NORMAL e os 33 ja' tem
-- CUSTO_ADICIONAL_IMAGEM > 0 (BX nao olha modalidade). Seguir a Sec 2.1 ao pe
-- da letra deixaria 6 deles com CUSTO gerencial MAIOR que o VALOR gerencial
-- (ex.: SKU 8592, custo 343,52 contra valor 280,00) - impossivel, porque o
-- valor e' BRUTO de credito e o custo e' LIQUIDO. Entao o adicional bruto
-- entra para INGRAX em qualquer modalidade, espelhando BX exatamente.
--
-- A propagacao de NULL tambem espelha BT/BU: ST_SUBSTITUTO sem MVA ou com nota
-- zerada sai NULL (nao zero), para a tela mostrar "-" dos dois lados do par
-- "ult / ger" em vez de "- / 0,00".
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
-- ── ⚠ ST JA EMBUTIDO NA ENTRADA: quando NAO se soma ICMS-ST ────────────────
-- REGRA FINAL, fechada pelo Diretor de Compras em 09/10/2026 depois de ele
-- conferir a versao anterior no servidor de teste. Quatro casos, e so' o
-- terceiro soma:
--
--   1. cadastro Normal ou ST RECOLHIDO .................. nao soma.
--      Compra dentro da Bahia ja tem de estar cadastrada como ST recolhido -
--      e' por aqui que a compra interna sai, e nao por uma regra de UF.
--   2. ST SUBSTITUTO com ultima COMPRA antes de 01/10/2022 .... nao soma.
--      Naquela compra o ST veio recolhido e esta no custo. O cadastro hoje e'
--      substituto porque uma compra NOVA viria sem ST - o cadastro fala do
--      futuro, a compra fala do passado.
--   3. ST SUBSTITUTO com ultima COMPRA a partir de 01/10/2022 . SOMA.
--      Decreto 7.799: o ST deixou de vir destacado na compra interestadual.
--   4. sem COMPRA nenhuma ............................... nao soma.
--
-- ── ⚠ A DATA E' A DA ULTIMA COMPRA, E ISSO E' O CERNE ──────────────────────
-- NAO e' PCEST.DTULTENT. O WinThor grava em DTULTENT qualquer entrada -
-- inclusive TRANSFERENCIA ENTRE FILIAIS e BONIFICACAO. A data da ultima
-- compra sai de `int_produto_ultima_entrada` (CODOPER = 'E', sem ER/ET/EB).
--
-- Medido pelo Diretor na aba Entradas: dos itens sem ST que deu para conferir,
-- 129 de 193 NAO tem compra na data da "ultima entrada" - exemplos 11, 63, 66,
-- 1463 e 1843. Nos itens que somam ST isso acontece em 1 de 2.436.
--
-- ── ⚠ A CONDICAO DE UF EXISTIU E FOI REPROVADA. Nao reintroduza. ───────────
-- Entre as 14h e as 20h de 09/10/2026 a regra tinha uma terceira condicao,
-- "fornecedor de fora da Bahia". O Diretor conferiu no servidor de teste e
-- reprovou com numero: 215 itens ST substituto com compra posterior ao
-- Decreto PERDERAM o ST. Exemplos que ele deu: 6771 caiu para custo gerencial
-- R$ 21,37 e sugerido R$ 32,01 (o certo e' 28,48 e 42,67); 6641 sugerido
-- R$ 37,97; 1843 voltou a R$ 39,82.
--
-- A causa: a UF saia do fornecedor da ultima ENTRADA, e quando essa entrada e'
-- transferencia de outra filial o "fornecedor" e' a propria empresa, na BA.
-- YPF, Lubrax, Ipiranga, Texaco, Petronas e Valvoline nao sao compradas na
-- Bahia. A condicao parecia certa e media outra coisa.
--
-- O que ela tentava pegar - compra DENTRO do estado - ja esta coberto pelo
-- caso 1: compra interna tem de estar cadastrada como ST RECOLHIDO.
--
-- ── A LEITURA DA NOTA E' SO' CONFERENCIA ───────────────────────────────────
-- `custo_ult_ent > custo_ult_ent_sem_st` continua calculada como
-- `st_destacado_na_nota`. NAO decide nada. Alimenta o relatorio de divergencia
-- (regra x nota x cadastro) que vai para o Fiscal - onde os dois discordam,
-- pode ser erro de CADASTRO, e nao do painel. O Diretor ja leu a primeira
-- rodada e classificou: o 4650 e' erro de cadastro (unico ST substituto entre
-- 27 sprays Mundial PR ativos, os outros 26 sao ST recolhido) e vai para
-- correcao; os 51 ST recolhido com ST na nota estao certos; os 12 Normal com
-- ST destacado vao para o Fiscal.
--
-- ── O QUE MUDA, e o que conferir ───────────────────────────────────────────
-- Conferencia pedida por ele:
--   6771 .... custo gerencial R$ 28,48, sugerido R$ 42,67
--   1689 .... gerencial igual a entrada, R$ 44,14
--   2671 .... gerencial igual a entrada, R$ 6,99
--   os 215 que a UF derrubou voltam a somar ST
--
-- ⚠ ISTO MUDA CUSTO_TOT_GERENCIAL, coluna de FAT_PEDIDO e base de toda margem
-- e todo preco sugerido. A comparacao celula a celula contra a planilha V11
-- (validar/validar_pedido.py) diverge nessa coluna: a planilha nao conhece a
-- regra. Divergencia DELIBERADA - e, desde 09/10/2026, o PAINEL e' a
-- referencia e a planilha nao sera corrigida.
--
-- ── AS DUAS REGRAS ANTERIORES, e por que nenhuma ficou ─────────────────────
-- 1. CORTE SO' POR DATA, sobre PCEST.DTULTENT. A medida do Diretor estava
--    certa (171 ativos; medimos 177), mas a populacao com ST na nota aparecia
--    em todos os anos, inclusive 2024-2026. A regra final conserta isso pela
--    fonte da data - aqueles casos tinham DTULTENT de transferencia.
-- 2. DETECCAO POR CUSTOULTENTSEMST. Acerta onde ha nota e nao tem resposta
--    onde nao ha: dos 26 ativos com data 30/06/2013 (carga inicial do
--    WinThor), 19 somavam ST e 7 nao, por diferenca de coluna e nao de fato.
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

-- A ULTIMA COMPRA de fornecedor - a data que decide o ST embutido. NAO e'
-- PCEST.DTULTENT: o WinThor grava ali qualquer entrada, inclusive
-- transferencia entre filiais e bonificacao. Ver o cabecalho.
compra as (
    select * from {{ ref('int_produto_ultima_entrada') }}
),

-- A origem da ultima ENTRADA (quem, de onde, e se foi compra). NAO decide
-- mais nada no ST desde 09/10/2026 - serve ao aviso "nao e compra" da
-- Precificacao (item 1.16) e ao relatorio de divergencia.
entrada as (
    select * from {{ ref('int_produto_entrada_fornecedor') }}
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
        -- ── AS TRES CONDICOES, escritas uma vez so' ───────────────────────
        -- `st_ja_na_entrada` = 1 significa "NAO soma o ST calculado". E' 1 por
        -- PADRAO: so' as tres condicoes juntas o levam a 0. Ver o bloco "ST JA
        -- EMBUTIDO NA ENTRADA" no cabecalho para o porque de cada uma.
        --
        -- ⚠ A negacao esta escrita como `case ... then 0 else 1`, e nao como
        -- um `not(...)`: com UF ou data NULAS, `not` daria UNKNOWN e a linha
        -- cairia no lugar errado em silencio. Assim, tudo que nao PROVA as
        -- tres condicoes vai para o 1 - a direcao conservadora.
        {{ compras_st_ja_na_entrada() }}                   as st_ja_na_entrada,
        -- A leitura da NOTA, que ate 09/10/2026 era a regra e agora e'
        -- CONFERENCIA: o WinThor guarda CUSTOULTENTSEMST ao lado de
        -- CUSTOULTENT, e quando os dois diferem o ST daquela nota esta DENTRO
        -- do custo. Nao decide nada aqui; alimenta o relatorio de divergencia
        -- (regra x nota x cadastro) que vai para o Fiscal. O `+ 0.005` e'
        -- tolerancia de centavo: igualdade exata entre dois NUMBER do Oracle
        -- nao e' garantia.
        case when f.custo_ult_ent > f.custo_ult_ent_sem_st + 0.005
             then 1 else 0
        end                                                as st_destacado_na_nota,
        e.dt_ult_ent,
        compra.dt_ult_ent_sem_frete                        as dt_ult_compra,
        e.uf_entrada,
        e.entrada_sem_nota,
        e.fornecedor_sem_uf,
        -- BT: base sobre o VALOR DA NOTA
        case when f.modalidade is null or f.modalidade <> 'ST_SUBSTITUTO'
             then 0
             -- o ST ja esta no valor de entrada: somar o calculado contaria
             -- 2x. As tres condicoes moram em `st_ja_na_entrada`, acima - nao
             -- repita a expressao aqui, que foi assim que a regra antiga
             -- acabou escrita em quatro lugares.
             when {{ compras_st_ja_na_entrada() }} = 1
             then 0
             when f.mva is null or f.vl_ent_unit = 0
             then null   -- o "" do Excel: sem MVA ou sem nota, nao ha base
             else greatest(0,   f.vl_ent_unit * (1 + f.mva) * par.aliq_icms_interna_ba
                              - f.vl_ent_unit * nvl(f.cred_icms, 0))
        end                                                as icms_st_s_valor,
        -- BU: base sobre o CUSTO CONTABIL; o guarda-corpo continua sendo $BH2
        case when f.modalidade is null or f.modalidade <> 'ST_SUBSTITUTO'
             then 0
             when {{ compras_st_ja_na_entrada() }} = 1
             then 0                                   -- idem BT: ja esta dentro
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
        end                                                as custo_adicional_imagem,
        -- ── VALOR GERENCIAL (sem letra de coluna) - ver cabecalho ──────────
        -- ICMS-ST BRUTO: igual a BT, mas SEM o termo de credito
        -- `- vl_ent_unit * cred_icms`. Mesmo guarda-corpo, mesma propagacao
        -- de NULL - o par "ult / ger" da tela tem de aparecer e sumir junto
        -- com o do custo.
        case when f.modalidade is null or f.modalidade <> 'ST_SUBSTITUTO'
             then 0
             when {{ compras_st_ja_na_entrada() }} = 1
             then 0                                   -- idem BT/BU: ja esta dentro
             when f.mva is null or f.vl_ent_unit = 0
             then null
             else f.vl_ent_unit * (1 + f.mva) * par.aliq_icms_interna_ba
        end                                                as icms_st_bruto,
        -- Adicional de imagem BRUTO: igual a BX sem o `* (1 - piscof_ef)`.
        -- A parcela de 20% vem em nota de debito de servico, que nao gera
        -- credito de PIS/COFINS - por isso o liquido desconta e o bruto nao.
        case when upper(b.fornecedor) = 'INGRAX'
             then f.vl_ent_unit * (1 / par.perc_nf_normal_ingrax - 1)
             else 0
        end                                                as valor_adicional_imagem
      from fiscal f
      join base b
        on b.codigo = f.codigo
      left join entrada e
        on e.codigo = f.codigo
      left join compra
        on compra.id_produto = f.codigo
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
        end                                                as custo_tot_gerencial,
        i.st_ja_na_entrada,
        -- Os insumos da CONFERENCIA (regra x nota x cadastro). Nao entram em
        -- fat_pedido nem em compras_pedido - as 122 colunas sao o gabarito e
        -- so' elas. Saem daqui para o relatorio que vai ao Fiscal, e ficam no
        -- modelo, e nao numa consulta solta do validador, para a lista ser
        -- montada pelos MESMOS numeros que a regra usou.
        i.st_destacado_na_nota,
        i.dt_ult_ent,
        i.dt_ult_compra,
        i.uf_entrada,
        i.entrada_sem_nota,
        i.fornecedor_sem_uf,
        i.icms_st_bruto,
        i.valor_adicional_imagem,
        -- O espelho BRUTO de custo_tot_gerencial. Nao entra em fat_pedido:
        -- sai por COMPRAS_PRODUTO_CONTEXTO - ver cabecalho.
        case when i.icms_st_bruto is not null
             then i.vl_ent_unit + i.icms_st_bruto + i.valor_adicional_imagem
        end                                                as valor_tot_gerencial
      from imposto i
)

select * from final
