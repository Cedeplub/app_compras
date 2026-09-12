-- ─────────────────────────────────────────────────────────────────────────────
-- int_produto_pedido — colunas BA a BG da aba `pedido`.
-- A quantidade que o comprador decidiu pedir e tudo que se calcula a partir dela.
--
-- Gabarito: docs/gabarito_pedido_formulas.txt. Mapa coluna a coluna:
--   BA PEDIDO           DIGITADA - sem fórmula. Vem de APP_DECISAO_PEDIDO.
--   BB PEDIDO_UNIDADES  $BA2 * $K2   (⚠ MELHORIA A5: fator CONGELADO
--                       da decisao quando ela existe - ver secao propria)
--   BC PEDIDO_NA_MEDIDA IF(MEDIDA_PEDIDO="LITROS",$BB2*$L2,
--                          IF(=" PESO",$BB2*$M2, IFERROR($BB2/$J2,0)))
--   BD VALOR_PEDIDO     IF($BW2="","",$BB2*$BW2)
--   BE SUG_PALETE       texto, só classe A - ver seção própria
--   BF MESES_EST+PED    IF($AG2=0,"",($V2+$BB2)/$AG2)
--   BG VALOR_ESTOQUE    IF($BW2="","",$V2*$K2*$BW2)
--
-- Grão: 1 linha por SKU. Espinha = int_produto_base (o cadastro inteiro).
--
-- ── ⚠ BA | PEDIDO é DECISÃO HUMANA, como ALT_PV_* ──────────────────────────
-- CONTEXTO.md regra 10 e §2. É uma das cinco colunas digitadas da planilha
-- inteira, e a única do bloco de compra. Vem de APP_DECISAO_PEDIDO por LEFT
-- JOIN. Diferença deliberada em relação a ALT_PV_*: aqui a ausência de decisão
-- vale ZERO, não nulo, porque a planilha traz a coluna zerada (medido: 8.772
-- de 8.772 linhas com PEDIDO = 0) e porque BB/BC/BF a usam em aritmética -
-- nulo apagaria MESES_EST+PED de todo SKU sem decisão. "Não pedi nada" e
-- "pedi zero" são a mesma coisa para esta coluna; para o preço final não são,
-- e por isso lá o nulo é preservado.
--
-- Consequência prática, igual à de ALT_PV_*: pedido gravado no dashboard só
-- aparece aqui depois do próximo `dbt run`.
--
-- ── ⚠ MELHORIA A5 (24/08/2026) | BB usa o FATOR CONGELADO na decisão ───────
-- DIVERGÊNCIA DELIBERADA da planilha. Decidida pelo Diretor de Compras em
-- 24/08/2026 (PENDENCIAS_DIRETORIA.md item 5; MELHORIAS.md A5; CONTEXTO.md
-- §6.0). Registro do que era: até 24/08/2026 este model reproduzia `$BA2*$K2`
-- com o fator CORRENTE, e a divergência entre os dois fatores ficava anotada
-- aqui como "reproduza, não julgue".
--
-- O que a planilha faz: `BB = $BA2 * $K2`, com K recalculado a cada abertura.
-- O que passamos a fazer: quando EXISTE decisão gravada, BB usa o
-- FATOR_EXIBICAO que APP_DECISAO_PEDIDO congelou no instante da decisão (a
-- tabela foi desenhada assim na Etapa 0 - ver sql/02_tabelas_app.sql, item 3,
-- justamente prevendo isto). Quando NÃO existe decisão, não há fator congelado
-- e vale o corrente da linha (K) - é o caso de 100% dos SKUs hoje, e é o que
-- mantém o modelo idêntico ao gabarito enquanto ninguém decidiu nada.
--
-- POR QUE (palavras do Diretor, item 5 das pendências): o que importa para o
-- negócio é sempre a conta EM UNIDADES - caixa é só a forma de digitar quando
-- o fornecedor está em MASTER. O EMBAL_COMPRA muda na ATUALIZAÇÃO DIÁRIA de
-- cadastro, não só numa reconfiguração manual de fornecedor. Recalcular faria
-- a quantidade de unidades - e o valor gasto - mudarem sozinhas, sem ninguém
-- ter redigitado nada. Se a embalagem mudou de verdade, o certo é gerar uma
-- decisão NOVA vendo o número atualizado, não reinterpretar a antiga.
--
-- Propaga para tudo que descende de BB: BC, BD, BE e BF. NÃO propaga para BG
-- (VALOR_ESTOQUE), que é estoque e não pedido - ali o fator corrente continua
-- certo, porque EST+PEND é lido do cadastro de hoje, não de uma decisão.
--
-- Referência visual em CAIXAS: não foi criada coluna nova, porque ela já
-- existe - BA (`pedido`) É a quantidade como a pessoa digitou, na unidade de
-- exibição do instante da decisão. Uma segunda coluna "em caixas" seria a
-- mesma informação com outro nome, e nome duplicado é onde o recálculo volta
-- por descuido.
--
-- Impacto medido em 24/08/2026: 0 SKUs (APP_DECISAO_PEDIDO vazia). A regra foi
-- exercitada de ponta a ponta com decisões de teste gravadas e apagadas - ver
-- MELHORIAS.md A5 - e é protegida pelo teste singular
-- `compras_pedido_unidades_usa_fator_congelado`.
--
-- ── BC | a unidade do pedido sai de PARÂMETRO, não de constante ────────────
-- MEDIDA_PEDIDO (Parametros!$B$19) escolhe entre LITROS, PESO e qualquer outro
-- valor, que cai no ramo "unidade master" ($BB2/$J2). O `else` é o terceiro
-- ramo do IF aninhado, não um fallback de segurança - é assim que a planilha
-- trata 'UNIDADE_MASTER'. O IFERROR do último ramo cobre EMBAL_COMPRA = 0
-- (divisão por zero): devolve 0, não erro. Como int_produto_base já aplica
-- `nvl(embal_compra, 1)`, o zero só chega aqui se estiver zerado na origem -
-- o `nullif` mantém a proteção mesmo assim, porque é o que o gabarito manda.
--
-- ── BD/BG | o "" que vem de BW ─────────────────────────────────────────────
-- As duas colunas de valor são apagadas quando CUSTO_TOT_OFICIAL é vazio -
-- os 5 SKUs de PCTABTRIB com codst = 0, sem correspondência no seed_icms
-- (CONTEXTO.md §6.2). Sem custo oficial não existe valor de pedido nem valor
-- de estoque, e a planilha prefere a célula vazia a um zero que pareceria
-- informação. Note que BG multiplica $V2 DE VOLTA por $K2: EST+PEND está em
-- unidade de exibição e o custo é unitário, então o fator tem de sair antes da
-- multiplicação (CONTEXTO.md regra 6).
--
-- ── BE | SUG_PALETE: três portas antes da conta ────────────────────────────
-- Só sugere completar palete quando o SKU é classe A, tem palete cadastrado e
-- há pedido - `IF(OR($AX2<>"A",$N2=0,$BB2=0),"",...)`. Depois disso mede a
-- SOBRA da última camada: MOD(caixas, QT_PALETE) / QT_PALETE. Se a sobra já
-- passou de PALETE_LIMIAR (0,7, do int_parametro - nunca chumbado), arredondar
-- para cima custa pouco e o alerta sugere as caixas que faltam.
-- MOD do Excel e MOD do Oracle divergem no sinal quando os operandos têm
-- sinais opostos; aqui as duas parcelas são não negativas (caixas ≥ 0 e
-- QT_PALETE > 0, garantido pelas portas), então os dois coincidem.
-- Medido: a coluna sai 100% vazia na planilha, porque BB = 0 em todas as
-- linhas - a terceira porta fecha antes de qualquer conta.
-- ─────────────────────────────────────────────────────────────────────────────

