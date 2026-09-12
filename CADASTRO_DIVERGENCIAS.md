# Divergências de cadastro no Winthor — correções solicitadas

**Para:** Diretoria de Compras
**Data do levantamento:** 11/09/2026
**Origem:** medição automática sobre o cadastro de produtos (4.558 SKUs ativos)

---

## Resumo

São **63 produtos ativos** com problema no campo **código de fábrica**, mais um
item de cadastro de **Seção** que afeta outra parte do sistema.

| Grupo | Produtos | Urgência |
|---|---|---|
| A — código de fábrica **repetido** em mais de um produto | 14 | **Alta** — 4 deles vendem |
| B — produto **sem** código de fábrica | 49 | Baixa — 46 não vendem |
| C — código com **espaço ou tabulação** invisível | 11 | Média — 4 ativos a verificar |
| D — **Seção** não cadastrada | 39 departamentos | Baixa — não afeta preço |

O grupo A é o único que pode causar prejuízo direto, e a correção dele é rápida:
são 6 códigos.

---

## Por que isso importa agora

O sistema passou a gerar a planilha de importação de preço da **rotina 201** do
Winthor, para o Cássio e a Gabriela aplicarem as decisões de preço da diretoria
sem digitar produto por produto.

A rotina 201 aceita quatro formas de identificar o produto, e **o código interno
da CEDEP não é nenhuma delas**. A única que existe no nosso cadastro é o
**código de fábrica** (opção "3 - Cód. de Fab. (Rotina 203)"). É por isso que a
qualidade desse campo específico passou a ter consequência financeira.

---

## Grupo A — código de fábrica repetido (14 produtos, 6 códigos)

**O risco:** a importação casa pelo código. Se dois produtos têm o mesmo código,
importar o preço de um **altera o preço de todos**, e não há aviso: o arquivo
importa "com sucesso".

### A.1 — `000019` — o caso mais grave

| SKU | Produto | Curva | Preço atacado |
|---|---|---|---|
| 4902 | FLANELA ALGODAO 39X59 VERMELHA UNID | B/C | R$ 3,10 |
| 7914 | RAYON SODA CAUSTICA 1KG | B/C | R$ 19,30 |

Dois produtos **sem nenhuma relação entre si**, os dois vendendo, com preços que
diferem em **6 vezes**. Uma importação de preço na flanela levaria o rayon de
R$ 19,30 para R$ 3,10 — uma queda de 84% que ninguém pediu e que só apareceria
na margem do mês seguinte.

### A.2 — `2` — código que não identifica nada

| SKU | Produto | Curva | Preço atacado |
|---|---|---|---|
| 1883 | ORBI VED SELANTE P/ MOTOR VERMELHO 50 GR | B/C | R$ 5,98 |
| 6643 | TRAPO P/LIMPEZA BRANCO FARDO 20KG | S/VEND | R$ 214,00 |

O código é literalmente o algarismo `2`. Diferença de preço de **36 vezes**.

### A.3 — `PSD160` — dois filtros parecidos, preços diferentes

| SKU | Produto | Curva | Preço atacado |
|---|---|---|---|
| 5165 | TF PSD 160 COMB MB ACTROS 2346, OM501 LA | S/VEND | R$ 143,80 |
| 5214 | TF PSD 160 COMB MB ACTROS OM501 10> | B/C | R$ 157,73 |

Aplicações diferentes do mesmo filtro TECFIL. Aqui o erro seria discreto — 10%
de diferença —, o que o torna mais difícil de perceber.

### A.4 — `120717.0.02` — quatro produtos no mesmo código

| SKU | Produto |
|---|---|
| 8170 | EVAP INT 12.000 GREE G-TOP AUTO |
| 8171 | COND EXT 12.000 GREE G-TOP |
| 8172 | EVAP INT 9.000 GREE G-TOP |
| 8173 | COND EXT 9.000 GREE G-TOP |

