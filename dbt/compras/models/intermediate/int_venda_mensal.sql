-- ─────────────────────────────────────────────────────────────────────────────
-- Origem: CTEs `produtos`, `meses`, `produtos_em_linha`, `produtos_incluir`,
-- `chaves` e o SELECT final, relatorios_compras/query_mensal.py (conferido
-- também contra app_relatorios/relatorios/compras_mensal.py) - 19 colunas.
-- Julho/2026: SQL original e refatorado devolvem as mesmas 2.839 linhas com
-- valores idênticos contra a rotina 1464. Não mudar nada aqui muda número de
-- relatório.
--
-- Grão: mês × produto. É a espinha final do relatório mensal, sempre LÍQUIDO
-- (faturado − devolvido).
--
-- A base do pivot mensal é TODO SKU que apareceu em QUALQUER mês, inclusive o
-- corrente (CONTEXTO.md regra 9) - não só quem tem mês fechado. Regra de quem
-- entra SEM ter vendido (`produtos_incluir`): em linha (OBS2 <> 'FL') + giro
-- cadastrado (qtgirodia > 0) na filial de estoque + `dtexclusao IS NULL`.
--
-- ⚠️ `dtexclusao IS NULL` aqui vale SÓ dentro de `produtos_incluir` (CONTEXTO.md
-- regra 11, segundo caso) - a CTE `produtos`, que alimenta toda linha da saída,
-- NÃO filtra por dtexclusao: produto excluído COM movimento no período tem que
-- aparecer. Aplicar globalmente apagaria essa linha.
--
-- A espinha `meses` lê os limites de int_periodo_mensal (ref, uma linha), não
-- mais a macro expandida direto aqui - ver o cabeçalho de int_periodo_mensal
-- para o porquê (janela dessincronizada em build parcial: sem isso, um
-- `dbt run --select int_venda_mensal` sozinho podia gerar espinha mais larga
-- que int_faturamento_mensal/int_devolucao_mensal, zerando o mês novo).
-- ─────────────────────────────────────────────────────────────────────────────

with produto as (
    select * from {{ ref('stg_produto') }}
),

departamento as (
    select * from {{ ref('stg_departamento') }}
),

secao as (
    select * from {{ ref('stg_secao') }}
),

estoque as (
    select * from {{ ref('stg_estoque') }}
),

faturamento_mensal as (
    select * from {{ ref('int_faturamento_mensal') }}
),

devolucao_mensal as (
    select * from {{ ref('int_devolucao_mensal') }}
),

dias_sem_estoque_mensal as (
    select * from {{ ref('int_dias_sem_estoque_mensal') }}
),

-- Sem filtro de produto/depto/secao de propósito: o dbt materializa o universo
-- completo (equivalente ao caminho "sem filtro" de montar_consulta em
-- query_mensal.py, onde {FILTRO_PRODUTOS} fica vazio).
produtos as (
    select
        p.id_produto,
        p.descricao_produto,
        p.fora_de_linha,
        p.id_departamento as codepto,
        dep.descricao_departamento as departamento,
        p.id_secao as codsec,
        sec.descricao_secao as secao
      from produto p
      left join departamento dep on dep.id_departamento = p.id_departamento
      left join secao sec on sec.id_secao = p.id_secao
),

-- Janela mensal lida de int_periodo_mensal (uma linha) - ver seu cabecalho
-- para o porque desta espinha nao expandir mais a macro direto aqui.
periodo as (
    select * from {{ ref('int_periodo_mensal') }}
),

-- Espinha de meses do periodo: produtos sem venda nao tem data de movimento
-- de onde derivar o mes.
meses as (
    select add_months(trunc(pe.data_inicio, 'MM'), level - 1) as mes
      from periodo pe
   connect by level <= months_between(pe.data_fim, trunc(pe.data_inicio, 'MM'))
),

-- Produtos EM LINHA. Nao e filtro global: serve so para decidir quem entra
-- SEM ter vendido. Produto fora de linha so aparece se teve movimento.
-- fora_de_linha ja vem calculado no staging com a mesma logica de OBS2='FL'
-- (NVL(UPPER(TRIM(obs2)),'-') <> 'FL' <=> fora_de_linha = 'N').
produtos_em_linha as (
    select p.id_produto
      from produto p
     where p.fora_de_linha = 'N'
),

-- Produtos acrescentados mesmo sem venda: alem de em linha, precisam de giro
-- cadastrado na filial de estoque (mesmo filtro da rotina 2080).
produtos_incluir as (
    select el.id_produto
      from produtos_em_linha el
     inner join produto p
        on p.id_produto = el.id_produto
     inner join estoque e
        on e.id_produto = el.id_produto
       and e.id_filial = '{{ var("compras_filial_estoque", "2") }}'
     where p.data_exclusao is null
       and nvl(e.giro_diario, 0) > 0
),

-- Espinha final (mes x produto):
--   * teve movimento no periodo (faturamento ou devolucao) -> entra, esteja
--     fora de linha ou nao;
--   * nao teve movimento -> so entra se estiver ATIVO e com giro
--     (produtos_incluir).
chaves as (
    select mes, id_produto from faturamento_mensal
    union
    select mes, id_produto from devolucao_mensal
    union
    select m.mes, pi.id_produto
      from meses m
     cross join produtos_incluir pi
),

final as (
    select
        k.mes,
        k.id_produto as codigo_produto,
        p.descricao_produto as produto,
        case when f.id_produto is not null then 'S' else 'N' end as teve_venda,
        p.fora_de_linha,
        p.codepto,
        p.departamento,
        p.codsec,
        p.secao,
        nvl(f.quantidade_total, 0) as quantidade_total,
        nvl(f.valor_total, 0) as valor_total,
        nvl(d.quantidade_devolucao, 0) as quantidade_devolucao,
        nvl(d.valor_devolucao, 0) as valor_devolucao,
        nvl(f.quantidade_total, 0) - nvl(d.quantidade_devolucao, 0) as quantidade_liquida,
        nvl(f.valor_total, 0) - nvl(d.valor_devolucao, 0) as valor_liquido,
        round(
            (nvl(f.valor_total, 0) - nvl(d.valor_devolucao, 0))
            / nullif(nvl(f.quantidade_total, 0) - nvl(d.quantidade_devolucao, 0), 0)
        , 2) as preco_medio,
        nvl(se.dias_sem_estoque, 0) as dias_sem_estoque,
        nvl(f.quantidade_clientes_atacado, 0) as quantidade_clientes_atacado,
        nvl(f.quantidade_clientes_varejo, 0) as quantidade_clientes_varejo
      from chaves k
      left join faturamento_mensal f
        on f.mes = k.mes
       and f.id_produto = k.id_produto
      left join devolucao_mensal d
        on d.mes = k.mes
       and d.id_produto = k.id_produto
     inner join produtos p
        on p.id_produto = k.id_produto
      left join dias_sem_estoque_mensal se
        on se.mes = k.mes
       and se.id_produto = k.id_produto
)

select * from final
