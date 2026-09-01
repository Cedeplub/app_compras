-- ─────────────────────────────────────────────────────────────────────────────
-- Origem: relatorios_compras/query.py (_SELECT + _FROM), 41 colunas.
-- Conferido também contra a versão legível em
-- app_relatorios/relatorios/compras_estoque.py (SQL idêntico, mesmos comentários).
-- Vira a aba dCadastroTI da planilha v10 (ver docs/gabarito_powerquery.m).
--
-- Grão: 1 linha por SKU (PCPRODUT.CODPROD), na filial de estoque
-- var('compras_filial_estoque', '2').
--
-- `p.dtexclusao IS NULL` é condição FIXA E GLOBAL neste relatório (CONTEXTO.md
-- regra 11, primeiro caso) - diferente do relatório mensal, onde só vale dentro
-- de `produtos_incluir`. Aplicar aqui globalmente é correto e pretendido.
--
-- `t.ufdestino = var('compras_uf_destino','BA')` vai no ON do join com
-- pctabtrib, nunca no WHERE - no WHERE descartaria produto sem linha de
-- tributação para a UF.
--
-- FORNECEDOR: a coluna "fornecedor" de query.py é literalmente pcfornec.fornecedor
-- (fornecedor legal da NF) - mas CONTEXTO.md regra 7 e docs/gabarito_powerquery.m
-- (linha "FORNECEDOR usa o texto do Departamento, nao o Fornecedor Legal") deixam
-- claro que o campo "FORNECEDOR" do MODELO é o texto do departamento, e que o
-- fornecedor legal vira uma coluna separada (FORNECEDOR_LEGAL no PowerQuery).
-- Para não repetir a armadilha aqui, esta coluna sai renomeada para
-- `fornecedor_legal_nf`, sem valor de negócio alterado - só o nome. `departamento`
-- (pcdepto.descricao) continua como a fonte do FORNECEDOR de negócio; a derivação
-- FORNECEDOR = departamento é responsabilidade da camada que porta o PowerQuery
-- (fora do escopo desta etapa).
--
-- VL_ULT_ENT nunca é dividido pela embalagem de compra - já vem unitário.
-- ─────────────────────────────────────────────────────────────────────────────

with estoque as (
    select *
      from {{ ref('stg_estoque') }}
     where id_filial = '{{ var("compras_filial_estoque", "2") }}'
),

produto as (
    select *
      from {{ ref('stg_produto') }}
     where data_exclusao is null
),

tributacao as (
    select * from {{ ref('stg_tributacao') }}
),

tributacao_desc as (
    select * from {{ ref('stg_tributacao_desc') }}
),

tributacao_piscofins as (
    select * from {{ ref('stg_tributacao_piscofins') }}
),

fornecedor as (
    select * from {{ ref('stg_fornecedor') }}
),

departamento as (
    select * from {{ ref('stg_departamento') }}
),

secao as (
    select * from {{ ref('stg_secao') }}
),

produto_filial as (
    select * from {{ ref('stg_produto_filial') }}
),

movimentacao as (
    select * from {{ ref('stg_movimentacao') }}
),

preco_tabela as (
    select * from {{ ref('stg_preco_tabela') }}
),

final as (
    select
        p.id_produto                                                       as codprod,
        p.cod_fabrica                                                      as codfab,
        p.descricao_produto                                                as produto,
        -- status ja vem calculado do staging (OBS2='FL' -> Inativo), mesma logica
        -- de query.py
        p.status,
        p.unidade,
        p.embalagem,
        p.embal_compra,
        p.embal_venda,
        pf.quantidade_palete                                               as qt_palete,
        p.peso_liquido                                                     as pesoliq,
        p.peso_bruto                                                       as pesobruto,
        e.id_filial                                                        as codfilial,
        -- fornecedor / classificacao
        f.id_fornecedor                                                    as codfornec,
        f.nome_fornecedor                                                  as fornecedor_legal_nf,
        f.uf_origem,
        p.id_departamento                                                  as codepto,
        d.descricao_departamento                                          as departamento,
        p.id_secao                                                        as codsec,
        s.descricao_secao                                                 as secao,
        -- tributacao
        t.uf_destino                                                      as ufdestino,
        t.id_tributacao                                                   as cod_tributacao,
        td.descricao_tributacao                                          as tributacao,
        p.ncm,
        p.ncm_excecao,
        t.id_tributacao_piscofins                                        as codtribpiscofins,
        tp_pf.descricao_tributacao_piscofins                             as descricaotribpiscofins,
        -- estoque
        nvl(e.quantidade_estoque, 0)                                      as estoque,
        nvl(e.quantidade_gerencial, 0)                                    as gerencial,
        nvl(e.quantidade_pedida, 0)                                       as qtpedida,
        nvl(e.quantidade_bloqueada, 0) - nvl(e.quantidade_avaria, 0)      as qtbloqueada,
        nvl(e.quantidade_avaria, 0)                                       as qtavaria,
        nvl(e.quantidade_reservada, 0)                                    as qtreserv,
        -- disponivel de venda (equivalente ao processo 'V' da PKG_ESTOQUE)
        greatest(  nvl(e.quantidade_gerencial, 0)
                 - nvl(e.quantidade_bloqueada, 0)
                 - nvl(e.quantidade_industria, 0)
                 - nvl(e.quantidade_reservada, 0)
               , 0)                                                       as qtdisp,
        -- ultimas movimentacoes
        e.data_ultima_entrada                                            as dt_ult_ent,
        nvl(e.quantidade_ultima_entrada, 0)                               as qt_ult_ent,
        e.data_ultima_saida                                              as dt_ult_saida,
        (select max(mv.quantidade) keep (dense_rank last order by mv.data_movimento)
           from movimentacao mv
          where mv.id_produto  = e.id_produto
            and mv.id_filial   = e.id_filial
            and mv.codigo_operacao in ('S', 'ST'))                        as qt_ult_saida,
        nvl(e.custo_ultima_entrada, 0)                                    as custo_ult_ent,
        -- VL_ULT_ENT nunca e dividido pela embalagem de compra - ja vem unitario
        nvl(e.valor_ultima_entrada, 0)                                    as vl_ult_ent,
        -- precos (regiao 1 = VAREJO / regiao 2 = ATACADO)
        (select pt.preco_venda from preco_tabela pt
          where pt.id_produto = e.id_produto and pt.id_regiao = 2)        as pv_atacado,
        (select pt.preco_venda from preco_tabela pt
          where pt.id_produto = e.id_produto and pt.id_regiao = 1)        as pv_varejo
      from estoque e
     inner join produto p
        on p.id_produto = e.id_produto
       and (   p.id_filial_produto = e.id_filial
            or p.id_filial_produto = '99'
            or p.id_filial_produto is null)
      left join tributacao t
        on t.id_produto     = p.id_produto
       and t.id_filial_nf   = e.id_filial
       and t.uf_destino     = '{{ var("compras_uf_destino", "BA") }}'
      left join fornecedor f
        on f.id_fornecedor = p.id_fornecedor
      left join departamento d
        on d.id_departamento = p.id_departamento
      left join secao s
        on s.id_secao = p.id_secao
      left join tributacao_desc td
        on td.id_tributacao = t.id_tributacao
      left join tributacao_piscofins tp_pf
        on tp_pf.id_tributacao_piscofins = t.id_tributacao_piscofins
      left join produto_filial pf
        on pf.id_produto = p.id_produto
       and pf.id_filial  = e.id_filial
)

select * from final
