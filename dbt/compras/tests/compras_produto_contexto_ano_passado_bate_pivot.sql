{{ config(severity = 'warn') }}

-- Aviso (severity warn, não error): VENDA_ANO_PASSADO tem de ser igual a
-- Q11 / FATOR_EXIBICAO de int_venda_mensal_sucessao, para todo SKU em que ela
-- não é nula.
--
-- ⚠ A DIVISÃO PELO FATOR faz parte do teste, e entrou em 02/09/2026 junto com
-- a correção do model. Q11 vem do pivot em UNIDADES; VENDA_ANO_PASSADO é a
-- quinta barra de um gráfico cujas outras quatro (VD_MES_ATUAL, VD_M_1/2/3)
-- saem de int_produto_demanda já divididas pelo fator — ou seja, em CAIXAS
-- para quem pede em caixa fechada. Comparar sem dividir aqui faria este teste
-- exigir do model exatamente a unidade errada.
--
-- Por que as duas coisas têm de bater hoje. O mês-alvo de VENDA_ANO_PASSADO é
-- add_months(max(mes), -12), e o offset do pivot é
-- months_between(max(mes), mes) - 1: o mesmo mês cai exatamente em Q11. As
-- duas leituras só podem divergir por duas causas — mês de referência
-- diferente ou herança de sucessão.
--
-- Falha que este teste previne, e por que ele NÃO se autodesliga como
-- compras_venda_mensal_sucessao_identico_sem_ativo: VD_MES_ATUAL (AC) e
-- VD_M_1/2/3 (AD/AE/AF) herdam histórico de antecessor via
-- int_venda_mensal_sucessao; VENDA_ANO_PASSADO lê só o próprio SKU. Enquanto
-- as 25 linhas de seed_sucessao estiverem com ATIVO='NAO' a herança é neutra
-- e as duas coincidem. No dia em que alguém ativar uma sucessão, elas
-- divergem — e aí a barra amarela do mini-gráfico (PROTOTIPO.md §2.10) deixa
-- de ser comparável com as quatro barras azuis ao lado dela, que herdaram.
-- Isso não é o comportamento correto passando a valer: é uma pergunta aberta
-- (VENDA_ANO_PASSADO deve herdar também?) que precisa ir ao Diretor de
-- Compras antes de virar número na tela. Por isso o teste continua medindo
-- depois da ativação, em vez de se calar — mas em `warn`, porque a resposta é
-- decisão de negócio e não pode travar o build de quem ativou a sucessão.
--
-- Só compara onde VENDA_ANO_PASSADO não é nula: nulo significa "sem evidência
-- de que o SKU existia no mês-alvo", e para esses o pivot nem tem linha (ou
-- teria 0 por nvl, que é justamente o valor que decidimos não afirmar).

with contexto as (
    select * from {{ ref('compras_produto_contexto') }}
),

sucessao as (
    select * from {{ ref('int_venda_mensal_sucessao') }}
),

-- FATOR_EXIBICAO sai de fat_pedido, a mesma fonte que int_produto_demanda usa
-- para dividir as outras quatro barras.
fator as (
    select codigo, fator_exibicao from {{ ref('fat_pedido') }}
)

select
    c.CODIGO,
    c.VENDA_ANO_PASSADO,
    s.q11,
    f.fator_exibicao,
    s.q11 / nullif(f.fator_exibicao, 0) as esperado
  from contexto c
  join sucessao s
    on s.codigo_produto = c.CODIGO
  join fator f
    on f.codigo = c.CODIGO
 where c.VENDA_ANO_PASSADO is not null
   and abs(c.VENDA_ANO_PASSADO - s.q11 / nullif(f.fator_exibicao, 0)) > 0.0001
