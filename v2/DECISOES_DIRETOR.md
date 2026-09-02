# Decisões pendentes do Diretor de Compras — tela de Alertas

A tela de Alertas está portada e funcionando com dado real (01/09/2026). O que falta
para dá-la por encerrada não é código: são oito decisões de negócio que eu não posso
tomar. Cada uma abaixo traz **o que está valendo hoje**, **por que precisa de decisão** e
**o número medido no banco** que torna a pergunta concreta.

Enquanto não houver resposta, a tela funciona com o que está marcado como "hoje" — que é
uma proposta defensável, não uma regra acordada.

---

## 1. A taxonomia de alertas não é a mesma (a mais importante)

O protótipo tem **6 tipos**: `ruptura`, `sem_giro`, `baixo_giro`, `estoque_alto`,
`margem_baixa`, `margem_alta`. O modelo tem **14**. Só **RUPTURA** existe nos dois.

| Do protótipo | Equivalente no modelo |
|---|---|
| `ruptura` | **RUPTURA** — igual |
| `sem_giro` / `baixo_giro` | **PARADO** (um só, não dois) |
| `margem_baixa` | **MARGEM_INSTAVEL** (+ MARGEM_INSTAVEL_VAREJO) |
| `estoque_alto` | **não existe** |
| `margem_alta` | **não existe** |

E o modelo tem oito que o protótipo não conhece: `IMPORTADO`, `LITRAGEM`, `TRIB`, `MVA`,
`CUSTO`, `SUCESSAO`, `FORA_DE_LINHA`, `FABRICA`, `INATIVO`, `DEVOLUCAO`.

**Hoje:** a tela usa os 14 do modelo, porque são os que têm dado.

**A decisão:** os 14 do modelo são a lista certa, ou faltam `estoque_alto` e
`margem_alta` — que existiriam na planilha e teriam de virar regra nova no dbt? E
`sem_giro` e `baixo_giro` devem voltar a ser dois níveis separados, em vez de um `PARADO`?

---

## 2. Um terço da lista não é decisão de compra

**Medido:** dos 2.589 produtos ativos com alerta, **885 (34%) têm como único alerta uma
pendência de cadastro** — `IMPORTADO`, `LITRAGEM`, `TRIB`, `MVA`, `SUCESSAO` ou `FABRICA`.
`IMPORTADO` sozinho pega 1.114 produtos: é o tipo mais numeroso de todos, mais que
`MARGEM_INSTAVEL` (975) e que `RUPTURA` (421).

Esses alertas dizem "confira este cadastro", não "decida esta compra". Misturados na mesma
lista, eles são 34% do que o comprador percorre.

**Hoje:** tudo na mesma lista, com cores diferentes por severidade.

**A decisão:** separar em duas visões — "Decisões" e "Pendências de cadastro"? Ou manter
junto e deixar que o comprador desligue os tipos que não quer ver?

---

## 3. O produto mais urgente não está na primeira página

O score de prioridade do protótipo é `soma dos pesos dos alertas + peso da curva ABC`.
Isso faz com que **acumular alertas pese mais que ser classe A em ruptura**.

**Medido:** existem **6 produtos classe A em ruptura**. Com a fórmula de hoje, eles caem
nas posições 18, 52, 57, 158, 307 e 331 — ou seja, **5 dos 6 estão da página 2 à página
7**. Quem olha só a primeira página perde quase todos.

A causa: só 39 produtos têm 4 ou mais alertas, e são eles que ocupam o topo — em geral
B/C, empilhando `IMPORTADO` + `LITRAGEM` + margem.

**Hoje:** a fórmula do protótipo, fielmente.

**A decisão:** classe A em ruptura deve vir antes de qualquer acúmulo de alertas? Uma
saída seria ordenar primeiro pela severidade máxima e só depois pela soma — mas é escolha
sua, não minha.

---

## 4. Os pesos de cada alerta são chute meu

O protótipo dá pesos 5/4/3/2/2/1 aos seis tipos dele. Traduzi por proximidade de sentido
para os 14 e inventei o resto. O peso decide a ordem, e a ordem decide o que é visto.

**Hoje** (em `app/api/alertas.py`): RUPTURA 5; MARGEM_INSTAVEL, MARGEM_INSTAVEL_VAREJO e
CUSTO 4; PARADO, FORA_DE_LINHA e INATIVO 3; DEVOLUCAO, MVA, TRIB e SUCESSAO 2; FABRICA,
IMPORTADO e LITRAGEM 1. Curva: A 3, B/C 2, S/VEND 1.

**A decisão:** confirmar ou corrigir a tabela. É uma linha por tipo.

---

## 5. "Valor em risco" não enxerga a ruptura

O KPI é a soma do **valor de estoque** dos produtos com alerta: hoje R$ 48,1 milhões.

