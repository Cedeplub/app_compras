# Etapa 12 — Preços Definidos: a decisão de preço vira documento

> **Prompt de execução.** Origem: mensagem do Diretor de Compras por WhatsApp em
> 09/09/2026, com print da tela de Precificação e um protótipo `.jsx` novo
> (`painel_cedep_prototipo_090926.jsx`, 4.092 linhas). Este documento traduz o pedido em
> tarefa, nomeia os arquivos, distribui por agente e fixa o aceite.
>
> **O `.jsx` do Diretor é referência, não fonte.** Nada dele é copiado e colado: as telas
> são construídas no padrão do `web/` que já existe. O que se porta é layout, rótulo,
> ordem de coluna e a máquina de estados — não o código.

---

## 1. O que o Diretor disse, e o que isso significa

Verbatim, na ordem em que ele escreveu:

1. *"A precificação quando eu coloco em gravar o preço, fica um preço decidido pequeno,
   mas não tem muita serventia."*
2. *"E nem tem opção de editar se eu quiser."*
3. *"Deveria ter um processo gerar uma planilha para eu enviar para Cassio ou Gabriela
   inserir no sistema ou até uma forma de importar essas alterações para facilitar."*
   — com o link da rotina **201** do Winthor (importação de preço de venda).
4. *"Atacado é região 2. Varejo é região 1."*
5. *"E só altera/importa o preço à vista, o preço a prazo o sistema que calcula."*
6. *"O Claude criou um exemplo aí de como seria, mas pode fazer da melhor maneira aí. Às
   vezes vocês conseguem fazer de forma mais efetiva e otimizada."*
7. *"Aí está baseado no meu protótipo antigo antes da sua implementação, então não leva em
   conta o restante, só a ideia da gravação das alterações de preço."*

Tradução: **a decisão de preço hoje morre onde nasce.** O Diretor grava, aparece
"decidido R$ 64,00" em corpo 9, e nada acontece com aquilo — nenhum documento, nenhum
arquivo, nenhum caminho até quem digita o preço no Winthor. O que falta não é um botão de
exportar: é a entidade que hoje não existe, **o lote de preços como documento**, com
status, itens congelados e histórico — exatamente o que a Etapa 9 fez para o pedido.

Os itens 1 e 2 são **defeito**, e o 2 é defeito de código, não de desenho (§2). O 3, 4 e
5 são **escopo novo**. O 6 é permissão explícita para divergir do protótipo dele quando
houver razão — e há três (§4.4, §4.5 e §4.6). A do §4.6 não é preferência: a documentação
da rotina 201 **não aceita o nosso código de produto**, e é o que mais muda o desenho.

---

## 2. Os dois defeitos, já localizados (não é preciso investigar)

**Defeito A — depois de gravar uma vez, a célula não grava mais.**
`web/src/telas/Precificacao.jsx:702` — `{podeSalvar && estado !== "salvo" && (`. O
`estado` é `useState` local de `CelulaEdicao` (linha 646) e nunca volta de `"salvo"` para
`"parado"`. Como `Linha` tem `key={p.codigo}`, o `buscar()` que roda depois de gravar
(linha 134) refaz o *render* mas **não remonta** o componente: o estado sobrevive. Efeito:
gravou o preço do SKU 6871, digita outro valor, e o botão "Gravar" não reaparece — só
volta trocando de página ou de filtro. **É literalmente o "nem tem opção de editar".**

O mesmo defeito, no mesmo formato, está em `web/src/telas/DecisaoSKU.jsx:384`
(`BlocoPreco`, estado na linha 291).

**Defeito B — o campo é esvaziado depois de gravar.**
`web/src/telas/Precificacao.jsx:130,133` apagam a entrada do mapa `precosAT`/`precosVAR`
depois do POST. O `input` volta a mostrar o *placeholder* (a sugestão do cenário) e o
valor decidido sobra só como texto cinza de 9px. Para ajustar de R$ 64,00 para R$ 66,00 é
preciso redigitar de cabeça — o número que ele mesmo decidiu não volta para o campo.

Os dois são de tela. Nada de banco, nada de dbt.

---

## 3. O que já existe e vai ser reaproveitado (não reconstrua)

| Peça | Onde | Serve para |
|---|---|---|
| Decisão de preço, com histórico e transação | `app/servicos/preco.py` (`_gravar_decisao_preco_conn`, `gravar_decisao_preco_lote`) | Continua sendo o dono de `APP_DECISAO_PRECO` — **não reescreva** |
| Máquina de estados de documento | `app/servicos/pedido.py:437` (`_transicionar`), `sql/03_tabelas_pedido.sql` | Molde exato do lote de preços |
| Gerador de xlsx sem cabeçalho | `app/servicos/pedido.py:598` (`_gerar_xlsx_winthor`) | Molde do arquivo da rotina 201 |
| Gerador de xlsx "rico", com estilo | `app/servicos/exportacao.py` (`gerar_xlsx`) | Molde do Excel de conferência |
| Download por blob + `Content-Disposition` | `web/src/api/cliente.js:169` (`baixarExportacao`) | Molde do download dos arquivos |
| PDF por `window.print()` em overlay | `web/src/telas/PedidoDetalhe.jsx:460` | Molde do comprovante de preços |
| Lista com filtro de status múltiplo + detalhe | `web/src/telas/PedidosSalvos.jsx`, `PedidoDetalhe.jsx`, `web/src/pedidoStatus.js` | Molde das duas telas novas |
| Região 1 = varejo, 2 = atacado | `dbt/compras/models/staging/stg_preco_tabela.sql` | **O de-para do Diretor já está no modelo, comentado no código.** Não é para acreditar, é para citar |

