-- ─────────────────────────────────────────────────────────────────────────────
-- int_produto_entrada_fornecedor — DE QUEM, E DE QUE ESTADO, VEIO A ÚLTIMA
-- ENTRADA que formou o custo do produto.
--
-- ── ⚠ QUAL COLUNA EXCEL REPRODUZ: NENHUMA. ──────────────────────────────────
-- A planilha v11 não conhece a origem da compra. Este modelo nasce da regra do
-- ST embutido fechada pelo Diretor de Compras em 09/10/2026, cuja condição 3 é
-- "fornecedor de FORA da Bahia" — e essa pergunta não tem resposta em
-- nenhuma coluna existente. Não entra em fat_pedido (as 122 colunas são o
-- gabarito e só elas).
--
-- ── POR QUE NÃO SERVE O FORNECEDOR DO CADASTRO ──────────────────────────────
-- `int_produto_fiscal.uf_origem` já existe, mas é a UF do fornecedor
-- CADASTRADO no produto (PCPRODUT.CODFORNEC) — quem costuma fornecer, não
-- quem forneceu AQUELA compra. Medido em 09/10/2026, nos 3.055 ativos onde a
-- condição 3 de fato decide: as duas UFs divergem em 235, e em 191 deles a
-- compra veio da BAHIA enquanto o cadastro aponta para fora. Usar o cadastro
-- somaria ST em 191 produtos que já vieram com ele no preço.
--
-- ── POR QUE NÃO SERVE int_produto_ultima_entrada ────────────────────────────
-- Aquele modelo responde outra pergunta: o PREÇO da última entrada SEM FRETE,
-- pela lógica da rotina 218, que filtra `CODOPER = 'E'` por decisão de
-- 29/09/2026. A entrada que ele acha não é necessariamente a que formou
-- PCEST.CUSTOULTENT — medido: as datas batem em 4.010 dos 4.553 ativos. Nos
-- SKUs 4890 e 4891 a diferença é de três anos (nota de 2017, custo de
-- 2019/2020), e seguir a 218 ali responderia pela compra errada.
--
-- ── A LIGAÇÃO QUE ESTE MODELO FAZ ───────────────────────────────────────────
-- `PCEST.DTULTENT` é a data da entrada que gravou o custo. Então a pergunta
-- "de quem veio esse custo" se responde procurando a entrada DAQUELE DIA:
--
--   int_cadastro_estoque.dt_ult_ent  ──(produto + dia)──►  PCMOV ──► PCNFENT
--                                                                      │
--                                                              PCFORNEC.ESTADO
--
-- Cobertura medida em 09/10/2026, no conjunto que importa (ativos
-- ST_SUBSTITUTO com entrada a partir de 01/10/2022): 3.055 de 3.055 acham a
-- entrada do dia — 100% —, e 3.027 deles têm UF do fornecedor. Os 28 sem UF
-- não viram "fora da BA" por omissão: ficam nulos, e a regra do ST trata
-- condição não comprovada como condição FALHA (não soma).
--
-- ⚠ `CODOPER like 'E%'`, e NÃO o `= 'E'` da 218. Aqui a pergunta não é "qual
-- preço negociar com o fornecedor" — é "esta mercadoria entrou de onde". Uma
-- bonificação (EB) ou um retorno de remessa (ER) que tenha gravado o custo
-- entrou de algum lugar, e esse lugar decide se o ST veio no preço. Excluí-los
-- deixaria o produto sem origem e, pela regra conservadora, sem ST somado.
--
-- ⚠ `max(id_cliente_devolucao)` quando o mesmo produto tem mais de uma entrada
-- no mesmo dia: é desempate arbitrário, e é deliberado. O que a condição 3
-- precisa saber é se a compra foi interestadual; duas entradas do mesmo dia de
-- UFs diferentes são raras e, nelas, qualquer escolha é igualmente defensável.
-- O relatório de divergência (regra × nota × cadastro) é onde esses casos
-- aparecem para o Fiscal olhar, em vez de o modelo fingir certeza.
--
-- ⚠ O nome `id_cliente_devolucao` em stg_nota_entrada é PCNFENT.CODFORNEC, que
-- em nota de DEVOLUÇÃO guarda o CODCLI do cliente (ver o aviso lá). Aqui as
-- devoluções não chegam: `tipo_descarga not in ('6','7','8','N','F')` é o
-- mesmo filtro que int_produto_ultima_entrada aplica, pela mesma razão.
-- ─────────────────────────────────────────────────────────────────────────────