**Medido:** dos 421 produtos ativos em ruptura, **201 têm valor de estoque zero** — porque
ruptura é, por definição, não ter estoque. Ou seja, **o pior problema da operação
contribui com R$ 0 para o indicador que deveria medir risco**. Os 421 juntos somam R$ 3,8
milhões, quase todo ele vindo dos que ainda têm alguma sobra.

**Hoje:** a definição do protótipo, fielmente.

**A decisão:** "valor em risco" deveria medir outra coisa para a ruptura — venda perdida
projetada (média mensal × preço), por exemplo? Ou são dois indicadores diferentes:
"capital parado" e "venda em risco"?

---

## 6. O texto da tela contradiz o cálculo da tela

No protótipo, a nota sob o seletor diz: *"Margem/MKP atual são o preço de hoje — não mudam
com o cenário"*. Mas o código muda os dois: `margemAtualPorCenario` troca a margem, e
`infoPreco` calcula o MKP sobre `custoPorCenario`. Os três mudam com o cenário.

**Hoje:** segui o **código**, e reescrevi a nota para "Custo, margem e MKP mudam com o
cenário — o preço praticado hoje, não."

**A decisão:** o comportamento certo é o do código (os três mudam) ou o do texto (só o
sugerido muda)?

---

## 7. Fora de linha é o mesmo que inativo?

O filtro de status tem Ativo / Inativo / Todos. Mas o modelo tem **duas coisas
diferentes**: a coluna `STATUS` (Ativo/Inativo) e o alerta `FORA_DE_LINHA`, que vem de
`OBS2 = 'FL'` no cadastro — 72 produtos.

Isto é o **item 3 do backlog de 26/08** ("incluir filtro de FL/ativo-inativo").

**Hoje:** são tratados como coisas distintas — status é filtro, FL é alerta.

**A decisão:** o filtro deve ter um quarto botão "Fora de linha"? Ou FL e Inativo são a
mesma situação para quem compra?

---

## 8. Comprador "A DEFINIR" aparece na tela

Nas linhas da tabela lê-se "DRAFT · A DEFINIR", "MANN · A DEFINIR". São **45 dos 60
departamentos**, cobrindo 5.964 SKUs. O dado vem do `seed_fornecedor.csv`, **não do
WinThor** — então corrigir é editar um CSV e rodar `dbt seed`, sem tocar em código.

Isto é o **item 2 do backlog de 26/08** ("colocar Washington").

**A decisão:** Washington assume os 45 departamentos sem dono, ou só alguns? Uma lista de
"departamento → comprador" resolve de uma vez.

---

## O que não depende dele

Para não misturar: estas duas eu resolvo sozinho assim que houver espaço.

- **Seção / Linha / Categoria** — os campos estão na tela, desabilitados, esperando o
  cadastro no Winthor. Depende de terceiros, não de decisão dele.
- **Validação no celular** — não consegui conferir por captura de tela nesta máquina. O
  layout mobile é o padrão e o de mesa é aditivo (risco menor que na v1, que tinha duas
  marcações), mas continua **não verificado**. Basta abrir `http://192.168.0.50:5173` no
  telefone.

---

# Resultado — implementado em 02/09/2026

As oito decisões foram aplicadas. O que ficou diferente do esperado, e o que
**voltou a precisar de decisão**:

## Já resolvido, sem pendência

| # | Decisão | Como ficou |
|---|---|---|
| 1 | Taxonomia | 10 tipos de decisão. `PARADO` virou `SEM_GIRO` (315) + `BAIXO_GIRO` (123); margens renomeadas; `OPORTUNIDADE_DE_GIRO` (39) e `MARGEM_ALTA` (1.600) criados |
| 2 | Separar cadastro | `CATEGORIA` = DECISAO/CADASTRO em `COMPRAS_ALERTA`. **1.871 SKUs** saíram da tela de Alertas |
| 4 | Pesos | Tabela aplicada em `app/api/alertas.py`, que gera o SQL da ordenação e a legenda da tela — uma fonte só |
| 5 | Dois indicadores | **Capital parado R$ 71,4 mi** e **Venda em risco R$ 2,3 mi**. A ruptura finalmente entra em algum lugar |
| 6 | Texto × código | Nada a fazer: o texto já havia sido corrigido |
| 8 | Washington | 5.932 SKUs |

## Item 3 — a ordenação melhorou, mas talvez não o suficiente

A regra agora é severidade máxima → soma → curva, como decidido. Os 6 produtos
classe A em ruptura saíram das posições 18/52/57/158/307/331 para **89, 111 e
112** (os outros três ficaram fora das 200 primeiras).

Ainda não estão na primeira página, e a razão é legítima: eles perdem para
outros produtos que **também** estão em ruptura e ainda somam problema de
margem. Isso respeita a sua regra à risca — a soma é o desempate.