**O front não ganha dependência nova.** O protótipo do Diretor usa `xlsx` (SheetJS) no
navegador; o nosso gera planilha **no servidor**, com `openpyxl`, como já faz o pedido.
Não adicione pacote em `web/package.json`.

---

## 4. As decisões de projeto — tomadas, com o motivo

### 4.1 O lote é uma tabela nova, e a decisão de preço continua onde está

`APP_DECISAO_PRECO` tem PK em `ID_PRODUTO`: uma linha por SKU, sem dono, sem status, sem
documento. É o mesmo impasse que `APP_DECISAO_PEDIDO` tinha antes da Etapa 9, e a resposta
é a mesma: **entidade nova, a antiga intacta.** As duas coisas são de fato diferentes —
`ALT_PV_AT_AV` é o que volta para o modelo no próximo `dbt run` (CONTEXTO §6 regra 10); o
lote é o que sai da diretoria em direção a quem digita no Winthor.

### 4.2 Decidir o preço e criar o documento são **um ato só**

O botão "Definir preços (N)" abre **uma transação** que: grava `APP_DECISAO_PRECO` com
histórico (chamando `preco._gravar_decisao_preco_conn`, sem duplicar regra), cria o
`APP_LOTE_PRECO` em Rascunho, insere os itens com o *snapshot* do preço atual, e registra
auditoria. Ou tudo, ou nada.

Por quê: gravar decisão sem gerar documento é justamente o beco sem saída de que o Diretor
reclamou. Não se conserta um beco sem saída mantendo o beco.

**Consequência: o botão "Gravar" de cada célula sai da tela de Precificação**, absorvido
pelo botão do rodapé. O de `DecisaoSKU.jsx` (um SKU por vez) **fica** — lá a decisão é
unitária e deliberada, e ele passa a criar um lote de 1 item, ou a somar a um lote em
Rascunho do próprio usuário se houver (§4.3).

### 4.3 Um lote em Rascunho por usuário, e ele acumula

`POST /api/lotes-preco` sem `idLote` cria um lote; com `idLote` acrescenta itens a um lote
existente em Rascunho. A tela reaproveita o Rascunho aberto do próprio usuário quando
existe, para que decidir preço hoje de manhã e mais 30 à tarde não vire dois arquivos para
a equipe de cadastro. Fechar o lote é explícito: "Marcar enviado".

⚠ **O teto de 200 itens por requisição continua valendo** (`preco.LIMITE_LOTE_PRECO`, e o
pool de 4 conexões é o motivo). Acima disso o front parte em pedaços — e **todos os
pedaços vão para o MESMO lote**: o primeiro cria, os seguintes acrescentam com o `idLote`
devolvido. Partir em N lotes seria produzir N documentos em silêncio, que é o defeito que
esta etapa existe para matar.

### 4.4 Canal não decidido fica **NULO** — divergência deliberada do protótipo

No `.jsx` do Diretor, `definirPrecos()` preenche os dois canais sempre:
`precoAtacadoNovo: Number(precosAtacado[codigo]) || p.pvAtacado`. Ou seja, quem mexeu só no
atacado sai do processo com uma linha de varejo dizendo "novo preço = o preço que já está lá".

No nosso, o canal não tocado é `NULL`, e **o arquivo da rotina 201 de um canal só traz os
itens com decisão naquele canal**. Motivo: um arquivo de importação que reescreve preço não
decidido pede à equipe de cadastro para alterar o que ninguém pediu, e reimportar valor igual continua
sendo uma alteração de preço no histórico do Winthor. Também é o que distingue "o Diretor
decidiu" de "o sistema repetiu", que é a linha que este projeto inteiro defende.

### 4.5 "Aplicado" passa a ser **medido**, não declarado — a parte "mais efetiva" do item 6

No protótipo, "Marcar aplicado no Winthor" é um botão de confiança: alguém clica e o
sistema acredita. Mas nós temos como conferir de graça: depois que a equipe de cadastro importa e o
próximo `dbt run` roda, `stg_preco_tabela` (PCTABPR, por `NUMREGIAO`) chega em
`COMPRAS_PEDIDO.PV_ATACADO`/`PV_VAREJO`. Então, no detalhe do lote, cada item mostra:

