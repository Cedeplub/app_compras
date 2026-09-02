-- ─────────────────────────────────────────────────────────────────────────────
-- fat_alerta — os CHECK_* da aba `pedido` DESPIVOTADOS, na TAXONOMIA decidida
-- pelo Diretor de Compras em 02/09/2026 (v2/DECISOES_DIRETOR.md item 1).
-- Grão: 1 linha por SKU x TIPO DE ALERTA ATIVO. SKU sem nenhum alerta não
-- aparece; SKU com quatro alertas aparece quatro vezes.
--
-- Qual coluna Excel reproduz: as mesmas X, AL, AV, AO, AP, AY, BS, CC, CD, CE,
-- CL, DO, DB de int_produto_alerta — nenhum TEXTO novo é inventado para elas.
-- O que muda é a FORMA (lá são colunas lado a lado, aqui são linhas) e o NOME
-- da chave `tipo_alerta`, que é NOSSO e não da planilha.
--
-- ── ⚠ A FRONTEIRA QUE ESTE ARQUIVO PROTEGE ────────────────────────────────
-- `int_produto_alerta` produz as 14 colunas CHECK_* e a string `ALERTA`
-- (coluna D). Aquilo é o GABARITO contra a MODELO_COMPRAS_CEDEP_v11.xlsx, e
-- `ALERTA` é coluna CRÍTICA do aceite (CONTEXTO.md §6.1.1). Por isso NADA da
-- taxonomia nova encostou lá: nenhum CHECK_* foi renomeado, removido ou teve o
-- texto alterado, e a string `ALERTA` sai deste build idêntica à do anterior.
-- Esta camada é o despivot — é NOSSA, não da planilha, e é aqui que
-- `tipo_alerta`, `categoria` e `pontua` são decididos.
--
-- Consequência que precisa estar clara: `tipo_alerta` e o conteúdo de `ALERTA`
-- DIVERGEM DE PROPÓSITO desde 02/09/2026. `ALERTA` continua dizendo
-- "SEM VENDA HA 214 DIAS - ESTOQUE PARADO" (planilha); a chave da tela diz
-- SEM_GIRO ou BAIXO_GIRO. Quem contar por `like '%PARADO%'` na string acha 460;
-- quem contar por `tipo_alerta` acha 306 + 154. Os dois estão certos, são
-- perguntas diferentes.
--
-- ── A TAXONOMIA, tipo a tipo (pesos decididos pelo Diretor) ────────────────
--   tipo_alerta            origem            categoria  pontua  peso
--   RUPTURA                AL                DECISAO    S       5
--   SEM_GIRO               AO (partição)     DECISAO    S       4
--   MARGEM_BAIXA           CL (renomeado)    DECISAO    S       4
--   MARGEM_BAIXA_VAREJO    DB (renomeado)    DECISAO    S       4
--   CUSTO                  CE                DECISAO    S       4
--   BAIXO_GIRO             AO (partição)     DECISAO    S       3
--   OPORTUNIDADE_DE_GIRO   NOVO              DECISAO    S       3
--   DEVOLUCAO              AV                DECISAO    S       2
--   MARGEM_ALTA            NOVO              DECISAO    S       1
--   FORA_DE_LINHA          AP                DECISAO    N       —
--   FABRICA                X                 CADASTRO   N       —
--   LITRAGEM               AY                CADASTRO   N       —
--   IMPORTADO              BS                CADASTRO   N       —
--   TRIB                   CC                CADASTRO   N       —
--   MVA                    CD                CADASTRO   N       —
--   SUCESSAO               DO                CADASTRO   N       —
-- O PESO não mora aqui de propósito: ele é ordenação de TELA, muda sem que o
-- dado mude, e hoje vive em app/api/alertas.py. O que este model publica é o
-- que a tela não pode adivinhar — categoria e pontuabilidade.
--
-- ── ⚠ INATIVO DEIXOU DE SER TIPO DE ALERTA (item 7 do Diretor) ────────────
-- "Fora de linha e Inativo são a mesma situação; o filtro de Status já cobre os
-- dois." O ramo `check_inativo` (Y) saiu daqui. Ele CONTINUA existindo em
-- int_produto_alerta e dentro da string `ALERTA` — é gabarito.
-- ⚠ Fato medido em 02/09/2026, contra a premissa do Diretor: no modelo os dois
-- sinais JÁ ERAM UM SÓ. `stg_produto` deriva `status` e `fora_de_linha` da
-- MESMA expressão (`upper(trim(OBS2)) = 'FL'`), então `OBS2='FL'` já implicava
-- `status = 'Inativo'` em 100% dos SKUs — 4.277 Inativos, 0 divergentes, e os
-- 72 de CHECK_FORA_DE_LINHA são todos Inativos. A unificação pedida não muda
-- NENHUM produto de Ativo para Inativo, porque nunca houve dois sinais aqui.
-- Nada foi mexido em stg_produto: mexer seria inventar uma diferença para
-- depois removê-la.
--
-- ── ⚠ FORA_DE_LINHA continua listado, mas NÃO PONTUA ──────────────────────
-- Decisão do Diretor: vira badge visual. A linha existe porque o comprador
-- precisa VER que o item está fora de linha ao decidir; ela só não pode empurrar
-- o SKU para o topo por si. Por isso `pontua = 'N'` em vez de sumir com a linha:
-- uma tela pode mostrar o que não pontua, mas não pode mostrar o que não existe.
--
-- ── `pontua` = "entra no score de priorização" ─────────────────────────────
-- 'N' para FORA_DE_LINHA **e para toda a categoria CADASTRO**. Não é
-- interpretação livre: a tabela de pesos do Diretor tem NOVE linhas, e são
-- exatamente os nove tipos com `pontua = 'S'`. Os de cadastro saíram da tela de
-- Alertas para a de "Pendência de Cadastro" e não receberam peso nenhum; deixá-
-- los com 'S' faria um `sum(peso) where pontua='S'` somar peso inexistente.
-- Consequência prática para quem consome: a tela de Decisões filtra por
-- `categoria = 'DECISAO'` e ordena por `pontua = 'S'`; as duas condições são
-- independentes e é FORA_DE_LINHA que as separa (DECISAO + não pontua).
--
-- ── A ordem de `ordem_exibicao` é a da coluna D, não a alfabética ──────────
-- A concatenação de ALERTA segue X, Y, AL, AV, AO, AP, AY, BS, CC, CD, CE, CL,
-- DO, DB — ordem do Excel, com AV antes de AO e DO antes de DB (ver
-- int_produto_alerta). Os números 1..14 foram PRESERVADOS nos tipos que vêm da
-- planilha, inclusive o 2 vago de INATIVO: renumerar para "ficar sem buraco"
-- mudaria a sequência que o comprador conhece, e o buraco é o registro de que
-- um tipo foi retirado. SEM_GIRO e BAIXO_GIRO herdam o 5 do PARADO que
-- partem — são mutuamente exclusivos no mesmo SKU, então nunca competem entre
-- si por posição. Os dois alertas NOVOS levam 15 e 16, depois de todos os da
-- planilha, e é esse `<= 14` que o teste de completude de ALERTA usa para saber
-- quem tem de estar dentro da string.
--
-- ── As colunas de recorte vêm de fat_pedido, não de um segundo join ────────
-- fornecedor, comprador e classe são lidos de fat_pedido - que já é a junção
-- consolidada. Buscá-los de novo em int_produto_base/int_produto_classe_abc
-- criaria a chance de esta tabela e o fat_pedido discordarem sobre o
-- fornecedor do mesmo SKU depois de um refactor. Uma fonte só.
--
-- ⚠ Consequência de grão que quem consome precisa saber: somar/contar sobre
-- esta tabela conta ALERTAS, não PRODUTOS. Para contar produtos é
-- `count(distinct codigo)`.
-- ─────────────────────────────────────────────────────────────────────────────

