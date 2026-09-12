-- ─────────────────────────────────────────────────────────────────────────────
-- int_produto_alerta — as 14 colunas CHECK_* da aba `pedido` e a coluna D
-- (ALERTA), que as concatena. É a camada que transforma número em frase para
-- quem compra.
--
-- Gabarito: docs/gabarito_pedido_formulas.txt. Mapa coluna a coluna:
--   X  CHECK_FABRICA                IF($W2="","",IF($BA2>$W2, ...))
--   Y  CHECK_INATIVO                IF(AND($E2="Inativo",$BA2>0), ...)
--   AL CHECK_RUPTURA                IF($AK2>Parametros!$B$17, ...)
--   AO CHECK_ESTOQUE_PARADO         IF(AND($V2>0,$AN2<>"",$AN2>90), ...)
--   AP CHECK_FORA_DE_LINHA          fVendaMes!$Y = "S"  (insumo: MELHORIA A3)
--   AV CHECK_DEVOLUCAO_ALTA         IF($AU2>Parametros!$B$18, ...)
--   AY CHECK_LITRAGEM               IF(ISNA(MATCH($H2,dEmbalagem!$A:$A,0)), ...)
--   BS CHECK_IMPORTADO              já pronto em int_produto_fiscal - só passa
--   CC CHECK_TRIB                   código de tributação VAZIO **ou ZERO** — ver abaixo
--   CD CHECK_MVA                    só ST_SUBSTITUTO; MVA ou valor de entrada
--   CE CHECK_CUSTO                  custo contábil acima do valor da nota
--   CL CHECK_MARGEM_INSTAVEL        CHOOSE($P2, ...) + " (fora da curva A)"
--   DO CHECK_SUCESSAO               COUNTIF nas colunas de ANTECESSOR
--   DB CHECK_MARGEM_INSTAVEL_VAREJO CHOOSE($DQ2, ...) sobre o pior cenário CZ
--   D  ALERTA                       MID(concatenação com "; ", 3, 9999)
--
-- Grão: 1 linha por SKU. Espinha = int_produto_base (o cadastro inteiro).
--
-- ── ⚠ A ORDEM DE D É A DO EXCEL, NÃO A ALFABÉTICA NEM A DAS LETRAS ─────────
-- A fórmula de D lista os IF nesta sequência, e ela NÃO é a ordem das colunas
-- na aba:
--     X, Y, AL, AV, AO, AP, AY, BS, CC, CD, CE, CL, DO, DB
-- Repare em AV ANTES de AO/AP (devolução antes de estoque parado) e em DO
-- ANTES de DB (sucessão antes da margem de varejo) - as duas inversões são
-- deliberadas na planilha e as duas passariam despercebidas se alguém
-- reordenasse "para ficar igual às letras". ALERTA é comparado como TEXTO
-- contra a planilha: qualquer troca de ordem reprova a linha inteira, mesmo
-- com os 14 checks individualmente corretos. Conferido: a concatenação nesta
-- ordem reproduz as 8.772 células de D da aba, com UMA exceção deliberada -
-- os 5 SKUs de `cod_icms = 0`, que desde 21/08/2026 ganham 'TRIB NAO
-- ENCONTRADA' por decisão do Diretor de Compras (ver CC, abaixo, e
-- CONTEXTO.md §6.4). A ordem não mudou.
--
-- O separador é "; " e o MID(...,3,9999) descarta o primeiro - o Excel
-- concatena "; " antes de CADA alerta e depois corta os dois primeiros
-- caracteres. Aqui isso vira concatenação condicional + `substr(..., 3)`, que
-- é o MID literal: em Oracle, `||` com NULL devolve o outro lado, então o mesmo
-- efeito sai de concatenar só o que existe. A célula sem nenhum alerta fica
-- VAZIA (o MID de "" devolve ""; o substr de NULL devolve NULL, e o validador
-- trata "" e NULL como equivalentes), não "; " e não um espaço solto.
-- `substr` e não `ltrim`: ltrim removeria QUALQUER ';' ou ' ' inicial, e um
-- alerta que um dia comece com espaço sairia mutilado sem ninguém perceber.
--
-- ── AY | "sem CADASTRO", não "litragem zero" ───────────────────────────────
-- ISNA(MATCH($H2,dEmbalagem!$A:$A,0)) testa se a EMBALAGEM existe na tabela -
-- não se a litragem é zero. A diferença é medida e grande: 1.001 SKUs não têm
-- cadastro (alertam) e 161 TÊM cadastro com litragem 0 legítima (não alertam).
-- Um alerta escrito como `l_por_unidade = 0` disparia nos 1.162 e mandaria o
-- comprador cadastrar 161 embalagens que já estão cadastradas. Por isso
-- int_produto_base publica `embalagem_cadastrada` ('S'/'N'): a informação
-- "o MATCH achou" não sobrevive à conversão para litragem, e é ela que este
-- alerta precisa.
--
-- ── AO | o limiar sai do parâmetro ─────────────────────────────────────────
-- A planilha tem 90 CHUMBADO na fórmula. Aqui é DIAS_ESTOQUE_PARADO, do
-- int_parametro (mesmo valor - o aceite célula a célula continua fechando).
-- As três condições são cumulativas: tem estoque ($V2>0), tem data de última
-- saída ($AN2<>"") e ela é antiga. Sem a segunda, produto que NUNCA vendeu
-- (sem data) entraria no alerta de "parou de vender", que é outra coisa.
-- ⚠ $AN2 depende de TODAY(): este alerta muda de um dia para o outro sem que
-- nada mude no dado (CONTEXTO.md §6.1.1 - componente VOLÁTIL de ALERTA).
--
-- ── ⚠ AP | MELHORIA A3: os 71 SKUs que NÃO alertavam passam a alertar ──────
-- Registro: MELHORIAS.md item A3, aprovado em 21/08/2026; CONTEXTO.md §6.0.
-- Divergência DELIBERADA da planilha — não reverter para "fechar o validador".
--
-- O QUE A PLANILHA FAZ: FORA_DE_LINHA vem SÓ da linha do mês corrente do
-- fVendaMes, e produto fora de linha sem movimento no mês não tem linha nenhuma
-- ali; o IFERROR(...,"N") da fórmula de AP transforma essa ausência em "está em
-- linha". Medido: 71 SKUs com 'S' em mês fechado saíam 'N' e não alertavam —
-- justamente os produtos parados, que são os que mais interessam ao alerta.
--
-- O QUE PASSAMOS A FAZER: int_venda_mensal_pivot passou a derivar
-- FORA_DE_LINHA do registro MAIS RECENTE em que o SKU aparece (ver o cabeçalho
-- de lá para o porquê e para o limite conhecido). Aqui a fórmula de AP não
-- mudou uma letra: continua `fora_de_linha = 'S'`. O que mudou é o insumo.
-- Efeito medido: CHECK_FORA_DE_LINHA vai de 1 para 72 SKUs alertados.
--
-- O `nvl(..., 'N')` continua: SKU que não aparece em mês NENHUM segue 'N'.
-- Continua VOLÁTIL no sentido do §6.1.1 (o cadastro OBS2='FL' muda quando o
-- comprador mexe nele), mas deixou de virar com a virada do mês.
--
-- ── X e Y | dependem de PEDIDO, que é decisão humana ───────────────────────
-- Os dois só disparam com $BA2 preenchido, e BA vem de APP_DECISAO_PEDIDO
-- (hoje vazia). Saem 100% vazios, como na planilha - onde a coluna PEDIDO
-- também está zerada nas 8.772 linhas. Não é dado faltando (CONTEXTO.md
-- §6.1.1 - componentes DEPENDENTES DE DECISÃO HUMANA de ALERTA).
-- Em X, o `IF($W2="","",...)` é a porta: SKU sem estoque de fábrica não é
-- comparável, então não alerta - e não alertar é diferente de "estoque zero".
--
-- ── ⚠ CC | CHECK_TRIB deixou de ser FÓRMULA MORTA (divergência deliberada) ─
-- Decidido pelo Diretor de Compras em 21/08/2026 (PENDENCIAS_DIRETORIA.md
-- item 4; CONTEXTO.md §6.4).
--
-- Como era: `IF($BJ2="","TRIB NAO ENCONTRADA","")` testava se o código de
-- tributação está VAZIO. Ele nunca está - int_produto_fiscal aplica
-- `nvl(cod_tributacao, COD_TRIB_ICMS_PADRAO)`, como a planilha, e o padrão
-- sempre preenche. O alerta nunca disparava: 0 células de 8.772 na aba
-- `pedido`.
--
-- E havia um buraco real por baixo: os 5 SKUs de PCTABTRIB com `codst = 0`
-- (CONTEXTO.md §6.2) têm código PREENCHIDO (zero **não é** vazio, então não
-- caem no padrão) e inexistente no seed_icms. Saem sem MODALIDADE, sem
-- alíquota e com margem em branco - e saíam sem alerta nenhum, porque o teste
-- era "vazio", não "não encontrado".
--
-- Como é agora: o alerta dispara quando o código é VAZIO **ou ZERO**. Os 5
-- SKUs passam a ser sinalizados; a fórmula deixa de ser morta. O ramo "vazio"
-- continua escrito, mesmo continuando impossível hoje, porque ele é a regra
-- do gabarito - o que a decisão fez foi ACRESCENTAR o zero, não substituir.
-- ⚠ Diverge do xlsx em referencia/ DE PROPÓSITO: lá esses 5 SKUs saem com CC
-- vazio (e, por tabela, com ALERTA sem esse componente). Não reverter.
--
-- ── CD | o MVA só interessa a quem substitui ───────────────────────────────
-- Fora de ST_SUBSTITUTO não há MVA a cobrar, então não há o que alertar
-- (CONTEXTO.md: ICMS-ST só existe para MODALIDADE = 'ST_SUBSTITUTO'). O
-- `nvl(modalidade,'?')` importa: em Oracle, `null <> 'ST_SUBSTITUTO'` é NULL,
-- não TRUE, e sem o nvl os 5 SKUs sem modalidade cairiam nos ramos seguintes e
-- ganhariam "MVA PENDENTE" - alerta que a planilha não dá (no Excel,
-- ""<>"ST_SUBSTITUTO" é VERDADEIRO).
--
-- ── CE | o texto carrega a data, e o formato importa ───────────────────────
-- TEXT($Z2,"dd/mm/aa") -> 'dd/mm/yy'. Quando DT_ULT_ENT é vazia o Excel
-- concatena string vazia; em Oracle `'x' || null` = 'x', mesmo resultado.
-- A porta é `OR($BH2=0,$BI2=0,$BI2<=$BH2)`: sem nota, sem custo, ou custo
-- abaixo do valor da nota, não há nada de errado a apontar.
--
-- ── CL/DB | CHOOSE(NIVEL_MARGEM, ...) e o agravante da curva ───────────────
-- `nivel_margem` (P) e `nivel_margem_varejo` (DQ) já vêm prontos de
-- int_produto_margem, inclusive o degrau a mais que produto fora da curva A
-- leva. Aqui só se traduz 1/2/3 nos três textos do CHOOSE, cola-se o PIOR
-- cenário formatado e acrescenta-se " (fora da curva A)" quando a classe não é
-- 'A'. Repare que o sufixo é redundante com o agravamento de P - a planilha
-- mostra as duas coisas de propósito, para o comprador saber que o nível subiu
-- por causa da curva e não por causa da margem.
-- O pior cenário é MARGEM_SEM_RED (CJ) no atacado e MARGEM_SEM_RED_VAREJO (CZ)
-- no varejo: a alíquota CHEIA, sem redução de base. Usar a margem oficial aqui
-- mostraria um número melhor do que o pior caso, que é justamente o que o
-- alerta existe para mostrar.
-- ⚠ Sobre o formato do percentual: MELHORIA A4 (MELHORIAS.md; CONTEXTO.md
-- §6.0). A planilha imprime percentual INTEIRO com dois dígitos ("05%"),
-- porque o "0.0%" da fórmula é lido no locale pt-BR do arquivo, onde o "."
-- é separador de MILHAR. Nós passamos a imprimir uma casa decimal com
-- vírgula ("5,5%"), que é o que a máscara quis dizer — sem isso o alerta não
-- distingue 5,0% de 5,9%. Vale para AV, CL e DB, num lugar só:
-- macros/compras_texto_percentual.sql. Divergência DELIBERADA de 2.180
-- células de texto; não reverter.
--
-- ── DO | "este produto é ANTECESSOR de alguém" ─────────────────────────────
-- COUNTIF(dSucessao!$B$3:$B$300,$A2) + COUNTIF(dSucessao!$D$3:$D$300,$A2) > 0
-- procura o código nas colunas de ANTIGO_1 e ANTIGO_2 - ou seja, avisa que
-- ESTE SKU foi substituído por outro. É o oposto de DK/DM
-- (int_produto_sucessao), que dizem de quem ESTE SKU herdou. Confundir os dois
-- inverte o alerta e o comprador continuaria comprando o item descontinuado.
-- Duas sutilezas do COUNTIF, ambas reproduzidas: ele NÃO olha a coluna ATIVO
-- (linha desligada continua alertando - o vínculo existe mesmo sem herança de
-- venda) e conta OCORRÊNCIAS, mas só o >0 é usado, então o mesmo antecessor
-- reivindicado por vários sucessores (CONTEXTO.md §6.2 - o produto 7095 aparece
-- 4 vezes) gera UM alerta, não quatro. O `distinct` na CTE garante isso e
-- impede fan-out na junção.
-- Medido: 16 antecessores distintos no seed, 16 SKUs alertados na planilha.
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