- **aplicado** — `|preço do banco − preço novo| < 0,005`
- **pendente** — o banco ainda está no preço antigo
- **divergente** — o banco mudou, mas para um terceiro valor

E a lista de lotes mostra "12 de 15 aplicados". Custo: um `join` com `COMPRAS_PEDIDO` na
leitura. Zero tabela nova, zero model dbt novo.

⚠ **A conferência tem a idade do último build.** A tela precisa dizer isso na cara, com o
carimbo que já existe em `/api/atualizacao` (`web/src/contexto/atualizacao.jsx`):
*"conferido com os dados de 09/09 06:05"*. Sem essa frase, um preço aplicado às 10h aparece
como pendente às 11h e o indicador perde a credibilidade em uma semana.

### 4.6 O identificador do arquivo **não é o nosso código de produto** — e isso é o ponto mais importante desta etapa

A documentação da rotina 201 (print da TOTVS confirmado pelo usuário em 10/09/2026) diz,
literalmente:

> *"Código de identificação do produto (1 - Código de Barras (UN - Venda) ou 2 - Código de
> Barras (UN - Master) ou 3 - Cód. de Fab. (Rotina 203) ou 4 - Cód. de Fab. (Rotina 253))
> informado na coluna A; Preço de venda do produto informado na coluna B."*

E o exemplo da planilha começa na **linha 1 com dado** (`191 | 3,5`) — confirmado: **sem
cabeçalho, duas colunas**. Isso valida o formato do protótipo, **mas derruba a premissa do
identificador**: o `CODPROD` interno da CEDEP — o número que aparece na coluna "Código" de
todas as nossas telas — **não é uma das quatro opções**. O comentário do protótipo do
Diretor ("a CEDEP usa o código interno como identificador") está errado.

Das quatro opções, **temos uma**: `COMPRAS_PEDIDO.COD_FAB`, que vem de `PCPRODUT.CODFAB`
(`stg_produto.sql:8`) — a **opção 3, Cód. de Fab. da rotina 203**. Código de barras
(opções 1 e 2) mora em `PCEMBALAGEM`, que **não é source do nosso dbt**; a opção 4 é o
código de fábrica por fornecedor da rotina 253, que também não está no modelo.

**Então o arquivo da 201 sai com `COD_FAB` na coluna A.** Medido no banco em 10/09/2026,
para saber o tamanho do problema que isso cria:

| Medida | Número |
|---|---|
| Produtos ativos (o universo da tela de Precificação) | **4.558** |
| Ativos **sem** `COD_FAB` | **49** (1,1%) |
| Ativos com `COD_FAB` **repetido em outro produto ativo** | **14 SKUs**, em 6 códigos |
| (o pior caso) `COD_FAB = '120717.0.02'` | **4 SKUs**: 8170, 8171, 8172, 8173 |
| Catálogo inteiro sem `COD_FAB` (quase todo inativo) | 2.390 de 8.841 |

Há também códigos de fábrica que são lixo de cadastro e agravam a colisão: `'2'` (SKUs 1883
e 6643), `'0000010'`, `'000019'`.

**A regra, então:** esses itens **entram no lote** — a decisão de preço é válida e o
documento é dela, não do identificador —, mas **não entram no arquivo da 201**, e a tela
diz na cara quais e por quê:

> *"3 itens não entram no arquivo de importação: 2 sem código de fábrica, 1 com código de
> fábrica repetido em outro produto. Eles estão no Excel de conferência, para digitação
> manual."*

Excluir é obrigatório, não conservador: importar um `COD_FAB` repetido **muda o preço de
até 4 produtos de uma vez**, e nenhum deles necessariamente é o que o Diretor decidiu. Esse
é o modo de falha caro desta etapa, e é silencioso — o arquivo importa "com sucesso".

⚠ **Na rotina 201, quem importa precisa escolher "3 - Cód. de Fab. (Rotina 203)"** no seletor
de código de identificação, e a região certa. Se ele deixar no padrão (código de barras),
a importação não acha nada — ou pior, acha outra coisa. Essa instrução vai **na tela**, ao
lado dos botões, e **no nome do arquivo**.

### 4.7 Baixar o arquivo **não** avança o status — divergência do precedente do pedido

Em `pedido.exportar_winthor` gerar o arquivo avança Fechado → Exportado na mesma
transação, e está certo lá: é um arquivo só. Aqui são **dois** (atacado e varejo). Se
baixar o do atacado marcasse o lote como Enviado, o do varejo ficaria para trás com o lote
dizendo que já foi. Então: baixar é baixar, "Marcar enviado" é um clique explícito, e cada
download vira linha de auditoria com o canal.

---

## 5. As tabelas novas

Arquivo: **`sql/05_tabelas_lote_preco.sql`**, no molde de `sql/03_tabelas_pedido.sql` —
idempotente (checa `USER_TABLES` antes de cada `CREATE`), `comment on column` em toda
coluna dizendo **por que ela existe**, nomes de constraint com até 30 caracteres.

