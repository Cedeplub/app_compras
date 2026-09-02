-- ─────────────────────────────────────────────────────────────────────────────
-- int_entrada_produto — enriquece int_entrada_compra com as dimensões que a
-- tela Entradas precisa (PROTOTIPO.md §2.3): produto, departamento, seção,
-- status. Grão inalterado: 1 linha por item de movimento de entrada.
--
-- ⚠ NÃO filtra `data_exclusao is null`. Diferente de int_cadastro_estoque
-- (onde dtexclusao IS NULL é global, CONTEXTO.md regra 11), esta é uma tela
-- operacional de "o que chegou", não um recorte de cadastro vigente - um
-- produto que acabou de ser excluído do cadastro ainda pode ter uma entrada
-- de ontem que o comprador precisa ver. Em vez de esconder, o STATUS
-- (Ativo/Inativo) vai como COLUNA, e a tela filtra por ele (PROTOTIPO.md §2.3:
-- `status` nasce em "Todos", diferente de Alertas que nasce em "Ativo") - a
-- mesma convenção de int_cadastro_estoque.status.
--
-- DEPARTAMENTO/SECAO (não FORNECEDOR): vocabulário do v2 (v2/PLANO.md §4,
-- item 1 do backlog - "Fornecedor" virou "Departamento" na interface nova).
-- COMPRAS_VENDA_MENSAL já segue essa convenção (CODEPTO/DEPARTAMENTO/
-- CODSEC/SECAO); aqui é o mesmo padrão, não o nome FORNECEDOR usado dentro de
-- fat_pedido/compras_pedido (que é contrato da planilha e não muda).
-- ─────────────────────────────────────────────────────────────────────────────

with entrada as (
    select * from {{ ref('int_entrada_compra') }}
),

produto as (
    select * from {{ ref('stg_produto') }}
),

departamento as (
    select * from {{ ref('stg_departamento') }}
),

secao as (
    select * from {{ ref('stg_secao') }}
),

final as (
    select
        e.id_transacao_entrada,
        e.id_transacao_item,
        e.id_produto,
        p.descricao_produto  as produto,
        p.status,
        p.id_departamento    as codepto,
        d.descricao_departamento as departamento,
        p.id_secao           as codsec,
        s.descricao_secao    as secao,
        e.id_fornecedor,
        e.tipo_entrada,
        e.data_entrada,
        e.quantidade,
        e.preco_unitario,
        e.valor
      from entrada e
      left join produto p
        on p.id_produto = e.id_produto
      left join departamento d
        on d.id_departamento = p.id_departamento
      left join secao s
        on s.id_secao = p.id_secao
)

select * from final