fiscal as (
    select * from {{ ref('int_produto_fiscal') }}
),

margem as (
    select * from {{ ref('int_produto_margem') }}
),

pedido as (
    select * from {{ ref('int_produto_pedido') }}
),

venda as (
    select * from {{ ref('int_venda_mensal_sucessao') }}
),

sucessao as (
    select * from {{ ref('seed_sucessao') }}
),

parametro as (
    select * from {{ ref('int_parametro') }}
),

-- DO: o universo dos ANTECESSORES, os dois lados de uma vez. distinct porque
-- o mesmo antigo pode ser reivindicado por varios sucessores - ver cabecalho.
antecessor as (
    select distinct codigo_antecessor
      from (
            select ANTIGO_1 as codigo_antecessor from sucessao where ANTIGO_1 is not null
             union all
            select ANTIGO_2 as codigo_antecessor from sucessao where ANTIGO_2 is not null
           )
),

-- Uma linha por SKU com TODO insumo dos 14 checks ao lado, para que cada check
-- abaixo seja so' a traducao literal da sua formula.
insumo as (
    select
        b.codigo,
        b.status,
        b.embalagem_cadastrada,
        d.est_pend,
        d.est_fabrica,
        d.dias_sem_estoque,
        d.dias_sem_venda,
        d.tx_devolucao_3m,
        d.dt_ult_ent,
        a.classe,
        f.cod_icms,
        f.modalidade,
        f.mva,
        f.vl_ent_unit,
        f.custo_ult_ent,
        f.check_importado,
        m.nivel_margem,
        m.margem_sem_red,
        m.nivel_margem_varejo,
        m.margem_sem_red_varejo,
        pe.pedido,
        -- AP: MELHORIA A3 - o pivot ja entrega o valor do registro MAIS
        -- RECENTE do SKU, nao o do mes corrente. O nvl cobre o SKU que nao
        -- aparece em mes nenhum (segue 'N', como o IFERROR da formula).
        nvl(v.fora_de_linha, 'N')                          as fora_de_linha,
        case when an.codigo_antecessor is not null then 1 else 0 end as e_antecessor,
        p.dias_sem_estoque_alerta,
        p.tx_devolucao_alerta,
        p.dias_estoque_parado
      from base b
      join demanda    d  on d.codigo  = b.codigo
      join classe_abc a  on a.codigo  = b.codigo
      join fiscal     f  on f.codigo  = b.codigo
      join margem     m  on m.codigo  = b.codigo
      join pedido     pe on pe.codigo = b.codigo
     cross join parametro p
      left join venda v
        on v.codigo_produto = b.codigo
      left join antecessor an
        on an.codigo_antecessor = b.codigo
),

