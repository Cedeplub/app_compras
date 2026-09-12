-- ─────────────────────────────────────────────────────────────────────────────
-- dim_fornecedor — a aba `dFornecedor` da planilha v10, com o alcance real de
-- cada linha medido no catálogo. Grão: 1 linha por FORNECEDOR.
--
-- Qual coluna Excel reproduz: nenhuma da aba `pedido` diretamente. É a tabela
-- de apoio que as fórmulas de `pedido` citam por lookup - G (COMPRADOR,
-- dFornecedor!$E), AB (N_MESES, $B), K (FATOR_EXIBICAO, $D = PEDIDO_EM) e a
-- cobertura de AZ (SUG_COBERTURA, $C).
--
-- ── ⚠ "FORNECEDOR" aqui é o texto do DEPARTAMENTO ─────────────────────────
-- CONTEXTO.md regra 7. Apesar do nome, a chave desta dimensão é o DEPARTAMENTO
-- do cadastro (`dCadastroTI!$M`), não o fornecedor legal da nota fiscal. É como
-- a planilha chama e como o Diretor de Compras fala, e é por isso que o nome
-- foi mantido (CONTEXTO.md §5: o vocabulário da planilha ganha). Quem procurar
-- aqui o CNPJ que emitiu a nota não vai achar - isso é
-- `int_cadastro_estoque.fornecedor_legal_nf`, outra coisa.
--
-- ── Por que o grão é o UNION, e não só o seed ─────────────────────────────
-- Os dois lados existem e nenhum contém o outro:
--   * departamento no seed SEM nenhum SKU - regra cadastrada que hoje não
--     alcança produto nenhum;
--   * departamento no catálogo SEM linha no seed - o SKU existe e cai nos
--     fallbacks do próprio Excel (IFERROR): comprador 'A DEFINIR', N_MESES 3,
--     cobertura 2, PEDIDO_EM 'UNIDADE'. Medido: ROBUST é esse caso hoje.
-- Uma dimensão só com o seed esconderia o segundo grupo justamente de quem
-- precisa vê-lo - é a lista do que falta cadastrar. `tem_regra_cadastrada`
-- separa os dois sem que ninguém precise deduzir pelo nulo.
--
-- ⚠ Os fallbacks NÃO são aplicados aqui: as colunas do seed saem nulas quando
-- não há linha. Aplicá-los criaria uma segunda cópia da regra que
-- int_produto_base e int_produto_demanda já implementam, e as duas poderiam
-- divergir. Esta dimensão descreve o que ESTÁ cadastrado; quem calcula com
-- fallback é o intermediate.
--
-- ── PEDIDO_EM decide o FATOR_EXIBICAO de todo SKU do departamento ─────────
-- 'MASTER' faz K valer EMBAL_COMPRA e, por CONTEXTO.md regra 6, divide
-- praticamente toda quantidade exibida do departamento inteiro. É a coluna
-- desta tabela com maior alcance por caractere alterado.
-- ─────────────────────────────────────────────────────────────────────────────

with seed as (
    select * from {{ ref('seed_fornecedor') }}
),

base as (
    select * from {{ ref('int_produto_base') }}
),

-- O alcance real de cada departamento, medido no catalogo de hoje.
uso as (
    select
        fornecedor,
        count(*) as qtd_sku
      from base
     group by fornecedor
),

-- O grao: a UNIAO das duas listas - ver cabecalho.
chave as (
    select upper(FORNECEDOR) as chave_fornecedor from seed
     union
    select upper(fornecedor)                     from uso
),

final as (
    select
        -- o texto como o CADASTRO grafa tem precedencia sobre o do seed: e' o
        -- que aparece na tela do comprador. So' cai no do seed quando nao ha
        -- SKU nenhum com esse departamento.
        nvl(u.fornecedor, s.FORNECEDOR)                    as fornecedor,
        c.chave_fornecedor,
        -- 'N' = departamento sem linha no dFornecedor: os SKUs dele caem nos
        -- fallbacks do Excel. E' a lista do que falta cadastrar.
        case when s.FORNECEDOR is null then 'N' else 'S' end as tem_regra_cadastrada,
        s.MESES_MEDIA                                      as meses_media,     -- AB
        s.COBERTURA_ALVO                                   as cobertura_alvo,  -- AZ
        s.PEDIDO_EM                                        as pedido_em,       -- K
        s.COMPRADOR                                        as comprador,       -- G
        nvl(u.qtd_sku, 0)                                  as qtd_sku
      from chave c
      left join seed s
        on upper(s.FORNECEDOR) = c.chave_fornecedor
      left join uso u
        on upper(u.fornecedor) = c.chave_fornecedor
)

select * from final