{{ config(materialized='table') }}

with cadastro as (
    select * from {{ ref('int_cadastro_estoque') }}
),

nota as (
    select
        id_transacao_entrada,
        id_cliente_devolucao as id_fornecedor
      from {{ ref('stg_nota_entrada') }}
     where id_filial = '{{ var("compras_filial_estoque", "2") }}'
       and tipo_descarga not in ('6', '7', '8', 'N', 'F')
),

movimentacao as (
    select * from {{ ref('stg_movimentacao') }}
),

fornecedor as (
    select * from {{ ref('stg_fornecedor') }}
),

-- Uma linha por produto + DIA de entrada. O agrupamento é o que impede o
-- fan-out: um movimento por item da nota viraria uma linha por item.
entrada_do_dia as (
    select
        m.id_produto,
        trunc(m.data_movimento)      as dia,
        max(n.id_fornecedor)         as id_fornecedor,
        -- A entrada daquele dia incluiu COMPRA de fornecedor? Item 1.16 do
        -- Diretor (09/10/2026): "bonificacao como ultima entrada na
        -- Precificacao - 8817 com R$ 227,87". O WinThor grava em PCEST
        -- QUALQUER entrada: no 8817 a unica que existe e' um RETORNO DE
        -- REMESSA (CODOPER 'ER', descarga 'R'), 1 unidade a R$ 227,87, num
        -- produto cujo atacado e' R$ 72,40.
        --
        -- `max`, e nao `min`: basta UMA compra no dia para a entrada do dia
        -- ser compra. Dia com compra e bonificacao juntas conta como compra -
        -- o valor de entrada veio da compra.
        max(case when m.codigo_operacao = 'E' then 1 else 0 end) as tem_compra
      from movimentacao m
      join nota n
        on n.id_transacao_entrada = m.id_transacao_entrada
     where m.codigo_operacao like 'E%'
       and m.data_cancelamento is null
     group by m.id_produto, trunc(m.data_movimento)
),

final as (
    select
        c.codprod                    as codigo,
        c.dt_ult_ent,
        e.id_fornecedor              as id_fornecedor_entrada,
        f.nome_fornecedor            as fornecedor_entrada,
        f.uf_origem                  as uf_entrada,
        -- "Não achei a entrada daquele dia" e "achei, mas o fornecedor não tem
        -- UF" são coisas diferentes e separá-las é o que permite ao relatório
        -- de divergência dizer qual das duas está acontecendo. As duas levam ao
        -- mesmo resultado na regra do ST (condição 3 falha), mas não à mesma
        -- providência: a primeira é dado de movimento, a segunda é cadastro de
        -- fornecedor.
        case when e.id_produto is null then 1 else 0 end as entrada_sem_nota,
        -- 1 quando a ultima entrada do WinThor FOI compra de fornecedor.
        -- Sem movimento no dia (119 ativos) nao e' "nao foi compra": e' "nao
        -- se sabe" - por isso NULL, e nao 0. A tela distingue os dois.
        e.tem_compra                                     as ult_entrada_e_compra,
        case when e.id_produto is not null and f.uf_origem is null
             then 1 else 0 end                           as fornecedor_sem_uf
      from cadastro c
      left join entrada_do_dia e
        on e.id_produto = c.codprod
       and e.dia        = trunc(c.dt_ult_ent)
      left join fornecedor f
        on f.id_fornecedor = e.id_fornecedor
)

select * from final
