-- ─────────────────────────────────────────────────────────────────────────────
-- int_produto_alerta_extra — os DOIS alertas que NÃO existem na planilha.
--
-- Qual coluna Excel reproduz: NENHUMA, e isso é o ponto do model. Decisão do
-- Diretor de Compras de 02/09/2026 (v2/DECISOES_DIRETOR.md item 1): a taxonomia
-- da tela de Alertas ganha `OPORTUNIDADE_DE_GIRO` (peso 3) e `MARGEM_ALTA`
-- (peso 1), que a aba `pedido` não tem.
--
-- ── ⚠ POR QUE UM MODEL SEPARADO, E NÃO MAIS DOIS CHECK_* EM ────────────────
-- ── int_produto_alerta ─────────────────────────────────────────────────────
-- `int_produto_alerta` é o GABARITO contra a MODELO_COMPRAS_CEDEP_v11.xlsx: as
-- 14 colunas CHECK_* e a string `ALERTA` (coluna D) são comparadas TEXTO A
-- TEXTO pelo `validar/validar_pedido.py`, e `ALERTA` é coluna crítica
-- (CONTEXTO.md §6.1.1). Um 15º CHECK_* ali entraria na concatenação de D e
-- reprovaria toda linha em que disparasse — hoje 2.179 SKUs só em MARGEM_ALTA.
-- Nascer FORA daquele model é a garantia estrutural de que isso não acontece:
-- não há como esquecer de excluir da string uma coluna que a string não
-- enxerga.
--
-- ── E por que não dentro do próprio fat_alerta ─────────────────────────────
-- Porque fat_alerta é DESPIVOT: ele vira coluna em linha e não decide regra.
-- Toda regra de negócio deste projeto mora na camada intermediate, com os
-- limiares vindo de `int_parametro` por `cross join` — e é ali que um teste
-- singular consegue apontar para a regra sozinha, sem passar pelo formato.
-- Manter a fronteira também deixa a próxima regra nova com um lugar óbvio.
--
-- Grão: 1 linha por SKU. Espinha = int_produto_base, igual a int_produto_alerta,
-- para que o join em fat_alerta seja 1:1 e não possa causar fan-out.
--
-- ── OPORTUNIDADE_DE_GIRO | classe A com cobertura acima de 3 meses ─────────
-- "Produto que vende bem mas está com estoque parado demais, para disparar
-- promoção." São as duas condições:
--   classe = 'A'                        (curva boa — AX)
--   meses_est > OPORTUNIDADE_GIRO_MESES (cobertura acima de 90 dias — AW)
-- `meses_est` (AW) já É a cobertura em meses: EST+PEND ÷ MEDIA_JANELA. Os 90
-- dias do Diretor viram 3 MESES da janela do departamento, não 90 dias de
-- calendário — é a mesma unidade que o resto do modelo usa para cobertura
-- (SUG_COBERTURA, COBERTURA_ALVO), e misturar as duas faria a tela dizer um
-- número e o pedido calcular outro.
--
-- ⚠ `meses_est` é NULO quando MEDIA_JANELA = 0 (a fórmula AW é
-- IF($AG2=0,"",...)), e nulo nunca é > 3 — produto que não vende fica de fora,
-- que é o correto: sem venda não há "giro" a oportunizar, isso é SEM_GIRO.
--
-- ⚠ SÓ CLASSE 'A'. A curva deste modelo tem três valores — 'A', 'B/C' e
-- 'S/VEND' — e NÃO existe um 'B' isolado para incluir: B e C estão fundidos
-- desde a planilha. Medido em 02/09/2026: classe A com cobertura > 3 meses são
-- 24 SKUs; admitir 'B/C' levaria o alerta a 1.929, mais que IMPORTADO (2.266) e
-- MARGEM_INSTAVEL (1.630) juntos com o resto da lista. Um alerta que pega 22%
-- do catálogo não prioriza nada. Recomendação registrada ao Diretor: manter só
-- 'A'; se ele quiser abrir para B, o caminho é separar B de C na curva primeiro.
--
-- ── MARGEM_ALTA | o PIOR cenário acima do limiar ───────────────────────────
-- "Preço possivelmente desposicionado, represando venda." Dispara com
--   MARGEM_SEM_RED        (CJ) > MARGEM_ALTA_MIN         (20%)   OU
--   MARGEM_SEM_RED_VAREJO (CZ) > MARGEM_ALTA_MIN_VAREJO  (45%)
-- Os limiares são diferentes DE PROPÓSITO (decisão do Diretor): o varejo opera
-- com margem naturalmente mais alta, então 20% ali não seria notícia.
--
-- ⚠ A escolha da coluna de margem importa e é deliberada: CJ e CZ são o PIOR
-- cenário (alíquota CHEIA, sem redução de base) — exatamente as mesmas que
-- CHECK_MARGEM_INSTAVEL (CL) e CHECK_MARGEM_INSTAVEL_VAREJO (DB) usam. Usar
-- aqui a margem OFICIAL e lá a pior faria os dois alertas se contradizerem no
-- mesmo SKU e NO MESMO CANAL: "margem baixa" pelo pior cenário e "margem alta"
-- pelo oficial, na mesma linha da tela. Com as duas lendo CJ/CZ isso é
-- aritmeticamente impossível DENTRO de um canal, porque os limiares não se
-- cruzam (MARGEM_ALERTA_MIN = 12% < MARGEM_ALTA_MIN = 20%).
--
-- ⚠ ENTRE canais a contradição é aparente e LEGÍTIMA, e ela existe: medido em
-- 02/09/2026, 1 SKU (o 5934) sai com MARGEM_ALTA e MARGEM_BAIXA_VAREJO ao mesmo
-- tempo — 66,2% no atacado e −15,8% no varejo. Não é defeito: são dois preços
-- diferentes para o mesmo custo, e a mensagem para o comprador é exatamente
-- essa. Não "resolver" suprimindo um dos dois.
--
-- ⚠ Margem NULA não dispara: são os 5 SKUs de `codst = 0` (CONTEXTO.md §6.2),
-- que saem sem alíquota e com margem em branco. Em Oracle `null > 0.2` é NULL,
-- não TRUE — o `case when` já os deixa de fora sem precisar de cláusula, e o
-- alerta que eles merecem é o TRIB, que já dispara.
-- ─────────────────────────────────────────────────────────────────────────────