with base as (
    select * from {{ ref('int_produto_base') }}
),

classe_abc as (
    select * from {{ ref('int_produto_classe_abc') }}
),

demanda as (
    select * from {{ ref('int_produto_demanda') }}
),

custo as (
    select * from {{ ref('int_produto_custo') }}
),

decisao as (
    select * from {{ ref('stg_decisao_pedido') }}
),

parametro as (
    select * from {{ ref('int_parametro') }}
),

-- BA e BB: a decisao humana e a conversao para unidades.
quantidade as (
    select
        b.codigo,
        b.embal_compra,
        b.fator_exibicao,
        b.l_por_unidade,
        b.peso_unitario_kg,
        b.qt_palete,
        a.classe,
        d.est_pend,
        d.media_janela,
        c.custo_tot_oficial,
        p.medida_pedido,
        p.palete_limiar,
        -- BA: sem linha em APP_DECISAO_PEDIDO = nao ha pedido = zero
        nvl(dp.pedido, 0)                                  as pedido,
        -- MELHORIA A5: o fator que vale para ESTA decisao. Com decisao gravada,
        -- o CONGELADO manda; sem decisao nao existe congelado e vale o corrente
        -- (K). O teste e' `dp.id_produto is not null`, e nao um nvl sobre o
        -- fator: se um dia a coluna admitir nulo, um nvl cairia calado no
        -- corrente e desfaria a decisao do Diretor sem ninguem perceber.
        case when dp.id_produto is not null
             then dp.fator_exibicao
             else b.fator_exibicao
        end                                                as fator_exibicao_pedido,
        -- BB: $BA2 * fator da decisao (congelado quando ha decisao - cabecalho)
        nvl(dp.pedido, 0)
            * case when dp.id_produto is not null
                   then dp.fator_exibicao
                   else b.fator_exibicao
              end                                          as pedido_unidades
      from base b
      join classe_abc a on a.codigo = b.codigo
      join demanda    d on d.codigo = b.codigo
      join custo      c on c.codigo = b.codigo
     cross join parametro p
      left join decisao dp
        on dp.id_produto = b.codigo
),