```
APP_LOTE_PRECO
  id_lote            number generated always as identity   pk
  status             varchar2(20) not null  check in ('Rascunho','Enviado','Aplicado')
  observacao         varchar2(400)          -- recado livre do Diretor para quem digita
  criado_em/por      timestamp / varchar2(60) not null
  atualizado_em/por
  index (status)

APP_LOTE_PRECO_ITEM
  id_lote            number not null   fk -> app_lote_preco  on delete cascade
  id_produto         number(10) not null
  pv_atacado_atual   number(14,4)      -- SNAPSHOT de COMPRAS_PEDIDO.PV_ATACADO na criação
  pv_atacado_novo    number(14,4)      -- NULO = atacado não foi decidido (§4.4)
  pv_varejo_atual    number(14,4)
  pv_varejo_novo     number(14,4)
  criado_em/por, atualizado_em/por
  pk (id_lote, id_produto)
  check (pv_atacado_novo is null or pv_atacado_novo > 0)          -- idem varejo
  check (pv_atacado_novo is not null or pv_varejo_novo is not null)  -- item vazio não existe

APP_LOTE_PRECO_STATUS_HIST
  id_hist, id_lote (fk cascade), status_anterior, status_novo, alterado_em, alterado_por
  check (status_anterior is null or status_anterior <> status_novo)
  index (id_lote, alterado_em)
```

**Por que `pv_*_atual` é congelado:** é o que dá sentido ao documento. Depois que a equipe de cadastro
aplica, `PV_ATACADO` no banco passa a ser o preço novo — e um "atual" lido ao vivo faria a
coluna "de → para" mostrar "de R$ 66,00 para R$ 66,00". Mesmo raciocínio do
`fator_exibicao` congelado em `APP_PEDIDO_ITEM` (MELHORIA A5).

---

## 6. O trabalho, por agente

### 6.1 `oracle-dba` — `model: sonnet`

**Tarefa:** criar `sql/05_tabelas_lote_preco.sql` conforme §5 e executá-lo no schema
`COMPRAS`. Conferir por `user_tab_columns` que as três tabelas subiram, e reportar a
contagem de colunas de cada uma.

**Leia:** `CONTEXTO.md` e `sql/03_tabelas_pedido.sql` (o molde). **Não leia `REGRAS.md`.**

**Não faça:** nada em `CEDEP`; nada com prefixo que não seja `APP_`; nenhuma alteração em
`APP_DECISAO_PRECO` nem em `APP_DECISAO_PRECO_HIST` — elas ficam como estão.

### 6.2 `backend-fastapi` — `model: sonnet`

**Tarefa 1 — serviço novo `app/servicos/lote_preco.py`.** No molde de
`app/servicos/pedido.py`, com as mesmas exceções nomeadas (`LoteNaoEncontrado`,
`TransicaoInvalida`, `EdicaoNaoPermitida`, `ProdutoInvalido`):

- `criar_lote(itens, observacao, usuario…)` e `acrescentar_itens(id_lote, itens, usuario…)`
  — uma transação, gravando `APP_DECISAO_PRECO` **pela função que já existe**
  (`preco._gravar_decisao_preco_conn`), lendo `PV_ATACADO`/`PV_VAREJO` de `COMPRAS_PEDIDO`
  para o *snapshot*, e recusando o lote inteiro se algum código não existir — o
  `gravar_decisao_preco_lote` já tem essa validação, copie o critério, nomeando os SKUs.
- `listar_lotes(filtros, pagina, por_pagina)` e `obter_detalhe(id_lote)` — com a
  conferência de aplicação de §4.5 no `join` com `COMPRAS_PEDIDO`.
- `upsert_item` e `remover_item` — só em Rascunho/Enviado. **Editar item regrava
  `APP_DECISAO_PRECO`** (o documento e o modelo não podem divergir). **Remover item NÃO
  desfaz a decisão** — sai do arquivo, permanece decidido; a tela precisa dizer isso em uma
  linha.
- `avancar_status` / `voltar_status` — um passo por vez, desfazer simétrico, 409 no pulo,
  histórico em `APP_LOTE_PRECO_STATUS_HIST`.
- `excluir_lote` — apaga o documento, não a decisão.
- `gerar_excel_conferencia(id_lote)` → colunas `Código CEDEP · Cód. Fábrica · Produto ·
  Departamento · Atacado atual · Atacado novo · Δ% atacado · Varejo atual · Varejo novo ·
  Δ% varejo · A prazo atacado · A prazo varejo · **Entra no arquivo 201?**`, com cabeçalho
  e largura de coluna, no molde de `exportacao.gerar_xlsx`. A última coluna diz "sim" ou o
  motivo da exclusão ("sem cód. de fábrica" / "cód. de fábrica repetido") — é ela que
  permite à equipe de cadastro digitar à mão o que o arquivo não carrega (§4.6). O a prazo vem de
  `ALT_PV_AT_AP`/`ALT_PV_VAR_AP` de `COMPRAS_PEDIDO` (calculado pelo dbt) — **informativo,
  e a planilha diz isso**, porque quem calcula o a prazo é o Winthor (item 5 do Diretor).