with pedido as (
    select * from {{ ref('fat_pedido') }}
),

-- Os dois alertas que NAO existem na planilha, calculados fora do gabarito -
-- ver o cabecalho de int_produto_alerta_extra para o porque.
extra as (
    select * from {{ ref('int_produto_alerta_extra') }}
),

-- O unpivot manual: um union all por check. Escrito por extenso, e nao com
-- UNPIVOT, porque cada ramo precisa carregar o TIPO e a ORDEM DE EXIBICAO
-- proprios - e porque assim a coluna Excel de origem fica visivel linha a
-- linha, do mesmo jeito que nos outros models.
despivotado as (
    select codigo, 'FABRICA'                  as tipo_alerta,  1 as ordem_exibicao, check_fabrica                as texto_alerta from pedido  -- X
     union all
    -- Y | CHECK_INATIVO deixou de ser tipo de alerta (Diretor, item 7). A
    -- ordem 2 fica VAGA de proposito - ver cabecalho.
    select codigo, 'RUPTURA',                  3, check_ruptura                from pedido  -- AL
     union all
    select codigo, 'DEVOLUCAO',                4, check_devolucao_alta         from pedido  -- AV
     union all
    -- ── AO | PARADO virou DOIS tipos. A particao e EXAUSTIVA e EXCLUSIVA ──
    -- SEM_GIRO: zero venda no periodo. "Periodo" e a janela do proprio
    -- departamento (MEDIA_JANELA, AG - N_MESES meses fechados) MAIS o mes
    -- corrente (VD MES ATUAL, AC), porque AG so' olha mes fechado e um produto
    -- que voltou a vender neste mes nao esta sem giro. Escolhi a janela do
    -- departamento, e nao um numero fixo de meses, porque e a mesma janela que
    -- decide MEDIA_JANELA, MESES_EST e SUG_COBERTURA - dois conceitos de
    -- "periodo" no mesmo modelo e' o comeco de dois numeros discordando na tela.
    -- Nenhum limiar novo foi preciso: a comparacao e contra ZERO.
    select codigo, 'SEM_GIRO',                 5, check_estoque_parado         from pedido  -- AO
     where media_janela = 0 and vd_mes_atual = 0
     union all
    -- BAIXO_GIRO: o COMPLEMENTO - vendeu alguma coisa na janela, mas o estoque
    -- esta parado ha mais de DIAS_ESTOQUE_PARADO dias (a porta do proprio AO ja
    -- garante isso). E' literalmente "vendendo, mas pouco frente ao estoque".
    -- ⚠ O ramo e' `not (... = 0 and ... = 0)` e nao `> 0 or > 0` de proposito:
    -- quantidade aqui e LIQUIDA (faturado - devolvido, CONTEXTO.md regra 1) e
    -- PODE SER NEGATIVA. Medido em 02/09/2026: 1 SKU dos 460 tem venda liquida
    -- negativa e cairia FORA dos dois ramos com a versao ingenua - um alerta
    -- desaparecendo em silencio. Com o complemento, SEM_GIRO + BAIXO_GIRO = o
    -- PARADO de antes, sempre (teste compras_alerta_giro_particiona_parado).
    select codigo, 'BAIXO_GIRO',               5, check_estoque_parado         from pedido  -- AO
     where not (media_janela = 0 and vd_mes_atual = 0)
     union all
    select codigo, 'FORA_DE_LINHA',            6, check_fora_de_linha          from pedido  -- AP
     union all
    select codigo, 'LITRAGEM',                 7, check_litragem               from pedido  -- AY
     union all
    select codigo, 'IMPORTADO',                8, check_importado              from pedido  -- BS
     union all
    select codigo, 'TRIB',                     9, check_trib                   from pedido  -- CC
     union all
    select codigo, 'MVA',                     10, check_mva                    from pedido  -- CD
     union all
    select codigo, 'CUSTO',                   11, check_custo                  from pedido  -- CE
     union all
    -- CL | renomeado de MARGEM_INSTAVEL. O CHECK_* de origem e o TEXTO nao
    -- mudaram - so' a chave que a tela usa.
    select codigo, 'MARGEM_BAIXA',            12, check_margem_instavel        from pedido  -- CL
     union all
    select codigo, 'SUCESSAO',                13, check_sucessao               from pedido  -- DO
     union all
    -- DB | renomeado de MARGEM_INSTAVEL_VAREJO, mesma observacao.
    select codigo, 'MARGEM_BAIXA_VAREJO',     14, check_margem_instavel_varejo from pedido  -- DB
     union all
    -- Os dois NOVOS, depois de todos os da planilha (ordem > 14) - sem coluna
    -- Excel, sem participacao na string ALERTA.
    select codigo, 'OPORTUNIDADE_DE_GIRO',    15, check_oportunidade_giro      from extra
     union all
    select codigo, 'MARGEM_ALTA',             16, check_margem_alta            from extra
),