final as (
    select
        q.codigo,
        q.pedido,
        -- Sem letra no Excel: o fator que ESTA linha usou em BB. Congelado
        -- quando ha decisao, corrente quando nao ha (MELHORIA A5). Fica
        -- exposto para que a divergencia contra K seja auditavel sem abrir a
        -- APP_*, e para o teste singular poder afirmar a regra.
        q.fator_exibicao_pedido,
        q.pedido_unidades,
        -- BC: a unidade em que o pedido e' expresso, escolhida no parametro
        case when q.medida_pedido = 'LITROS'
             then q.pedido_unidades * q.l_por_unidade
             when q.medida_pedido = 'PESO'
             then q.pedido_unidades * q.peso_unitario_kg
             -- IFERROR(...,0): embal_compra zerado nao explode, devolve 0
             else nvl(q.pedido_unidades / nullif(q.embal_compra, 0), 0)
        end                                                as pedido_na_medida,
        -- BD: IF($BW2="","",$BB2*$BW2)
        q.pedido_unidades * q.custo_tot_oficial            as valor_pedido,
        -- BE: tres portas, depois a sobra da ultima camada do palete
        case when q.classe <> 'A' or q.qt_palete = 0 or q.pedido_unidades = 0
             then null
             when mod(q.pedido_unidades / nullif(q.embal_compra, 0), q.qt_palete)
                  / q.qt_palete >= q.palete_limiar
             then 'COMPLETAR PALETE: +'
                  || to_char(round(q.qt_palete
                       - mod(q.pedido_unidades / nullif(q.embal_compra, 0), q.qt_palete)))
                  || ' CAIXAS'
        end                                                as sug_palete,
        -- BF: IF($AG2=0,"",($V2+$BB2)/$AG2)
        case when q.media_janela <> 0
             then (q.est_pend + q.pedido_unidades) / q.media_janela
        end                                                as meses_est_ped,
        -- BG: $V2 * $K2 * $BW2 - desfaz o FATOR_EXIBICAO antes do custo unitario
        q.est_pend * q.fator_exibicao * q.custo_tot_oficial as valor_estoque
      from quantidade q
)

select * from final
