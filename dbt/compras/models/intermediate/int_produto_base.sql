-- ─────────────────────────────────────────────────────────────────────────────
-- int_produto_base — colunas A a N da aba `pedido` (identificacao e fatores).
--
-- Gabarito: docs/gabarito_pedido_formulas.txt, linhas A..N. Mapa coluna a coluna:
--   A  CODIGO            colado de dCadastroTI!$A (sem formula)
--   B  COD_FAB           colado de dCadastroTI!$B
--   C  DESCRICAO         colado de dCadastroTI!$C
--   D  ALERTA            NAO E DAQUI - concatena 14 colunas de check, leva seguinte
--   E  STATUS            dCadastroTI!$D, vazio -> '?'
--   F  FORNECEDOR        dCadastroTI!$M (DEPARTAMENTO_TXT), vazio -> 'NAO MAPEADO'
--   G  COMPRADOR         dFornecedor!$E por $F, sem linha -> 'A DEFINIR'
--   H  EMBALAGEM         colado de dCadastroTI!$F
--   I  (nao usado)       coluna vazia na planilha - nao vira coluna aqui
--   J  EMBAL_COMPRA      dCadastroTI!$G, vazio -> 1
--   K  FATOR_EXIBICAO    $J se dFornecedor!$D = 'MASTER', senao 1
--   L  L_POR_UNIDADE     dEmbalagem!$D por $H, sem linha -> 0
--   M  PESO_UNITARIO_KG  dCadastroTI!$AG, vazio -> 0
--   N  QT_PALETE         dCadastroTI!$AH, vazio -> 0
-- (o mapa das letras de dCadastroTI sai de docs/gabarito_powerquery.m, passo
-- `Selecionado`, que fixa a ordem das 34 colunas da aba.)
--
-- Grao: 1 linha por SKU. A espinha e int_cadastro_estoque - a mesma dCadastroTI
-- que a planilha cola na aba `pedido` -, entao TODO SKU do cadastro aparece,
-- inclusive quem nunca vendeu.
--
-- ── F | FORNECEDOR e o texto do DEPARTAMENTO, nao o fornecedor legal da NF ──
-- CONTEXTO.md regra 7 e o passo `ComFornecedor` do Power Query
-- ("FORNECEDOR usa o texto do Departamento, nao o Fornecedor Legal"). O
-- fornecedor legal existe em int_cadastro_estoque como `fornecedor_legal_nf` e
-- NAO entra aqui. Isso importa muito alem do rotulo: `FORNECEDOR` e a chave de
-- busca de G (COMPRADOR), AB (N_MESES), K (FATOR_EXIBICAO), AZ
-- (SUG_COBERTURA), BO (CRED_TOTAL, via 'FORNECEDOR|COD_ICMS') e BX (o ajuste
-- Ingrax, que testa $F2 = 'INGRAX'). Trocar a fonte muda imposto e preco.
--
-- ── K | FATOR_EXIBICAO: por que ele nasce aqui ──────────────────────────────
-- CONTEXTO.md regra 6: praticamente toda quantidade EXIBIDA e dividida por ele.
-- Ele vale EMBAL_COMPRA quando o fornecedor compra em caixa fechada
-- (dFornecedor.PEDIDO_EM = 'MASTER') e 1 caso contrario - e o fallback do
-- proprio Excel quando o departamento nao esta em dFornecedor e 'UNIDADE'
-- (IFERROR(...,"UNIDADE")), ou seja, fator 1. Hoje sao 5 departamentos MASTER
-- (PETRONAS, YPF, INGRAX, KOUBE, VALVOLINE); ROBUST e o unico departamento sem
-- linha no seed e cai no fallback.
--
-- ── L | L_POR_UNIDADE: upper() SIM, trim() NAO ──────────────────────────────
-- CONTEXTO.md 6.2, armadilha medida no dado. O MATCH do Excel ignora CAIXA mas
-- NAO ignora espaco. Medido nesta base:
--   * 158 SKUs (`40x500 ML`, `6x3 LTS`, `24x200 ML`...) so casam ignorando
--     caixa - a planilha os encontra, um join exato nao encontraria;
--   * 5 valores de EMBALAGEM tem espaco a direita (`TAMBOR `, `BALDE `,
--     `10X1 `, `12X250 ML `, `24 X1KG `, 12 SKUs no total) e NEM O EXCEL casa -
--     aplicar trim() aqui seria DIVERGIR do gabarito, nao consertar nada.
-- Por que isso e grave e nao cosmetico: L_POR_UNIDADE decide de qual dos DOIS
-- universos da curva ABC o SKU participa (CONTEXTO.md regra 5). Errar o join
-- muda o DENOMINADOR de um universo inteiro e, com ele, a CLASSE de TODOS os
-- SKUs - nao so a dos que casaram errado.
--
-- O seed tem 10 pares de linhas que diferem SO na caixa (`10X1`/`10x1`,
-- `6X4 LTS`/`6x4 LTS`...). O MATCH do Excel devolveria a PRIMEIRA; um join com
-- upper() daria fan-out (4.105 SKUs duplicados, medido). Por isso a CTE
-- `embalagem` agrupa por upper() antes de juntar. Os 10 pares tem
-- LITROS_POR_UNIDADE IDENTICO, entao min() devolve o mesmo numero que o Excel -
-- e `tests/compras_embalagem_upper_sem_conflito.sql` reprova o build se algum
-- dia deixarem de ser identicos, em vez de escolher em silencio.
--
-- ── embalagem_cadastrada: coluna de APOIO, nao e coluna do gabarito ─────────
-- 'S'/'N' de ISNA(MATCH($H2,dEmbalagem!$A:$A,0)), que a coluna AY
-- (CHECK_LITRAGEM) precisa. Existe porque L_POR_UNIDADE = 0 e AMBIGUO: pode
-- ser "nao achou no cadastro" OU "achou e o produto nao tem litragem mesmo"
-- (`12X1 KG`, `36X80 GR` estao no seed com 0). AY dispara so no primeiro caso,
-- e a leva de alertas nao teria como distinguir os dois a partir de L sozinho.
-- ─────────────────────────────────────────────────────────────────────────────