- `gerar_xlsx_201(id_lote, canal)` → **exatamente 2 colunas, sem cabeçalho**: coluna A o
  **`COD_FAB`** (§4.6 — não o `CODIGO`), coluna B o preço à vista com 2 casas
  (`number_format = "0.00"`). Entram só os itens que têm decisão naquele canal (§4.4)
  **e** `COD_FAB` preenchido **e** não repetido em outro produto. Devolva junto a lista de
  excluídos com o motivo, para a tela e a auditoria — arquivo que sai menor do que o lote
  sem dizer por quê é pior que arquivo nenhum. O identificador fica em **uma constante só**
  no módulo, com o comentário das quatro opções da rotina: se a equipe de cadastro pedir código de
  barras, muda ali (e aí é dbt, ver §9). Nome do arquivo:
  `winthor_201_atacado_regiao2_codfab203_<id>.xlsx` /
  `winthor_201_varejo_regiao1_codfab203_<id>.xlsx` — região e tipo de código no nome,
  porque são as duas escolhas que quem importa faz na tela da 201 e errar qualquer uma escreve
  preço no lugar errado.

  ⚠ A checagem de `COD_FAB` repetido é **contra o catálogo inteiro**, não contra os itens
  do lote: o risco é o código do lote colidir com um produto que não está nele.

**Tarefa 2 — rotas em `app/api/rotas.py`**, com a mesma tradução de erro do pedido (use
`_erro_pedido` como molde de um `_erro_lote`):

```
POST   /api/lotes-preco                        cria (ou acrescenta, com idLote)   diretoria
GET    /api/lotes-preco                        lista, filtro de status múltiplo   login
GET    /api/lotes-preco/{id}                   detalhe + conferência              login
PUT    /api/lotes-preco/{id}/itens/{codigo}    edita o preço do item              diretoria
DELETE /api/lotes-preco/{id}/itens/{codigo}    remove o item                      diretoria
POST   /api/lotes-preco/{id}/avancar|voltar    status                             diretoria
DELETE /api/lotes-preco/{id}                   exclui                             diretoria
GET    /api/lotes-preco/{id}/exportar/excel    xlsx de conferência                login
GET    /api/lotes-preco/{id}/exportar/201      xlsx da rotina 201, `?canal=`      login
```

**Por que exportar é `login` e não `diretoria`:** decidir preço é da diretoria; baixar o
arquivo para levar à equipe de cadastro não é decisão. Se o Diretor preferir travar, é um `Depends` —
está registrado em §9 como pergunta a ele.

**Tarefa 3 — `app/api/contrato.py`:** `lote_preco()`, `item_lote_preco()` e
`pagina_lotes_preco()`, no molde exato de `pedido()` / `item_pedido()`. O item leva
`situacao: "aplicado" | "pendente" | "divergente" | null` e `pvAtacadoBanco` /
`pvVarejoBanco` (o que o banco tem hoje), para a tela poder mostrar "de → para → está".

**Leia:** `CONTEXTO.md` e `app/servicos/pedido.py`. **Não leia `REGRAS.md`** — não há
cálculo fiscal nesta etapa; toda margem e todo preço sugerido chegam prontos de
`COMPRAS_PEDIDO`. Se você se pegar calculando alíquota, a tarefa é de outro agente.

**Não faça:** nenhuma consulta ao `CEDEP`; nenhum acesso a banco fora de
`app/core/database.py`; nenhuma escrita em tabela sem prefixo `APP_`; nenhuma fórmula de
margem nova em Python.

### 6.3 `frontend-react` — `model: sonnet`

**Tarefa 1 — os dois defeitos (§2). Pode começar antes de tudo: não depende de banco.**

- `web/src/telas/Precificacao.jsx:702` e `web/src/telas/DecisaoSKU.jsx:384`: o `estado`
  volta para `"parado"` assim que o valor digitado muda. O caminho direto é derivar o
  estado do valor em vez de guardá-lo cru — `useEffect` no valor, ou o próprio `aoTrocar`
  limpando o estado. "Salvo" é um aviso momentâneo, não um estado permanente da célula.
- O `input` passa a **nascer com o preço decidido** quando existe decisão (editável — é a
  correção do item 2 do Diretor); a sugestão do cenário fica no *placeholder* apenas quando
  **não** há decisão, e nesse caso passa para a linha de apoio de baixo, rotulada
  "sugerido". ⚠ Isto **não** viola a regra 10 do CONTEXTO: campo preenchido com um número
  que uma **pessoa decidiu** é o oposto de campo preenchido por cálculo. O que continua
  proibido é o campo nascer com a sugestão.
- `Precificacao.jsx:130,133`: ao gravar, em vez de apagar a entrada do mapa, sincronize-a
  com o valor gravado (`{valor, decidido: valorGravado}`) — assim o campo continua
  mostrando o número e o contador do rodapé para de contá-lo como pendente pelo critério
  que já existe (`Math.abs(num − decidido) >= 0,005`).

