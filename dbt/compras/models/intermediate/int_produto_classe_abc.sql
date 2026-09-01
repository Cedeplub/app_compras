-- ─────────────────────────────────────────────────────────────────────────────
-- int_produto_classe_abc — coluna AX (CLASSE) da aba `pedido`.
--
-- Gabarito, docs/gabarito_pedido_formulas.txt, coluna AX:
--   IF($AG2=0,"S/VEND",
--      IF($L2>0,
--         IF(IFERROR($AH2/SUMPRODUCT(($L$2:$L$8773>0)*$AH$2:$AH$8773),0)
--            > Parametros!$B$10,"A","B/C"),
--         IF(IFERROR(($AG2*$K2)/SUMPRODUCT(($L$2:$L$8773=0)*$AG$2:$AG$8773*$K$2:$K$8773),0)
--            > Parametros!$B$10,"A","B/C")))
--
-- ── DOIS universos, DOIS denominadores — CONTEXTO.md regra 5 ────────────────
-- Os dois SUMPRODUCT não são o mesmo total com filtro diferente: são grandezas
-- FISICAMENTE DIFERENTES, e é por isso que precisam de universos separados.
--   * quem tem litragem ($L2>0) é medido em LITROS vendidos por mês
--     ($AH2 = MEDIA_L), e o denominador soma MEDIA_L só das linhas com $L>0;
--   * quem não tem ($L2=0) é medido em UNIDADES vendidas por mês
--     ($AG2*$K2, a média já reconvertida de caixa para unidade), e o
--     denominador soma isso só das linhas com $L=0.
-- Somar litro com unidade num denominador único não significaria nada. Como
-- L_POR_UNIDADE nunca é negativo, ">0" e "=0" particionam o catálogo inteiro -
-- toda linha entra em exatamente um universo, e cada participação é relativa
-- ao total do SEU universo.
--
-- ── O total TEM que recalcular a cada build ─────────────────────────────────
-- CONTEXTO.md regra 5 e o PDF §12 registram que travar esse total em valor fixo
-- já foi bug REAL nesta planilha. Um SKU novo, um produto que parou de vender
-- ou um join de embalagem que mudou de universo alteram o denominador e,
-- portanto, a CLASSE de TODOS os SKUs - não só a do que mudou. Por isso o
-- denominador é `sum(...) over (partition by universo)`, avaliado sobre as
-- linhas do build corrente, e nunca uma constante nem uma tabela de apoio
-- materializada à parte. Depender de int_produto_base/int_produto_demanda por
-- ref() amarra isso no DAG: o total não tem como ficar velho.
--
-- ── Ordem dos testes: S/VEND ganha de tudo ──────────────────────────────────
-- MEDIA_JANELA = 0 devolve 'S/VEND' ANTES de qualquer conta de participação -
-- inclusive para o SKU com litragem cadastrada. Essas linhas continuam DENTRO
-- do denominador do seu universo (contribuindo 0), exatamente como o
-- SUMPRODUCT do Excel, que soma a faixa inteira. Excluí-las do denominador
-- daria participações maiores e classificaria SKU demais como 'A'.
--
-- ── O IFERROR(...,0) do meio ────────────────────────────────────────────────
-- Protege o caso "universo com total zero" (nenhum SKU do universo vendeu).
-- Participação vira 0, que nunca é > CORTE_ABC, então a linha sai 'B/C'. O
-- nvl(.../nullif(total,0), 0) reproduz isso.
--
-- CORTE_ABC (Parametros!$B$10) vem do int_parametro por cross join - nenhum
-- 0,0022 escrito dentro do SQL.
--
-- Grão: 1 linha por SKU. `universo`, `base_participacao`, `total_universo` e
-- `participacao` não são colunas da aba `pedido`: são a conta INTERMEDIÁRIA
-- exposta de propósito, para que a soma das participações dentro de cada
-- universo (tem que dar 1) seja verificável direto no banco, sem refazer a
-- consulta na mão. `tests/compras_classe_abc_participacao_soma_um.sql` cobra
-- isso a cada build.
-- ─────────────────────────────────────────────────────────────────────────────

with base as (
    select * from {{ ref('int_produto_base') }}
),

demanda as (
    select * from {{ ref('int_produto_demanda') }}
),

parametro as (
    select * from {{ ref('int_parametro') }}
),

-- A grandeza que cada universo mede, e em qual universo a linha cai.
universo as (
    select
        b.codigo,
        b.l_por_unidade,
        b.fator_exibicao,
        d.media_janela,
        d.media_l,
        case when b.l_por_unidade > 0
             then 'COM_LITRAGEM'
             else 'SEM_LITRAGEM'
        end                                       as universo,
        case when b.l_por_unidade > 0
             then d.media_l                       -- $AH2, em litros/mes
             else d.media_janela * b.fator_exibicao  -- $AG2*$K2, em unidades/mes
        end                                       as base_participacao
      from base b
      join demanda d
        on d.codigo = b.codigo
),

-- O denominador de cada universo, recalculado agora - nunca um valor fixo.
participacao as (
    select
        u.*,
        sum(u.base_participacao) over (partition by u.universo) as total_universo
      from universo u
),

final as (
    select
        p.codigo,
        p.universo,
        p.base_participacao,
        p.total_universo,
        nvl(p.base_participacao / nullif(p.total_universo, 0), 0) as participacao,
        case when p.media_janela = 0
             then 'S/VEND'
             when nvl(p.base_participacao / nullif(p.total_universo, 0), 0) > par.corte_abc
             then 'A'
             else 'B/C'
        end                                                      as classe
      from participacao p
     cross join parametro par
)

select * from final