final as (
    select
        d.codigo,
        d.tipo_alerta,
        d.texto_alerta,
        d.ordem_exibicao,
        -- CADASTRO = "confira este cadastro", nao "decida esta compra". Vai
        -- para a tela de Pendencia de Cadastro; sai da tela de Alertas.
        case when d.tipo_alerta in ('IMPORTADO', 'TRIB', 'MVA',
                                    'SUCESSAO', 'LITRAGEM', 'FABRICA')
             then 'CADASTRO'
             else 'DECISAO'
        end                                                as categoria,
        -- entra no score de priorizacao? Os nove tipos com peso do Diretor -
        -- ver cabecalho.
        case when d.tipo_alerta = 'FORA_DE_LINHA'          then 'N'
             when d.tipo_alerta in ('IMPORTADO', 'TRIB', 'MVA',
                                    'SUCESSAO', 'LITRAGEM', 'FABRICA')
             then 'N'
             else 'S'
        end                                                as pontua,
        -- recorte: como o comprador filtra a lista dele
        p.fornecedor,
        p.comprador,
        p.classe,
        p.descricao
      from despivotado d
      join pedido p
        on p.codigo = d.codigo
     -- so' alerta ATIVO vira linha - e' o grao declarado no cabecalho
     where d.texto_alerta is not null
)

select * from final