**Tarefa 2 — Precificação: o botão do rodapé passa a ser "Definir preços (N)".** O
`ConfirmarGravarLote` (linha 400) vira `ConfirmarDefinirPrecos`, dizendo com números o que
vai acontecer: *"N produtos, M preços. Isto grava a decisão e cria um lote em Rascunho na
área Preços Definidos."* Mantenha o aviso de "X fora da página atual" — é bom e foi pedido
antes. Some o botão por célula (§4.2). Depois de definir, a faixa verde de sucesso leva
para o lote criado: link, não só texto.

**Tarefa 3 — área nova.** `web/src/componentes/Cabecalho.jsx:21` (array `AREAS`): entrada
`precos_definidos` → `/precos-definidos`, rótulo "Preços Definidos", sub "Lotes de preço
para a equipe de cadastro aplicar", ícone `Save` (é o do protótipo, linha 421).
`web/src/App.jsx`: rotas `/precos-definidos` e `/precos-definidos/:id`, entradas em
`TITULOS`, e o prefixo em `areaDaRota`.

**Tarefa 4 — telas novas**, no molde de `PedidosSalvos.jsx` e `PedidoDetalhe.jsx`:

- `web/src/lotePrecoStatus.js` — espelho de `pedidoStatus.js`: `STATUS`, `COR_STATUS`
  (Rascunho `#6B7280`, Enviado `#B98A2E`, Aplicado `#15803D` — as cores do protótipo),
  `editavel`, `ROTULO_AVANCAR` (`{Rascunho: "Marcar enviado", Enviado: "Marcar aplicado no
  Winthor"}`), `ROTULO_VOLTAR`. Com o mesmo cabeçalho dizendo que a regra vive no servidor
  e que isto decide só o que a tela desenha.
- `web/src/telas/PrecosDefinidos.jsx` — lista com filtro de status múltiplo (Rascunho e
  Enviado já marcados, como no protótipo), colunas Data · Itens · Status · **Aplicados
  (12/15)** · Ações. Ações: Ver/editar, Excel, os dois arquivos 201, avançar, e excluir com
  confirmação.
- `web/src/telas/LotePrecoDetalhe.jsx` — cabeçalho com status e o controle de
  avançar/desfazer sempre visível (o protótipo faz isso de propósito, e o motivo está no
  comentário da linha 2145: sem ele dá para ficar preso num status errado). Tabela Produto ·
  Atacado atual · Atacado novo · Varejo atual · Varejo novo · **Situação**, com os dois
  "novo" editáveis em Rascunho/Enviado e texto em Aplicado. Botões: PDF, Excel, Importar
  Atacado — região 2 (201), Importar Varejo — região 1 (201). Sob eles, a frase do
  protótipo, que é boa e é dele: *"Os dois arquivos já vão prontos para a rotina 201 do
  Winthor — só o preço à vista, o Winthor calcula o a prazo sozinho."* Overlay de impressão
  no molde de `PedidoDetalhe.jsx:460`.

  Mais duas coisas que esta tela **precisa** dizer, por causa de §4.6:

  1. **A instrução de importação, ao lado dos botões:** *"Na rotina 201, escolha a região
     (2 = atacado, 1 = varejo) e o código de identificação **3 - Cód. de Fab. (Rotina
     203)**."* Não é enfeite: é a escolha que decide se o arquivo acerta o produto.
  2. **Os itens que não entram no arquivo**, contados no topo e etiquetados na linha —
     "sem cód. fábrica" ou "cód. fábrica repetido", em âmbar, com o `COD_FAB` visível na
     linha. O contador é frase, não número solto: *"3 dos 15 itens não entram no arquivo de
     importação — estão no Excel, para digitação manual."*
- `web/src/api/cliente.js` — os métodos novos. `baixarExportacao` (linha 169) está com o
  caminho do pedido cravado: extraia o miolo para um `baixarArquivo(caminho)` e faça as
  duas chamadas usarem ele. Não duplique o tratamento de `Content-Disposition`.

**Regras de tela que valem em tudo desta etapa** (§5 do `v2/PLANO.md`): estado de
carregando, de erro e de vazio em cada tela; sair do detalhe com edição pendente avisa;
excluir pede confirmação; celular a 400px sem rolagem horizontal do corpo (a tabela do lote
rola dentro do container dela, como as outras); nenhuma URL externa.

**Leia:** `CONTEXTO.md`, `v2/PLANO.md` e as três telas-molde. **Não leia `REGRAS.md`.** O
`.jsx` novo do Diretor está em
`C:\Users\Administrator\.claude\uploads\d3949555-3c26-4f2f-b5b1-8126c8ad82eb\6744cd77-painel_cedep_prototipo_090926.jsx`
— use as linhas 1363-1460 (exportações e comprovante) e 2114-2382 (área 5) **como
referência de layout e rótulo**, nunca como código a copiar: ele não conhece rota, sessão,
permissão, paginação nem os 8.772 SKUs.