Evaporador e condensador, em duas capacidades. São **quatro equipamentos
distintos**. Nenhum vende hoje (todos S/VEND), então o risco é futuro — mas é o
pior caso estrutural do cadastro.

### A.5 — `0000010` — produto cadastrado duas vezes

| SKU | Produto |
|---|---|
| 6817 | TRANSPALETE RTN 222-2000 |
| 7118 | TRANSPALETE RTN 222-2000 |

Nome idêntico. Aqui provavelmente o código não está errado — o **produto** está
duplicado no cadastro. Vale conferir se um dos dois deve ser inativado.

### A.6 — `7898578852335` — código de barras no campo errado

| SKU | Produto |
|---|---|
| 8925 | CADILLAC CERA GRAN FINALE CREME 500ML |
| 8926 | CADILLAC CERA CLEANER WAX CREME 500ML |

Esse número é um **código de barras EAN-13**, não um código de fábrica. É o dado
certo no campo errado — e ainda repetido em dois produtos diferentes.

### O que pedimos no grupo A

Atribuir a cada produto o código de fábrica **real do fabricante**. Onde o
produto estiver duplicado (A.5), inativar o excedente em vez de criar código
novo.

**Prioridade:** A.1, A.2 e A.3 primeiro — são os que têm produto vendendo.

---

## Grupo B — produtos sem código de fábrica (49)

Desses 49, **46 são S/VEND** (sem venda no período) e **3 vendem**:

| SKU | Produto | Departamento |
|---|---|---|
| 1767 | DRAFT ADITIVO P/ ALCOOL 200 ML | DRAFT |
| 4301 | BROKITS GRAXA GRAFITADA 80 GR | DIVERSOS |
| 6866 | TF ARL 5144/80 AR SANDERO 2.0 | TECFIL |

**O que pedimos:** preencher o código de fábrica desses **3**. Os outros 46 podem
esperar — e vale avaliar se parte deles deveria estar inativa, já que não vendem
e não têm identificação de fabricante.

A lista completa dos 49 está no anexo.

---

## Grupo C — caracteres invisíveis no código (11)

São códigos com espaço ou tabulação que não aparecem na tela, mas que a
importação enxerga.

### C.1 — espaço/tabulação nas pontas (5 produtos, **todos inativos**)

| SKU | Produto | Código como está |
|---|---|---|
| 471 | 3M RESPI. P/PINTURA CONJ SERIE 6000 | `H0002317339` + 3 tabulações |
| 3446 | TUTELA ZC 80-Y GL-4 20 LTS | `28111910J` + 3 espaços |
| 3517 | TUTELA ZC 140-Y GL-4 20 LTS | `28171910J` + 3 espaços |
| 4294 | 3M FITA AUTO CREPE ALTA PERF. 16MMX40M | espaço + `HC000660486` |
| 5938 | ORBI ALCOOL GEL 70% 100GR | `1` + espaço |

Nosso sistema já remove esses caracteres das pontas antes de gerar o arquivo,
então **não há risco imediato**. Vale corrigir por higiene — e porque o SKU 4294
cria uma colisão invisível com o SKU 4851 (`HC000660486`), que é ativo.

### C.2 — espaço duplo **no meio** do código (6 produtos, 4 ativos)

| SKU | Produto | Código como está |
|---|---|---|
| 5993 | SHELL MAXI PERFORMACE 10W40 1LT | `G/` + 2 espaços + `JZZ107/R2/BRA` |
| 5994 | SHELL MAXI PERFORMACE 20W50 1LT | `G/` + 2 espaços + `JZZ250/R2/BRA` |
| 7791 | SHELL MAXI PERF GF-6A SP 5W30 1LT | `G/` + 2 espaços + `JZZ530/Q2/BRA` |
| 8864 | LUBRAX MAX PERF A3 B4 SN 5W40 508/509 1L | `G/` + 2 espaços + `S55553/R2/BRA` |