with base as (
    select * from {{ ref('int_produto_base') }}
),

demanda as (
    select * from {{ ref('int_produto_demanda') }}
),

classe_abc as (
    select * from {{ ref('int_produto_classe_abc') }}
),

margem as (
    select * from {{ ref('int_produto_margem') }}
),

parametro as (
    select * from {{ ref('int_parametro') }}
),

-- Uma linha por SKU com os insumos ao lado, no mesmo desenho de
-- int_produto_alerta, para que cada regra abaixo seja so' a propria regra.
insumo as (
    select
        b.codigo,
        a.classe,
        d.meses_est,
        m.margem_sem_red,
        m.margem_sem_red_varejo,
        p.oportunidade_giro_meses,
        p.margem_alta_min,
        p.margem_alta_min_varejo
      from base b
      join demanda    d on d.codigo = b.codigo
      join classe_abc a on a.codigo = b.codigo
      join margem     m on m.codigo = b.codigo
     cross join parametro p
),

final as (
    select
        i.codigo,
        -- cobertura em MESES da janela, nao em dias de calendario - ver cabecalho
        case when i.classe = 'A'
              and i.meses_est > i.oportunidade_giro_meses
             then 'CURVA A COM COBERTURA DE '
                  || to_char(round(i.meses_est, 1),
                             'FM9999990D0',
                             'NLS_NUMERIC_CHARACTERS='',.''')
                  || ' MESES - AVALIAR PROMOCAO'
        end                                                as check_oportunidade_giro,
        -- pior cenario nos dois canais (CJ e CZ), limiares diferentes de
        -- proposito - ver cabecalho
        case when i.margem_sem_red > i.margem_alta_min
             then 'MARGEM ALTA - pior cenario '
                  || {{ compras_texto_percentual('i.margem_sem_red') }}
                  || ' - AVALIAR PRECO'
             when i.margem_sem_red_varejo > i.margem_alta_min_varejo
             then 'MARGEM ALTA NO VAREJO - pior cenario '
                  || {{ compras_texto_percentual('i.margem_sem_red_varejo') }}
                  || ' - AVALIAR PRECO'
        end                                                as check_margem_alta
      from insumo i
)

select * from final