### 6.4 `validador` — `model: sonnet`

**Tarefa:** `validar/validar_lote_preco.py`, com autoteste — defeito injetado antes de
valer, que é a lição do CONTEXTO. Prove, com número:

1. O xlsx da 201 tem **2 colunas e zero linha de cabeçalho**, a coluna A é o `COD_FAB` (e
   **não** o `CODIGO`), e a contagem de linhas é igual à de itens elegíveis **naquele**
   canal. Injete um item só de varejo e prove que ele não aparece no arquivo do atacado.
2. **As duas exclusões de §4.6, com os SKUs reais do banco:** um item sem `COD_FAB` (dos 49
   ativos) e um com `COD_FAB` repetido (use `120717.0.02` — SKUs 8170/8171/8172/8173) entram
   no lote, **não** entram no arquivo, aparecem na lista de excluídos com o motivo certo, e
   aparecem no Excel de conferência com a coluna "Entra no arquivo 201?" preenchida. Este é
   o teste que impede a falha caríssima e silenciosa da etapa.
3. O preço gravado no arquivo é o **à vista**, com 2 casas — nunca `ALT_PV_*_AP`.
4. Criar lote é atômico: um código inexistente no meio de 30 recusa os 30 e não deixa nem
   decisão nem lote.
5. Editar item de lote atualiza `APP_DECISAO_PRECO` **e** grava `APP_DECISAO_PRECO_HIST`.
6. Transição: Rascunho → Aplicado dá 409; desfazer volta um passo; toda transição deixa
   linha em `APP_LOTE_PRECO_STATUS_HIST`.
7. Conferência de aplicação: monte os três casos (aplicado, pendente, divergente) e prove
   que a classificação respeita a tolerância de 0,005.

### 6.5 `revisor` — `model: opus`. Último, sempre.

Revise **só o que esta etapa mudou**: `sql/05_tabelas_lote_preco.sql`,
`app/servicos/lote_preco.py`, `app/api/rotas.py`, `app/api/contrato.py`, as três telas
novas, as duas alteradas, `cliente.js` e o validador. Além da sua lista habitual, procure
especificamente:

- **Fórmula duplicada.** Nenhuma margem, MKP ou preço a prazo recalculado em Python nesta
  etapa: tudo vem de `COMPRAS_PEDIDO`. O projeto já carrega uma fórmula duplicada de
  propósito (`int_produto_pedido.sql` × `app/servicos/compra.py`) e não vai ganhar outra.
- **Decisão humana virando cálculo.** O `input` que nasce preenchido é legítimo só quando o
  valor vem de `APP_DECISAO_PRECO`. Se em algum caminho ele nascer com `PV_SUG_*`, é
  quebra da regra 10.
- **Gravação parcial silenciosa.** Criar lote, acrescentar itens e editar item são uma
  transação cada. Metade dos preços gravados sem o Diretor saber quais é o pior modo de
  falha desta etapa.
- **O arquivo que sai da diretoria.** O xlsx da 201 e o de conferência circulam fora. Veja
  se não escapou custo, margem, curva, alerta, MVA ou alíquota — mesma régua do cabeçalho
  de `app/servicos/exportacao.py`.

### 6.6 Quem **não** entra nesta etapa

`dbt-staging`, `dbt-relatorios`, `dbt-regras` e `infra-windows`. **Nenhuma coluna nova,
nenhum model novo, nenhum seed, nenhum `.bat`.** Todo dado de que esta etapa precisa já
está em `COMPRAS_PEDIDO`. Se alguém sentir falta de um campo, **pare e reporte** — não abra
atalho pelo `CEDEP` e não invente coluna no meio do caminho.

---

## 7. Ordem, e o que roda junto

```
   ┌─ frontend-react: Tarefa 1 (os dois defeitos) ────────────────┐
   │  não depende de banco nem de API: pode sair primeiro         │
   │                                                              ├─→ revisor
   └─ oracle-dba (DDL) ─→ backend-fastapi ─→ frontend-react 2,3,4 ┘
                                    └────────→ validador
```

Os dois defeitos podem ser corrigidos e entregues em commit próprio, antes do resto — é o
que o Diretor sente todo dia, e não custa esperar o banco. O `validador` começa quando o
backend fecha, em paralelo com o front.

---

## 8. Aceite — o que precisa ser demonstrado, com número

1. Na Precificação, gravar o preço de um SKU, digitar outro valor **na mesma célula, sem
   trocar de página**, e gravar de novo. Hoje é impossível (§2).
2. O campo de um SKU já decidido abre mostrando o valor decidido, editável.
3. Definir preços de 3 SKUs (um só atacado, um só varejo, um nos dois) cria **um** lote em
   Rascunho com 3 itens; `APP_DECISAO_PRECO` fica com as 4 decisões; `APP_DECISAO_PRECO_HIST`
   ganha uma linha por decisão que já existia antes.
