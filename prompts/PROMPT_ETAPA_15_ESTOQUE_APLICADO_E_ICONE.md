# Etapa 15 — Estoque na precificação, preço aplicado e o ícone da aba

> **Prompt de execução.** Origem: pedido do usuário no prompter, 16/09/2026, cinco pontos
> escritos de uma vez, mais uma resposta dele no mesmo dia que decidiu a fonte da data do
> ponto 2 (§1.1).
>
> Base: repositório `app_compras_v2`, commit `fbfc626` ("A decisão de compra da tela do
> produto vai para o carrinho"), com a Etapa 14 (migração) já executada em 12/09 e as
> Etapas 12 e 13 no ar. O prompt parte do código como ele está hoje — não do protótipo, e
> nunca da pasta `app_compras`, que está congelada.
>
> **Quatro dos cinco pontos não mudam número: mudam onde um número que já existe aparece.**
> O quinto — o ponto 2, depois da resposta de §1.1 — **acrescenta duas colunas de data à
> cadeia do dbt**. Não altera nenhuma fórmula, nenhuma margem, nenhum preço: passa uma data
> que já existe no WinThor por três models até o schema `COMPRAS`. Mas mexe em
> `int_cadastro_estoque`, que é a espinha de quatro models intermediários — inclusive o de
> margem. É por isso que a etapa abre pelo dbt e que o `dbt-regras` entra em `opus` (§8.2).

---

## 1. Os cinco pontos, verbatim

1. *"criar uma tag também para os lotes de aplicado, caso todos os preços tenham sido
   aplicados."*
2. *"Quando a alteração de preços for aplicada, não mostrar o "preço decidido" ba tela
   tabela onde tem os preços. Assim que aplicado, é como se "resetasse" e aquele preço é o
   definido. Deve ser criado um texto com a última data que o preço foi alterado."*
3. *"Incluir coluna com estoque também na tabela de preços depois da coluna de "última
   entrada". Deve ter uma cor diferente, laranja talvez."*
4. *"criar um filtro de "com/sem estoque" tanto na tela da tabela de pedidos e também de
   precificação"*
5. *"incluir um ícone para aparecer na aba do navegador que está no caminho
   C:\Users\Administrator\Desktop\app_compras_v2\carrinho-de-compras.png"*

### 1.1 A resposta que fechou o ponto 2 — 16/09/2026

Perguntado de qual data se trata ("a data em que o preço mudou no WinThor" ou "a data em
que a decisão foi gravada no app"), com o custo de cada uma na mesa:

> *"deve ser quando a alteração foi realizada no sistema"*

e, com as duas leituras lado a lado, a escolha explícita foi **"Quando o preço mudou no
Winthor"**, ciente de que isso custa trabalho de dbt.

**O raciocínio que fechou a escolha, e que manda no desenho todo do §4:** depois do
"reset", a tela mostra o preço **do WinThor** — então a data ao lado dele tem de ser a data
**daquele** preço. Texto e número falando da mesma coisa. `APP_DECISAO_PRECO.ATUALIZADO_EM`
é a data do **ato de decidir**: outro momento, outra pessoa, outra tabela. Ela não some do
projeto (§4.7) — fica onde já serve, acompanhando o **valor decidido**.

Os pontos **1 e 2 são a mesma máquina de estados vista dos dois lados**: "aplicado" já é
medido e nunca declarado desde a Etapa 12, e os dois pedidos são consequências disso que
ainda não tinham sido tiradas. O 3 e o 4 são o mesmo dado (`EST_DISP`) em duas telas. O 5 é
de quinze minutos e tem uma armadilha de publicação.

---

## 2. O que foi medido — 16/09/2026

Leitura, só `SELECT`. As consultas de `COMPRAS` são as de sempre; as de `CEDEP.PCTABPR`
foram feitas com o **mesmo privilégio de leitura que o dbt já usa** (a `source('cedep',
'pctabpr')` de `stg_preco_tabela`), para decidir o desenho do §4 — **nunca** para o
dashboard ler de lá, o que continua proibido.

**Recontar antes de usar como critério de aceite**: `APP_DECISAO_PRECO` e os lotes crescem a
cada uso da tela, `EST_DISP` muda a cada `dbt run` e `DTULTALTPVENDA` muda a cada preço
digitado na rotina 201.

### 2.1 Decisões, lotes e estoque (schema `COMPRAS`)

| Fato | Número medido |
|---|---|
| `APP_DECISAO_PRECO` | **28 linhas**, todas com atacado **e** varejo decididos; todas gravadas em 14/09/2026 entre 11:43 e 11:58; `ATUALIZADO_EM` é `NOT NULL` e está preenchida nas 28 |
| `APP_DECISAO_PRECO_HIST` | **0 linhas** — segue vazia (o achado da Etapa 14 continua de pé; §4.7 explica por que isso não é defeito) |
| Decisões já aplicadas | **28 de 28** no atacado e **28 de 28** no varejo (`abs(PV_* − ALT_PV_*_AV) < 0,005`) |
| As decisões eram mudança de verdade? | Sim: nos 28 itens de lote, `PV_*_ATUAL` (snapshot) **difere** de `PV_*_NOVO` nos dois canais. Não houve um único "decidiu o preço que já valia" |
| `APP_LOTE_PRECO` | **2 lotes**, ambos `Enviado`, 28 itens no total, **28 aplicados** → os **2** ganham a tag do ponto 1 |
| `EST_DISP` em `COMPRAS_PEDIDO` | 8.841 SKUs, **zero nulos**, **zero negativos**; 3.386 com `> 0`; 5.455 com `= 0` |
| Ativos (o filtro padrão das duas telas) | 4.558 → **3.305 com estoque**, **1.253 sem** (destes, 567 ainda vendem) |
| Inativos | 4.283 → 81 com, 4.202 sem |
| Estoque fracionário | 106 SKUs com `EST_DISP > 0` não inteiro; **10 ativos com `0 < EST_DISP < 1`**, o menor 0,0833 (SKU 5290, YPF, embalagem 12X1 LT: **1 litro solto de uma caixa de 12**) |
| Departamentos MASTER (`FATOR_EXIBICAO > 1`) | 508 SKUs, 223 deles com estoque |
| Colunas de data em `COMPRAS_PEDIDO` | só `DT_ULT_ENT` e `DT_ULT_SAIDA` — **não existe** data de alteração de preço em lugar nenhum do schema `COMPRAS` hoje |

### 2.2 `CEDEP.PCTABPR.DTULTALTPVENDA` — a fonte nova do ponto 2

| Pergunta | Resposta medida |
|---|---|
| Grão | **8.848 linhas por região**, 8.848 SKUs distintos, **zero pares `(CODPROD, NUMREGIAO)` duplicados** → o subselect escalar que já lê `PVENDA` é seguro para a data também |
| Cobertura dos 8.841 SKUs de `COMPRAS_PEDIDO` | **todos** têm linha nas duas regiões (0 sem linha em 1, 0 sem linha em 2) |
| Data **nula** | **650 SKUs** (mesmo número nas duas regiões); entre os **ativos**, **226 de 4.558** |
| Data zerada / no futuro | **nenhuma**. Mais antiga **06/06/2013**, mais recente **15/09/2026** |
| Distribuição (atacado) | 2026: **4.986** · 2025: 723 · 2024: 105 · 2023: 197 · 2022: 122 · 2021: 608 · 2020: **1.365** · 2016: 81 · 2013: 4 |
| As duas regiões concordam? | **Não sempre.** Dos 8.191 SKUs com as duas datas: **8.112 iguais, 79 diferentes**, e o **maior intervalo é de 454 dias** |
| Nos 28 SKUs decididos | decisão em **14/09 11:43**, alteração no WinThor em **14/09 17:17** — mesmo dia, ~5h30 depois. ⚠ **Truncadas no dia, as duas datas são iguais** (ver §10, critério 7) |
| `PVENDA` (região 2, ao vivo) × `COMPRAS_PEDIDO.PV_ATACADO` (última carga) | batem em 7.449 de 8.841 — **1.392 divergem**, que é a defasagem normal entre o CEDEP ao vivo e a foto do último `dbt run` |

Essa última linha é o argumento decisivo de desenho: **a data tem de viajar pela cadeia do
dbt, fotografada no mesmo build que o preço.** Uma data lida ao vivo (além de furar a
fronteira) apareceria ao lado de um preço de outra carga em 1.392 SKUs — texto e número
discordando na mesma célula, que é exatamente o que a resposta de §1.1 quer evitar.

---

## 3. Ponto 1 — a tag de lote aplicado

**Muda número? Não.** Os dois números que a tag resume já são calculados no banco e já
chegam na tela.

### 3.1 O dado já existe, agregado em SQL

`app/servicos/lote_preco.py:117-131` agrega **no próprio `select`** da listagem:
`qtd_itens` e `qtd_aplicados`, com a tolerância `_TOLERANCIA_APLICACAO = 0.005`
(linha 72) escrita dentro do SQL para nunca divergir do `_status_canal` em Python.
`app/api/contrato.py:lote_preco` devolve os dois como `qtdItens` e `qtdAplicados` — na
**lista** (`listar_lotes`) e no **detalhe** (`obter_lote`). A tela já os desenha como
texto: `web/src/telas/PrecosDefinidos.jsx:190` ("28 de 28 aplicado(s)") e
`web/src/telas/LotePrecoDetalhe.jsx:136`.

Ou seja: a informação está na tela desde a Etapa 12. O que o pedido quer é que ela **salte
aos olhos** quando estiver completa, em vez de exigir a leitura de dois números.

### 3.2 Decisão: a tag é **apresentação**, não estado novo, nem coluna derivada

Não entra valor novo em `APP_LOTE_PRECO.STATUS`. O domínio tem dois valores
(`Rascunho`, `Enviado`), garantido por `CK_APP_LOTE_PRECO_STATUS` em
`sql/05_tabelas_lote_preco.sql`, e a ausência de um terceiro valor "Aplicado" **é uma
decisão documentada em quatro lugares** (o `comment on column` do STATUS, o comentário de
cabeçalho de `web/src/lotePrecoStatus.js`, o de `lote_preco.py` e o `comment on table` do
histórico): não há usuário no app para quem digita o preço no WinThor, então ninguém daria
o clique — e o sistema já mede a aplicação de graça. Gravar agora um status que só pode ser
derivado seria criar duas versões do mesmo fato, uma delas capaz de mentir.

Também **não** é coluna nova no JSON: `qtdItens` e `qtdAplicados` já viajam, e a regra cabe
em uma linha no front.

O que entra, em `web/src/lotePrecoStatus.js`, ao lado de `COR_SITUACAO`/`ROTULO_SITUACAO`
que já existem:

```js
/** O lote inteiro aplicado — `qtdAplicados >= qtdItens`, com `qtdItens > 0` para que
 *  um lote vazio não se declare aplicado por vacuidade. Mesma medição do item
 *  (`_situacao_item` no servidor), agregada; nunca um status gravado. */
export const loteAplicado = (l) => (l.qtdItens ?? 0) > 0 && (l.qtdAplicados ?? 0) >= (l.qtdItens ?? 0);
```

### 3.3 Como a tag aparece, e por que diferente do chip de status

Nos **dois** lugares onde o chip de status aparece hoje — `PrecosDefinidos.jsx:178-182`
(cartão da lista) e `LotePrecoDetalhe.jsx:133` (cabeçalho) —, logo **depois** do chip de
status:

- rótulo **"Aplicado"**, cor `COR_SITUACAO.aplicado` (`#15803D`, a mesma do item aplicado —
  a tela não pode ter dois verdes para a mesma ideia);
- estilo **contornado** (borda + texto na cor, fundo transparente), enquanto o chip de
  status é **preenchido** (`background: <cor>18`). Dois chips lado a lado com a mesma
  aparência seriam lidos como dois valores da mesma máquina de estados — exatamente o
  terceiro status que o projeto decidiu não ter. A diferença visual é o que diz "isto é de
  outra natureza";
- ícone `Check` de 11px do `lucide-react` (já importado no projeto — **sem dependência
  nova**);
- `title` com a frase de conferência que já existe: `textoConferencia(atualizacao)` de
  `lotePrecoStatus.js` → *"Todos os N itens já estão com o preço novo no banco — conferido
  com os dados de 16/09 às 06:05"*.

A linha de texto "N de M aplicado(s)" **continua** onde está, nos dois lugares. Ela é a
evidência por trás da tag, é o único informe útil no lote parcial, e é a coluna a que a
ordenação `qtdAplicados` se refere.

### 3.4 A tag aparece também em lote `Rascunho`?

**Sim.** A tag afirma um fato medido contra o banco, e suprimi-la por causa do status faria
a tela esconder algo que é verdade (o preço foi aplicado no WinThor antes de o documento ser
marcado como enviado — possível, e vale saber). O chip de status ao lado continua dizendo
`Rascunho`, então não há ambiguidade sobre o que é o quê.

### 3.5 O que **não** fazer no ponto 1

- Não acrescentar `"Aplicado"` ao array `STATUS` de `lotePrecoStatus.js`: ele alimenta os
  botões de filtro de `PrecosDefinidos.jsx:80` e o `semNenhum` da linha 69, e é o espelho do
  `CHECK` do banco. Um terceiro elemento ali pediria um filtro no servidor que não existe e
  quebraria a contagem de "nenhum lote ainda".
- Não criar filtro "só os aplicados". Não foi pedido, e a ordenação por **Aplicados** já
  existe no seletor (`PrecosDefinidos.jsx:104`).
- Não tocar em `sql/05_tabelas_lote_preco.sql`. Nenhuma DDL nesta etapa.

---

## 4. Ponto 2 — o preço decidido some quando já está aplicado, e entra a data do WinThor

**Muda número? A tela, não** — nenhum valor é recalculado, muda o que a célula mostra e com
que valor o campo nasce. **O dbt, sim, em extensão:** duas colunas de data novas em
`COMPRAS_PRODUTO_CONTEXTO`. Nenhuma fórmula, nenhuma margem, nenhum preço muda — e §4.4
mostra por que isso é garantido por construção, não por cuidado.

É o ponto de maior risco dos cinco: mexe na tela onde uma pessoa decide preço de venda, e
na espinha de que o model de margem depende.

### 4.1 O que a tela faz hoje

Em `web/src/telas/Precificacao.jsx`:

- linhas **607-612**: o campo de edição **nasce preenchido** com
  `p.precoDecididoAtacadoAV` / `precoDecididoVarejoAV` quando o mapa de digitação ainda não
  tem entrada para o SKU;
- linhas **769-772** (`CelulaEdicao`): abaixo do campo, a linha azul **"decidido R$ 66,00"**;
- linhas **776-780**: com decisão presente, a sugestão do cenário desce para uma segunda
  linha cinza ("sugerido R$ ...").

O mesmo par existe na tela de um SKU só: `web/src/telas/DecisaoSKU.jsx:399` (o campo nasce
com `paraCampoPreco(decidido)`), **415** (o `useEffect` que o reinicia) e **517-521**
("Já decidido: R$ ...").

Os dois valores vêm **ao vivo** de `APP_DECISAO_PRECO`, pelo `left join d` de
`app/servicos/produto.py:_DE` — não da cópia materializada em `COMPRAS_PEDIDO`. Isso está
certo e não muda: é o que faz a tela mostrar a decisão recém-gravada em vez do valor velho
do último `dbt run` (regra 10 do `CONTEXTO.md`).

### 4.2 Quando um preço está "aplicado", aqui

Mesma medida do lote, aplicada à linha que a tela já tem em mãos, **por canal**:

```
aplicado(atacado) := precoDecididoAtacadoAV != null && |pvAtacado − precoDecididoAtacadoAV| < 0,005
```

`pvAtacado`/`pvVarejo` vêm de `COMPRAS_PEDIDO` (o preço que está no WinThor na última
carga); o decidido vem de `APP_DECISAO_PRECO`. A tolerância já existe no front:
`TOLERANCIA_PRECO_IGUAL = 0.005` em `web/src/precificacao.js:32`, o mesmo 0,005 de
`_TOLERANCIA_APLICACAO` no servidor.

**Decisão: a função mora em `web/src/precificacao.js`, exportada, e as duas telas a
chamam** — nunca duas comparações escritas à mão. É a mesma dívida que o projeto já paga em
`int_produto_pedido.sql` × `compra.py` (a fórmula do valor do pedido em dois lugares sem
teste que os compare); não se abre uma segunda igual de propósito.

```js
/** "O preço decidido por gente já é o preço que está no banco" — por canal.
 *  Cobre dois casos que a tela não precisa distinguir: o preço foi aplicado no
 *  Winthor, ou o valor decidido já era o vigente. Nos dois, repetir "decidido
 *  R$ 66,00" ao lado de um "Atacado atual R$ 66,00" é ruído. */
export const precoJaAplicado = (precoAtual, precoDecidido) =>
  precoDecidido != null && precoAtual != null
  && Math.abs(precoAtual - precoDecidido) < TOLERANCIA_PRECO_IGUAL;
```

⚠ **A conferência tem a idade do último `dbt run`.** `PV_ATACADO`/`PV_VAREJO` só mudam na
próxima carga: um preço digitado no WinThor às 10h continua aparecendo como "decidido, não
aplicado" até a carga seguinte. É a mesma contrapartida já assumida e documentada para a
coluna "Aplicados" dos lotes (§4.5 da Etapa 12) — **não é defeito, e não se conserta lendo
o CEDEP**. A tela já carrega o carimbo da carga no cabeçalho.

### 4.3 Os três estados da célula

| Estado | Campo de edição | Linha de apoio |
|---|---|---|
| Sem decisão gravada | vazio, `placeholder` = sugestão do cenário (**como hoje**) | só "Pz ..." |
| Decidido, **ainda não aplicado** | nasce com o valor decidido (**como hoje**) | **"decidido R$ 66,00 · 14/09/26"** — o valor decidido, com a data da **decisão** |
| Decidido e **aplicado** | **nasce vazio**, `placeholder` volta a ser a sugestão | **"preço alterado em 14/09/26"**, em cinza (`#6B7280`) — a data da alteração **no WinThor**; some o "decidido" |

O "resetasse" do pedido é literalmente isto: o campo volta ao estado de quem não tem
decisão pendente, porque não há mais decisão pendente — o preço decidido virou o preço
vigente. A segunda linha cinza "sugerido R$ ..." (Precificacao.jsx:776) só existe para
compensar o placeholder ocupado; **no estado aplicado ela sai**, porque o placeholder
voltou a mostrar a sugestão.

**As duas datas não são a mesma, e é de propósito** (§1.1): cada linha traz a data da fonte
do número que está ao lado dela. Valor decidido → data da decisão (`APP_DECISAO_PRECO`).
Preço vigente → data da alteração no WinThor (`PCTABPR`). Nunca cruzar as duas.

**Data nula (650 SKUs, 226 deles ativos):** o texto vira **"preço aplicado"**, sem data —
mesma cor cinza. Não some por completo: sem nenhuma linha de apoio, um SKU aplicado ficaria
visualmente idêntico a um SKU nunca decidido, e a tela perderia a informação de que existe
decisão gravada. E não se inventa "alterado em —": o traço não é uma data.

### 4.4 A cadeia do dbt — **três models, e `int_produto_margem` não é um deles**

A rota óbvia (`stg_preco_tabela` → `int_cadastro_estoque` → `int_produto_margem` →
`fat_pedido` → `compras_pedido`) é a errada, e não por ser longa: `fat_pedido` reproduz as
**122 colunas** da aba `pedido` da planilha e `compras_pedido` é projeção pura dele. Uma
coluna a mais em qualquer um dos dois **quebra de uma vez** os testes
`compras_fat_pedido_122_colunas` e `compras_app_pedido_espelha_fat`, além da validação
célula a célula contra a V10/V11, que casa coluna pelo nome.

Já existe um lugar feito exatamente para isto, e o cabeçalho dele diz isso com todas as
letras: **`COMPRAS_PRODUTO_CONTEXTO`** — *"contexto que a planilha não tem mora aqui, ao
lado, e é juntado por CODIGO"*. Ele já tem grão de 1 linha por SKU, já cobre o mesmo
universo de `COMPRAS_PEDIDO` (com teste nos dois sentidos), **já lê `int_cadastro_estoque`**
(`compras_produto_contexto.sql:129`, CTE `cadastro`, com `left join ... on c.codprod =
p.codigo` no `final`) e **já está no `left join ctx` do serviço**
(`app/servicos/produto.py:_DE`). A cadeia fica em três arquivos:

| # | Arquivo | O que entra |
|---|---|---|
| 1 | `dbt/compras/models/staging/stg_preco_tabela.sql` | `DTULTALTPVENDA as data_ultima_alteracao_preco` — o model tem 14 linhas e já traz `CODPROD`, `NUMREGIAO` e `PVENDA` da mesma linha |
| 2 | `dbt/compras/models/intermediate/int_cadastro_estoque.sql` | **dois subselects escalares**, colados logo abaixo dos de `pv_atacado`/`pv_varejo` (linhas 137-141), com a **mesma resolução de região** |
| 3 | `dbt/compras/models/app/compras_produto_contexto.sql` | `c.dt_ult_alt_pv_atacado as DT_ULT_ALT_PV_ATACADO` e `c.dt_ult_alt_pv_varejo as DT_ULT_ALT_PV_VAREJO`, no `final`, ao lado de `c.qt_ult_saida` |

Mais a documentação obrigatória nos três `schema.yml` correspondentes (convenção do projeto:
coluna sem `description` não entra).

**O que muda em `int_produto_margem`: nada.** Nem uma linha. E isso é seguro por
construção, não por cuidado — verificado arquivo por arquivo:

- os quatro consumidores de `int_cadastro_estoque` (`int_produto_base:74`,
  `int_produto_demanda:99`, `int_produto_fiscal:141`, `int_produto_margem:125`) importam o
  model numa CTE `select *`, mas **todos terminam em `select * from final`, com `final`
  listando colunas explicitamente**. Coluna nova na espinha não vaza para a saída de
  nenhum deles;
- `fat_pedido` (linhas 149-283) lista as 122 colunas uma a uma, com a letra do gabarito ao
  lado. Nada entra lá por acidente;
- `int_produto_margem:125-133` importa `cadastro` e usa **exatamente duas** colunas dela
  (`cad.pv_atacado`, `cad.pv_varejo`, linhas 142-143), dentro da CTE `entrada`, de lista
  explícita.

Quem executar **tem de confirmar isso rodando os testes**, não lendo:
`compras_fat_pedido_122_colunas`, `compras_app_pedido_espelha_fat`,
`compras_produto_contexto_grao_unico`, `compras_produto_contexto_cobre_pedido`,
`compras_produto_contexto_ano_passado_bate_pivot` e
`compras_produto_contexto_regime_segue_modalidade` — todos já existem em
`dbt/compras/tests/` e todos têm de continuar passando.

**Não editar `fat_pedido.sql`, `compras_pedido.sql`, `int_produto_margem.sql`,
`int_produto_custo.sql`, `int_produto_fiscal.sql` nem `int_produto_base.sql`.** Se a
implementação parecer precisar de qualquer um deles, o desenho saiu do trilho — **parar e
reportar**, não improvisar.

### 4.5 ⚠ A região: **duas datas, uma por canal** — a mesma resolução que o preço já usa

`PCTABPR` é preço **por região**, e `int_cadastro_estoque:136-141` já resolve isso com dois
subselects escalares e um comentário explícito: *"precos (regiao 1 = VAREJO / regiao 2 =
ATACADO)"*. A data segue **a mesma regra, no mesmo `select`**:

```sql
-- precos (regiao 1 = VAREJO / regiao 2 = ATACADO)
(select pt.preco_venda from preco_tabela pt
  where pt.id_produto = e.id_produto and pt.id_regiao = 2)   as pv_atacado,
(select pt.preco_venda from preco_tabela pt
  where pt.id_produto = e.id_produto and pt.id_regiao = 1)   as pv_varejo,
-- ⚠ A data de alteração acompanha o PREÇO DA MESMA REGIÃO, subselect por
-- subselect. Não é a mais recente entre as duas, nem uma região canônica:
-- medido em 16/09/2026, 79 dos 8.191 SKUs com as duas datas têm datas
-- DIFERENTES entre atacado e varejo, e o maior intervalo é de 454 dias.
-- Uma data só apareceria errada nesses 79, ao lado do preço do outro canal —
-- e a tela mostra os dois canais lado a lado, um do lado do outro.
(select pt.data_ultima_alteracao_preco from preco_tabela pt
  where pt.id_produto = e.id_produto and pt.id_regiao = 2)   as dt_ult_alt_pv_atacado,
(select pt.data_ultima_alteracao_preco from preco_tabela pt
  where pt.id_produto = e.id_produto and pt.id_regiao = 1)   as dt_ult_alt_pv_varejo
```

O grão foi conferido: **zero pares `(CODPROD, NUMREGIAO)` duplicados** em 8.848 linhas por
região, então o subselect escalar não corre risco de `ORA-01427` — e continua sendo o mesmo
risco que `PVENDA` já corre desde sempre.

Inventar uma segunda regra de região para a data — "a mais recente", "só o atacado" — seria
criar divergência silenciosa entre o preço exibido e a data exibida em 79 SKUs. **Não
fazer.**

### 4.6 A data antiga e o nulo — decididos aqui, não na hora

- **Sem corte por idade.** A distribuição vai de 06/06/2013 (4 SKUs) a 15/09/2026, com
  1.365 SKUs em 2020 e 4.986 em 2026. "Preço alterado em 12/03/2019" é **verdade** e é
  informação de valor — preço parado há anos é sinal, não ruído. Além disso, o texto só
  aparece no estado **aplicado**, que exige decisão gravada: por construção, quem chega lá
  tem data recente. Esconder data velha atrás de um corte esconderia justamente o caso raro
  que mereceria atenção.
- **Nulo (650 SKUs, 226 ativos):** tratado na tela, não no dbt — a coluna fica **nula**,
  nunca com data inventada nem `nvl(..., sysdate)`. A tela escreve **"preço aplicado"** sem
  data (§4.3).
- **Zerada não existe** e **futuro não existe** — medido. Nada de saneamento defensivo no
  SQL: filtro que nunca filtra é código que ninguém sabe se funciona.

### 4.7 `APP_DECISAO_PRECO.ATUALIZADO_EM` **fica** — no lugar dela

A resposta de §1.1 trocou a fonte de **um** texto; não aposentou o campo.

- `preco.obter_cenarios` (`app/servicos/preco.py:58-68`) continua lendo
  `atualizado_em`/`atualizado_por` como hoje. **Não mexer.**
- Ela passa a alimentar a data do estado **"decidido, ainda não aplicado"** (§4.3), onde é
  a fonte certa: acompanha o **valor decidido**, que é o número ao lado.
- ⚠ **`APP_DECISAO_PRECO_HIST` continua vazia: 0 linhas, medido de novo hoje.**
  `preco.py:_gravar_decisao_preco_conn` só insere histórico quando **já existia** valor
  anterior, e nenhum dos 28 SKUs foi decidido duas vezes. **Isso não é defeito e não se
  "conserta" nesta etapa**: a tabela guarda o valor que **saiu**; na primeira gravação não
  há valor saindo, e inserir uma linha de nulos ali destruiria justamente o que ela serve
  para responder. Nenhuma das duas datas depende dela.

### 4.8 O que muda no backend — três linhas

Em `app/servicos/produto.py:_COLUNAS`, junto do bloco `ctx.` que já existe (linha 71) e do
bloco `d.` (linhas 61-65):

```sql
ctx.dt_ult_alt_pv_atacado, ctx.dt_ult_alt_pv_varejo,
d.atualizado_em                                    as decisao_atualizado_em,
```

Em `app/api/contrato.py:produto()`, ao lado de `precoDecididoAtacadoAV` (linha 355):

```python
"precoAlteradoEmAtacado": _data(p.get("dt_ult_alt_pv_atacado")),
"precoAlteradoEmVarejo":  _data(p.get("dt_ult_alt_pv_varejo")),
"precoDecididoEm":        _data(p.get("decisao_atualizado_em")),
```

**`_data`, não `_dt`**, nas três. `_dt` carregaria a hora, e alguém acabaria imprimindo
"14/09 11:43" — sugerindo uma precisão que nenhuma das duas datas tem para o que a frase
promete. E `data(iso)` de `formato.js:109` **quebra** se receber um ISO com hora (o
`split("-")` devolveria `"14T11:43:00"` como dia): mais uma razão para truncar no dia na
borda do JSON.

`produto.obter` (linha 411) usa o **mesmo** `_COLUNAS`, então a `DecisaoSKU` recebe os três
campos sem nenhum trabalho adicional.

### 4.9 O que **não** fazer no ponto 2

- **Não ler o CEDEP fora do dbt.** Nem no serviço, nem "só para conferir a data". A data
  chega por `COMPRAS_PRODUTO_CONTEXTO` e por mais nada — e §2.2 mostra o preço disso em
  números: o CEDEP ao vivo já discorda de `COMPRAS_PEDIDO` em 1.392 SKUs.
- **Não mexer na captura de `decidido` do lote.** `Precificacao.jsx:617-623` guarda, junto
  do que foi digitado, o `precoDecidido*AV` daquele instante, e `alteracoesLote`
  (linhas 182-191) usa isso para decidir se a digitação é alteração de verdade. Esconder a
  linha na tela **não** pode esconder o valor dessa comparação: com o campo nascendo vazio,
  a entrada no mapa só passa a existir quando a pessoa digita, e o `decidido` capturado
  continua vindo do JSON. Nada a alterar ali — e nada a "simplificar".
- **Não mexer no `podeGravar` da `DecisaoSKU`** (linha 433). Ele compara o digitado com
  `decidido`, e no estado aplicado `decidido == pvAtacado`: digitar o mesmo número continua
  sendo "nada a gravar", que é o comportamento certo.
- Não remover o campo de edição nem torná-lo somente-leitura no estado aplicado. "Resetar"
  é voltar ao campo em branco, não travar a tela: decidir um preço novo por cima de um
  aplicado é o uso normal.
- Não gravar nada de novo em `APP_DECISAO_PRECO_HIST`, nem "backfillar" as 28 linhas.
- Não acrescentar alerta, KPI ou ordenação sobre as datas novas. Elas entram para um texto;
  o resto é outra conversa.

---

## 5. Ponto 3 — coluna de estoque na tabela de Precificação

**Muda número? Não.** `estDisp` já viaja no JSON desde a Etapa 7
(`app/api/contrato.py:271`), lido de `p.est_disp` em `produto.py:_COLUNAS:37`. A tela de
Precificação simplesmente não desenha. **Zero mudança de API.**

### 5.1 Onde entra

Em `web/src/telas/Precificacao.jsx`, **depois** da coluna "Últ. entrada" (cabeçalho na
linha 572, célula nas 678-682) e **antes** do bloco azul de atacado — exatamente o lugar
pedido.

Cabeçalho **clicável**: `coluna="estoque" padrao="desc"`. A chave já existe no whitelist do
servidor (`produto.py:ORDENACOES["estoque"] → ("p.est_disp", "desc")`, linha 120), então não
há nada a acrescentar no backend.

⚠ E, junto: acrescentar `estoque: "Estoque"` ao `ROTULO_COLUNA` de `Precificacao.jsx:67-74`.
Sem isso, ordenar pela nova coluna deixa o `<select>` "Ordenar por" **sem `<option>`
casada** e ele renderiza **em branco** — é o ajuste 2 do revisor de 13/09, já pago duas
vezes neste projeto.

### 5.2 A cor

`#FFF7ED` de fundo (laranja-50) e `#C2410C` no número (laranja-700). A paleta das tabelas é
toda Tailwind-50/100 — `#EFF6FF` azul-50, `#DBEAFE` azul-100, `#F0FDF4` verde-50,
`#DCFCE7` verde-100, `#FAF5FF` roxo-50 —, então o laranja entra na mesma família e não
disputa com as faixas de atacado (azul) e varejo (verde) que organizam a leitura das 15
colunas. Constante nomeada no topo do arquivo, junto de `FUNDO_AT`/`FUNDO_VAR`:
`const FUNDO_EST = "#FFF7ED";`.

### 5.3 ⚠ `FATOR_EXIBICAO`: **não dividir de novo**

`EST_DISP` **já vem dividido**: `int_produto_demanda.sql:138` —
`nvl(c.qtdisp, 0) / r.fator_exibicao as est_disp`. A coluna está em unidade de exibição
(caixa, nos 508 SKUs de departamento MASTER). Dividir outra vez na tela erraria por 12 ou
24 em 223 SKUs com estoque. É a regra 6 do `CONTEXTO.md` na direção oposta à da armadilha
famosa: aqui o defeito é dividir, não deixar de dividir.

### 5.4 O formato, e os 10 SKUs que o `numero(v, 0)` apagaria

`Pedidos.jsx:442` imprime `numero(p.estDisp, 0)`. Com 0 casas, os **10 SKUs ativos com
`0 < EST_DISP < 1`** aparecem como **"0"** — e a partir do ponto 4 eles estarão dentro do
filtro "com estoque" mostrando zero na coluna de estoque. Uma tela que se contradiz na
mesma linha.

**Decisão:** um formatador só, em `web/src/formato.js`, usado pelas **duas** telas:

```js
/** Quantidade de estoque em unidade de exibição (EST_DISP já vem dividido por
 *  FATOR_EXIBICAO). Inteiro sem casas; fracionário com 2 — 1 litro solto de uma
 *  caixa de 12 vale 0,08 e não pode ser impresso como "0" numa linha que o
 *  filtro classificou como "com estoque". 10 SKUs ativos hoje, o menor 0,0833. */
export const quantidadeEstoque = (v) =>
  v == null ? "—" : numero(v, Number.isInteger(v) ? 0 : 2);
```

`Pedidos.jsx:442` passa a usar o mesmo formatador. As colunas vizinhas (`pendente`,
`estPend`) ficam como estão — não foram pedidas, e mexer nelas alarga a etapa sem motivo.

### 5.5 O que **não** fazer no ponto 3

- Não mostrar `estDisp + estPend` ("EST+PED") nem a coluna de pendente. O pedido é
  "coluna com estoque"; a Precificação já tem 15 colunas.
- Não escrever a unidade ("cx"/"un") na célula: a Precificação já está no limite de largura,
  e `Pedidos.jsx` não escreve. A embalagem está na tela do produto.
- Não acrescentar KPI, total nem soma de estoque no topo.

---

## 6. Ponto 4 — filtro "com/sem estoque" em Pedidos e Precificação

**Muda número? Não.** Muda quais linhas entram na lista. Nenhum valor existente é
recalculado — e a contagem do rodapé (`total`) passa a refletir o recorte, como já faz para
os outros filtros.

### 6.1 As duas telas compartilham o mesmo servidor

`Pedidos.jsx` e `Precificacao.jsx` chamam a mesma `GET /api/produtos`
(`api.produtos` em `web/src/api/cliente.js:100`), que cai em `produto.listar` →
`produto._condicoes` (linha 200). **Um filtro no servidor atende as duas telas.**

### 6.2 O corte, decidido com o número na mão

```sql
-- com: nvl(p.est_disp, 0) > 0
-- sem: nvl(p.est_disp, 0) <= 0
```

- **`> 0`, não `>= 1`.** Com `>= 1`, os 10 SKUs ativos de estoque fracionário — entre eles o
  5290 (YPF, 12X1 LT, 1 litro solto = 0,0833 caixa) — seriam classificados como **sem
  estoque** tendo produto físico na prateleira. O sinal não muda com a divisão pelo
  `FATOR_EXIBICAO` (o fator é sempre positivo), então o corte `> 0` vale igual nas duas
  unidades.
- **Nulo e negativo caem em "sem".** Hoje `EST_DISP` não tem nulo nem negativo em nenhum dos
  8.841 SKUs — o `nvl` e o `<= 0` existem para o dia em que houver (devolução lançada antes
  da saída produz estoque negativo no WinThor). O importante é que os dois ramos formem uma
  **partição**: `com + sem = total`, sempre, sem SKU sumindo das duas listas. Isso é
  critério de aceite, não observação.
- **Ausente = todos**, como todo filtro desta rota.

Contagem de hoje, com `status=Ativo` (o padrão das duas telas): **3.305 com / 1.253 sem**,
de 4.558. Sem filtro de status: 3.386 / 5.455, de 8.841. O filtro não nasce inútil em
nenhum dos dois lados — e, dos 1.253 ativos sem estoque, **567 têm média de venda > 0**
(ruptura de verdade) e 686 não vendem.

### 6.3 Onde o código muda

- `app/api/rotas.py:listar_produtos` (assinatura na linha 149): parâmetro
  `estoque: str | None = None`, validado junto dos outros — `if estoque not in (None, "com",
  "sem"): raise HTTPException(422, ...)`, no mesmo bloco onde `ordenar` e `dir` são
  validados (linhas 179-184). **Entrada de usuário virando `where` passa por whitelist** —
  mesma regra que já vale para `ordenar`. E entra em `filtros` (linha 199).
- `app/servicos/produto.py:_condicoes`: o bloco novo vai **antes** do
  `if not incluir_alerta` (linha 244), para que valha também no `resumo`/contagem dos
  KPIs — senão o número do botão de alerta passaria a discordar da lista.
- Front: componente **compartilhado** `web/src/componentes/FiltroEstoque.jsx`, molde
  `FiltroUltimaEntrada.jsx` (que já serve as duas telas). Três botões no mesmo padrão
  visual do grupo "Status" (`Pedidos.jsx:235-247`): **Todos · Com estoque · Sem estoque**,
  com `aria-pressed`. Colocado logo **depois** do grupo Status nas duas telas.
- Estado local (`useState`) nas duas telas, **não na URL**: o par `ordenar`/`dir` vive na
  URL porque o cabeçalho clicável e o dropdown precisam do mesmo estado compartilhado
  (Etapa 13 §3.3); `departamento`, `status` e `busca` são `useState`. O filtro novo segue a
  maioria — não se inventa um terceiro padrão.
- Trocar o filtro **zera a página** (`setPagina(1)`), como todos os outros.

### 6.4 O que **não** fazer no ponto 4

- Não filtrar no cliente. A lista é paginada de 50 em 50 no servidor; filtrar a página
  devolveria "12 de 3.305" e pareceria funcionar.
- Não usar `EST_PEND` (estoque + pendente) no corte: "com estoque" é o que está na
  prateleira hoje; o que está por chegar é outra pergunta.
- Não criar um terceiro valor ("negativo", "crítico"): não foi pedido, e hoje não há dado
  que o sustente.

---

## 7. Ponto 5 — o ícone na aba do navegador

**Muda número? Não.**

### 7.1 O arquivo, medido

`C:\Users\Administrator\Desktop\app_compras_v2\carrinho-de-compras.png`: **PNG 512×512,
RGBA 8 bits, não entrelaçado, 22.607 bytes.** Está **fora do controle de versão** (é o único
`??` do `git status` hoje) e na **raiz do repositório**, que não é lugar de asset.

**Serve como está.** Todo navegador atual aceita PNG em `rel="icon"` e reduz para os 16/32px
da aba; 22 KB são baixados uma vez e ficam em cache, e o alvo é um celular na rede interna.
**Nada de converter para `.ico`, nada de redimensionar, nada de biblioteca nova** — o
`package.json` não ganha dependência nesta etapa.

### 7.2 Onde ele passa a morar, e a armadilha

**`web/public/carrinho-de-compras.png`** — a pasta `web/public/` **não existe ainda** e
precisa ser criada. É o `publicDir` padrão do Vite: tudo que está lá é copiado **para a raiz
do `outDir`** no build, sem hash no nome. O arquivo é **movido** da raiz do repositório
(não copiado): a raiz não pode ficar com uma segunda cópia.

⚠ **A armadilha:** `web/vite.config.js` tem `outDir: "../app/static/v2"` **com
`emptyOutDir: true`**. Copiar o PNG à mão para dentro de `app/static/v2` funciona — até a
próxima publicação, que apaga a pasta inteira e leva o ícone junto, **sem erro nenhum em
lugar nenhum**. Por `web/public/` o arquivo é regerado a cada build.

O nome fica `carrinho-de-compras.png`, o mesmo que o usuário apontou: renomear para
`favicon.png` só criaria a dúvida de qual arquivo era.

### 7.3 As duas linhas no `web/index.html`

Dentro do `<head>` (o arquivo tem 17 linhas; entram depois do `theme-color`):

```html
<link rel="icon" type="image/png" href="/carrinho-de-compras.png" />
<!-- O alvo é o celular do Diretor: "adicionar à tela de início" usa este. -->
<link rel="apple-touch-icon" href="/carrinho-de-compras.png" />
```

Caminho **absoluto** (`/...`), não relativo: o react-router usa history, e de
`/precos-definidos/41` um `href` relativo procuraria o ícone em
`/precos-definidos/carrinho-de-compras.png`. O `location /` do nginx
(`infra/nginx/compras.conf`) serve o arquivo direto pelo `try_files $uri` — o app está na
raiz do vhost, então `/carrinho-de-compras.png` resolve.

### 7.4 Publicar, ou nada disso chega ao usuário

O front em produção é estático servido pelo nginx a partir de `app/static/v2`. **O único
caminho** é:

```
powershell -ExecutionPolicy Bypass -File infra\publicar.ps1
```

(`npm ci` + `npm run build` + reinício do serviço `app_compras`). Sem isso, quem abre
`http://compras.cdp.lub` continua vendo o build antigo, **sem erro visível**.

E, ao conferir: **navegador cacheia favicon com agressividade** — validar com recarga forçada
(Ctrl+F5) ou aba anônima. JS e CSS saem do build com hash no nome; o PNG do `public/` não.
Se um dia o ícone mudar, muda-se o **nome do arquivo**, não o conteúdo.

---

## 8. O trabalho, por agente

**A ordem importa, e mudou com a resposta de §1.1.** O ponto 2 deixou de ser o mais barato e
virou o **caminho crítico**: a tela não pode mostrar a data antes de a coluna existir no
banco, e a coluna só existe depois de um `dbt run`. Os pontos 1, 3, 4 e 5 **não dependem do
dbt** — mas se o dbt começar por último, a etapa inteira espera por ele.

Ordem: **`dbt-staging` → `dbt-regras` → `backend-fastapi` → `frontend-react` → `validador` →
`revisor`.**

### 8.1 `dbt-staging` — `model: haiku`. Abre a etapa.

Uma coluna em `dbt/compras/models/staging/stg_preco_tabela.sql` (o model tem 14 linhas):
`DTULTALTPVENDA as data_ultima_alteracao_preco`, no `renamed`, abaixo de `PVENDA`. Mais a
`description` da coluna em `dbt/compras/models/staging/schema.yml`.

É território do agente de staging por definição, e é trivial — não vale pagar opus por ela,
nem misturar dono de arquivo.

**Ler:** `stg_preco_tabela.sql`, `sources.yml` (linhas 44-46), §4.4 e §4.5 deste documento.
**Não ler `REGRAS.md`.**

**Não fazer:** nenhum filtro, nenhum `nvl`, nenhuma conversão. A coluna sobe crua, com o
nome traduzido — é o contrato de staging deste projeto.

### 8.2 `dbt-regras` — `model: opus`. O ponto de maior risco da etapa.

`opus` **não** porque a tarefa muda número — ela não muda —, mas porque mexe em
`int_cadastro_estoque`, que é a espinha de `int_produto_base`, `int_produto_demanda`,
`int_produto_fiscal` e `int_produto_margem`. Um erro ali muda número em 8.841 SKUs, e o
custo do modelo é irrelevante perto disso.

1. `int_cadastro_estoque.sql`: os **dois subselects escalares** de §4.5, colados logo abaixo
   dos de preço (linhas 137-141), com o comentário que explica a regra de região e os 79
   SKUs divergentes.
2. `compras_produto_contexto.sql`: as duas colunas no `final`, ao lado de `c.qt_ult_saida`
   (a CTE `cadastro` e o `left join c` já existem — **não** acrescentar join novo).
3. `description` das colunas nos `schema.yml` de `intermediate/` e `app/`, dizendo de onde
   vêm, qual região cada uma usa, e que **nulo significa "o WinThor nunca registrou
   alteração de preço deste SKU nesta região"** (650 SKUs, 226 ativos) — nunca "nunca
   mudou de preço".
4. Rodar `dbt\rodar_dbt.bat` (~70s) e **os testes**. Os seis nomeados em §4.4 têm de passar.
5. Conferir, com um `select` de leitura, que `COMPRAS_PRODUTO_CONTEXTO.DT_ULT_ALT_PV_ATACADO`
   bate com `CEDEP.PCTABPR.DTULTALTPVENDA (NUMREGIAO=2)` nos 8.841 SKUs, e que os **650
   nulos** continuam nulos.

**Ler:** `int_cadastro_estoque.sql` (linhas 100-160), `compras_produto_contexto.sql`
(cabeçalho e `final`), `dbt/compras/tests/compras_fat_pedido_122_colunas.sql`,
`.../compras_produto_contexto_cobre_pedido.sql`, e §4.4/§4.5/§4.6 deste documento.
**Não ler `REGRAS.md`** — nenhuma regra fiscal, de margem, de curva ABC ou de alerta é
tocada; são 460 linhas e ~7,6 mil tokens sem uso aqui. Se a implementação parecer precisar
delas, o desenho saiu do trilho (§4.4).

**Não fazer:** `fat_pedido.sql`, `compras_pedido.sql`, `int_produto_margem.sql`,
`int_produto_custo.sql`, `int_produto_fiscal.sql`, `int_produto_base.sql` — nenhum deles é
tocado. Nenhum seed muda (e, portanto, nada a dizer sobre `dbt seed` aqui). Nenhuma DDL
escrita à mão: `COMPRAS_PRODUTO_CONTEXTO` é `table`, o dbt derruba e recria com as colunas
novas, e o `post_hook` do índice em `CODIGO` se refaz sozinho.

### 8.3 `backend-fastapi` — `model: sonnet`

1. **Ponto 2**: `ctx.dt_ult_alt_pv_atacado`, `ctx.dt_ult_alt_pv_varejo` e
   `d.atualizado_em as decisao_atualizado_em` em `produto.py:_COLUNAS`; os três campos em
   `contrato.produto()` com `_data` (§4.8). Nada mais — `produto.obter` compartilha o mesmo
   `_COLUNAS`, e o `left join ctx` já existe em `_DE`.
2. **Ponto 4**: parâmetro `estoque` em `rotas.py:listar_produtos` com whitelist
   (`None|"com"|"sem"`, 422 fora disso) e o ramo em `produto._condicoes`, **antes** do
   `return` de `incluir_alerta=False`.

**Ler:** `app/servicos/produto.py` (`_COLUNAS`, `_DE`, `_condicoes`, `listar`, `resumo`),
`app/api/rotas.py:145-215`, `app/api/contrato.py:_data/_f/produto`, e §4.8 e §6 deste
documento. **Não ler `REGRAS.md`.**

**Não fazer:** nada em `preco.py` (§4.7 — a gravação da decisão, o histórico e
`obter_cenarios` ficam como estão), nada em `lote_preco.py` (o ponto 1 é só front), nenhuma
consulta ao CEDEP, nenhuma DDL.

### 8.4 `frontend-react` — `model: sonnet`. É o dono da maior parte da etapa.

Os itens 1 e 3 a 5 podem começar antes de o dbt terminar; o item 2 espera o campo no JSON.

1. **Ponto 1** — `loteAplicado` em `lotePrecoStatus.js`; chip em `PrecosDefinidos.jsx`
   (`CartaoLote`, linhas 173-195) e em `LotePrecoDetalhe.jsx:130-140`.
2. **Ponto 2** — `precoJaAplicado` em `precificacao.js`; os **três estados** da célula
   (§4.3) em `Precificacao.jsx` (linhas 607-612, 737-785) e no `BlocoPreco` de
   `DecisaoSKU.jsx` (linhas 399, 415, 506-525). A data do estado aplicado é
   `precoAlteradoEmAtacado`/`...Varejo` — **cada canal com a sua**, nunca uma só para os
   dois (§4.5). Data nula → "preço aplicado", sem data.
3. **Ponto 3** — `quantidadeEstoque` em `formato.js`; coluna nova em `Precificacao.jsx`
   (cabeçalho após a linha 572, célula após a 682), `ROTULO_COLUNA` + `FUNDO_EST`;
   `Pedidos.jsx:442` passa a usar o formatador.
4. **Ponto 4** — `web/src/componentes/FiltroEstoque.jsx`, ligado nas duas telas, com o
   parâmetro chegando em `api.produtos({...})`.
5. **Ponto 5** — mover o PNG para `web/public/`, duas linhas no `index.html`.
6. **Publicar**: rodar `infra\publicar.ps1` e conferir que
   `app/static/v2/carrinho-de-compras.png` existe depois do build.

**Ler:** `web/src/telas/Precificacao.jsx`, `web/src/telas/Pedidos.jsx`,
`web/src/telas/PrecosDefinidos.jsx`, `web/src/telas/LotePrecoDetalhe.jsx`,
`web/src/telas/DecisaoSKU.jsx` (só o `BlocoPreco`), `web/src/lotePrecoStatus.js`,
`web/src/precificacao.js`, `web/src/formato.js`,
`web/src/componentes/FiltroUltimaEntrada.jsx` (o molde do filtro compartilhado),
`web/index.html`, `web/vite.config.js`, e §3 a §7 deste documento.
**Não ler `REGRAS.md`** nem os models do dbt.

**Não fazer:**
- nenhuma dependência nova em `web/package.json`, nenhuma URL externa (fonte, CDN, ícone);
- nenhuma marcação duplicada por `modoDesktop` — responsividade é CSS, uma marcação só;
- não tocar no `relative z-30` do `Cabecalho.jsx` nem na barra de abas;
- navegação é `<Link>`, ação é `<button>` — o chip do ponto 1 não é nem um nem outro: é
  `<span>`, não clica em nada.

### 8.5 `validador` — `model: sonnet`

1. **A fonte da data (ponto 2)**: script de leitura que compara, para os **8.841 SKUs**,
   `COMPRAS_PRODUTO_CONTEXTO.DT_ULT_ALT_PV_ATACADO` × `CEDEP.PCTABPR.DTULTALTPVENDA`
   (`NUMREGIAO=2`) e o par de varejo (`NUMREGIAO=1`). Aceite: **zero divergência** e
   **650 nulos dos dois lados**. Molde de conexão e credencial:
   `validar/validar_pedido.py:_ler_credencial_compras` / `conectar` (thick obrigatório).
2. ⚠ **Exercitar com defeito injetado** (armadilha 15): rodar a mesma comparação com a
   coluna de atacado apontando para `NUMREGIAO=1` e **confirmar que reprova em 79 SKUs**
   (§2.2) — o número exato é a prova de que o validador enxerga a diferença de região, e
   não só a ausência de dado.
3. **Ponto 4, o invariante**: função nova em `validar/validar_api.py` que, para cada
   `status` em (ausente, `Ativo`, `Inativo`), confere
   `total(estoque=com) + total(estoque=sem) == total(sem o filtro)` lendo o campo `total`
   da resposta. Nove requisições.
4. ⚠ **Defeito injetado também aqui**: rodar uma vez com o ramo "sem" escrito como
   `nvl(p.est_disp,0) < 0` e **confirmar que reprova** nos três status, com a diferença
   batendo nos 5.455 SKUs de estoque zero. Depois restaurar e rodar limpo.
5. **Ponto 4, as combinações**: acrescentar `"estoque": [None, "com", "sem"]` ao `EIXOS` de
   `validar_api.py:33`. Isso **triplica** o produto cartesiano (de 1.728 para 5.184
   chamadas) — se o tempo de execução ficar impraticável, **reportar o tempo medido**, não
   remover o eixo em silêncio.

**Ler:** `validar/validar_api.py`, `validar/validar_pedido.py` (só a seção de conexão),
§2.2 e §6 deste documento. Nada de `REGRAS.md`.

### 8.6 `revisor` — `model: sonnet`. Último, sempre.

`sonnet` e não `opus` porque nenhuma fórmula é tocada: a etapa transporta uma data e desenha
telas. Foco da revisão, em ordem:

1. **`git diff --stat` do dbt bate com §4.4**: três models e os `schema.yml`. Se
   `fat_pedido.sql`, `compras_pedido.sql` ou `int_produto_margem.sql` aparecerem no diff, a
   etapa parou ali;
2. a data de cada canal vem do **subselect da região correspondente** — não da "mais
   recente", não de uma região só;
3. a tag do ponto 1 não virou status em lugar nenhum (nem em `STATUS`, nem no filtro, nem
   no banco);
4. o ponto 2 não alterou o que o lote considera "alteração de verdade"
   (`alteracoesLote` e `podeGravar` continuam comparando contra o `decidido` do JSON), e
   `preco.py` não foi tocado;
5. `EST_DISP` não foi dividido de novo por `FATOR_EXIBICAO` em lugar nenhum;
6. o filtro do ponto 4 é whitelist no servidor e particiona o universo;
7. o favicon está em `web/public/`, não em `app/static/v2` (que o próximo build apaga).

### 8.7 Quem **não** entra

- **`oracle-dba`** — nenhuma DDL, nenhum `GRANT`, nenhuma tabela `APP_*` nova. As colunas
  novas nascem pelo dbt, que derruba e recria `COMPRAS_PRODUTO_CONTEXTO` a cada build.
- **`dbt-relatorios`** — os dois relatórios portados não são tocados.
- **`infra-windows`** — `infra/publicar.ps1`, `infra/nginx/compras.conf` e os `.bat` ficam
  como estão. O `publicar.ps1` é **executado**, não editado.

---

## 9. Pergunta — uma, de vocabulário

1. **O rótulo da tag do ponto 1: "Aplicado" ou "Tudo aplicado"?** Este prompt decidiu
   "Aplicado", como o pedido escreveu, com estilo contornado e ícone de check para não
   parecer um terceiro status ao lado de "Enviado". "Tudo aplicado" seria mais claro quanto
   a ser um agregado de itens, e mais feio. Se o Diretor ler os dois chips como uma
   sequência de estados, troca-se o texto em uma linha.

*(A segunda pergunta desta etapa — de onde sai a data do ponto 2 — foi respondida em 16/09 e
virou o §1.1.)*

---

## 10. Aceite

Numerado e conferível. Cada item é uma coisa a **demonstrar**, não a afirmar.

1. `COMPRAS_PRODUTO_CONTEXTO` tem as colunas `DT_ULT_ALT_PV_ATACADO` e
   `DT_ULT_ALT_PV_VAREJO`, as duas documentadas no `schema.yml`, e
   `select count(*) from compras_produto_contexto` continua em **8.841 linhas**.
2. `git diff --name-only` do dbt lista **exatamente** `stg_preco_tabela.sql`,
   `int_cadastro_estoque.sql`, `compras_produto_contexto.sql` e os `schema.yml` deles.
   `fat_pedido.sql`, `compras_pedido.sql` e `int_produto_margem.sql` **não** aparecem.
3. `dbt\rodar_dbt.bat` roda limpo e os seis testes de §4.4 passam — com destaque para
   `compras_fat_pedido_122_colunas` (a prova de que a coluna nova não vazou para a tabela
   validada contra a planilha).
4. O validador compara as **8.841** linhas contra `CEDEP.PCTABPR` nas duas regiões:
   **zero divergência**, **650 nulos** de cada lado (recontados no dia).
5. A execução do validador com a região trocada (atacado lendo `NUMREGIAO=1`) **reprova em
   79 SKUs**, com a saída anexada ao relatório. Sem essa execução, o item 4 não prova nada.
6. Na Precificação, num SKU com preço decidido **igual** ao preço atual (28 SKUs hoje): o
   campo de edição nasce **vazio** com o placeholder da sugestão, a linha "decidido R$ ..."
   **não** aparece, e no lugar dela aparece **"preço alterado em 14/09/26"** em cinza — a
   data de `DT_ULT_ALT_PV_ATACADO`, conferida contra o banco na mesma sessão.
7. ⚠ **A prova de que a fonte é o WinThor, e não a decisão, é a dos itens 4, 5 e 8 — não a
   inspeção da tela.** Medido em 16/09: nos 28 SKUs decididos, a decisão foi às **14/09
   11:43** e a alteração no WinThor às **14/09 17:17** — **truncadas no dia, as duas datas
   são idênticas**, então nenhuma inspeção visual distingue as duas fontes hoje. Um critério
   que exigisse "as datas diferem na tela" seria impossível de cumprir, e por isso não está
   aqui.
8. Num SKU entre os **79 com datas diferentes entre canais** (a lista sai da consulta do
   item 4), atacado e varejo exibem **datas diferentes**. Como
   `APP_DECISAO_PRECO.ATUALIZADO_EM` é **uma só por SKU**, duas datas diferentes na mesma
   linha só podem vir da fonte por região. Se nenhum dos 79 tiver decisão aplicada no dia do
   teste, conferir o mesmo par direto em `COMPRAS_PRODUTO_CONTEXTO` e registrar o SKU.
9. Num SKU **sem** data no WinThor (um dos 226 ativos) e com preço aplicado, a linha diz
   **"preço aplicado"**, sem data e sem traço.
10. Num SKU com preço decidido **diferente** do atual (para provar: decidir um preço qualquer
    e conferir antes do próximo `dbt run`): o campo nasce preenchido com o decidido e a linha
    "decidido R$ ... · dd/mm/aa" aparece com a data da **decisão** — comportamento de hoje
    mais a data, nada perdido.
11. O mesmo par de estados vale na tela de Decisão do SKU (`DecisaoSKU.jsx`), usando a mesma
    `precoJaAplicado` de `precificacao.js`; e `git diff` mostra `app/servicos/preco.py`
    **intocado**.
12. Gravar um preço novo por cima de um aplicado continua funcionando: a barra de gravação em
    lote conta o SKU, o lote é criado/acrescentado, e a linha volta ao estado "decidido, não
    aplicado" depois do rebusque.
13. Na lista de Preços Definidos, os lotes com todos os itens aplicados exibem o chip verde
    contornado "Aplicado" ao lado do chip de status — **hoje, 2 de 2 lotes** (recontar).
    Um lote com ao menos um item pendente **não** exibe o chip, e a linha "N de M
    aplicado(s)" continua visível nos dois casos. O mesmo chip aparece no cabeçalho do
    detalhe, pela mesma função `loteAplicado`.
14. `grep -n "Aplicado" web/src/lotePrecoStatus.js` mostra que a palavra **não** entrou no
    array `STATUS`; os botões de filtro de status continuam sendo dois; `git status --short
    sql/` vazio.
15. A tabela de Precificação tem coluna "Estoque" logo depois de "Últ. entrada", com fundo
    `#FFF7ED`, cabeçalho clicável que ordena no **servidor** (`?ordenar=estoque&dir=desc`
    aparece na URL e a **primeira página** muda de conteúdo, não só a ordem dos 50 visíveis),
    e o dropdown "Ordenar por" mostra "Estoque" — não fica em branco.
16. O SKU **5290** (YPF, 12X1 LT) aparece na coluna como **0,08**, e não como "0" — nas duas
    telas, Precificação e Pedidos.
17. O filtro "Com/Sem estoque" existe nas duas telas, com os mesmos três botões e o mesmo
    componente. Com `status=Ativo`: **Com estoque 3.305**, **Sem estoque 1.253**, **Todos
    4.558** no contador do topo (números recontados no dia da execução).
18. `GET /api/produtos?estoque=qualquercoisa` responde **422**, com mensagem em português.
19. O validador do invariante `com + sem = total` **passa** nos três status; e a execução com
    o defeito injetado (`< 0` no ramo "sem") **reprova**, com a saída anexada. Sem as duas
    execuções, o item 19 não está cumprido.
20. A aba do navegador mostra o carrinho em `http://compras.cdp.lub` **depois** de
    `infra\publicar.ps1`, verificado com recarga forçada.
21. `web/public/carrinho-de-compras.png` existe e está versionado; a **raiz** do repositório
    **não** tem mais o PNG (`git status --short` sem o `??` de hoje); e
    `app/static/v2/carrinho-de-compras.png` existe **depois** de um `npm run build` — prova
    de que o arquivo vem do `public/` e não sobrevive por acaso ao `emptyOutDir`.
