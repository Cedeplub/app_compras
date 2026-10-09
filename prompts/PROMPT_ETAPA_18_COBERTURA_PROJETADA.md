# Etapa 18 — A cobertura projetada soma caixas como se fossem unidades, em três telas

**Origem.** Diretor de Compras, item **1.12** de uma lista maior, repassado pelo usuário
(suporte.ia1@cedeplub.com) pelo prompter em **08/10/2026**. Os demais itens da lista não
vieram; nada aqui depende deles.

**Base de código.** `4d1af6a` (30/09/2026 08:23 — "A quantidade pedida vai para o campo, e o
que muda fica visível"), árvore limpa. Repositório `app_compras_v2`, cujo commit inicial é
`fbac519`.

**Por que 18 e não 17.** A numeração 17 já foi consumida: o trabalho de 29–30/09/2026
(commits `1950964`, `1fdd8c1`, `dbf0ccf`, `4d1af6a`) está registrado no código como "Etapa
17" em `web/src/telas/PedidoDetalhe.jsx:358`, `web/src/componentes/CatalogoPedido.jsx:12` e
`:126` e `web/src/telas/Pedidos.jsx:27`. Um segundo documento com o número 17 tornaria esses
comentários ambíguos. Esta é a **18**.

**Isto muda número?** **Muda número na tela, e só na tela.** Nenhuma coluna de
`COMPRAS_PEDIDO`/`FAT_PEDIDO` é recalculada, nenhum model dbt é editado, nenhuma linha de
`APP_PEDIDO_ITEM` é reescrita, nenhuma rota de `/api` muda de contrato. O defeito é inteiro
do cliente: três fórmulas em JavaScript que somam quantidade em **unidade real** a estoque e
média que já chegam em **unidade de exibição**. `app/` e `dbt/` não são tocados por ninguém
nesta etapa — ver §8 e §9.

---

## 1. O pedido, verbatim

> 1. ⚠️ *1.12 · Cobertura depois do pedido inflada nos itens MASTER (edição de pedido
>    salvo): soma as caixas do pedido como se fossem unidades.*
> 2. *• Cod. 2808: mostra 39,5 meses; o certo é 7,0.*
> 3. *• Cod. 5177: mostra 19,9 meses; o certo é 5,4.*

---

## 2. A hipótese fechou nos dois SKUs, até a casa decimal

Medido em 08/10/2026 contra o schema `COMPRAS` (só `SELECT`). Os dois SKUs do Diretor estão
no **pedido 361** (`APP_PEDIDO`: PETRONAS, status `Rascunho`, criado em 02/10/2026, 20
itens) — é a tela de edição desse pedido que ele tinha aberta.

| | 2808 | 5177 | 3860 (controle) |
|---|---|---|---|
| `COMPRAS_PEDIDO.FATOR_EXIBICAO` | 24 | 12 | **1** |
| `EST_DISP` | 165,5000 | 435,5833 | 637 |
| `PENDENTE` | 70 | 500 | 700 |
| `EST_PEND` | 235,5000 | 935,5833 | 1.337 |
| `MEDIA_JANELA` | 42,4306 | 228,6389 | 453,6667 |
| `MESES_EST` | 5,5502 | 4,0920 | 2,9471 |
| `APP_PEDIDO_ITEM.QUANTIDADE` (pedido 361) | 60 | 300 | 700 |
| `APP_PEDIDO_ITEM.FATOR_EXIBICAO` (congelado) | 24 | 12 | 1 |

A conta que a tela faz hoje, `(EST_PEND + qtd × fator) / MEDIA_JANELA`:

- 2808: (235,5 + 60×24) / 42,4306 = 1.675,5 / 42,4306 = 39,4879 → a tela imprime com uma
  casa: **39,5**. É o número do Diretor, exato.
- 5177: (935,5833 + 300×12) / 228,6389 = 4.535,5833 / 228,6389 = 19,8373 → **19,8**. O
  Diretor leu **19,9**; a diferença de 0,1 é a deriva de `EST_DISP` entre o `dbt run` do
  print e o de agora (`EST_DISP` é coluna volátil — `validar/validar_pedido.py`, bloco
  VOLATIL). Não é um segundo defeito.

A conta correta, `(EST_PEND + qtd) / MEDIA_JANELA`:

- 2808: 295,5 / 42,4306 = 6,9643 → **7,0**. É o número do Diretor, exato.
- 5177: 1.235,5833 / 228,6389 = 5,4042 → **5,4**. É o número do Diretor, exato.

**Hipótese confirmada, e a fórmula do defeito é esta — não há outra causa a procurar.**
As razões não serem múltiplos limpos (39,5/7,0 = 5,64; 19,8/5,4 = 3,67) é consequência de só
**uma parcela** da soma estar na unidade errada, exatamente como previsto.

### Por que `× fator` é o termo errado, e não os outros

`int_produto_demanda.sql` divide a fonte por `FATOR_EXIBICAO` **antes** de compor qualquer
coisa:

| Linha | Expressão |
|---|---|
| `int_produto_demanda.sql:138` | `nvl(c.qtdisp,0) / r.fator_exibicao as est_disp` |
| `:142` | `nvl(c.qtpedida,0) / r.fator_exibicao as pendente` |
| `:171` | `… / r.fator_exibicao as media_janela` |
| `:201` | `e.est_disp + e.pendente as est_pend` |

Logo `EST_DISP`, `PENDENTE`, `EST_PEND` e `MEDIA_JANELA` chegam ao front **em unidade de
exibição** (caixa, quando o departamento é MASTER). O campo de digitação também é em unidade
de exibição — `CatalogoPedido.jsx:498` escreve literalmente "caixas" abaixo dele, e
`DecisaoSKU.jsx:684` rotula "(caixas de N)". **O único termo que sai da unidade é
`× fatorExibicao`.** Tirá-lo é o conserto; qualquer outro ajuste conserta o que está certo.

Isto é a **regra 6 do `CONTEXTO.md`** espelhada em relação à Etapa 13: lá a fonte vinha em
unidade real e faltava dividir; aqui tudo já está em unidade de exibição e sobra uma
multiplicação.

---

## 3. O mesmo defeito está em três lugares — e são três fórmulas diferentes

Varredura feita (`grep -rn` em `web/src`, `app`, `dbt`, `validar`, fora de
`app/static/v2/`). Existem **duas** implementações em JavaScript da "cobertura depois do
pedido" e **uma** no dbt. As três divergem entre si.

### 3.1 `web/src/componentes/CatalogoPedido.jsx:364-371` — `calcMesesCoberturaComPedido`

```js
const pedidoUnidades = qtd * (p.fatorExibicao || 1);
return (Number(p.estPend || 0) + pedidoUnidades) / p.mediaJanela;
```

Renderizada em `CatalogoPedido.jsx:465-471`, na coluna "Cob./Alvo", como a linha "→ 39,5"
abaixo do "agora 5,5". **Tem o defeito.**

`TabelaCatalogo` é usada em **três pontos**, e os três herdam o defeito do mesmo arquivo:

| Onde | Linha | Tela |
|---|---|---|
| `web/src/telas/PedidoDetalhe.jsx:625` | tabela de cima, os itens já no pedido | **é esta que o Diretor viu** |
| `web/src/telas/PedidoDetalhe.jsx:667` | tabela de baixo, o resto do departamento | mesma tela |
| `web/src/telas/Pedidos.jsx:234` | catálogo de `/pedidos` (carrinho) | mesma conta, mesmo erro |

Como o campo de quantidade nasce preenchido com a quantidade gravada
(`PedidoDetalhe.jsx:381-382`, commit `4d1af6a`), na edição de pedido salvo a projeção
aparece **sem ninguém digitar nada** — por isso o Diretor topou com ela.

### 3.2 `web/src/telas/DecisaoSKU.jsx:89-90` — `coberturaAposPedido`

```js
const coberturaAposPedido = p.mediaJanela > 0
  ? (p.estDisp + (p.estPend ?? 0) + pedidoUnidades) / p.mediaJanela : null;
```

Renderizada em `DecisaoSKU.jsx:700-706`, "Cobertura depois deste pedido". **Tem o defeito —
e tem um segundo, independente dele.** `EST_PEND` **já inclui** `EST_DISP`
(`int_produto_demanda.sql:201`; medido: em **8.944 de 8.944** linhas de `COMPRAS_PEDIDO`,
`EST_PEND = EST_DISP + PENDENTE` com diferença abaixo de 0,0001). Somar `estDisp` de novo
conta o estoque duas vezes.

Consequência medida, sobre os 3.461 SKUs com `MEDIA_JANELA ≠ 0`: a dupla contagem infla a
projeção em **2,75 meses na mediana**, até **920 meses** no pior caso, e é visível (≥ 0,05
mês) em **2.958** deles. **Esse erro não depende de `FATOR_EXIBICAO`** — atinge também os
SKUs com fator 1. Para o 3860 (fator 1), a tela mostra hoje 5,89 m onde o certo é 4,49 m.

Para o 2808 com as 60 caixas do pedido 361, as duas telas discordam hoje: o catálogo diz
39,5 e a Decisão do SKU diz 43,39. **É exatamente o "duas coberturas discordantes para o
mesmo produto" que esta etapa existe para acabar.**

### 3.3 `dbt/compras/models/intermediate/int_produto_pedido.sql:207-210` — `meses_est_ped`

```sql
-- BF: IF($AG2=0,"",($V2+$BB2)/$AG2)
case when q.media_janela <> 0
     then (q.est_pend + q.pedido_unidades) / q.media_janela
end as meses_est_ped
```

Mistura as mesmas duas unidades — mas é **porte fiel da coluna BF da planilha**, e a mistura
é da planilha (a coluna vizinha BG, `:211`, faz `est_pend * fator_exibicao * custo` e o
comentário do próprio arquivo diz "desfaz o FATOR_EXIBICAO": na planilha V também está em
unidade de exibição). Sai em `COMPRAS_PEDIDO.MESES_EST_PED` e `FAT_PEDIDO.MESES_EST_PED`, e
a API a expõe como `mesesCoberturaComPedido` (`app/api/contrato.py:276`).

**Nenhuma tela consome esse campo.** Conferido: `grep -rn "mesesCoberturaComPedido" web/src`
devolve só duas linhas de **comentário** (`CatalogoPedido.jsx:353` e `:358`), nenhum uso.

**Decisão: `int_produto_pedido.sql` não é tocado nesta etapa.** Motivo, e é o que separa
esta etapa de uma que muda número: alterar `meses_est_ped` muda uma coluna de `FAT_PEDIDO`,
reprova a comparação de `validar/validar_pedido.py` contra o gabarito (122 colunas × 8.772
linhas, tolerância 0,01, bloco ESTRUTURAL) e passa a divergir da planilha que o Diretor ainda
usa como referência. Vira pergunta para o Diretor (§10, pergunta A), não trabalho de agente.

### 3.4 O que **não** tem o defeito — não conserte

| Conta | Onde | Veredito |
|---|---|---|
| Valor total do pedido salvo | `app/servicos/pedido.py:114` — `sum(quantidade * fator_exibicao * preco_unitario)` | **Certo.** `PRECO_UNITARIO` vem de `COMPRAS_PEDIDO.VL_ENT_UNIT`, que é **por unidade real**. Multiplicar por `fator_exibicao` é obrigatório aqui. Conferido contra `COMPRAS_PEDIDO`: 2808, `PEDIDO_UNIDADES` 2.640 × `CUSTO_TOT_OFICIAL` 33,1349 = `VALOR_PEDIDO` 87.476,27 — a mesma aritmética fecha |
| Totais do carrinho (valor/peso/litros) | `web/src/telas/Pedidos.jsx:167-175` — `unidades = n × fatorExibicao`, depois `× valorEntradaUnitario / pesoUnidade / litragemUnidade` | **Certo.** São medidas absolutas por unidade real; `media_l` em `int_produto_demanda.sql:211` usa a mesma multiplicação. Regra 6: faturamento, peso e litros **não** se dividem |
| Total por linha no painel do carrinho | `web/src/telas/Pedidos.jsx:451` | **Certo**, mesmo motivo |
| "Em unidades" na Decisão do SKU | `DecisaoSKU.jsx:83`, `:694-698` | **Certo.** Converter caixas em unidades para **exibir** é o propósito do campo |
| `PEDIDO_UNIDADES = quantidade × FATOR_EXIBICAO` gravado | `app/servicos/pedido.py`, `stg_decisao_pedido` | **Certo e intocável** — ver §4 |
| `SUG_COBERTURA` | `int_produto_demanda.sql:277` | **Certo.** `media_janela × alvo − est_pend`, tudo em unidade de exibição; o botão da sugestão preenche o campo em caixas |

---

## 4. ⚠ O fator congelado não se recalcula, e a gravação não se toca

`APP_PEDIDO_ITEM.FATOR_EXIBICAO` é o fator **do momento em que o item foi gravado**, não o
fator corrente do cadastro (`app/servicos/pedido.py:13-17`). `PEDIDO_UNIDADES = quantidade ×
FATOR_EXIBICAO gravado` é regra, e há test que a prova.

Esta etapa **não escreve em `APP_PEDIDO_ITEM`**, não muda `upsert_item`, não muda o que
`stg_decisao_pedido` lê e não recalcula fator nenhum. O conserto é na **aritmética de
exibição da cobertura**, três arquivos `.jsx`, e nada mais.

Se a investigação do executor apontar para mudar o que se grava: **pare e reporte**. Seria
outra conversa, e mudaria número em `FAT_PEDIDO`.

E a consequência de fronteira continua valendo, inclusive aqui: **uma decisão gravada no
dashboard só chega ao `fat_pedido` no próximo `dbt run`** — o que esta etapa corrige aparece
na hora, porque é conta de tela sobre dado já lido.

---

## 5. Quantos são — a medida que dimensiona a urgência

Sobre `APP_PEDIDO_ITEM` inteiro, 08/10/2026:

| Medida | Valor |
|---|---|
| Itens de pedido gravados | **973**, em 17 pedidos, 899 SKUs distintos |
| Itens com `FATOR_EXIBICAO > 1` | **103** (10,6%), em 4 pedidos |
| Desses 103, quantos têm erro **acima de 1 mês** | **103 — todos** |
| Erro mediano, em meses de cobertura | **15,77** |
| Erro máximo | **195,59 meses** (item 8811, pedido 282, 15 caixas de 24, `MEDIA_JANELA` 1,7639) |
| Fatores em uso | 12, 20, 24 e 36 — não só 12 e 24 |
| SKUs do catálogo com `FATOR_EXIBICAO > 1` | **516** de 8.944 |

Erro = `qtd × (fator − 1) / MEDIA_JANELA`. Os quatro pedidos atingidos: 141 (INGRAX,
Orçamento Enviado), 261 (PETRONAS, Fechado), 282 (KOUBE, Orçamento Enviado), 361 (PETRONAS,
Rascunho).

Não é cosmético: **em todo item MASTER de todo pedido salvo o número está errado**, e o erro
mediano é dez vezes maior que a própria cobertura alvo (2,0 meses nestes fornecedores). O ⚠️
do Diretor está correto.

A dupla contagem da §3.2 é ainda mais ampla: 2.958 dos 3.461 SKUs com média não nula, em
qualquer departamento, com ou sem fator.

---

## 6. A terceira discordância: o cartão "Cobertura" da Decisão do SKU

`DecisaoSKU.jsx:88` calcula `coberturaAtual = p.estDisp / p.mediaJanela` e o cartão
"Cobertura" (`:172-174`) mostra esse número. As listas mostram `p.mesesCobertura`
(`CatalogoPedido.jsx:458`), que é `COMPRAS_PEDIDO.MESES_EST` = `est_pend / media_janela`
(`int_produto_demanda.sql:272-274`). **São duas definições de cobertura para o mesmo
produto**, e não é arredondamento:

| Medida (3.461 SKUs com `MEDIA_JANELA ≠ 0`) | Valor |
|---|---|
| SKUs em que cartão e lista discordam em mais de 0,05 mês | **1.318** |
| Maior discordância | **1.104 meses** |
| SKUs que o cartão pinta de **crítico** e a lista não (alvo real × 0,6) | **313** |
| SKUs que a lista pinta de crítico e o cartão não | **0** |

2808: cartão 3,90 m, lista 5,55 m. 3860: cartão 1,40 m, lista 2,95 m.

**Decisão: o cartão passa a usar `p.mesesCobertura`**, o número do modelo (coluna AX da
planilha), e deixa de recalcular no cliente. Motivo: a cobertura do projeto inclui o
pendente — é assim em `MESES_EST`, em `SUG_COBERTURA`, nos alertas de `fat_alerta` e nas
duas listas; a Decisão do SKU era a única discordante, e era a única que recalculava à mão.
Um dos dois tinha de ceder, e cede quem não é fonte de verdade.

**Isto não muda nada no banco** — é a tela parando de refazer, errado, uma conta que já vem
pronta no JSON.

No mesmo cartão, um defeito irmão: `DecisaoSKU.jsx:168-169` rotula a nota como
`+ pendente ${estPend}`, mas `estPend` **é o estoque mais o pendente**. Para o 2808 a tela
diz "+ pendente 236" quando o pendente é 70. O contrato já manda o campo certo separado
(`app/api/contrato.py:273`, `"pendente"`). Troque `p.estPend` por `p.pendente` na nota — e só
na nota; o valor principal do cartão continua `p.estDisp`.

---

## 7. A decisão de desenho: uma fórmula, um arquivo

Depois do conserto existem **duas** chamadas a corrigir hoje e nenhuma garantia de que a
terceira não nasça amanhã. O comentário que hoje está em `CatalogoPedido.jsx:346-363` é a
prova: ele **descreve a mistura de unidades com precisão** e conclui "Não é bug para corrigir
no front: é regra de negócio do modelo, relatada para o Diretor decidir". A conclusão está
errada — a conta do front é do front — e foi ela que manteve o defeito vivo por um mês.

**Decisão: a fórmula vai para um módulo novo, `web/src/cobertura.js`**, com duas funções
puras exportadas, e as duas telas passam a importá-lo. Nenhuma tela recalcula cobertura por
conta própria depois desta etapa.

```js
// web/src/cobertura.js  (arquivo NOVO)

/** Cobertura projetada, em meses, somando uma quantidade AINDA NÃO GRAVADA.
 *
 *  ⚠ CONTEXTO.md regra 6. `estPend` e `mediaJanela` chegam da API já DIVIDIDOS
 *  por FATOR_EXIBICAO (int_produto_demanda.sql:138,142,171,201) — estão em
 *  unidade de EXIBIÇÃO. O campo onde se digita a quantidade também é em
 *  unidade de exibição (o rótulo abaixo dele diz "caixas"). Portanto NÃO se
 *  multiplica a quantidade por fatorExibicao aqui: foi essa multiplicação que
 *  fez o item 2808 mostrar 39,5 meses onde o certo eram 7,0 (item 1.12 do
 *  Diretor, 08/10/2026; medido em 103 dos 973 itens de pedido gravados, erro
 *  mediano de 15,77 meses).
 *
 *  ⚠ `estPend` JÁ INCLUI `estDisp` (int_produto_demanda.sql:201; medido em
 *  8.944 de 8.944 linhas de COMPRAS_PEDIDO). Somar os dois conta o estoque
 *  duas vezes — era o segundo defeito de DecisaoSKU.jsx:89.
 *
 *  Multiplicar por fatorExibicao continua CERTO para valor, peso e litros
 *  (Pedidos.jsx:167-175): são medidas absolutas, por unidade real.
 */
export function coberturaComPedido(p, quantidadeDigitada) {
  const qtd = Number(String(quantidadeDigitada ?? "").replace(",", ".")) || 0;
  if (qtd <= 0) return null;
  if (!p?.mediaJanela) return null;
  return (Number(p.estPend || 0) + qtd) / p.mediaJanela;
}
```

Para a cobertura atual não se escreve função nenhuma: **usa-se `p.mesesCobertura`**, que a
API já manda pronto (`contrato.py:275`). Se o executor sentir vontade de escrever
`coberturaAtual(p)`, é sinal de que está recriando o problema.

Sobre o `qtd <= 0 → null` em `DecisaoSKU`: hoje o cartão "Cobertura depois deste pedido"
mostra um número mesmo com o campo vazio (e, por causa da dupla contagem, mostra o dobro da
cobertura atual — 9,45 m para o 2808). Com `null` ele passa a mostrar "—" enquanto não há
quantidade digitada. **É o comportamento certo**: "depois deste pedido" sem pedido não é um
número, é uma pergunta sem resposta. Não invente um terceiro estado.

---

## 8. O trabalho, por agente

### 8.1 `frontend-react` — `model: sonnet`

Sonnet e não opus, apesar de a etapa mudar números na tela: a fórmula está escrita acima,
fechada contra dois SKUs medidos no banco, e não sobrou decisão de cálculo para o executor
tomar. O que ele faz é aplicar.

**Ler antes:** `CONTEXTO.md §0` e **§6 regra 6** (a regra, não o `REGRAS.md` inteiro); este
documento; `web/src/componentes/CatalogoPedido.jsx:340-472`; `web/src/telas/DecisaoSKU.jsx:76-180`
e `:650-712`; `web/src/telas/Pedidos.jsx:155-180`; `web/src/telas/PedidoDetalhe.jsx:600-680`.

**Não ler:** `REGRAS.md` (460 linhas, ~7,6 mil tokens — nada aqui é fiscal, margem, preço,
curva ABC ou alerta); `historico/`; `docs/gabarito_pedido_formulas.txt`;
`v2/prototipo/painel_cedep_prototipo_2.jsx`.

**Na ordem:**

1. **Criar `web/src/cobertura.js`** com `coberturaComPedido` exatamente como na §7, comentário
   incluído. Arquivo novo, sem dependência nova — nada entra em `web/package.json`.
2. **`web/src/componentes/CatalogoPedido.jsx`** — apagar `calcMesesCoberturaComPedido`
   (`:364-371`) **e o bloco de comentário `:346-363`**, que está factualmente certo e
   conclusivamente errado; importar `coberturaComPedido` e usá-la em `:396`. O resto da
   célula (`:455-472`: cores `criticaProjetada`/`atingiuAlvo`, o "agora", a seta `→`, o
   `numero(mesesComPedido, 1)`) **fica como está** — o layout não é o defeito.
3. **`web/src/telas/DecisaoSKU.jsx`** — três edições, e nenhuma a mais:
   - `:89-90` passa a `const coberturaAposPedido = coberturaComPedido(p, pedidoValor);`.
     `pedidoUnidades` (`:87`) **continua existindo**: ele alimenta o "Em unidades" de
     `:694-698`, que está certo.
   - `:88` some; `:91-92` e `:172-174` passam a usar `p.mesesCobertura` no lugar de
     `coberturaAtual`. Repasse `p.mesesCobertura` ao `Contexto` em vez da prop
     `coberturaAtual` (`:114`, `:165`), ou leia direto de `p` dentro dele — tanto faz, desde
     que ninguém recalcule.
   - `:169` — a nota do cartão "Estoque disponível" troca `p.estPend` por `p.pendente`. O
     valor principal do cartão continua `p.estDisp`.
4. **Conferir que `web/src/telas/Pedidos.jsx` e `web/src/telas/PedidoDetalhe.jsx` não
   precisam de edição nenhuma** — as duas consomem `TabelaCatalogo` e herdam o conserto.
   Se alguma edição parecer necessária ali, releia: provavelmente é o certo sendo
   "consertado".

**Não faça, em nenhuma hipótese:**

- não encoste em `web/src/telas/Pedidos.jsx:157-180` (totais de valor/peso/litros) nem em
  `:451` — a multiplicação por `fatorExibicao` **é correta ali** (§3.4);
- não altere `app/`, `dbt/`, `sql/`, `validar/` (o validador é da §8.2) nem `infra/`;
- não acrescente dependência em `web/package.json`, nem URL externa em tela ou CSS — o
  dispositivo alvo é o celular na rede interna;
- não duplique marcação para celular: responsividade é CSS, uma marcação só;
- não troque `<button>` por `<Link>` nem o contrário nesta etapa;
- não mexa no `relative z-30` do cabeçalho nem na navegação de dois níveis;
- não "arrume" `estPend` para virar só o pendente: a coluna é `EST_DISP + PENDENTE` por
  definição do modelo, e 8.944 de 8.944 linhas confirmam. Quem tem de ceder é o rótulo.

### 8.2 `validador` — `model: sonnet`

**Ler antes:** `CONTEXTO.md §0` e **§6 regra 6**; este documento §2, §3 e §5;
`validar/validar_grafico_produto.py` (é o molde — mesmo defeito, mesma estrutura de
autoteste); `validar/validar_pedido.py:1800-1816` (credencial e conexão).
**Não ler:** `REGRAS.md`, `historico/`.

**Escrever `validar/validar_cobertura_projetada.py`.** Só leitura — nenhuma gravação, nenhum
usuário criado. Modo thick obrigatório (`oracledb.init_oracle_client(lib_dir=r"C:\Oracle\instantclient_21_17")`;
thin dá `DPY-3015`).

O script, na ordem:

1. **Autoteste com o defeito injetado, primeiro.** Roda a comparação com a fórmula ANTIGA
   (`(est_pend + qtd × fator) / media_janela`) e **prova que ela acusa**: 103 dos 973 itens
   de `APP_PEDIDO_ITEM` divergem, erro mediano 15,77 meses, erro máximo 195,59 meses no item
   8811 do pedido 282. Validador que nunca reprovou não prova nada — se este passo passar
   limpo, o script está errado, não o banco.
2. Roda a comparação real (`(est_pend + qtd) / media_janela`) e prova que fecha.
3. **Spot-check pelo código de verdade**, não por SQL reescrito: chama
   `produto.obter` + `contrato.produto` para 2808, 5177 e 3860 e confere que `estPend`,
   `mediaJanela`, `pendente` e `mesesCobertura` chegam ao JSON com os valores da tabela da
   §2. É isso que prova que a correção do front opera sobre os campos que ele de fato recebe.
4. **Invariante `EST_PEND = EST_DISP + PENDENTE`** sobre `COMPRAS_PEDIDO` inteiro: 8.944 de
   8.944, tolerância 0,0001. É a afirmação que sustenta a remoção do `estDisp` em
   `DecisaoSKU`; se um dia ela quebrar, a correção da §3.2 deixa de valer e alguém precisa
   saber na hora.
5. Imprime, como contagem recalculada (não copiada deste documento): itens com fator > 1 por
   pedido e por status, e os 10 maiores erros.

**Não faça:** não escreva em tabela nenhuma; não toque em `dbt/`; não compare contra
`MESES_EST_PED` como se ele fosse o gabarito — ele carrega a mistura da planilha (§3.3) e
vai divergir por desenho. Se quiser citá-lo, cite como "o número da planilha", separado.

### 8.3 `infra-windows` — `model: haiku`

**Ler antes:** `infra/README.md`. **Não ler:** mais nada.

O front em produção é estático, servido pelo FastAPI atrás do nginx — **não há Vite no ar**.
Sem este passo a correção fica só na máquina de quem desenvolveu.

1. `powershell -ExecutionPolicy Bypass -File infra\publicar.ps1` a partir de
   `C:\Users\Administrator\Desktop\app_compras_v2` (os scripts recusam rodar de outra pasta,
   e isso é proposital).
2. Confirmar o serviço NSSM `app_compras` em `Running` e a tela nova em
   `http://192.168.0.50/`.

**Não faça:** não edite `nginx.conf`, não rode `nginx -s reload`, não mexa em vhost nenhum —
o `nginx.conf` desta máquina serve outras áreas e esta etapa não muda rota, porta nem
arquivo servido. Não mexa na Tarefa Agendada. Não reinicie a máquina (socket órfão,
`CONTEXTO.md §0.4` — não é decisão a tomar sozinho).

### 8.4 `revisor` — `model: opus`, sempre o último

Opus, apesar de não haver cálculo fiscal: a armadilha de unidade é a mais cara deste projeto
e já foi reintroduzida uma vez. O revisor refaz a aritmética da §2 contra o banco em vez de
confiar nos números daqui.

**Ler antes:** `CONTEXTO.md` inteiro, este documento, o diff completo da etapa.
**Não ler:** `REGRAS.md`.

Checar, nomeadamente:

1. Que `app/`, `dbt/`, `sql/` e `infra/` estão **intactos** — `git status --short` só mostra
   `web/` e `validar/`.
2. Que **nenhuma** multiplicação por `fatorExibicao` sobrou dentro de uma fórmula de
   cobertura, e que **todas** as de valor, peso e litros continuam no lugar.
3. Que existe uma só implementação da projeção, e que as três telas a usam.
4. Que o comentário de `CatalogoPedido.jsx:346-363` foi **removido**, não editado para
   continuar afirmando que o defeito é do modelo.
5. Que o autoteste do validador **falha de verdade** quando rodado com o defeito injetado —
   rodando, não lendo o código.

---

## 9. Quem não entra

| Agente | Por quê |
|---|---|
| `oracle-dba` | Nenhum DDL, nenhum GRANT, nenhuma tabela `APP_*` criada ou alterada |
| `dbt-staging` | Nenhum `stg_*`, nenhum seed. `dbt seed` não é necessário e `dbt run` não é parte do aceite |
| `dbt-relatorios` | Os dois relatórios portados não têm cobertura projetada |
| `dbt-regras` | `int_produto_pedido.sql` **não é tocado** (§3.3). Nada de fiscal, margem, preço, curva ABC ou alerta |
| `backend-fastapi` | O contrato JSON já manda tudo que a correção precisa: `estPend`, `pendente`, `mediaJanela`, `mesesCobertura`, `fatorExibicao` (`contrato.py:260-277`). Nenhuma rota, nenhum serviço, nenhuma chave nova |

---

## 10. Perguntas — só as que o executor não pode responder

**A. `MESES_EST_PED` (coluna BF) fica como está?** Ela carrega a mesma mistura de unidades,
mas é porte fiel da planilha e sai em `FAT_PEDIDO`. Nenhuma tela a lê hoje, então corrigi-la
não mudaria nada para o usuário — mas faria `FAT_PEDIDO` divergir da planilha que o Diretor
ainda usa, e reprovaria `validar/validar_pedido.py` contra o gabarito. **Esta etapa a deixa
intacta.** O Diretor quer que a planilha seja corrigida também, ou a coluna BF fica como
registro histórico do Excel?

**B. "Cobertura" passa a incluir o pendente também no cartão da Decisão do SKU** (§6), para
parar de discordar das listas em 1.318 SKUs. Isso faz 313 SKUs **deixarem** de aparecer
pintados de crítico naquela tela — eles nunca estiveram críticos pela definição do modelo. O
Diretor quer ver, além disso, a cobertura só do estoque disponível (sem pendente) como um
segundo número no cartão?

---

## 11. Aceite

Numerado, e cada item é uma demonstração, não uma afirmação. Os valores de 1 a 7 são os do
banco em 08/10/2026 e dependem de `EST_DISP`/`MEDIA_JANELA`, que mudam a cada `dbt run`:
**recalcule o esperado na hora de conferir, pela fórmula, e não copie destes números** — a
estrutura (hoje × certo) é o que não muda.

1. **2808**, pedido **361** (PETRONAS, Rascunho, 60 caixas gravadas, fator 24), tela de
   edição do pedido salvo, coluna "Cob./Alvo": a linha "→" mostra **7,0** onde hoje mostra
   **39,5**. É o número que o Diretor pediu.
2. **5177**, mesmo pedido 361 (300 caixas, fator 12): mostra **5,4** onde hoje mostra
   **19,8**. É o número que o Diretor pediu. (Ele leu 19,9; a diferença de 0,1 é deriva de
   `EST_DISP` entre builds — se o executor encontrar 19,8 antes do conserto, está certo.)
3. **Controle, 3860**, mesmo pedido 361, **`FATOR_EXIBICAO = 1`**, 700 unidades, `EST_PEND`
   1.337, `MEDIA_JANELA` 453,6667: a mesma coluna mostra **4,5 antes e 4,5 depois** —
   **não muda**. É este item que pega a correção aplicada no lugar errado.
4. Os três números de 1 a 3 aparecem **idênticos** na tela `/pedidos` (carrinho), digitando
   as mesmas quantidades, e nas **duas** tabelas de `PedidoDetalhe` (a dos itens do pedido e
   a do catálogo). Quatro pontos de exibição, um número.
5. **Decisão do SKU do 2808** com 60 no carrinho: "Cobertura depois deste pedido" mostra
   **6,96 m** onde hoje mostra **43,39 m** — e bate com o 7,0 do item 1 (a tela usa duas
   casas, a lista usa uma; é a mesma conta).
6. **Decisão do SKU do 3860** com 700 no carrinho: mostra **4,49 m** onde hoje mostra
   **5,89 m**. ⚠ **Este muda apesar de `FATOR_EXIBICAO = 1`** — é a dupla contagem de
   `EST_DISP` (§3.2), e é esperado. Não confunda com o item 3, que não pode mudar.
7. **Cartão "Cobertura" da Decisão do SKU do 2808**: **5,55 m** (= `MESES_EST`) onde hoje
   mostra 3,90 m, idêntico ao "agora 5,5" da coluna "Cob./Alvo" da lista. E o cartão
   "Estoque disponível" do 2808 mostra a nota **"+ pendente 70"**, não "+ pendente 236".
8. `validar/validar_cobertura_projetada.py` **rodado**, com a saída colada no relatório: o
   autoteste com o defeito injetado **acusa 103 de 973 itens**, erro máximo **195,59 meses**
   no item 8811 do pedido 282; a comparação real passa; o invariante
   `EST_PEND = EST_DISP + PENDENTE` fecha em **8.944 de 8.944** linhas.
9. `grep -rn "fatorExibicao" web/src/componentes/CatalogoPedido.jsx web/src/telas/DecisaoSKU.jsx web/src/cobertura.js`
   colado no relatório: nenhuma das ocorrências restantes está dentro de uma divisão por
   `mediaJanela`.
10. `git status --short` colado: só arquivos sob `web/` e `validar/`. Zero linhas de `dbt/`,
    `app/`, `sql/`, `infra/`.
11. `infra\publicar.ps1` rodado, serviço `app_compras` em `Running`, e os itens 1, 2 e 3
    conferidos **em `http://192.168.0.50/`** — não no Vite da máquina de desenvolvimento.
12. Relatório final nomeando, em uma linha cada: o que mudou de número na tela, o que
    deliberadamente **não** mudou (§3.4), e a resposta às perguntas A e B se o Diretor já a
    tiver dado.