**Se a intenção era vê-los na primeira página**, o ajuste é inverter dois
critérios: severidade máxima → **curva** → soma. Aí todo classe A em ruptura
vem antes de qualquer B/C em ruptura. É uma linha de código. Diga qual prefere.

## Item 7 — a premissa não se aplica ao nosso modelo

Você orientou tratar `OBS2='FL'` como Inativo, supondo dois sinais que poderiam
divergir. **Medimos: eles nunca divergem.** `stg_produto` já deriva `status` e
`fora_de_linha` da mesma expressão `upper(trim(OBS2))='FL'`. Existem 72 produtos
fora de linha, e os 72 já são Inativos. **Zero produtos mudam.**

Nada foi alterado — inventar dois sinais para depois unificá-los seria pior.
`FORA_DE_LINHA` ficou como etiqueta que não pontua, como você pediu.

Efeito colateral a saber: com o filtro padrão em "Ativo", o botão "Fora de
linha" mostra sempre **0**, porque todo produto fora de linha é inativo. Só
aparece em "Inativo" ou "Todos".

## Três coisas novas que precisam de você

**a) Classe B em OPORTUNIDADE_DE_GIRO — a recomendação é não.** A curva do
modelo não tem 'B' isolado: é `A`, `B/C`, `S/VEND`, com B e C fundidos desde a
planilha. Abrir para `B/C` leva o alerta de **39 para ~1.929 SKUs** (22% do
catálogo). Se quiser B, o caminho é separar B de C na curva antes.

**b) MARGEM_ALTA pega 1.600 SKUs ativos** com os cortes de 20%/45% — o segundo
maior tipo, mais que MARGEM_BAIXA (946). Com peso 1 fica no fim da fila, mas
vale confirmar se 20% no atacado é mesmo o corte pretendido.

**c) ROBUST e ADIBRAX continuam sem comprador** (36 e 2 SKUs). Não é o caso do
"A DEFINIR" que você resolveu: esses dois departamentos **não têm linha nenhuma**
em `seed_fornecedor.csv`, então caem no valor de reserva. Para incluí-los faltam
três parâmetros que são decisão sua: `MESES_MEDIA`, `COBERTURA_ALVO` e
`PEDIDO_EM` (unidade ou caixa fechada).

---

# Segunda rodada — implementada em 02/09/2026

## Item 3 — ordenação invertida, e agora resolve

`severidade máxima → curva ABC → soma`, como decidido. **Os 7 produtos classe A
em ruptura passaram a ocupar as posições 1 a 7.** Percurso do indicador:

| Regra | Onde caíam os classe A em ruptura |
|---|---|
| soma pura (protótipo) | 18, 52, 57, 158, 307, 331 |
| severidade → soma → curva | 89, 111, 112 |
| **severidade → curva → soma** | **1, 2, 3, 4, 5, 6, 7** |

## Item (b) — MARGEM_ALTA com 25% / 50%

O volume que você pediu para conferir:

| | 20% / 45% | **25% / 50%** |
|---|---|---|
| SKUs ativos | 1.634 | **874** |
| Total | 2.179 | 1.336 |

Queda de 47%. Deixou de ser o segundo maior tipo da tela e agora fica atrás de
MARGEM_BAIXA (947 ativos). Ordem completa dos alertas de decisão, só ativos:
MARGEM_BAIXA 947 · **MARGEM_ALTA 874** · RUPTURA 467 · SEM_GIRO 313 ·
MARGEM_BAIXA_VAREJO 164 · BAIXO_GIRO 125 · DEVOLUCAO 113 ·
OPORTUNIDADE_DE_GIRO 39 · CUSTO 2.

Se ainda achar grande, o próximo corte natural seria 30%/55% — é uma linha em
`seed_parametros.csv`.

## Item (c) — ROBUST e ADIBRAX entraram

| | MESES_MEDIA | COBERTURA_ALVO | PEDIDO_EM | COMPRADOR |
|---|---|---|---|---|
| ROBUST (36 SKUs) | 3 | 2,0 | UNIDADE | WASHINGTON |
| ADIBRAX (2 SKUs) | 3 | 1,5 | UNIDADE | WASHINGTON |

O comprador não estava na sua tabela, mas seguiu a decisão da 1ª rodada
("Washington assume os departamentos sem comprador definido"). **Agora são 0 os
SKUs com "A DEFINIR"** — antes eram 38.

## Item (a) — nada a fazer

OPORTUNIDADE_DE_GIRO segue só na classe A: 39 SKUs.

---

**Estado:** `dbt test` 276 passando, 0 erros. As 1.728 combinações de filtro da
API respondem 200 (`validar/validar_api.py`). Restam as duas pendências que não
dependem de decisão: Seção/Linha/Categoria aguardando o Winthor, e a validação
visual em celular.
