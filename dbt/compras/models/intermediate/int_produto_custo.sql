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
-- Regra FECHADA pelo Diretor de Compras em 09/10/2026. Ela substitui tanto o
-- corte por data que ele propos na primeira rodada quanto a deteccao por
-- CUSTOULTENTSEMST que vigorou entre as duas - as duas estao descritas no fim
-- deste bloco, com os numeros, porque quem reabrir este codigo precisa saber
-- por que nenhuma das duas ficou.
--
-- SOMA-SE o ICMS-ST ao custo/valor gerencial quando as TRES condicoes valem
-- AO MESMO TEMPO:
--
--   1. CADASTRO: modalidade = ST_SUBSTITUTO. A CEDEP e' a substituta e recolhe
--      o ST na SAIDA. Produto Normal ou ST_RECOLHIDO nunca soma.
--   2. DATA: ultima entrada a partir de ST_BENEFICIO_INICIO (01/10/2022,
--      Decreto 7.799). Antes dela, produto ST vinha com o ST destacado na nota
--      e o imposto ja entrava no custo.
--   3. ORIGEM: fornecedor de FORA da Bahia. O beneficio vale so' para compra
--      INTERESTADUAL - distribuidor ou industria da BA sempre veio, e continua
--      vindo, com o ST ja no preco.
--
-- Falhando QUALQUER uma, o ST ja esta no valor de entrada (ou nao existe) e
-- nao soma. E' por isso que a flag se chama `st_ja_na_entrada` e e' 1 por
-- padrao: a excecao e' somar, nao deixar de somar.
--
-- ── POR QUE AS TRES JUNTAS, nas palavras dele ──────────────────────────────
--   * so' a DATA falha nas compras dentro do estado depois de 2022 - sao os
--     casos de 2024-2026 que a deteccao por coluna achava e ninguem explicava;
--   * so' a NOTA falha nas entradas SEM nota (19 ativos com data 30/06/2013,
--     a carga inicial do WinThor) e trata igual o que e' diferente: outros 7
--     com a MESMA data saiam como "sem ST" so' porque a coluna nao diferia;
--   * so' o CADASTRO nao diz como aquela compra especifica veio.
--
-- ── A LEITURA DA NOTA NAO SUMIU: virou CONFERENCIA ─────────────────────────
-- `custo_ult_ent > custo_ult_ent_sem_st` continua calculada, agora com o nome
-- que descreve o que ela e': `st_destacado_na_nota`. Ela NAO decide mais nada
-- no custo. Serve ao relatorio de divergencia (regra x nota x cadastro) que o
-- Diretor pediu para mandar ao Fiscal - onde regra e nota discordam, pode ser
-- erro de CADASTRO, e nao do painel.
--
-- ── A ORIGEM DA COMPRA NAO E' A DO CADASTRO ────────────────────────────────
-- A condicao 3 le `int_produto_entrada_fornecedor.uf_entrada`, que e' a UF do
-- fornecedor da entrada QUE FORMOU O CUSTO (casada por produto + dia de
-- PCEST.DTULTENT) - nao `int_produto_fiscal.uf_origem`, que e' a UF do
-- fornecedor CADASTRADO no produto. Medido em 09/10/2026 nos 3.055 ativos onde
-- a condicao 3 decide: as duas divergem em 235, e em 191 deles a compra veio
-- da BAHIA com o cadastro apontando para fora. O cadastro somaria ST em 191
-- produtos que ja vieram com ele no preco.
--
-- ⚠ CONDICAO NAO COMPROVADA E' CONDICAO FALHA. Sem UF do fornecedor da entrada
-- (28 ativos) ou sem data de ultima entrada (43), a condicao nao se verifica e
-- o ST NAO soma. E' a direcao conservadora de proposito: deixar de somar
-- subestima o custo e o preco sugerido, e aparece; somar sobre um ST que ja
-- estava dentro conta o imposto duas vezes e nao aparece em lugar nenhum.
--
-- ── O QUE MUDA, medido em 09/10/2026 ───────────────────────────────────────
--   ativos ST_SUBSTITUTO ................................. 3.279
--   param de somar por DATA (entrada antes de 01/10/2022) .. 181
--   param de somar por DATA AUSENTE ......................... 43
--   param de somar por ORIGEM (fornecedor da BA) ............ 214
--   param de somar por FALTA DE UF .......................... 28
--   continuam somando .................................... ~2.813
-- Conferencia do Diretor: 1689 e 2671 (entradas de 2013 e 2014) param de
-- somar - gerencial igual a entrada, R$ 44,14 e R$ 6,99.
--
-- ⚠ ISTO MUDA CUSTO_TOT_GERENCIAL, que e' coluna de FAT_PEDIDO e base de toda
-- margem e todo preco sugerido. A comparacao celula a celula contra a planilha
-- V11 (validar/validar_pedido.py) diverge nessa coluna para esses SKUs: a
-- planilha nao conhece a regra. E' divergencia DELIBERADA - e, desde a
-- resposta do Diretor em 09/10/2026, o PAINEL e' a referencia e a planilha nao
-- sera corrigida.
--
-- ── AS DUAS REGRAS QUE NAO FICARAM, e por que ──────────────────────────────
-- 1. CORTE SO' POR DATA (1a proposta, 09/10/2026). Media dele: 171 ativos com
--    ST embutido. Medindo contra PCEST: 177 - a MEDIDA estava certa. Mas a
--    populacao aparecia em TODOS os anos, inclusive 2024 (12), 2025 (5) e 2026
--    (5), e o corte puro acertaria 131, alteraria 40 sem ST embutido e deixaria
--    29 de fora. Os de 2024-2026 eram compra DENTRO do estado - que a condicao
--    3 agora explica.
-- 2. DETECCAO POR CUSTOULTENTSEMST (o que vigorou entre as duas rodadas).
--    Pergunta a fonte se o ST esta dentro daquele custo, e acerta quando ha
--    nota. Nao tem resposta para entrada SEM nota: dos 26 ativos com data
--    30/06/2013 (carga inicial), 19 saiam somando ST e 7 nao, por diferenca de
--    coluna e nao de fato. O SKU 1843, que o Diretor deu como exemplo na 1a
--    rodada, nao tem ST na ultima entrada (VLSTULTENT = 0,00) - pela regra
--    nova ele soma ou nao conforme data e origem, nao conforme a coluna.
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

-- A ORIGEM da compra que formou o custo - condicao 3 das tres do ST embutido.
-- Nao e' o fornecedor do cadastro; ver o bloco "A ORIGEM DA COMPRA NAO E' A DO
-- CADASTRO" no cabecalho.
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
