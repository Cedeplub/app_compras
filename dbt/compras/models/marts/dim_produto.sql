-- ─────────────────────────────────────────────────────────────────────────────
-- dim_produto — o SKU e seus atributos DESCRITIVOS. Grão: 1 linha por `codigo`.
--
-- Qual coluna Excel reproduz: A, B, C, E, F, G, H, J, K, L, M, N (identificação
-- e fatores, de int_produto_base) e AX (CLASSE, de int_produto_classe_abc).
-- Nenhuma regra nova: cada coluna sai pronta do intermediate que a calcula.
--
-- ── Por que existe, se fat_pedido já tem tudo ──────────────────────────────
-- fat_pedido tem 122 colunas e uma linha por SKU - é a planilha inteira, feita
-- para o aceite célula a célula. Quem só precisa preencher um filtro de
-- fornecedor, resolver um código em descrição ou desenhar um seletor de classe
-- não deveria varrer 122 colunas para isso. Esta é a tabela estreita que o
-- dashboard lê nesses casos.
--
-- ── O corte: atributo DESCRITIVO entra, medida NÃO ─────────────────────────
-- Entra o que identifica ou classifica o SKU e muda devagar (nome, embalagem,
-- departamento, comprador, curva). Fica de fora tudo que é medida do período -
-- estoque, venda, custo, margem, preço, alerta. Uma dimensão que carregue
-- estoque vira uma segunda cópia do fato, e no dia em que as duas discordarem
-- ninguém sabe qual está certa.
--
-- ⚠ CLASSE (AX) é a exceção discutível, e entra de propósito: apesar de ser
-- recalculada a cada build (é participação no faturamento - CONTEXTO.md regra
-- 5), ela é usada como RECORTE em praticamente toda tela, não como número. Fica
-- registrado que ela NÃO é um atributo estável: a classe de um SKU muda quando
-- o catálogo inteiro muda, mesmo que o SKU não tenha se mexido.
--
-- ── FORNECEDOR é o texto do DEPARTAMENTO ──────────────────────────────────
-- CONTEXTO.md regra 7. Não é o fornecedor legal da nota fiscal - esse existe em
-- int_cadastro_estoque como `fornecedor_legal_nf` e não entra aqui. É a chave
-- de junção com dim_fornecedor e o que decide comprador, meses de média,
-- cobertura, crédito e o ajuste Ingrax. Trocar a fonte muda imposto e preço.
-- ─────────────────────────────────────────────────────────────────────────────

with base as (
    select * from {{ ref('int_produto_base') }}
),

classe_abc as (
    select * from {{ ref('int_produto_classe_abc') }}
),

final as (
    select
        b.codigo,                       -- A | CODIGO
        b.cod_fab,                      -- B | COD_FAB
        b.descricao,                    -- C | DESCRICAO
        b.status,                       -- E | STATUS ('Ativo' | 'Inativo' | '?')
        b.fornecedor,                   -- F | FORNECEDOR (texto do departamento)
        b.comprador,                    -- G | COMPRADOR
        b.embalagem,                    -- H | EMBALAGEM
        b.embal_compra,                 -- J | EMBAL_COMPRA
        b.fator_exibicao,               -- K | FATOR_EXIBICAO
        b.l_por_unidade,                -- L | L_POR_UNIDADE
        b.peso_unitario_kg,             -- M | PESO_UNITARIO_KG
        b.qt_palete,                    -- N | QT_PALETE
        -- apoio de AY: 'N' = embalagem sem linha no seed_embalagem. Fica aqui
        -- porque explica L_POR_UNIDADE = 0 sem obrigar a abrir o fat_alerta.
        b.embalagem_cadastrada,
        c.classe,                       -- AX | CLASSE ('A' | 'B/C' | 'S/VEND')
        -- de qual dos DOIS universos da curva o SKU participa, e com que peso.
        -- Sem isso, uma classe 'B/C' parece comparável a outra 'B/C' de universo
        -- diferente - e elas têm denominadores diferentes (CONTEXTO.md regra 5).
        c.universo,
        c.participacao
      from base b
      join classe_abc c
        on c.codigo = b.codigo
)

select * from final