4. O arquivo de atacado desse lote tem **2 itens** (o de varejo puro não entra), 2 colunas,
   sem cabeçalho, **`COD_FAB` na coluna A**, e o nome traz `regiao2` e `codfab203`. O de
   varejo tem 2 itens e `regiao1`.
4b. Um lote que inclua o SKU 8170 (`COD_FAB` repetido em 8171/8172/8173) e um dos 49 ativos
   sem `COD_FAB`: os dois aparecem no lote e no Excel, **nenhum** dos dois aparece no
   arquivo da 201, e a tela conta e nomeia os dois motivos.
5. Definir preços de 250 SKUs de uma vez gera **um** lote com 250 itens — dois pedidos
   HTTP, um documento.
6. Rascunho → Enviado → Aplicado funciona um passo por vez; Rascunho → Aplicado dá 409;
   desfazer volta um passo; lote em Aplicado é só leitura na tela **e** a API recusa a
   escrita.
7. Um item cujo preço já está aplicado no banco aparece como **aplicado**, e a tela diz com
   que data de dados a conferência foi feita.
8. `grep -ril "cedep" app/ web/src/` não encontra consulta nova. `dbt test` continua em 276
   passando — esta etapa não toca no dbt; se o número mudou, alguém mexeu no que não devia.
9. A 400px de largura, as duas telas novas não rolam o corpo na horizontal.

---

## 9. Perguntas para o Diretor — uma delas vale responder **antes** de começar

1. ✅ **O layout do arquivo está confirmado** (print da documentação da TOTVS, 10/09/2026):
   2 colunas, sem cabeçalho, `.xlsx`. **Mas o identificador não é o nosso código** — ver
   §4.6. O que sobra de pergunta é a consequência disso:

   **a) Confirmar com a equipe de cadastro que eles usam a opção "3 - Cód. de Fab. (Rotina
   203)".** Se eles hoje importam por **código de barras** (opções 1 e 2), o nosso arquivo
   não serve, e aí a etapa ganha uma dependência de dbt que hoje não tem: `PCEMBALAGEM`
   não é source do projeto (`dbt/compras/models/staging/sources.yml`), então seria GRANT
   novo (`oracle-dba`), `stg_embalagem` (`dbt-staging`), coluna nova em `COMPRAS_PEDIDO`
   (`dbt-regras`) e só então o arquivo. **Vale perguntar antes de começar** — é a diferença
   entre uma etapa de front+backend e uma etapa que atravessa o dbt inteiro.

   **b) Os 14 SKUs com código de fábrica repetido e os 49 sem código** ficam de fora do
   arquivo por decisão nossa (§4.6). Se o Diretor quiser esses produtos importáveis, o
   caminho é **corrigir o cadastro no Winthor** — `COD_FAB = '2'` em dois produtos
   diferentes é erro de cadastro, não limitação do nosso app. Vale mandar a lista para ele
   junto com a entrega.
2. **Quem marca "Aplicado".** Hoje a equipe de cadastro não tem usuário no app. Fica com a
   diretoria, ou eles ganham login para fechar o ciclo onde ele de fato termina?
3. **Baixar o arquivo exige perfil de diretoria?** A proposta é não — decidir preço é da
   diretoria, levar o arquivo não é.
4. **Um lote pode misturar departamentos?** A proposta é sim, sem quebra: a rotina 201 não
   pede fornecedor, e o pedido só é um-por-fornecedor por exigência da 220. Se ele preferir
   um lote por departamento, é um `group by` na criação.
5. **A observação do lote** — o campo livre de recado para quem digita — é útil, ou é campo
   que ninguém preenche? Está previsto na tabela; não desenhar na tela custa nada.

---

## 10. Fora do pedido — uma observação sobre o print, para não perder

No print, "Sugerido AT" e "Sugerido VAR" são **idênticos ao centavo nas 11 linhas** (507,04
/ 410,58 / 31,02 / 52,40 / 80,66 / 89,41 / 14,16 / 576,63 / 332,86 / 19,28 / 23,53).
Conferi o caminho do dado e **provavelmente está correto**: no cenário "ST s/Valor" as duas
praças usam o mesmo custo e a mesma alíquota efetiva de saída, e a margem alvo cai no mesmo
padrão de 20% quando não há decisão — então os dois preços coincidem por construção, não
por defeito. A leitura das colunas está certa (`pv_sug_st_s_valor_av` contra
`pv_sug_st_s_valor_var_av`, em `app/api/contrato.py:134`).

Se quiser a confirmação de graça, é uma consulta:

```sql
select count(*) from compras_pedido
 where abs(nvl(pv_sug_st_s_valor_av,0) - nvl(pv_sug_st_s_valor_var_av,0)) >= 0.01;
```

Zero significa "coincidem sempre", e aí vale perguntar ao Diretor se é isso que ele espera;
qualquer número maior que zero encerra o assunto — o modelo distingue as praças e o print
só pegou uma faixa onde elas empatam. **Isto não é pedido do Diretor e não deve entrar no
escopo da etapa** — está aqui para não ser redescoberto daqui a um mês.