**Este é o único item que precisa de uma verificação, não de uma decisão.**
Nosso sistema **preserva** o espaço interno de propósito: mexer no meio do código
mudaria o identificador, e não temos como saber se o espaço faz parte dele.

**Pergunta para o Cássio ou a Gabriela:** a rotina 201 encontra esses quatro
produtos quando o código tem espaço duplo no meio? Se não encontrar, o cadastro
precisa ser normalizado. Um teste com um desses SKUs responde.

---

## Grupo D — Seção não cadastrada (39 de 47 departamentos)

Fora do escopo da importação de preço, mas afeta as telas de Monitoramento e
Entradas.

Dos 47 departamentos, **39 têm a Seção preenchida com o próprio nome do
departamento** — ou seja, a Seção não informa nada além do que o Departamento já
diz. Só 8 têm seção própria.

Enquanto isso durar, o filtro de Seção fica **desabilitado** nas telas, com a
mensagem "Aguardando o cadastro de seções no Winthor". Foi decisão consciente: um
filtro com os mesmos nomes do filtro ao lado parece uma segunda dimensão de
análise sem ser uma, e faz a pessoa perder tempo cruzando dois filtros que não se
cruzam.

Quando o cadastro for feito, o filtro se habilita sozinho — a checagem é feita
sobre o dado, não sobre uma lista fixa no código. **Não é necessário nos avisar.**

---

## O que o sistema faz enquanto o cadastro não é corrigido

Nenhum desses produtos fica de fora da decisão de preço. O que muda é o caminho
até o Winthor:

- Eles **entram** normalmente no lote de preços da diretoria — a decisão é válida
  e o documento é dela, não do código.
- Eles **não entram** no arquivo de importação automática, para não alterar o
  preço de produto que ninguém decidiu.
- Eles **aparecem no Excel de conferência**, com uma coluna dizendo o motivo
  ("sem código de fábrica" / "código de fábrica repetido"), para digitação manual
  pelo Cássio ou pela Gabriela.
- A tela do lote conta e nomeia quantos ficaram de fora, em vez de entregar um
  arquivo menor sem explicação.

Ou seja: o sistema não trava e não erra — apenas exige trabalho manual para esses
63 produtos, que deixa de ser necessário assim que o cadastro for corrigido.

---

## Anexo — os 49 produtos ativos sem código de fábrica

Os três primeiros são os que vendem.

