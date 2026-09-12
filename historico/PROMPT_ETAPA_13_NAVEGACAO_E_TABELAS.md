# Etapa 13 — Navegação, tabelas ordenáveis e o gráfico do produto

> **Prompt de execução.** Origem: mensagem do Diretor de Compras por WhatsApp em
> 11/09/2026, com print da tela de Decisão do SKU (produto 7066, TEXACO GRAXA MARFAK MP2).
> Seis pontos, todos de interface — **nenhum muda número, nenhum toca regra fiscal.**
>
> Base: a Etapa 12 já está no ar (commits `0df396e` e `b735f1c`). Este prompt parte do
> código como ele está hoje, não do protótipo.

---

## 1. Os seis pontos, verbatim

1. *"Quando abre a pagina do produto, o gráfico de vendas tem que mostrar em
   faturamento/quantidade/peso e litros como na página de monitoramento"*
2. *"clicar em Cedep deve ir para o painel"*
3. *"as páginas (painel, pedidos, precificação, etc) quando na visualizçaão de desktop,
   deve aparecer ao longo da barra superior para faciliar o acesso"*
4. *"Onde há tabela, deve ser possível reordenar clicando na coluna, Em crescente e
   decrescente, como o padrão em algumas aplicações/relatórios"*
5. *"O usuário deve poder abrir em abas diferentes (para que, por exemplo, abra um produto
   para visualizar informações, sem sair da pagina de pedidos que está sendo criado)"*
6. *"remover os nomes Cassio e Gabriela de onde aparece no sistema, pois são funcionários e
   podem ser substituídos ou a função passar para outras pessoas"*

Os pontos 2 e 6 são de minutos. O 5 é de uma hora e **revela um defeito maior que o
pedido** (§6). O 1 e o 4 são os de verdade, e cada um tem uma armadilha medida no banco.

---

## 2. Ponto 1 — o gráfico do produto com as quatro métricas

### 2.1 O dado já existe, com índice feito para isso

`COMPRAS_MONITORAMENTO` tem grão **DIA × PRODUTO** e carrega as quatro métricas:
`QUANTIDADE_LIQUIDA`, `VALOR_LIQUIDO`, `PESO_LIQUIDO_KG`, `LITROS_LIQUIDO`. E já tem
índice em `CODIGO_PRODUTO` (`compras_monitoramento.sql`, `post_hook`). **Zero trabalho de
dbt nesta etapa.**

A janela da tabela é de 400 dias — medido em 11/09/2026: de **08/08/2025 a 11/09/2026**,
337.540 linhas. O gráfico precisa de 4 meses + o mesmo mês do ano anterior, ou seja desde
01/09/2025: **cabe, com 24 dias de folga.** A folga não encolhe com o tempo (as duas
pontas andam juntas), mas é fina — se algum dia o Diretor pedir mais histórico no gráfico,
o limite é a var `compras_monitoramento_dias_historico`, não a tela.

### 2.2 ⚠ A armadilha: `FATOR_EXIBICAO`. Medida, não suposta.

O gráfico hoje vem de `vendaHistorico` (`VD_MES_ATUAL`, `VD_M_1..3` de `COMPRAS_PEDIDO`).
Trocar a fonte para `COMPRAS_MONITORAMENTO` **sem dividir pelo fator multiplica a
quantidade por 12 ou por 24 em 324 SKUs ativos.** Comparei as duas fontes para o mês
fechado anterior, nos 8.841 SKUs:

| Medida | Número |
|---|---|
| SKUs comparados | 8.841 |
| Divergentes | **230** |
| Maior diferença | **45.655,96 unidades** |
| Divergentes com sucessão | **0** (não é sucessão) |
| Casos em que o monitoramento é o maior | **230 de 230** |

E a causa é exata:

| SKU | `FATOR_EXIBICAO` | `VD_M_1` | Monitoramento | `VD_M_1 × fator` |
|---|---|---|---|---|
| 7305 | 24 | 1.985,0417 | 47.641 | **47.641** |
| 7279 | 24 | 1.829,8333 | 43.916 | **43.916** |
| 3827 | 12 | 1.596,1667 | 19.154 | **19.154** |
| 6771 | 12 | 1.240,0833 | 14.881 | **14.881** |
| 7066 (o do print) | 1 | 2.534 | 2.534 | 2.534 |