-- Os 14 checks, cada um literal em relacao a sua formula do gabarito.
avaliado as (
    select
        i.codigo,
        -- X: porta em $W2="" (sem estoque de fabrica nao ha comparacao)
        case when i.est_fabrica is not null and i.pedido > i.est_fabrica
             then 'PEDIDO ACIMA DO ESTOQUE DA FABRICA'
        end                                                as check_fabrica,
        -- Y
        case when i.status = 'Inativo' and i.pedido > 0
             then 'PRODUTO INATIVO NO CADASTRO'
        end                                                as check_inativo,
        -- AL: limiar do parametro (DIAS_SEM_ESTOQUE_ALERTA), nao 5 chumbado
        case when i.dias_sem_estoque > i.dias_sem_estoque_alerta
             then 'RUPTURA RECORRENTE - ' || to_char(i.dias_sem_estoque)
                  || ' DIAS SEM ESTOQUE'
        end                                                as check_ruptura,
        -- AO: limiar do parametro (DIAS_ESTOQUE_PARADO), nao 90 chumbado
        case when i.est_pend > 0
              and i.dias_sem_venda is not null
              and i.dias_sem_venda > i.dias_estoque_parado
             then 'SEM VENDA HA ' || to_char(i.dias_sem_venda)
                  || ' DIAS - ESTOQUE PARADO'
        end                                                as check_estoque_parado,
        -- AP
        case when i.fora_de_linha = 'S'
             then 'FORA DE LINHA - AVALIAR LIQUIDACAO'
        end                                                as check_fora_de_linha,
        -- AV: limiar do parametro (TX_DEVOLUCAO_ALERTA), nao 0,1 chumbado
        case when i.tx_devolucao_3m > i.tx_devolucao_alerta
             then 'DEVOLUCAO ACIMA DO PADRAO - '
                  || {{ compras_texto_percentual('i.tx_devolucao_3m') }}
        end                                                as check_devolucao_alta,
        -- AY: ISNA(MATCH(...)) - sem CADASTRO, nao litragem zero
        case when i.embalagem_cadastrada = 'N'
             then 'SEM CADASTRO NA dEmbalagem'
        end                                                as check_litragem,
        -- BS: pronto em int_produto_fiscal, so' viaja junto para D
        i.check_importado                                  as check_importado,
        -- CC: vazio OU zero. O ramo `is null` nunca e' verdadeiro hoje
        -- (nvl com COD_TRIB_ICMS_PADRAO sempre preenche) e fica escrito porque
        -- e' a regra do gabarito; o `= 0` e' a ampliacao decidida pelo Diretor
        -- em 21/08/2026, e e' ele que pega os 5 SKUs de codst = 0.
        case when i.cod_icms is null or i.cod_icms = 0
             then 'TRIB NAO ENCONTRADA'
        end                                                as check_trib,
        -- CD: o nvl e' obrigatorio - ver cabecalho
        case when nvl(i.modalidade, '?') <> 'ST_SUBSTITUTO' then null
             when i.mva is null            then 'MVA PENDENTE'
             when i.vl_ent_unit = 0        then 'SEM VALOR DE ENTRADA'
        end                                                as check_mva,
        -- CE
        case when i.vl_ent_unit = 0
               or i.custo_ult_ent = 0
               or i.custo_ult_ent <= i.vl_ent_unit
             then null
             else 'CUSTO ACIMA DA NOTA - ult.entrada '
                  || to_char(i.dt_ult_ent, 'dd/mm/yy')
        end                                                as check_custo,
        -- CL: CHOOSE(P) + pior cenario (CJ) + agravante de curva
        case when nvl(i.nivel_margem, 0) = 0 then null
             else case i.nivel_margem
                       when 1 then 'ALERTA DE MARGEM'
                       when 2 then 'MARGEM CRITICA'
                       when 3 then 'MARGEM MAXIMA'
                  end
                  || ' - pior cenario '
                  || {{ compras_texto_percentual('i.margem_sem_red') }}
                  || case when i.classe <> 'A' then ' (fora da curva A)' end
        end                                                as check_margem_instavel,
        -- DO: e' ANTECESSOR de alguem - ver cabecalho
        case when i.e_antecessor = 1
             then 'VERIFICAR SUCESSAO'
        end                                                as check_sucessao,
        -- DB: mesmo desenho de CL, sobre DQ e CZ
        case when nvl(i.nivel_margem_varejo, 0) = 0 then null
             else case i.nivel_margem_varejo
                       when 1 then 'ALERTA DE MARGEM'
                       when 2 then 'MARGEM CRITICA'
                       when 3 then 'MARGEM MAXIMA'
                  end
                  || ' - pior cenario varejo '
                  || {{ compras_texto_percentual('i.margem_sem_red_varejo') }}
                  || case when i.classe <> 'A' then ' (fora da curva A)' end
        end                                                as check_margem_instavel_varejo
      from insumo i
),