| SKU | Produto | Departamento | Curva |
|---|---|---|---|
| 1767 | DRAFT ADITIVO P/ ALCOOL 200 ML | DRAFT | B/C |
| 4301 | BROKITS GRAXA GRAFITADA 80 GR | DIVERSOS | B/C |
| 6866 | TF ARL 5144/80 AR SANDERO 2.0 | TECFIL | B/C |
| 533 | 3M LIXA DAGUA 500-A UN | 3M | S/VEND |
| 2615 | BOSCH PALH B 046 14 TRAZEIRA | BOSCH | S/VEND |
| 2533 | CASTROL GTX ECOFLEX 1 LT | CASTROL | S/VEND |
| 3323 | CENTRALSUL INTERCLIMA SORTIDO 60 ML | CENTRALSUL | S/VEND |
| 913 | W 950/09 FILTRO LUBRIFICANTE | CLICK | S/VEND |
| 934 | W 923 FILTRO LUBRIFICANTE | CLICK | S/VEND |
| 969 | H 1049/1 FILT LUB P/CATERPILAR | CLICK | S/VEND |
| 972 | H 1273 FILT LUB P/FORD NEW HOLLAND | CLICK | S/VEND |
| 980 | P 934 FILT COMB P/CATERPILLAR (8M 9641) | CLICK | S/VEND |
| 986 | WK 842 FILT COMB P/CUMMINS MOT BC | CLICK | S/VEND |
| 989 | H 117 FILT P/SIST HD TRATOR FORD | CLICK | S/VEND |
| 991 | H 76 FILT P/SIST HIDR. P/M PERKINS | CLICK | S/VEND |
| 992 | H 914 FILT P/SIST HD MASSEY FERGUSON | CLICK | S/VEND |
| 1232 | TC 3080 TAMPA DE COMB CLICK | CLICK | S/VEND |
| 1233 | TC 4020 TAMPA DE COMB CLICK | CLICK | S/VEND |
| 1234 | TC 3030 TAMPA DE COMB CLICK | CLICK | S/VEND |
| 1237 | TC 3090 TAMPA DE COMBS CLICK | CLICK | S/VEND |
| 1938 | GALAO DE EMERGENCIA C/MANGUEIRA 5 LTS | DIVERSOS | S/VEND |
| 3444 | DRAFT DESCARBONIZANTE 1 LT | DRAFT | S/VEND |
| 3214 | IMPECA SAC-5056 FILT AR COND. FRONTIER | IMPECA | S/VEND |
| 3216 | IMPECA SAC-5067 FILT AR COND FOCUS 08> | IMPECA | S/VEND |
| 3233 | IMPECA SAR-4014 FIL AR MOTO SUNDOWN 125c | IMPECA | S/VEND |
| 3234 | IMPECA SAR-4018 FILT AR MOTO DAFRA 100c | IMPECA | S/VEND |
| 3243 | IMPECA SUN-0007 COMB MOTO HOND/SUZU/KAWA | IMPECA | S/VEND |
| 3542 | IMPECA SAS-8849 AR VOLVO N10/N12 (AS571) | IMPECA | S/VEND |
| 6282 | MANN WA 9 MULTI 11/16 REFRIG (WA940/9) | MANN | S/VEND |
| 3107 | CAIXA P/ REPOSICAO | OUTROS | S/VEND |
| 4329 | KIT EMB. HR/K2500/H1 LUCK | OUTROS | S/VEND |
| 4498 | ROTULO PLAST. POLIETILENO QUEROSENE 900ML | OUTROS | S/VEND |
| 5328 | ESPREMEDOR FRUTAS MONDIAL 220V | OUTROS | S/VEND |
| 7964 | SCOOTER ELETRICA | OUTROS | S/VEND |
| 8020 | TV DLED 50 TB022M 4K | OUTROS | S/VEND |
| 8062 | IMPRESSORA MULTIFUNCIONAL LASER | OUTROS | S/VEND |
| 8305 | RACK 44 US PRETO | OUTROS | S/VEND |
| 7262 | PALLET PBR | PALLET | S/VEND |
| 2650 | PARKER RCK-40015 KIT COMB CAM. VW ELETR | PARKER | S/VEND |
| 2772 | PARKER RCK-40016 KIT COM MBB AXO/ACE/ATE | PARKER | S/VEND |
| 2926 | PARKER RCK-40021 KIT FILTRO COMBUST | PARKER | S/VEND |
| 2927 | PARKER RCK-40023 KIT FILTRO COMBUST | PARKER | S/VEND |
| 2967 | PARKER AFI-6782RS FILT AR SEC | PARKER | S/VEND |
| 2968 | PARKER KR 11031-B KIT COPO FG/FH | PARKER | S/VEND |
| 3351 | PARKER AR-6343RS FILT AR M FERG COLHEIT | PARKER | S/VEND |
| 296 | RADIEX LIMP CARTER CL2004 320 ML | RADIEX | S/VEND |
| 364 | SHELL SPIRAX S2 G 140 20 LTS | SHELL | S/VEND |
| 3406 | SHELL GRAXA GADUS S2 V220AD 2 (HDX2) 18K | SHELL | S/VEND |
| 3752 | SHELL SPIRAX G 140 20 LTS | SHELL | S/VEND |

---

*Levantamento gerado a partir do cadastro em 11/09/2026. Os números mudam
conforme o cadastro for corrigido — uma nova medição pode ser feita a qualquer
momento para acompanhar o progresso.*
