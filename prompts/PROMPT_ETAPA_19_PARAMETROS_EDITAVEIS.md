# Etapa 19 — Margem, MKP e cobertura alvo viram parâmetro ajustável na tela; e o filtro de produtos sem preço

**Origem.** Três itens repassados pelo usuário (suporte.ia1@cedeplub.com) pelo prompter em
**08/10/2026**, na mesma conversa em que veio o item 1.12 que gerou a Etapa 18. Os itens 1 e
2 são o mesmo pedido em duas telas; o 3 é independente.

**Base de código.** `4d1af6a` (30/09/2026 — "A quantidade pedida vai para o campo, e o que
muda fica visível"). `git status --short` hoje só mostra, como não versionado, o próprio
`prompts/PROMPT_ETAPA_18_COBERTURA_PROJETADA.md`. Repositório `app_compras_v2`, commit
inicial `fbac519`.

**Por que 19.** A **17** está consumida pelo trabalho de 29–30/09 (o número está escrito em
comentário de `web/src/telas/PedidoDetalhe.jsx:358` e mais três arquivos). A **18** é a
cobertura projetada, **já escrita e ainda não executada**. Esta é a **19**.

**Isto muda número?** **Muda número na tela, e só na tela.** Nenhuma coluna de
`COMPRAS_PEDIDO`/`FAT_PEDIDO` é recalculada, nenhum model dbt é editado, nenhum seed muda,
nenhuma linha de `APP_DECISAO_PRECO` ou `APP_PEDIDO_ITEM` é gravada por causa dos itens 1 e
2. O item 3 acrescenta **um** parâmetro de consulta e **uma** condição no `where` — muda
quem aparece na lista, não o valor de nada.

---

## ⚠ Ordem obrigatória: a Etapa 18 entra antes desta

A Etapa 18 conserta a conta da **cobertura projetada** (`(est_pend + qtd × fator) /
media_janela`, que multiplica por `FATOR_EXIBICAO` o que já está em unidade de exibição). O
item 2 desta etapa constrói, em cima dessa mesma conta, o controle que a alimenta.

A dependência não é de conveniência — é de **demonstrabilidade**. A identidade que prova que
o controle está certo é:

```
sug       = round(media_janela × alvo − est_pend)
projetada = (est_pend + sug) / media_janela = alvo
```

Ou seja: **pôr o alvo em 3,0 e clicar na sugestão tem de fazer a coluna de cobertura
projetada mostrar 3,0.** Hoje, para um item MASTER, ela mostra `alvo × fator` — 72,0 em vez
de 3,0 num item de fator 24. Sem a Etapa 18, o item 2 não tem como ser aceito, e quem o
construir vai "consertar" o controle para compensar um defeito que não é dele.

**Não comece esta etapa antes de a 18 estar executada e aprovada.** Se ela não estiver, os
itens 1 e 3 podem seguir (são independentes); o item 2 espera.

---

## 1. O pedido, verbatim

> 1. *Margem e MKP editáveis para a sugestão de preços;*
> 2. *Cobertura editável (slider talvez?) para a sugestão de quantidade nos pedidos;*
> 3. *Filtro de produtos sem preço na tela de precificação;*

O "talvez?" do item 2 é literal: a forma do controle ficou em aberto, e esta etapa a decide
(§4.3), com a medida que sustenta a escolha.

---

## 2. A decisão que vale para os itens 1 e 2: parâmetro **de sessão**, nunca gravado

É uma decisão só, de propósito. Se a margem salvasse e a cobertura não, as duas telas
ensinariam regras opostas sobre o mesmo gesto.

**O valor ajustado na tela vive em `sessionStorage`, pelo `useEstadoPersistente` que estas
telas já usam. Não vai para o banco, não cria tabela, não cria coluna.** Três motivos, e o
segundo é o que fecha a questão:

**(a) O que este projeto grava é a decisão, não a régua.** O preço decidido vai para
`APP_DECISAO_PRECO` com autor, histórico (`APP_DECISAO_PRECO_HIST`) e perfil de diretoria; a
quantidade decidida vai para `APP_PEDIDO_ITEM`. Margem, MKP e cobertura alvo são **o caminho
até esses dois números** — mexer na margem para achar um preço e gravar o preço é uma
decisão completa e auditável. Gravar também a régua criaria um segundo registro de decisão,
com dono e alcance indefinidos.

**(b) Gravar a margem produziria, hoje, um defeito visível.** A coluna "Sugerido AT/VAR" da
Precificação vem de `PV_SUG_*`, calculado pelo **dbt**. `APP_DECISAO_PRECO.MARGEM_ALVO` é
lida por `stg_decisao_preco` → `int_produto_preco_sugerido.sql:134`. Logo: gravar 25% **não
muda a coluna "Sugerido" até o próximo `dbt run`** (CONTEXTO.md §2). O Diretor gravaria, veria
a coluna continuar no preço de 20%, e concluiria que a gravação falhou — é o mesmo defeito de
25/08/2026 que obrigou `app/servicos/preco.py:obter_cenarios` a ler `ALT_PV_*` ao vivo. Para
fazê-lo direito seria preciso **recalcular `PV_SUG_*` também no servidor**, ou seja, uma
segunda implementação da fórmula de preço sugerido fora do dbt. Essa duplicação foi fechada em
12/09/2026 (`REGRAS.md §9.1`) e não se reabre por um campo de tela.

**(c) Efêmero puro seria o defeito do carrinho da Etapa 13.** Perder o ajuste ao trocar de
página, de filtro ou ao usar "Voltar" é o descarte silencioso que este projeto vem corrigindo
tela por tela. Daí **de sessão**: sobrevive à navegação e ao F5, morre ao fechar a aba — o
ajuste de terça não reaparece na quinta (`web/src/estadoTela.js`, decisões 1 e 2).

E **guarda só o que a pessoa digitou**: a margem (fração) e a cobertura alvo (meses). Nunca
preço, custo, cobertura ou sugestão derivados — eles envelhecem no próximo `dbt run`
(armadilha do `estadoTela.js`, e o mesmo motivo pelo qual `Precificacao.jsx:155-175` projeta
só `{codigo: valor}` antes de gravar no storage).

### A ambiguidade produto × departamento se dissolve — e por quê

Como nada é gravado, "muda só este SKU ou os 300 do departamento?" deixa de ser pergunta de
schema e vira pergunta de alcance visual, que o grão do dado responde sozinho:

| Parâmetro | Grão do dado hoje | Grão do controle nesta etapa |
|---|---|---|
| `MARGEM_ALVO` / `MARGEM_ALVO_VAREJO` | **por SKU** — `APP_DECISAO_PRECO`, uma linha por produto, com fallback global `MARGEM_ALVO_PADRAO` = 0,20 | **por célula**: um SKU, um canal |
| `COBERTURA_ALVO` | **por departamento** — `seed_fornecedor.csv`, resolvido em `int_produto_demanda.sql:127` | **um controle só**, no topo, valendo para o recorte visível |

Medido em 08/10/2026: `MARGEM_ALVO` = **0,200000 em 8.944 de 8.944 linhas** de
`COMPRAS_PEDIDO`, atacado e varejo, e `APP_DECISAO_PRECO` tem **166 linhas, 0 com
`MARGEM_ALVO` preenchida** (166 com preço de atacado, 83 com preço de varejo).
`APP_DECISAO_PRECO_HIST` está vazia. Isto é: **ninguém nunca decidiu uma margem alvo**, e a
coluna que existiria para isso está lá, pronta e sem uso. Vira pergunta para o Diretor (§8.A),
não trabalho desta etapa.

`COBERTURA_ALVO` na mesma data: **2,0 em 60 departamentos** e **1,5 em um** (ADIBRAX, 8 SKUs);
`HITECH` não tem linha no seed e chega ao JSON com `coberturaAlvo` **nulo** em 10 SKUs — o dbt
usa o fallback `COBERTURA_ALVO_PADRAO` = 2 internamente (`int_produto_demanda.sql:127`), mas
`COMPRAS_IND_FORNECEDOR.COBERTURA_ALVO`, que é de onde a API lê
(`app/servicos/produto.py:69`), fica nula. **Trate `coberturaAlvo` nulo caindo em
`parametros.cobertura_alvo_padrao`** (`GET /api/parametros` devolve a linha inteira de
`COMPRAS_PARAMETRO`, então o campo já chega). Não "conserte" a coluna no dbt: ela está
coerente com o seed.

---

## 3. Item 1 — margem e MKP editáveis na Precificação (e na Decisão do SKU)

**Muda número na tela.** Nenhuma gravação nova, nenhum campo novo no JSON, nenhuma rota.

### 3.1 O que já existe, e que não se refaz

| Peça | Onde | O que faz |
|---|---|---|
| `calcMKP(preco, custo)` | `web/src/precificacao.js:45` | `preco / custo` |
| `calcMargem(preco, custo, {pisCofins, comissao, icmsEf})` | `web/src/precificacao.js:60` | `1 − pisCofins − comissao − icmsEf − custo/preco` |
| `simular({...})` | `web/src/precificacao.js:105` | resolve o cenário visível e devolve `custo`, `mkpNovo`, `margemNova`, `sugerido`, `prazo`… |
| A célula que já mostra os três | `web/src/telas/Precificacao.jsx` → `CelulaEdicao` (≈:905) | input de preço + o texto `1,91x/35%` |
| O bloco equivalente no SKU | `web/src/telas/DecisaoSKU.jsx:396` `BlocoPreco`, render em `:564-565` | input de preço + `→ MKP … · Margem …` |
| Comissão e fatores de prazo | `GET /api/parametros` | `comissao` = 0,04 hoje; nunca literal no JS |

### 3.2 A fórmula é **uma só**, invertida — e está provada no banco

Margem, MKP e preço são três vistas do mesmo número, e as três passam pelo **custo do
cenário**:

```
margem = 1 − pisCofins − comissao − icmsEf − custo/preco      (já existe: calcMargem)
preco  = custo / (1 − pisCofins − comissao − icmsEf − margem) (o inverso)
mkp    = preco / custo                                        (já existe: calcMKP)
preco  = mkp × custo                                          (o inverso)
```

O inverso **não é uma segunda cópia**: é a mesma expressão resolvida para `preco`, e é
literalmente a fórmula que o dbt usa para a sugestão
(`int_produto_preco_sugerido.sql:26-30`: `pv_sug = custo / (1 - aliq_icms - piscof -
comissao - margem_alvo)`).

**Medido em 08/10/2026, schema `COMPRAS`, só `SELECT`:** aplicando
`custo/(1 − icms_sem_red − piscof_ef − 0,04 − margem_alvo)` sobre `COMPRAS_PEDIDO` e
comparando com `PV_SUG_ST_S_VALOR_AV` — **0 divergências em 8.759 linhas**, tolerância
R$ 0,01. Exemplo conferível à mão (SKU **9**, PETROBRAS, cenário ST s/Valor): custo
237,9053; ICMS 0,000000; PIS/COFINS 0,0925; comissão 0,04; margem alvo 0,20 →
237,9053 / 0,6675 = **356,4124**, que é exatamente `PV_SUG_ST_S_VALOR_AV`. E o preço atual
455,40 dá margem 1 − 0,0925 − 0,04 − 0 − 237,9053/455,40 = **0,34509**, exatamente
`MARGEM_ST_S_VALOR`.

Daí sai o critério de aceite mais forte da etapa: **digitar 20 no campo de margem tem de
produzir no campo de preço exatamente o número da coluna "Sugerido" daquela linha.** Se não
produzir, a conta está errada — não a coluna.

**Arquivo novo: `web/src/precoEditavel.js`**, com as duas inversas puras e nada mais. Elas
não entram em `precificacao.js` porque aquele arquivo é "o que a tela refaz a cada tecla" e
já está no limite do que se lê de uma vez; mas `precoEditavel.js` **importa** `calcMKP` e
`calcMargem` dali e não redefine nenhuma das duas.

```js
/** Preço que produz uma MARGEM alvo, no cenário dado. Inverso algébrico de
 *  `calcMargem` (precificacao.js) — a MESMA expressão resolvida para `preco`,
 *  e a mesma fórmula de `int_produto_preco_sugerido.sql:26-30`. Conferido
 *  contra PV_SUG_ST_S_VALOR_AV: 0 divergências em 8.759 linhas (08/10/2026).
 *
 *  `margem` em FRAÇÃO (0,205 = 20,5%), como em `calcMargem`.
 *  Devolve null quando o denominador não é positivo: acima do teto do cenário
 *  não existe preço que produza aquela margem. Teto medido nos 4.552 ativos:
 *  entre 66,25% e 96% no ST s/Valor, entre 74,69% e 96% no Oficial — nenhum
 *  SKU com teto abaixo de 20%, então a margem alvo padrão é sempre atingível.
 */
export function precoDeMargem(margem, custo, { pisCofins, comissao, icmsEf }) { … }

/** Preço que produz um MKP. Inverso de `calcMKP`. */
export function precoDeMKP(mkp, custo) { … }
```

Para ler o texto digitado nos dois campos novos, use **`parseNumeroPreco`**
(`web/src/formato.js:62`) — não `Number(String(v).replace(",", "."))`, que lê "1.234,56" como
NaN e já apagou o botão "Gravar" de 254 SKUs neste projeto.

### 3.3 Como o laço é evitado — o mecanismo, não a intenção

O defeito clássico (digitar margem → recalcula preço → recalcula margem → arredonda → o
cursor pula) é evitado por construção, com **duas** decisões:

**(1) O estado continua sendo um número só: o PREÇO.** `precosAT`/`precosVAR` em
`Precificacao.jsx:152-170` não mudam de forma, não mudam de chave de `sessionStorage`, não
mudam o que vai para `alteracoesLote` nem para a API. **Margem e MKP não são estado — são
formas de entrada.** Digitar na margem escreve um PREÇO no mapa de sempre.

**(2) Enquanto um campo está sendo digitado, ele é o único que renderiza o texto cru.** Um
`useState` local por célula:

```js
const [editando, setEditando] = useState(null);   // null | { campo: "margem"|"mkp", texto }
```

- **input de preço** — `value={valor ?? ""}`; `onChange` faz `setEditando(null)` e
  `aoTrocar(texto)`. É exatamente o comportamento de hoje.
- **input de margem** — `value` é `editando?.campo === "margem" ? editando.texto :
  (sim.margemNova != null ? numero(sim.margemNova * 100, 1) : "")`. `onChange(t)` faz
  `setEditando({campo:"margem", texto:t})` **e** `aoTrocar(paraCampoPreco(precoDeMargem(
  parseNumeroPreco(t)/100, sim.custo, base)))`.
- **input de MKP** — idêntico, com `precoDeMKP`.
- `onBlur` de qualquer um dos dois: `setEditando(null)` — o campo volta a mostrar o valor
  derivado, formatado.

O cursor não pula porque **a `value` do campo sob o cursor nunca é recalculada**: ela é o
texto que a pessoa escreveu, intacto, até o blur. O arredondamento para 2 casas acontece **só
na direção margem → preço** (via `paraCampoPreco`, o mesmo formatador do campo de preço:
duas casas, vírgula, sem ponto de milhar) e nunca volta para o campo de origem.

Casos em que `precoDeMargem`/`precoDeMKP` devolvem `null` — margem acima do teto do cenário,
MKP ≤ 0, custo ausente: **não escreva nada no campo de preço** e marque o campo de entrada
com borda vermelha e `title` explicando. Não limpe o preço que já estava lá; apagar o
trabalho de alguém porque ele digitou um caractere a mais é o descarte silencioso de novo.
Medido: **51 SKUs ativos** sem custo no cenário ST s/Valor e **65** sem custo gerencial —
nesses, `sim.custo` é nulo, `calcMKP` já devolve `null` hoje, e os dois campos novos nascem
**desabilitados**, não vazios-e-clicáveis.

### 3.4 Cenário fiscal: o preço **persiste**, margem e MKP **recalculam**

Custo e alíquota mudam com o cenário (`contrato._CUSTO_DO_CENARIO` e `_ICMS_DO_CENARIO`,
`app/api/contrato.py:85-98`): "Oficial" e "Sem Redução" usam `custo_tot_gerencial`; "ST
s/Valor" usa `custo_tot_s_valor + custo_adicional_imagem`. E `custoGerencial` **é** o custo do
cenário Oficial — não é um quarto valor, e não se exibe como tal.

**Regra, uma linha:** trocar o cenário **não altera o preço digitado**, e faz margem e MKP
serem recalculados sob o custo e a alíquota novos.

Por quê: o preço é o único dos três que não depende do cenário, e é o único que vai ser
gravado. Margem e MKP são leituras dele. Isto, aliás, já é o comportamento de hoje para a
margem exibida — a etapa torna os dois campos editáveis sem mudar a regra. **Nada é
limpo**; limpar seria descartar edição sem avisar.

Consequência operacional a implementar: `useEffect(() => setEditando(null), [cenarioSel])`.
Se a pessoa estava digitando no campo de margem quando o cenário mudou, o campo dirigente
volta a ser o preço — o preço que a margem produziu fica, e o campo de margem passa a exibir
a margem que **esse** preço dá no cenário novo. Uma linha, e é a diferença entre coerente e
inexplicável.

⚠ `simular` já resolve o cenário visível com `cenarioVisivel` (`precificacao.js:97`), que cai
no cenário **real** do produto quando o escolhido não existe naquela praça — o varejo não tem
"Oficial". **Use `sim.custo` e `sim.cenario.icmsEf`, nunca re-resolva o cenário nos campos
novos**: duas resoluções é como nasce uma tela que calcula a sugestão com uma alíquota e a
margem com outra, que é o defeito do protótipo documentado em `precificacao.js:52-57`.

### 3.5 Atacado e varejo são **dois controles**, não um

Cada `CelulaEdicao` já é de um canal. São duas margens alvo no schema (`MARGEM_ALVO` e
`MARGEM_ALVO_VAREJO`, independentes — `int_produto_preco_sugerido.sql:11` diz "INDEPENDENTE
de CN"), dois conjuntos de cenários (`cenariosAtacado` / `cenariosVarejo`), duas alíquotas e
dois fatores de prazo. Um controle único forçaria a mesma margem nos dois e ainda assim
produziria dois preços diferentes — a aparência de simetria sem a simetria.

### 3.6 Onde entram os campos, e o que **não** muda de lugar

- **`Precificacao.jsx` → `CelulaEdicao`:** o texto `1,91x/35%` que hoje fica ao lado do input
  vira **dois inputs pequenos**, na mesma célula, mesma linha: `[preço] [margem]% [MKP]x`.
  Suba o `minWidth` da `<td>` de 180 para ~215. **Não acrescente coluna à tabela** — são 15 e
  ela já rola de lado.
- **`DecisaoSKU.jsx` → `BlocoPreco`:** o `→ MKP … · Margem …` de `:564-565` vira os mesmos
  dois inputs. Entra nesta etapa **porque não entrar criaria a incoerência**: margem editável
  numa tela e só texto na outra, para o mesmo produto e o mesmo preço.
- A linha "Pz …" (preço a prazo), o `placeholder` com a sugestão, as linhas "decidido …" e
  "preço aplicado" de `CelulaEdicao` **ficam exatamente como estão**.
- A coluna "Sugerido AT/VAR" **continua vindo de `PV_SUG_*`** (`sim.sugerido`) e **não é
  recalculada no cliente**. Ela é o número do modelo e é o gabarito contra o qual o campo de
  margem é conferido (§9, aceite 1).
- `alteracoesLote`, `definirPrecos`, o payload de `POST /lotes-preco` e as chaves de
  `sessionStorage` dos preços **não mudam em nada**.

---

## 4. Item 2 — cobertura alvo ajustável, para a sugestão de quantidade

**Muda número na tela.** Nenhuma gravação, nenhum seed editado, nenhum `dbt seed`, nenhuma
chamada nova à API.

### 4.1 A conta que o controle alimenta — e que já está provada

`SUG_COBERTURA` é a coluna AZ da planilha (`int_produto_demanda.sql:277`):

```sql
greatest(0, round(d.media_janela * d.cobertura_alvo - d.est_pend, 0))
```

**Medido em 08/10/2026:** reproduzir essa expressão fora do dbt, com
`nvl(COMPRAS_IND_FORNECEDOR.COBERTURA_ALVO, 2)`, bate com `COMPRAS_PEDIDO.SUG_COBERTURA` em
**8.944 de 8.944 linhas**, tolerância 0,0001. Logo: com o alvo **do modelo**, o cliente tem de
reproduzir `p.sugCobertura` exatamente — e esse é o estado inicial do controle (§4.4).

⚠ `round` do Oracle é "metade para longe do zero" (o próprio comentário de
`int_produto_demanda.sql:275-276` registra isso). `Math.round` do JavaScript é "metade para
cima". Os dois só divergem em negativo, que o `greatest(0, …)` já elimina — **`Math.round` é
seguro aqui**, e não é motivo para escrever um arredondador próprio.

### 4.2 Unidade: o controle opera em **meses**; o resultado sai em **unidade de exibição**

`media_janela` e `est_pend` chegam ao front **já divididos por `FATOR_EXIBICAO`**
(`int_produto_demanda.sql:171` e `:138/:142/:201`). O alvo é um número de **meses**, sem
unidade de produto. Logo a sugestão sai na **mesma unidade de exibição** — caixas onde
`FATOR_EXIBICAO > 1`, que é a unidade que o botão de sugestão já mostra, que o campo de
quantidade já recebe, e que o rótulo abaixo dele já chama de "caixas"
(`CatalogoPedido.jsx:498`).

**Nada se multiplica por `fatorExibicao` nesta conta.** É a regra 6 do `CONTEXTO.md`, e é o
mesmo erro que a Etapa 18 está removendo três linhas acima. Se o executor sentir vontade de
multiplicar, é sinal de que está recriando o defeito.

### 4.3 Slider **mais** campo numérico — e a medida que decide isso

A faixa real de `COBERTURA_ALVO` hoje, medida no seed e no banco (08/10/2026):

| Valor | Departamentos | SKUs |
|---|---|---|
| 1,5 | 1 (ADIBRAX) | 8 |
| 2,0 | 60 | 8.926 |
| sem linha no seed (nulo em `COMPRAS_IND_FORNECEDOR`) | 1 (HITECH) | 10 |

Ou seja: **o universo inteiro cabe no intervalo [1,5; 2,0]**, e a única casa decimal em uso é
o 0,5 da ADIBRAX. Isso resolve a dúvida do Diretor:

- **Slider puro de 0 a 12 está errado.** Num celular, 0–12 com passo 0,1 são 120 posições em
  ~250 px — 2 px por passo. A precisão que importa é inatingível com o dedo.
- **Slider de 0 a 6, passo 0,5** são 13 posições, ~19 px cada: é um gesto confortável, e 0,5
  é a granularidade que o próprio seed usa.
- **Campo numérico ao lado, aceitando uma casa decimal, de 0 a 12**, para quando 0,1 — ou um
  valor fora da faixa do slider — importar.

**Decisão: os dois, lado a lado, escrevendo o MESMO estado.** O slider é o gesto rápido sobre
a faixa que interessa; o campo é a precisão. Um não é alternativa ao outro — e é por isso que
o Diretor escreveu "talvez?": slider sozinho não carrega precisão, campo sozinho não dá a
sensação de varrer a faixa. Nenhuma dependência nova em `web/package.json`:
`<input type="range">` é nativo.

Quanto o controle de fato move, medido sobre os 4.552 SKUs ativos:

| Alvo | SKUs com sugestão > 0 | Unidades sugeridas (soma) |
|---|---|---|
| 1,0 | 428 | — |
| **2,0 (hoje)** | **803** | **599.039** |
| 3,0 | 1.141 | 1.265.986 |
| 4,0 | 1.609 | — |
| 6,0 | 2.297 | — |

De 2,0 para 3,0 a quantidade sugerida **mais que dobra**. O controle não é cosmético, e por
isso precisa de um caminho de volta explícito (§4.4).

### 4.4 Onde fica, o que recalcula, e o que **não** recalcula

**Onde:** no bloco de filtros compartilhado, `web/src/componentes/CatalogoPedido.jsx →
FiltrosCatalogo` (`:151`). Assim as **duas** telas que montam pedido o recebem de uma vez:
`/pedidos` (`Pedidos.jsx:234`) e a edição de pedido salvo (`PedidoDetalhe.jsx:625` e `:667`).
Entra **por prop** (`coberturaAlvoSimulada`, `setCoberturaAlvoSimulada`), nunca por `if` de
tela — é a regra escrita no cabeçalho daquele arquivo (`:18-22`).

**Estado:** um `useEstadoPersistente` por tela, com **chaves diferentes**
(`app_compras_cobertura_alvo_pedidos_v1` e `app_compras_cobertura_alvo_pedido_detalhe_v1`),
pelo mesmo motivo que os filtros já usam chaves separadas: mexer no catálogo dentro de um
pedido não pode alterar o que ficou montado em `/pedidos`.

⚠ **Não coloque o valor dentro do objeto `filtros`.** Ele não é filtro: não vai para a API,
não deve disparar `buscar()`, não entra no `where` do servidor e não reordena nada. Pôr junto
dos filtros é como ele acabaria dentro de uma `useCallback` e provocando uma consulta por
movimento do slider.

**Estado inicial: `null` — "use o alvo do modelo".** Com `null`, cada linha usa
`p.coberturaAlvo` (ou `parametros.cobertura_alvo_padrao` quando nulo, §2) e a sugestão exibida
é **`p.sugCobertura`, o número do servidor, sem recálculo nenhum**. Só depois de a pessoa
mexer no controle é que o cliente passa a recalcular. Isso dá a partição exata que torna a
etapa conferível: *sem toque = o modelo, byte a byte; com toque = a simulação.* E exige um
botão **"voltar ao alvo do modelo"** ao lado, que devolve o estado a `null`.

**O que recalcula quando o valor muda:** só a **coluna "Sug."** de cada linha visível
(`CatalogoPedido.jsx:482-489`) — aritmética pura sobre dados já carregados, 50 linhas por
página, sem ida ao servidor.

**O que NÃO recalcula, e é tão importante quanto:**

- **A quantidade já digitada não é tocada.** Mexer no controle não reescreve campo nenhum, não
  mexe no carrinho e não altera item gravado. Quem quiser a sugestão nova **clica nela**, como
  já faz hoje.
- **A coluna "Cob./Alvo"** continua mostrando `p.mesesCobertura` e `p.coberturaAlvo` — a
  cobertura atual e o alvo **do modelo**. O alvo simulado não substitui o alvo real na
  leitura; se substituísse, a pessoa perderia a referência de onde partiu. O valor simulado
  aparece **no controle**, que é onde ele mora.
- **As cores de "crítica" e "atingiu o alvo"** (`CatalogoPedido.jsx:390-400`) continuam
  calculadas sobre `p.coberturaAlvo`. Pintar de verde porque o alvo foi baixado no slider é
  fazer o indicador seguir o ajuste em vez de julgá-lo.
- **A ordenação não muda.** A lista é paginada e ordenada **no servidor**
  (`produto.ORDENACOES`); reordenar no cliente ordenaria os 50 da página e mentiria com
  aparência de funcionar.
- **Nada no dbt, nada no seed.** O `seed_fornecedor.csv` não é editado. (E, se um dia for:
  `dbt run` não roda `dbt seed`.)

---

## 5. Item 3 — filtro de produtos sem preço na Precificação

**Muda quem aparece na lista.** Não muda número nenhum.

### 5.1 "Sem preço" é `PV_ATACADO = 0` — e os dois lados foram medidos

Medido em `COMPRAS_PEDIDO` em 08/10/2026:

| | Ativos (4.552) | Inativos (4.392) |
|---|---|---|
| `PV_ATACADO` **nulo** | **0** | **0** |
| `PV_ATACADO = 0` | **205** | 2.898 |
| `PV_VAREJO = 0` | **205** | 2.899 |
| sem os **dois** | **205** | 2.898 |
| sem **algum** dos dois | **205** | 2.899 |

Três conclusões, e cada uma fecha uma pergunta do pedido:

1. **`PV_ATACADO` nunca é nulo.** A ausência de preço é gravada como **zero**, nos 8.944
   SKUs. O `nvl` entra mesmo assim, para a partição continuar exata se um dia houver nulo —
   é o mesmo cuidado do filtro de estoque (`produto.py:260-266`).
2. **"Com atacado e sem varejo" não existe entre os ativos**: os três conjuntos têm as mesmas
   205 linhas. Só há **1** caso assim, e é inativo. Portanto um critério composto por canal
   acrescentaria complexidade e mudaria **zero** linhas na tela que o Diretor usa. O corte é
   **um só, pelo atacado** — o canal pelo qual a tela já ordena (`ORDENACOES["preco"] =
   p.pv_atacado`) e pelo qual a margem é colorida.
3. **Não há preço negativo**, e o menor preço positivo ativo é **R$ 0,83** no atacado (5 SKUs
   abaixo de R$ 1,00). Por isso o corte é `> 0` e não `>= 1`: há produto com preço de
   centavos, e ele tem preço.

Contexto que dimensiona o filtro: dos **205 ativos sem preço**, **88 têm estoque** e **117
não**; **nenhum** tem média de venda. Somando todos os status, são **3.103 SKUs** e
**R$ 8,89 milhões** de valor de estoque sem preço de atacado. É lista grande o bastante para
merecer filtro e pequena o bastante (205 ativos) para caber em 5 páginas.

### 5.2 O desenho — molde do filtro de estoque da Etapa 15

**Partição exata do universo, sem terceiro estado:**

```
sem  →  nvl(p.pv_atacado, 0) = 0
com  →  nvl(p.pv_atacado, 0) > 0
          com + sem = total, sempre
```

- **Servidor.** Condição em `app/servicos/produto._condicoes`, logo após o bloco de estoque
  (`produto.py:260-266`) e **antes** do corte de `incluir_alerta` — assim ela também vale no
  `resumo`/contagem dos KPIs, pelo mesmo motivo que o filtro de estoque vale.
- **Parâmetro.** `preco: str | None` em `GET /api/produtos` (`rotas.py:168` é a linha vizinha,
  onde `estoque` está). **Whitelist estrito:** `None | "com" | "sem"`, qualquer outra coisa é
  **422** com mensagem em português, exatamente como `rotas.py:187-190` já faz. É entrada de
  usuário virando `where`.
- **Filtro de lista paginada é do servidor.** Não existe versão "filtra no cliente" disto: ela
  filtraria os 50 da página.
- **Tela.** Componente novo `web/src/componentes/FiltroPreco.jsx`, cópia estrutural de
  `FiltroEstoque.jsx` (três pílulas: *Todos* / *Com preço* / *Sem preço*), montado **só** em
  `Precificacao.jsx`, ao lado do `<FiltroEstoque>` (`:439`). `Pedidos.jsx` **não** recebe o
  filtro — não foi pedido.
- **Estado.** Acrescente `preco: ""` ao `FILTROS_PADRAO` de `Precificacao.jsx:88-91`, à
  desestruturação e ao `buscar()`. **A chave de `sessionStorage` não muda de versão**:
  `useEstadoPersistente` mescla campo a campo, então uma chave nova nasce no padrão e nada do
  que estiver guardado é perdido (`estadoTela.js:lerStorage`).
- Trocar o filtro chama `setPagina(1)`, como todos os outros.

---

## 6. O trabalho, por agente

### 6.1 `backend-fastapi` — `model: sonnet`, primeiro (item 3)

Primeiro porque o front do item 3 depende de o parâmetro existir.

**Ler antes:** `CONTEXTO.md §0` e `§2`; este documento §5; `app/servicos/produto.py:207-315`
(o `_condicoes` inteiro, com o bloco de estoque como molde); `app/api/rotas.py:150-230`.
**Não ler:** `REGRAS.md` (460 linhas, ~7,6 mil tokens — nada aqui é fiscal, margem, curva ABC
ou alerta); `historico/`; `dbt/`.

1. `produto._condicoes`: o par `preco` = "com"/"sem", com `nvl`, depois do bloco de estoque e
   antes do `if not incluir_alerta`.
2. `rotas.listar_produtos`: parâmetro `preco`, validação de whitelist com 422, entrada no dict
   `filtros`.
3. Comentário no código citando a medida: 205 ativos, `PV_ATACADO` nunca nulo, partição exata.

**Não faça:** não toque em `ORDENACOES` nem no whitelist de ordenação (nenhuma coluna nova é
ordenável); não mexa em `contrato.py` (nenhum campo novo no JSON); não toque em `preco.py`,
`lote_preco.py` nem em `APP_DECISAO_PRECO` — **esta etapa não grava nada**.

### 6.2 `frontend-react` — `model: sonnet`

Sonnet e não opus, apesar de a etapa mudar números na tela: as fórmulas estão escritas acima,
as duas que importam estão conferidas contra o banco (0/8.759 e 0/8.944), e não sobrou decisão
de cálculo para o executor tomar. O que ele faz é aplicar — mesmo critério da Etapa 18.

**Ler antes:** `CONTEXTO.md §0` e **§6, as regras 6 e 10** (as duas linhas do índice, não o
`REGRAS.md`); este documento; `web/src/precificacao.js` inteiro (138 linhas);
`web/src/formato.js:20-100`; `web/src/estadoTela.js`;
`web/src/telas/Precificacao.jsx:88-100`, `:150-200`, `:430-450` e `:890-971`;
`web/src/telas/DecisaoSKU.jsx:396-460` e `:550-575`;
`web/src/componentes/CatalogoPedido.jsx:80-88`, `:151-275` e `:378-500`;
`web/src/componentes/FiltroEstoque.jsx`.
**Não ler:** `REGRAS.md`; `historico/`; `docs/gabarito_pedido_formulas.txt`;
`v2/prototipo/painel_cedep_prototipo_2.jsx`; `dbt/`.

**Na ordem:**

1. **`web/src/precoEditavel.js`** (novo) — `precoDeMargem` e `precoDeMKP`, §3.2, com o
   comentário de cabeçalho citando a prova numérica. Importa `calcMKP`/`calcMargem` de
   `precificacao.js`; **não redefine nenhuma das duas**.
2. **`web/src/telas/Precificacao.jsx` → `CelulaEdicao`** — os dois inputs, o `editando` local,
   o `useEffect` de reset por `cenarioSel`, o tratamento de `null` (§3.3). O estado
   `precosAT`/`precosVAR` **não muda de forma**.
3. **`web/src/telas/DecisaoSKU.jsx` → `BlocoPreco`** — os mesmos dois inputs, mesma lógica,
   layout do bloco.
4. **`web/src/componentes/CatalogoPedido.jsx`** — o controle (slider + campo + "voltar ao alvo
   do modelo") em `FiltrosCatalogo`, por prop; o recálculo da coluna "Sug." em
   `LinhaCatalogo`, com `null` = usa `p.sugCobertura` sem recalcular.
5. **`web/src/telas/Pedidos.jsx` e `web/src/telas/PedidoDetalhe.jsx`** — só o
   `useEstadoPersistente` novo (chaves distintas) e o repasse das props. Nenhuma outra edição.
6. **`web/src/componentes/FiltroPreco.jsx`** (novo) + montagem em `Precificacao.jsx`
   (`FILTROS_PADRAO`, desestruturação, `buscar`, o JSX ao lado do `FiltroEstoque`).

**Não faça, em nenhuma hipótese:**

- não grave margem, MKP ou cobertura alvo em lugar nenhum — nem `APP_*`, nem `localStorage`;
- não multiplique nada por `fatorExibicao` dentro da conta de cobertura (§4.2), e não encoste
  nos totais de valor/peso/litros de `Pedidos.jsx:167-175`, onde a multiplicação **é** correta;
- não recalcule `PV_SUG_*` no cliente: a coluna "Sugerido" continua vindo do JSON;
- não troque `p.coberturaAlvo` pelo alvo simulado na coluna "Cob./Alvo" nem nas cores;
- não mexa em `alteracoesLote`, `definirPrecos`, no payload de `/lotes-preco` nem nas chaves
  de `sessionStorage` dos preços digitados;
- não ordene lista paginada no cliente; não acrescente coluna ordenável;
- não acrescente dependência em `web/package.json` nem URL externa em tela ou CSS — o
  dispositivo alvo é o celular na rede interna;
- não duplique marcação para celular: responsividade é CSS, uma marcação só;
- não troque `<button>` por `<Link>` nem o contrário; não mexa no `relative z-30` do cabeçalho
  nem na navegação de dois níveis;
- não altere `app/` (é da §6.1), `dbt/`, `sql/`, `validar/` nem `infra/`.

### 6.3 `validador` — `model: sonnet`

**Ler antes:** `CONTEXTO.md §0` e **§6 regras 6 e 10**; este documento §3.2, §4.1 e §5.1;
`validar/validar_grafico_produto.py` (molde da estrutura com autoteste);
`validar/validar_pedido.py:1795-1820` (credencial e conexão).
**Não ler:** `REGRAS.md`, `historico/`.

**Escrever `validar/validar_parametros_editaveis.py`.** Só leitura, só `COMPRAS`. Modo thick
obrigatório (`oracledb.init_oracle_client(lib_dir=r"C:\Oracle\instantclient_21_17")`; thin dá
`DPY-3015`).

Na ordem:

1. **Autoteste com o defeito injetado, primeiro.** Rode a inversa de margem **sem** o termo de
   comissão (`custo/(1 − icms − piscof − margem)`) e prove que ela **acusa**: tem de divergir
   de `PV_SUG_ST_S_VALOR_AV` em praticamente todas as 8.759 linhas. E rode a sugestão de
   cobertura **multiplicando por `FATOR_EXIBICAO`** e prove que ela acusa nos 516 SKUs de
   fator > 1. Validador que nunca reprovou não prova nada.
2. **Inversa de margem, real:** `custo/(1 − icms_sem_red − piscof_ef − comissao − margem_alvo)`
   × `PV_SUG_ST_S_VALOR_AV` — tolerância R$ 0,01; o mesmo para o cenário Oficial
   (`custo_tot_gerencial`, `icms_saida_ef`, `PV_SUG_OFICIAL_AV`) e para o varejo
   (`PV_SUG_ST_S_VALOR_VAR_AV`, com `margem_alvo_varejo`).
3. **Ida e volta:** aplicar a fórmula da margem ao preço que a inversa produziu devolve a
   margem de partida, tolerância 1e-6. É a prova de que os dois campos não divergem entre si.
4. **Sugestão de cobertura:** `greatest(0, round(media_janela × nvl(cobertura_alvo, 2) −
   est_pend, 0))` × `SUG_COBERTURA` — espera-se **8.944 de 8.944**. E a identidade do topo
   deste documento: `(est_pend + sug) / media_janela = alvo` para todo SKU com
   `media_janela > 0` e sugestão **não** clampeada em zero (quando clampeia, a identidade não
   vale — reporte à parte, não como falha).
5. **Partição do filtro de preço:** `com + sem = total`, por status, e a contagem recalculada
   de ativos sem preço (hoje 205) — **recalcule, não copie deste documento**.
6. **Spot-check pelo código de verdade**, não por SQL reescrito: `produto.obter` +
   `contrato.produto` para os SKUs 9, 11 e 28, conferindo que `cenariosAtacado[st_valor].custo`,
   `.icmsEf`, `pisCofinsEfetivo`, `margemAlvo` e `.pvSugeridoAV` chegam ao JSON com os valores
   da §3.2. É isso que prova que a conta do front opera sobre os campos que ele de fato recebe.

**Não faça:** não escreva em tabela nenhuma; não toque em `dbt/`; não trate `MESES_EST_PED`
como gabarito — ele carrega a mistura de unidades da planilha (Etapa 18 §3.3).

### 6.4 `infra-windows` — `model: haiku`, depois do front

**Ler antes:** `infra/README.md`. **Não ler:** mais nada.

O front em produção é estático, servido pelo FastAPI atrás do nginx — **não há Vite no ar**.
Sem este passo, nada disto chega ao Diretor.

1. `powershell -ExecutionPolicy Bypass -File infra\publicar.ps1` a partir de
   `C:\Users\Administrator\Desktop\app_compras_v2` (os scripts recusam rodar de outra pasta, e
   isso é proposital).
2. Confirmar o serviço NSSM `app_compras` em `Running` e as telas novas em
   `http://192.168.0.50/`.

**Não faça:** não edite `nginx.conf`, não rode `nginx -s reload`, não mexa em vhost nenhum — o
`nginx.conf` desta máquina serve outras áreas e esta etapa não muda rota, porta nem arquivo
servido. Não mexa na Tarefa Agendada. Não reinicie a máquina (socket órfão, `CONTEXTO.md
§0.4`).

### 6.5 `revisor` — `model: opus`, sempre o último

Opus porque a etapa mexe em margem e preço, e porque um parâmetro novo vira `where`. O revisor
**refaz as duas aritméticas contra o banco**, em vez de confiar nos números daqui.

**Ler antes:** `CONTEXTO.md` inteiro, este documento, o diff completo.
**Não ler:** `REGRAS.md`.

Checar, nomeadamente:

1. `dbt/`, `sql/`, `seeds/` e `infra/` **intactos** — `git status --short` só mostra `web/`,
   `app/`, `validar/` e `prompts/`.
2. Que **nada** grava margem, MKP ou cobertura alvo: nenhum `POST` novo, nenhuma coluna nova,
   `localStorage` não aparece em lugar nenhum.
3. Que o estado do preço digitado continua sendo **um número por célula** e que
   `alteracoesLote` não mudou de forma.
4. Que o campo de margem, **sob o cursor**, nunca é reescrito pelo recálculo — testando,
   digitando "20,55" caractere a caractere e conferindo que o cursor não pula.
5. Que com o controle de cobertura **intocado** a coluna "Sug." mostra `p.sugCobertura` do
   JSON, sem recálculo — e que nenhum `fatorExibicao` sobrou dentro de uma conta de cobertura.
6. Que `preco` inválido no `GET /api/produtos` devolve **422**, não 500 nem a lista inteira.
7. Que o autoteste do validador **falha de verdade** quando rodado com o defeito injetado —
   rodando, não lendo o código.

---

## 7. Quem não entra

| Agente | Por quê |
|---|---|
| `oracle-dba` | Nenhum DDL, nenhum GRANT, nenhuma tabela `APP_*` criada ou alterada. A decisão da §2 é justamente a de **não** mudar schema |
| `dbt-staging` | Nenhum `stg_*`, nenhum seed. `seed_fornecedor.csv` **não** é editado |
| `dbt-relatorios` | Os dois relatórios portados não têm nem margem alvo nem cobertura alvo |
| `dbt-regras` | Nenhum model de fiscal, margem, preço, curva ABC ou alerta é tocado. A fórmula do dbt é o **gabarito** que o cliente tem de reproduzir, não algo a alterar. Se a execução concluir que um model precisa mudar: **pare e reporte** — seria outra conversa, e mudaria `FAT_PEDIDO` |

---

## 8. Perguntas — só as que o executor não pode responder

**A. A margem alvo deve passar a ser GRAVADA por SKU?** A coluna
`APP_DECISAO_PRECO.MARGEM_ALVO` **já existe**, com `CHECK` entre −1 e 1, histórico em
`APP_DECISAO_PRECO_HIST`, exigência de perfil de diretoria e leitura pelo dbt
(`int_produto_preco_sugerido.sql:134`) — e está **vazia em 166 de 166 linhas**: ninguém nunca
decidiu uma margem alvo. Esta etapa a deixa vazia, pelos motivos da §2(b). Se o Diretor quiser
que o ajuste **fique valendo** e mude a coluna "Sugerido" de verdade, é outra etapa, e ela
carrega junto a decisão de quando mostrar o efeito (só depois do `dbt run`, ou com
sobreposição ao vivo no servidor).

**B. A cobertura alvo é do departamento. Se o ajuste tiver de ficar valendo, ele muda o
departamento ou o SKU?** Hoje é atributo de **fornecedor/departamento**, num seed
(`seed_fornecedor.csv`, 2,0 em 60 departamentos e 1,5 na ADIBRAX). Mudar o seed muda todos os
SKUs daquele departamento de uma vez; guardar por SKU exige uma tabela `APP_*` nova e um
conceito que o modelo não tem hoje. **Isto é decisão de negócio, não de desenho** — esta etapa
não a toma, e o controle de sessão funciona em qualquer um dos dois futuros.

**C. A cobertura alvo simulada deve valer para o recorte visível, ou por departamento?** Esta
etapa decidiu "um controle, para o que está na tela", porque `COBERTURA_ALVO` é praticamente
uniforme hoje (2,0 em 8.926 dos 8.944 SKUs) e a tela de edição de pedido já é travada em um
departamento. Se o Diretor quiser ajustar dois departamentos com alvos diferentes na mesma
lista de `/pedidos`, isso é um controle por departamento e é outro desenho.

**D. "Sem preço" é só o atacado?** Medido: entre os ativos, "sem atacado" e "sem varejo" são
**o mesmo conjunto de 205 SKUs** — o corte pelo atacado e um corte composto dariam listas
idênticas. Se o Diretor quiser, em algum momento, "tem atacado e falta varejo" como recorte
próprio, hoje ele alcançaria **1** SKU, inativo.

---

## 9. Aceite

Numerado, e cada item é uma demonstração. Os valores dependem de `COMPRAS_PEDIDO`, que muda a
cada `dbt run`: **recalcule o esperado na hora, pela fórmula; não copie destes números.** A
estrutura (hoje × depois) é o que não muda.

1. **Precificação, SKU 9 (PETROBRAS), cenário "ST s/Valor", bloco de atacado:** digitar **20**
   no campo de margem põe **356,41** no campo de preço — exatamente o valor da coluna
   "Sugerido AT" da mesma linha. Os dois números colados num print.
2. **O mesmo SKU 9:** digitar **455,40** no campo de preço mostra **34,5%** na margem e
   **1,91x** no MKP; digitar **1,91** no MKP devolve o preço a **455,4**. Ida e volta fechada
   nos três campos.
3. **O cursor não pula:** digitar "20,55" caractere a caractere no campo de margem — o campo
   mostra exatamente "20,55" e o preço acompanha. Demonstrado, não afirmado.
4. **Trocar o cenário de "ST s/Valor" para "Oficial" com um preço digitado:** o preço
   **permanece**, a margem e o MKP **mudam** (custo gerencial e `icms_saida_ef`), e nada é
   limpo.
5. **SKU sem custo no cenário** (um dos 51 ativos sem custo ST s/Valor): os campos de margem e
   MKP nascem **desabilitados**, e o campo de preço continua funcionando como hoje.
6. **Varejo:** margem e MKP editáveis no bloco verde operam sobre o cenário do varejo, de forma
   independente do atacado; mexer num não altera o outro.
7. **Decisão do SKU do 9:** os mesmos três campos, com os mesmos números do item 1 — uma conta,
   duas telas.
8. **Pedidos, controle de cobertura intocado:** a coluna "Sug." de uma página inteira é
   **idêntica** a `p.sugCobertura` do JSON (compare contra `/api/produtos` na aba de rede). Com
   `null`, zero recálculo.
9. **PETRONAS 7305** (fator 24, `MEDIA_JANELA` 1.459,6111 cx, `EST_PEND` 0,5833,
   `SUG_COBERTURA` 2.919): pôr o controle em **3,0** faz a coluna "Sug." mostrar **4.378**.
   Clicando nela, e **com a Etapa 18 já aplicada**, a cobertura projetada mostra **3,0**. (Sem
   a Etapa 18 ela mostra ~72 — é a prova de que a ordem importa.)
10. **Controle, PETROBRAS 11** (fator **1**, média 4, `EST_PEND` 0, `SUG_COBERTURA` 8): em 3,0
    a sugestão vira **12** e a projetada, **3,0**. Mesmo resultado que o item 9 com fator 24 —
    é este item que pega a correção aplicada no lugar errado.
11. **"Voltar ao alvo do modelo"** devolve a coluna "Sug." aos valores do item 8, e **nenhuma
    quantidade digitada ou gravada muda** em nenhum dos passos 9 a 11.
12. **O controle sobrevive:** ajustar para 3,0, abrir um produto, voltar, trocar de página —
    continua em 3,0. Fechar a aba e reabrir o app — volta ao alvo do modelo.
13. **Filtro "Sem preço" na Precificação, status Ativo:** mostra **205** produtos; "Com preço"
    mostra **4.347**; "Todos" mostra **4.552**. `205 + 4.347 = 4.552`, a partição fecha. Os
    três números recalculados na hora.
14. **`GET /api/produtos?preco=xyz`** devolve **422** com mensagem em português; `preco=sem`
    devolve a mesma contagem do item 13. Resposta colada.
15. `validar/validar_parametros_editaveis.py` **rodado**, saída colada: o autoteste com defeito
    injetado **acusa** nos dois casos; a inversa de margem fecha em **0 divergências** contra
    `PV_SUG_*`; a sugestão de cobertura fecha em **8.944 de 8.944**; a partição do filtro fecha
    por status.
16. `git status --short` colado: nada sob `dbt/`, `sql/` nem `infra/`. Nenhuma linha nova em
    `web/package.json`.
17. `infra\publicar.ps1` rodado, serviço `app_compras` em `Running`, e os itens 1, 9 e 13
    conferidos **em `http://192.168.0.50/`** — não no Vite da máquina de desenvolvimento.
18. Relatório final nomeando, em uma linha cada: o que passou a ser editável, o que
    deliberadamente **não** é gravado (§2) e por quê, e a resposta às perguntas A a D se o
    Diretor já as tiver dado.