with cadastro as (
    select * from {{ ref('int_cadastro_estoque') }}
),

fornecedor as (
    select * from {{ ref('seed_fornecedor') }}
),

-- upper() reproduz a insensibilidade a caixa do MATCH; o group by desarma o
-- fan-out das 10 colisoes de caixa do seed - ver cabecalho.
embalagem as (
    select
        upper(EMBALAGEM)        as chave_embalagem,
        min(LITROS_POR_UNIDADE) as litros_por_unidade
      from {{ ref('seed_embalagem') }}
     group by upper(EMBALAGEM)
),

-- F | FORNECEDOR resolvido antes, porque G, K (e, nas levas seguintes, AB e AZ)
-- todos buscam dFornecedor por ELE, ja com o fallback aplicado.
identificacao as (
    select
        c.codprod                      as codigo,
        c.codfab                       as cod_fab,
        c.produto                      as descricao,
        nvl(c.status, '?')             as status,
        nvl(c.departamento,
            'NAO MAPEADO')             as fornecedor,
        c.embalagem                    as embalagem,
        nvl(c.embal_compra, 1)         as embal_compra,
        nvl(c.pesoliq, 0)              as peso_unitario_kg,
        nvl(c.qt_palete, 0)            as qt_palete
      from cadastro c
),

final as (
    select
        i.codigo,
        i.cod_fab,
        i.descricao,
        i.status,
        i.fornecedor,
        nvl(f.COMPRADOR, 'A DEFINIR')                     as comprador,
        i.embalagem,
        i.embal_compra,
        -- K: IF(IFERROR(dFornecedor!$D,"UNIDADE")="MASTER",$J2,1). O nvl
        -- reproduz o IFERROR: departamento fora do seed = 'UNIDADE' = fator 1.
        case when nvl(f.PEDIDO_EM, 'UNIDADE') = 'MASTER'
             then i.embal_compra
             else 1
        end                                               as fator_exibicao,
        nvl(e.litros_por_unidade, 0)                      as l_por_unidade,
        i.peso_unitario_kg,
        i.qt_palete,
        -- apoio para AY (CHECK_LITRAGEM) - ver cabecalho
        case when e.chave_embalagem is null then 'N' else 'S' end as embalagem_cadastrada
      from identificacao i
      left join fornecedor f
        on upper(f.FORNECEDOR) = upper(i.fornecedor)
      left join embalagem e
        on e.chave_embalagem = upper(i.embalagem)
)

select * from final
