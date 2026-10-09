# "Valor NF" projetado — pergunta para o Diretor de Compras

**Data:** 25/09/2026
**Para:** Diretor de Compras
**Assunto:** um número que a tela mostrava e que foi retirado — confirmar se deve voltar

---

## O que aconteceu, em uma frase

A tela de **Decisão do SKU** mostrava um campo chamado **"Valor NF"** que **não era o valor de
nota fiscal nenhuma** — era um número calculado a partir do custo. Ele foi retirado, e este
documento existe para o Diretor confirmar se essa retirada está certa.

---

## Por que isso veio à tona

Comparando a tela de **Pedidos** com a de **Precificação**, o mesmo produto aparecia com valores
de nota diferentes:

| SKU 8741 — CADILLAC DEMOLIDOR LAVA ALTO | |
|---|---|
| Tela de Pedidos | R$ 75,07 |
| Tela de Precificação | R$ 74,97 |

Investigando, descobriu-se que as duas telas **não liam o mesmo dado**. Pedidos lia o valor real
gravado no banco; Precificação **reconstruía uma estimativa** a partir do custo.

A Precificação foi corrigida para ler o valor real. Restava o mesmo cálculo na tela de Decisão do
SKU — que também foi corrigido, e é sobre a parte retirada que perguntamos aqui.

---

## A fórmula que era usada

```
valor = custo ÷ [ (1 − crédito ICMS) × (1 − crédito PIS/COFINS) ]
```

A ideia era: pegar o custo (que é líquido, já descontados os créditos de imposto) e **desfazer os
créditos** para estimar quanto era o valor bruto na nota.

### De onde vinha cada entrada

| Entrada | Coluna em `COMPRAS_PEDIDO` |
|---|---|
| custo — lado **"últ"** | `CUSTO_ULT_ENT` (custo da última entrada) |
| custo — lado **"ger"** | `CUSTO_TOT_GERENCIAL` |
| custo — lado "ger", no cenário **ST s/Valor** | `CUSTO_TOT_S_VALOR` + `CUSTO_ADICIONAL_IMAGEM` |
| crédito ICMS | `CRED_ICMS` |
| crédito PIS/COFINS | `CRED_PISCOF` |

O lado **"ger"** mudava conforme o cenário fiscal escolhido na tela (ST s/Valor, Oficial, Sem
Redução).

---

## Os números, para conferência

### SKU 8741 — CADILLAC DEMOLIDOR LAVA ALTO MOL 5L

```
denominador = (1 − 0,070000) × (1 − 0,086025) = 0,849997

"ger"  = 63,7276 ÷ 0,849997 =  74,9739
valor REAL da nota           =  75,0720
                     diferença:  R$ 0,10
```

### SKU 1654 — YPF HELICOIDAL R 90 20 LTS

```
denominador = (1 − 0,000000) × (1 − 0,092500) = 0,907500

"últ"  = 296,2855 ÷ 0,907500 = 326,4854
"ger"  = 394,8945 ÷ 0,907500 = 435,1455
valor REAL da nota            = 325,4230
             diferença do "ger":  R$ 109,72  (34%)
```

---

## Por que o número foi retirado

**O lado "ger" não corresponde a nota nenhuma.** No SKU 1654 ele dá R$ 435,15 enquanto a nota real
foi R$ 325,42 — R$ 110 de diferença, 34%.

A causa: o `CUSTO_TOT_GERENCIAL` (R$ 394,89) **não é o custo daquela entrada**. É o custo gerencial
do produto, que embute substituição tributária, ajustes e outras parcelas. Aplicar a fórmula sobre
ele produz um valor que não bate com a última nota nem com qualquer outra — é uma **projeção
fiscal**, não um valor de nota.

O lado **"últ"** chegava perto (R$ 326,49 contra R$ 325,42 reais), porque partia do custo daquela
entrada específica. Ainda assim errava, porque a fórmula não reverte exatamente a composição real
da nota.

**O problema central é o rótulo.** Chamar qualquer um dos dois de "Valor NF" leva quem lê a
acreditar que está vendo o que o fornecedor cobrou — e foi exatamente essa leitura que gerou a
divergência entre telas relatada.

---

## O que mudou na prática

| Tela | Antes | Agora |
|---|---|---|
| **Pedidos** | valor da nota **com frete** | valor do produto **sem frete** (rotina 218 do WinThor) |
| **Precificação** | estimativa reconstruída do custo | valor **real** da nota, **com frete** |
| **Decisão do SKU** | estimativa reconstruída ("últ" e "ger") | valor **real** da nota; lado "ger" **retirado** |

O valor real vem de `PCEST.VALORULTENT`, o mesmo campo que o WinThor grava.

---

## A pergunta

**O número projetado tem uso para a decisão de compra ou de preço?**

- **Se tiver** — ele volta facilmente, mas precisa de **outro rótulo**, porque não é valor de nota.
  Algo como "Valor bruto projetado" ou "Valor s/ créditos". Precisamos do nome que faça sentido
  para quem usa.

- **Se não tiver** — fica como está: as telas mostram o valor real da nota, lido direto do banco,
  e as três param de divergir entre si.

---

## Observação sobre o que já está no ar

As correções de leitura (valor real nas três telas) **já estão em produção** desde 25/09/2026. O
que este documento questiona é apenas se o número **projetado** deve ser reintroduzido, com nome
adequado, como informação adicional.
