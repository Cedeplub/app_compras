-- ─────────────────────────────────────────────────────────────────────────────
-- int_produto_sucessao — colunas DK a DN da aba `pedido`.
-- Quem este SKU sucede, e com que peso.
--
-- Gabarito: docs/gabarito_pedido_formulas.txt. Mapa coluna a coluna:
--   DK ANT_1   IF(dSucessao!$F <> "SIM", 0, dSucessao!$B) — antecessor 1
--   DL PESO_1  IF($DK2 = 0, 0, dSucessao!$C)
--   DM ANT_2   IF(dSucessao!$F <> "SIM", 0, dSucessao!$D) — antecessor 2
--   DN PESO_2  IF($DM2 = 0, 0, dSucessao!$E)
--
-- Grão: 1 linha por SKU. Espinha = int_produto_base (o cadastro inteiro), com
-- left join no seed: SKU fora do dSucessao devolve #N/A no MATCH, o IFERROR
-- externo devolve 0, e é isso que o `nvl(..., 0)` reproduz.
--
-- ── Por que estas quatro colunas existem separadas da herança de venda ──────
-- A herança propriamente dita (somar a venda do antecessor à do sucessor) já
-- acontece a montante, em int_venda_mensal_sucessao, que lê o MESMO seed com a
-- MESMA regra de ATIVO. Estas quatro colunas são a EXIBIÇÃO desse vínculo na
-- aba `pedido`: o comprador precisa ver de quem o número herdou antes de
-- confiar nele. São dados derivados do mesmo seed, nunca uma segunda fonte de
-- verdade — se as duas divergirem, uma das duas está lendo o seed errado.
--
-- ── ⚠ A trava é ATIVO, e ela vale para os DOIS antecessores de uma vez ──────
-- A coluna $F (ATIVO) é lida uma única vez na fórmula de DK e outra na de DM,
-- sempre da MESMA linha do dSucessao. Não existe "antecessor 1 ativo e
-- antecessor 2 desativado": ou a linha inteira vale, ou nenhum dos dois vale.
-- Reproduzir isso com dois `case` independentes daria o mesmo resultado hoje e
-- divergiria no dia em que alguém quisesse desativar só um lado — por isso o
-- `case` é UM só, sobre ATIVO, e os quatro valores saem de dentro dele.
--
-- Medido no seed de hoje: as 25 linhas têm ATIVO = 'NAO'. Logo DK..DN saem
-- ZERADAS nos 8.776 SKUs, exatamente como na planilha (conferido: 8.772 linhas
-- da aba `pedido` com (0,0,0,0)). Isso NÃO é dado faltando — é a sucessão
-- desligada, esperando decisão de quem compra. Ligar uma linha muda a demanda
-- do sucessor e, por consequência, a curva ABC de todo o catálogo
-- (CONTEXTO.md regra 5).
--
-- ── PESO só existe se o antecessor existir ──────────────────────────────────
-- DL/DN testam DK/DM antes de ler o peso. Sem isso, uma linha com peso
-- preenchido e antecessor vazio multiplicaria a venda de "produto nenhum" —
-- inofensivo na aritmética, mas mostraria ao comprador um peso que não se
-- aplica a nada.
-- ─────────────────────────────────────────────────────────────────────────────

with base as (
    select * from {{ ref('int_produto_base') }}
),

sucessao as (
    select * from {{ ref('seed_sucessao') }}
),

-- A trava de ATIVO, aplicada uma vez para a linha inteira - ver cabecalho.
regra as (
    select
        CODIGO_NOVO                                        as codigo,
        case when ATIVO = 'SIM' then nvl(ANTIGO_1, 0) else 0 end as ant_1,
        case when ATIVO = 'SIM' then nvl(ANTIGO_2, 0) else 0 end as ant_2,
        case when ATIVO = 'SIM' then nvl(PESO_1, 0)   else 0 end as peso_1_bruto,
        case when ATIVO = 'SIM' then nvl(PESO_2, 0)   else 0 end as peso_2_bruto
      from sucessao
),

final as (
    select
        b.codigo,
        -- DK/DM: IFERROR(...,0) - SKU fora do seed vale zero, nao nulo
        nvl(r.ant_1, 0)                                    as ant_1,
        -- DL: IF($DK2=0,0,...) - peso so' vale com antecessor
        case when nvl(r.ant_1, 0) = 0 then 0 else r.peso_1_bruto end as peso_1,
        nvl(r.ant_2, 0)                                    as ant_2,
        -- DN: IF($DM2=0,0,...)
        case when nvl(r.ant_2, 0) = 0 then 0 else r.peso_2_bruto end as peso_2
      from base b
      left join regra r
        on r.codigo = b.codigo
)

select * from final