**As duas fontes concordam perfeitamente — estão em unidades diferentes.** `VD_M_*` está em
unidade de **exibição** (caixa, quando o fornecedor é MASTER); `COMPRAS_MONITORAMENTO` está
em unidade **real**. É a regra 6 do `CONTEXTO.md`, e é por isso que o 7066 do print não
mostra problema: o fator dele é 1.

**Portanto:**

- **Quantidade do gráfico = `sum(QUANTIDADE_LIQUIDA) / FATOR_EXIBICAO`**, porque a tela
  inteira do produto fala em unidade de exibição — "Estoque disponível 680", "Média mensal
  866", "Cobertura 0,79 m" e a sugestão de compra, todos. Um gráfico 24× maior logo abaixo
  de "Média mensal 866" não seria um número errado: seria uma tela que se contradiz de
  forma plausível, que é pior.
- **Faturamento, peso e litros NÃO são divididos.** São medidas absolutas (R$, kg, L), não
  contagem de embalagem. A regra 6 diz "quase toda quantidade" — o "quase" é aqui.

### 2.3 A barra do ano anterior, e o zero que não é nulo

`vendaAnoPassado` vem de `COMPRAS_PRODUTO_CONTEXTO` e distingue **zero** ("estava vivo e
não vendeu" → barra rente ao chão) de **nulo** ("não há evidência de que existisse" →
nenhuma barra). O monitoramento não sabe fazer essa distinção: ausência de linha é ausência
de linha.

**Regra:** o campo `vendaAnoPassado` continua sendo quem decide **se a barra amarela
existe**; os **valores** das quatro métricas vêm do monitoramento. Uma linha de código,
e a semântica que já estava certa não se perde.

### 2.4 Litros é zero de verdade em 436 produtos ativos

Medido: dos 4.558 ativos, **436 não têm litragem** (`L_POR_UNIDADE` nulo ou zero) e apenas
**2 não têm peso**. O 7066 do print é um deles — graxa de 500 GR, peso sim, litros não.

Então a métrica "Litros" vai render cinco barras zeradas em ~10% dos produtos. A tela
**não** desenha isso: quando o produto não tem litragem cadastrada, o botão da métrica fica
desabilitado com a dica *"este produto não tem litragem cadastrada"*. Gráfico rente ao
chão parece defeito; campo desabilitado com motivo é informação.

### 2.5 Onde o dado entra

Estenda **`/api/produtos/{codigo}`** (`app/servicos/produto.py`, `obter_produto`) para
trazer as quatro métricas dos cinco períodos de uma vez — 20 números, uma consulta na
coluna indexada. **Não** crie endpoint por métrica: trocar a métrica é um toque, e um
toque não deve ir ao servidor. É o mesmo raciocínio que já mantém a simulação de margem no
cliente.

No contrato (`app/api/contrato.py`), `vendaHistorico` deixa de ser uma lista de números e
passa a ser uma lista por métrica — `{quantidade: [...], faturamento: [...], peso: [...],
litros: [...]}`, mantendo a ordem `[Atual, M-1, M-2, M-3]` que o resto do código já
assume, mais `anoAnterior` no mesmo formato. **Quem consome `vendaHistorico` hoje:**
`web/src/telas/DecisaoSKU.jsx:210`. É o único lugar — confira com `grep` antes de mudar a
forma, e não deixe a lista antiga e a nova convivendo.

---

## 3. Ponto 4 — tabelas ordenáveis por clique na coluna

### 3.1 A regra que não pode ser quebrada: ordenação de lista paginada é do servidor

A Precificação lista **4.558 produtos em páginas de 50**. Ordenar no cliente ordenaria
**os 50 da página** — o defeito clássico, que parece funcionar e mente: o produto de pior
margem do catálogo continua na página 7 enquanto a coluna diz "ordenado por margem".

Então:

| Tabela | Paginada? | Onde ordena |
|---|---|---|
| Precificação, Pedidos, Alertas (`/api/produtos`) | sim | **servidor** |
| Preços Definidos, Pedidos Salvos (as listas) | sim | **servidor** |
| Itens de um pedido / de um lote (o detalhe) | não | cliente, e é barato |
| Monitoramento (por dimensão / por produto) | não (teto de 50) | cliente |
| Entradas | não (teto de 200) | cliente |

**Coluna que não tem como ser ordenada no servidor não vira clicável.** Melhor uma coluna
que não ordena do que uma que ordena errado.

### 3.2 O `ORDENACOES` precisa passar a ter direção

Hoje, em `app/servicos/produto.py:102`, cada entrada do dicionário traz a direção
**cravada** — `"cobertura": "p.meses_est asc nulls last, p.codigo"`. Para o clique
alternar crescente/decrescente, a direção tem de sair do texto e virar parâmetro.

⚠ **`nulls last` acompanha a direção, sempre.** No Oracle o padrão é `nulls last` em `asc`
e `nulls first` em `desc` — trocar a direção sem escrever `nulls last` explicitamente faz
o produto sem número calculado **encabeçar** a lista. O comentário que já está lá ("produto
sem o número calculado não pode encabeçar uma lista ordenada por ele") vale nas duas
direções.

Proposta de forma: cada entrada guarda **expressão** e **direção padrão** em separado, e
`_ordem(ordenacao, cenario_margem, direcao)` monta `"<expressão> <direção> nulls last,
p.codigo"`. O desempate por `p.codigo` fica, sempre — sem ele, duas páginas da mesma
consulta podem repetir ou omitir uma linha (o Oracle não garante ordem estável em
`order by` empatado com paginação).

As ordenações que dependem do cenário fiscal (`margem` e `mkp`) continuam resolvendo a
coluna por `contrato.COLUNA_MARGEM` — **não duplique essa tabela**, é a mesma que a tela usa
para exibir.

### 3.3 O seletor de ordenação atual **não** morre

`SeletorOrdenacao` guarda ordens que **não são coluna nenhuma** — a principal é
`prioridade` (severidade máxima → curva ABC → soma, a decisão do Diretor de 02/09 que
levou os 7 classe A em ruptura para as posições 1 a 7). Isso não é cabeçalho clicável.

Regra: **o que é coluna, clica na coluna; o que é ordem composta, fica no seletor**, e os
dois escrevem no mesmo estado — clicar numa coluna atualiza o seletor, e escolher no
seletor tira a seta da coluna. Dois controles que mostram o mesmo estado, não dois estados.

### 3.4 O componente, e o que ele precisa ter

Um só, novo: **`web/src/componentes/CabecalhoOrdenavel.jsx`** — usado por todas as tabelas.

- Primeiro clique aplica a **direção padrão daquela coluna** (margem abre em "pior
  primeiro"; valor de estoque abre em "maior primeiro"; código abre crescente). Segundo
  clique inverte. Não existe terceiro clique que desliga: a lista está sempre ordenada por
  algo.
- Seta visível só na coluna ativa (▲/▼), e **`aria-sort="ascending" | "descending"`** no
  `<th>` — é o atributo que faz a tabela ser navegável por teclado e por leitor de tela.
- O `<th>` inteiro é o alvo do clique (`<button>` ocupando a célula), não um ícone de 8px.
- Em lista paginada, trocar a ordenação **volta para a página 1**. Manter a página 12 com
  outra ordenação mostra um pedaço arbitrário do meio do novo resultado.
- A ordenação **entra na URL** (`?ordenar=margem&dir=desc`), pelo mesmo motivo do ponto 5:
  ordenou, achou, manda o link.

---

## 4. Ponto 3 — as áreas na barra superior, no desktop

Hoje as cinco áreas (`AREAS`, em `web/src/componentes/Cabecalho.jsx:21`) só existem dentro
do menu ☰ (`MenuArea`, linha 304) — dois cliques para trocar de área, em qualquer largura.
No desktop elas passam a aparecer na barra.

⚠ **A navegação tem dois níveis, e achatá-los já foi tentado e deu errado.** O comentário
no topo do `Cabecalho.jsx` registra: *"A primeira versão desta tela achatou os dois níveis
numa fileira de seis abas, o que fazia 'Alertas' e 'Pedidos' parecerem irmãos quando um é
aba do Painel do Dia e o outro é uma área inteira."* Com as áreas na barra, o desktop passa
a ter **duas fileiras** de navegação — áreas em cima, abas do Painel embaixo (`BarraAbas`,
que só existe dentro do Painel). Elas precisam ser **visivelmente de níveis diferentes**:
as áreas na faixa navy do cabeçalho, as abas na faixa branca abaixo, como já são. Não
unifique o estilo das duas.

- Ponto de corte: inline a partir de **`lg:` (1024px)**; abaixo disso, o ☰ continua. São
  cinco rótulos ("Painel · Pedidos · Pedidos Salvos · Precificação · Preços Definidos") e
  em 768px eles não caem bem — e a Etapa 12 acabou de acrescentar o quinto.
- O ☰ **não desaparece** no desktop: ele é quem mostra o subtítulo de cada área
  ("Decisão de compra — visão ampla"), que a barra não tem espaço para carregar. Ele passa
  a ser o caminho secundário.
- `NavLink` com `aria-current="page"` na área ativa (o `MenuArea` já usa `NavLink` — reuse
  a mesma lista `AREAS`, não escreva a segunda).
- ⚠ `relative z-30` na raiz do cabeçalho é o que faz o ☰ abrir **por cima** da barra de
  abas, e o comentário da linha 52 explica em detalhe por que mexer no `z-index` do menu
  não resolve. Não mexa nisso ao reorganizar a barra.

---

## 5. Ponto 2 — clicar no logo vai para o painel

`web/src/componentes/Cabecalho.jsx:70`: o `<img>` do logo não é clicável. Envolva num
`<Link to="/painel/alertas">` com `aria-label="Ir para o painel"`.

⚠ O logo tem `relative z-[1]`, e **é ele que põe o logo sobre o corte diagonal** da faixa.
O `<Link>` precisa herdar isso (ou levar a classe), senão o logo passa a ser pintado por
baixo do corte. Confira no navegador, não só no código.

---

## 6. Ponto 5 — abrir em outra aba, e o defeito que o pedido revelou

### 6.1 O pedido: navegação por `<Link>`, não por `onClick`

Toda ida para o produto hoje é um `<button onClick={() => navegar(...)}>`:
`Alertas.jsx:418` e `:457`, `Pedidos.jsx:183`, `Monitoramento.jsx:332`, `Entradas.jsx:200`.
Em `<button>` não existe ctrl+clique, não existe clique do meio, não existe "abrir em nova
aba" no menu do botão direito — **o navegador não sabe que ali tem um destino.**

Troca: `<Link to={`/produto/${codigo}`}>`, com a aparência que já têm. É o que o Diretor
pediu, e dá de graça o "copiar link do produto".

Vale para navegação; **não** para ação. Botão que grava, exporta, avança status ou remove
item continua `<button>` — esses não têm URL e não devem parecer ter.

### 6.2 ⚠ O defeito por trás do pedido: **o carrinho não sobrevive a sair da tela**

Leia a frase dele de novo: *"abra um produto para visualizar informações, **sem sair da
pagina de pedidos que está sendo criado**"*. Ele não está pedindo só uma aba nova — está
dizendo que sair da tela de Pedidos **custa o trabalho feito**. E custa mesmo:

`web/src/telas/Pedidos.jsx:66` — `const [carrinho, setCarrinho] = useState({})`. Estado
local da tela. Navegar para o produto e voltar **zera o carrinho inteiro**. Não há
`localStorage`, não há `sessionStorage`, não há contexto: `grep -rn "sessionStorage\|
localStorage" web/src` não devolve nada, e `web/src/contexto/` só tem `atualizacao.jsx`.

E isso **contradiz o que o projeto já decidiu**: `v2/PLANO.md` §3, Etapa 9, lista entre as
diferenças deliberadas em relação ao protótipo — *"o carrinho sobrevive à troca de tela"*.
Ficou por fazer.

**Então o ponto 5 são duas tarefas, não uma:**

1. `<Link>` no lugar de `onClick` (o que ele pediu);
2. **o carrinho passa a sobreviver à navegação** (a causa do que ele pediu) — um
   `web/src/contexto/carrinho.jsx` no molde de `atualizacao.jsx`, com persistência em
   `sessionStorage` para sobreviver também ao F5.

Sobre a persistência, duas decisões de desenho:

- **`sessionStorage`, não `localStorage`.** O carrinho é trabalho em curso de uma sessão,
  não preferência permanente; `localStorage` faria o carrinho de terça reaparecer na
  quinta, com preço e cobertura de outro build. E `sessionStorage` é por aba — o que é
  exatamente o comportamento certo aqui: a aba nova que ele abrir para ver o produto **não**
  herda nem atropela o carrinho da aba onde ele está montando o pedido.
- **Guarde o mínimo: código e quantidade digitada.** Nunca preço, custo, margem ou
  cobertura — esses envelhecem no próximo `dbt run`, e carrinho com número velho é decisão
  tomada sobre dado que não existe mais. Ao montar a tela, os números vêm da API; do
  armazenamento vem só o que a pessoa digitou.

---

## 7. Ponto 6 — os nomes saem do sistema

Ele está certo, e a razão que ele dá é boa: nome de funcionário em texto de sistema
envelhece. Medido: **50 ocorrências em 16 arquivos.** O tratamento não é o mesmo para
todas.

### 7.1 Texto que o usuário lê — **obrigatório**

| Arquivo | Linha | Texto hoje |
|---|---|---|
| `web/src/App.jsx` | 48 | `"Lotes de preço para o Cássio/Gabriela aplicarem"` |
| `web/src/componentes/Cabecalho.jsx` | 34 | `sub: "Lotes de preço para o Cássio/Gabriela aplicarem"` |
| `web/src/telas/Precificacao.jsx` | 436 | `"…o documento que vai virar arquivo para o Cássio/Gabriela importarem no…"` |

### 7.2 Comentário de código e docstring — **também, pela mesma razão**

`app/servicos/lote_preco.py` (7), `app/api/rotas.py` (1), `web/src/lotePrecoStatus.js` (3),
`web/src/telas/PrecosDefinidos.jsx` (3), `LotePrecoDetalhe.jsx` (1), `DecisaoSKU.jsx` (1),
`web/src/api/cliente.js` (1), `v2/PROMPT_ETAPA_12_PRECOS_DEFINIDOS.md` (13).

### 7.3 `comment on column` no banco — **sim, e é DDL**

`sql/05_tabelas_lote_preco.sql` tem **8 ocorrências**, das quais duas dentro de
`comment on column` (linhas 160 e 162) — isso é metadado que vive no dicionário do Oracle
e sobrevive a todo mundo. Reescrever o arquivo **e** rodar os `comment on column` de novo,
senão o banco continua com o texto antigo.

### 7.4 O que **não** se mexe

`v2/prototipo/PROTOTIPO.md`, `v2/prototipo/painel_cedep_prototipo_2.jsx` e
`docs/documentacao_tecnica_v10.txt`. São documentos **do Diretor e da diretoria**, registro
histórico do que foi escrito na época — editar o registro para ficar bonito é pior que o
nome estar lá. `CADASTRO_DIVERGENCIAS.md` (3 ocorrências, ainda não versionado) é documento
de saída: trate como texto que o usuário lê.

### 7.5 O vocabulário que entra

Proposta: **"equipe de cadastro"** — *"Lotes de preço para a equipe de cadastro aplicar"*.
Onde o texto descreve o ato e não as pessoas, melhor ainda dizer o ato: *"quem importa o
preço no Winthor"*, *"para digitação no Winthor (rotina 201)"*.

⚠ É a única coisa desta etapa que não posso decidir: **o nome certo da função é o que a
CEDEP usa internamente.** Se "equipe de cadastro" não for como se chama lá, é trocar uma
constante — está em §9.

---

## 8. O trabalho, por agente

### 8.1 `frontend-react` — `model: sonnet`. É o dono desta etapa.

Quatro frentes, nesta ordem (as duas primeiras são independentes e curtas — entregue-as
primeiro, elas dão resultado visível no mesmo dia):

**A. Pontos 2 e 6.1** — logo clicável (§5) e os três textos visíveis (§7.1). Meia hora.

**B. Ponto 3** — as áreas na barra do desktop (§4). Reuse `AREAS`; respeite o `z-30` e a
separação dos dois níveis de navegação.

**C. Ponto 5** — `<Link>` em toda navegação (§6.1) e `web/src/contexto/carrinho.jsx`
(§6.2), com `sessionStorage` guardando só código e quantidade. Ao ligar o contexto,
confira que o botão "Salvar pedido(s)" continua lendo o mesmo estado — é o único consumidor
do carrinho, e trocar a fonte dele sem olhar é como se perde um fluxo que funcionava.

**D. Pontos 1 e 4** — o `CabecalhoOrdenavel` (§3.4) aplicado a todas as tabelas, e o
gráfico do produto com o seletor de métricas (§2), no mesmo desenho do `METRICAS` que
`Monitoramento.jsx:105` já usa (**importe de `web/src/periodo.js`, não redeclare a lista**).
O botão de métrica sem dado fica desabilitado com a dica (§2.4).

**Leia:** `CONTEXTO.md` e `v2/PLANO.md`. **Não leia `REGRAS.md`.**
**Não faça:** dependência nova em `web/package.json`; segunda marcação mobile/desktop
(responsividade é CSS, uma marcação só — §2.5 do `PLANO.md`); ordenação no cliente de lista
paginada (§3.1); `localStorage` para o carrinho (§6.2).

### 8.2 `backend-fastapi` — `model: sonnet`

1. **Direção na ordenação** (§3.2): `ORDENACOES` passa a guardar expressão + direção
   padrão; `_ordem` ganha o parâmetro; `nulls last` explícito nas duas direções; desempate
   por `p.codigo` mantido. Acrescente as colunas que a tela mostra e o `whitelist` ainda
   não cobre — e **só** essas: parâmetro de ordenação é entrada de usuário virando `order
   by`, então nada de interpolar o que vier do cliente. O `whitelist` é a defesa.
2. **As rotas paginadas** (`/api/produtos`, `/api/pedidos`, `/api/lotes-preco`) aceitam
   `ordenar` e `dir`, validam contra o `whitelist` e recusam o resto com 422.
3. **Histórico do produto nas quatro métricas** (§2.5): uma consulta em
   `COMPRAS_MONITORAMENTO` por `CODIGO_PRODUTO`, agregada por mês, **quantidade dividida
   por `FATOR_EXIBICAO`** e faturamento/peso/litros não (§2.2), dentro de
   `obter_produto`. A barra do ano anterior existe ou não conforme `vendaAnoPassado` (§2.3).
4. **`app/api/contrato.py`**: `vendaHistorico` por métrica (§2.5), sem deixar a forma antiga
   conviver.
5. **§7.2** nos arquivos de backend.

**Leia:** `CONTEXTO.md`, `app/servicos/produto.py`, `app/servicos/monitoramento.py` (a
consulta de métrica que já existe). **Não leia `REGRAS.md`** — mas **a regra 6 do índice do
CONTEXTO é exatamente o assunto do item 3**, então leia o §6 do `CONTEXTO.md` inteiro antes
de escrever a divisão pelo fator.

### 8.3 `oracle-dba` — `model: sonnet`. Tarefa pequena.

Reescrever os `comment on column` de `sql/05_tabelas_lote_preco.sql` sem os nomes (§7.3) e
**rodar os comentários no banco** — o arquivo corrigido sem execução deixa o dicionário do
Oracle com o texto antigo. Confira lendo `user_col_comments` depois.

### 8.4 `validador` — `model: sonnet`

Dois números, e são os que protegem esta etapa:

1. **`validar/validar_grafico_produto.py`** — para **todos** os 8.841 SKUs, a quantidade do
   gráfico (soma de `COMPRAS_MONITORAMENTO` no mês ÷ `FATOR_EXIBICAO`) bate com `VD_M_1` /
   `VD_M_2` de `COMPRAS_PEDIDO`, tolerância 0,01. Hoje, **sem** a divisão, dão 230
   divergências e a maior é de 45.655,96 unidades — use esse número como o **defeito
   injetado** do autoteste: rode uma vez sem dividir, confirme as 230, e só então valide
   com a divisão. Teste que nunca falhou não prova nada.
2. **Ordenação paginada** — para cada coluna clicável, a primeira linha da página 1 em
   `desc` é o **máximo do conjunto inteiro** (e o mínimo em `asc`), conferido contra um
   `select max()`/`min()` direto. É o teste que pega a ordenação "só da página", que é
   justamente o defeito fácil de introduzir aqui. Inclua uma coluna com nulo e prove que o
   nulo ficou no fim nas duas direções.

### 8.5 `revisor` — `model: opus`. Último.

Revise só o que a etapa mudou. Além da sua lista, procure especificamente:

- **`FATOR_EXIBICAO` esquecido ou aplicado no lugar errado** (§2.2) — é o único ponto desta
  etapa que muda número na tela, e o modo de falha é plausível: um gráfico 24× maior parece
  um produto que vende muito.
- **Ordenação de lista paginada feita no cliente** (§3.1).
- **`nulls last` perdido na direção invertida** (§3.2).
- **Interpolação de parâmetro de ordenação em SQL** sem passar pelo `whitelist`.
- **Carrinho guardando preço ou margem** (§6.2) — número velho reaparecendo como decisão.
- **Os dois níveis de navegação achatados** (§4) — o erro que esta tela já cometeu uma vez.

### 8.6 Quem **não** entra

`dbt-staging`, `dbt-relatorios`, `dbt-regras`, `infra-windows`. **Nenhum model, nenhuma
coluna, nenhum seed.** Todo dado das quatro métricas já está em `COMPRAS_MONITORAMENTO`. Se
alguém sentir falta de um campo, pare e reporte.

---

## 9. Perguntas — uma só, e é de vocabulário

**Como se chama internamente a função de quem digita preço no Winthor?** A proposta é
"equipe de cadastro" (§7.5). Se na CEDEP se diz "cadastro", "faturamento", "preços" ou
outra coisa, é essa palavra que deve entrar — e é uma constante, não um refactor. Vale
perguntar junto com o ponto 6, que é dele.

As outras decisões desta etapa estão tomadas e justificadas: `lg:` como corte do desktop
(§4), `sessionStorage` por aba (§6.2), coluna clica / ordem composta no seletor (§3.3), e
os documentos do Diretor que não se editam (§7.4).

---

## 10. Aceite

1. Na tela do produto, alternar entre Faturamento · Quantidade · Peso · Litros troca as
   cinco barras sem ida ao servidor.
2. **No SKU 7305 (fator 24), a barra de agosto mostra 1.985, não 47.641** — e o número bate
   com a "Média mensal" logo acima. Idem 3827 e 6771 (fator 12).
3. No SKU 7066, o botão "Litros" está desabilitado com a dica de litragem não cadastrada.
4. Um produto sem venda no mesmo mês do ano anterior **não** desenha barra amarela; um que
   vendeu zero desenha a barra rente ao chão.
5. Clicar no logo vai para o Painel; o logo continua por cima do corte diagonal.
6. A 1280px, as cinco áreas aparecem na barra superior e o ☰ continua funcionando; a barra
   de abas do Painel continua visualmente distinta das áreas.
7. Ctrl+clique (e clique do meio) em qualquer produto abre em aba nova; a aba de origem não
   navega.
8. Montar um carrinho de 5 itens em Pedidos, abrir um produto **na mesma aba**, voltar: os
   5 itens estão lá. F5: continuam lá. Abrir a mesma tela em **outra aba**: carrinho vazio,
   e o da primeira aba intacto.
9. Em Precificação ordenada por "Margem AT" decrescente, a primeira linha da página 1 é a
   pior margem **do filtro inteiro** — conferida contra um `select min()` no banco, não
   contra a página.
10. Clicar numa coluna volta para a página 1 e a ordenação aparece na URL; recarregar
    mantém a ordem.
11. `grep -rn -i "cassio\|cássio\|gabriela" app/ web/src/ sql/` não devolve nada.
    `user_col_comments` de `APP_LOTE_PRECO` também não.
12. `dbt test` continua em 276 passando — esta etapa não toca no dbt.