-- D: a concatenacao, NA ORDEM DO EXCEL - ver cabecalho.
final as (
    select
        a.codigo,
        a.check_fabrica,
        a.check_inativo,
        a.check_ruptura,
        a.check_estoque_parado,
        a.check_fora_de_linha,
        a.check_devolucao_alta,
        a.check_litragem,
        a.check_importado,
        a.check_trib,
        a.check_mva,
        a.check_custo,
        a.check_margem_instavel,
        a.check_sucessao,
        a.check_margem_instavel_varejo,
        substr(
            case when a.check_fabrica                is not null then '; ' || a.check_fabrica                end
         || case when a.check_inativo                is not null then '; ' || a.check_inativo                end
         || case when a.check_ruptura                is not null then '; ' || a.check_ruptura                end
         || case when a.check_devolucao_alta         is not null then '; ' || a.check_devolucao_alta         end
         || case when a.check_estoque_parado         is not null then '; ' || a.check_estoque_parado         end
         || case when a.check_fora_de_linha          is not null then '; ' || a.check_fora_de_linha          end
         || case when a.check_litragem               is not null then '; ' || a.check_litragem               end
         || case when a.check_importado              is not null then '; ' || a.check_importado              end
         || case when a.check_trib                   is not null then '; ' || a.check_trib                   end
         || case when a.check_mva                    is not null then '; ' || a.check_mva                    end
         || case when a.check_custo                  is not null then '; ' || a.check_custo                  end
         || case when a.check_margem_instavel        is not null then '; ' || a.check_margem_instavel        end
         || case when a.check_sucessao               is not null then '; ' || a.check_sucessao               end
         || case when a.check_margem_instavel_varejo is not null then '; ' || a.check_margem_instavel_varejo end
        , 3)                                               as alerta
      from avaliado a
)

select * from final
