# REGRAS — App Compras CEDEP

Continuação do `CONTEXTO.md`, separada dele por custo: são 445 linhas que só fazem
sentido para quem escreve ou revisa **regra de negócio, cálculo fiscal ou validação
numérica**. Quem trabalha em infraestrutura, DDL, backend ou tela não precisa carregar
isto a cada invocação — o índice das regras está no `CONTEXTO.md` §6, e ele diz quando
vir para cá.

**Leia este arquivo se** você vai mexer em model `int_*`/`fat_*`, em seed, em fórmula de
custo/margem/preço, na curva ABC, na coluna `ALERTA`, ou em qualquer script de `validar/`.

**Não precisa ler se** seu trabalho é `.bat`, serviço, DDL de tabela `APP_*`, rota
FastAPI ou template — nesses casos o `CONTEXTO.md` basta, e o seu próprio agente já
carrega as poucas regras de negócio que te alcançam.

> **Nota de numeração.** As seções aqui continuam sendo §6, §6.0, §6.1, §6.2, §6.3 e
> §6.4, exatamente como eram quando moravam no `CONTEXTO.md`. Toda citação espalhada pelo
> projeto — `validar/*.py`, `MELHORIAS.md`, `PENDENCIAS_DIRETORIA.md` escrevem
> "CONTEXTO.md §6.3" — continua válida e aponta para cá. A numeração foi preservada de
> propósito, para que a separação dos arquivos não custasse uma varredura de referências.

---

## 6. Regras de negócio que não podem escorregar

Cada uma já causou ou pode causar erro de preço real. Fonte: PDF §8-§12 e as fórmulas.

1. **Quantidade e valor são sempre líquidos** (faturado − devolvido). A única exceção é
   `TX_DEVOLUCAO_3M`, que por definição precisa do bruto no denominador.
2. **Ajuste Ingrax** (80/20): entra em margem e preço via `CUSTO_TOT_GERENCIAL`, e
   **nunca** na base fiscal de ICMS-ST, que usa só o custo oficial.
3. **Redução de base de ICMS vale só para as filiais de atacado.** O varejo usa sempre a
   alíquota cheia, sem redução. ⚠️ O código de filial no banco é `'1'`, `'2'`, `'9'` —
   **sem zero à esquerda**. `PCEST.CODFILIAL` e `PCFILIAL.CODIGO` são `VARCHAR2(2)`.
   Escrever `in ('02','09')` retorna zero linhas, a redução nunca é aplicada e o atacado
   sai com alíquota cheia. A documentação de negócio fala "02/09"; o dado diz "2"/"9".
4. **Crédito de PIS/COFINS** é sobre a NF **sem IPI**, descontado o crédito de ICMS.
5. **Curva ABC é relativa ao catálogo inteiro** e precisa recalcular o total a cada
   build — usar `sum() over (...)`, nunca um total fixo. Esse bug já aconteceu de
   verdade neste modelo. E são **dois universos separados**: produtos com litragem
   (`L_POR_UNIDADE > 0`) e sem litragem, cada um com seu próprio total.
6. **`FATOR_EXIBICAO`** (= embalagem de compra quando `PEDIDO_EM = 'MASTER'`, senão 1)
   divide praticamente toda quantidade exibida. Esquecer isso erra estoque e pedido.
   ⚠ **Uma exceção decidida (MELHORIA A5, 24/08/2026):** onde existe decisão gravada em
   `APP_DECISAO_PEDIDO`, `PEDIDO_UNIDADES` (BB) e o que descende dela (BC, BD, BE, BF)
   usam o fator **congelado** naquela linha, não o corrente — decisão tomada não muda de
   tamanho porque o cadastro atualizou depois. Sem decisão, vale o corrente. `VALOR_ESTOQUE`
   (BG) segue com o corrente, porque é estoque e não pedido. Ver §6.0 e `MELHORIAS.md` A5.
7. **`FORNECEDOR` é o texto do departamento**, não o fornecedor legal da nota fiscal.
8. **`VL_ULT_ENT` nunca é dividido pela embalagem de compra** — já vem unitário.
9. **A base de consolidação mensal inclui todo SKU que apareceu em qualquer mês**,
   inclusive o corrente. Produto de primeira venda no mês corrente tem que aparecer,
   com os meses fechados zerados.
10. **O preço final (`ALT_PV_*`) é decisão humana.** Nunca preencher automaticamente com
    uma das sugestões. `MARGEM_ALVO` cai no padrão 20% quando não houver decisão gravada.
11. **`dtexclusao is null` tem uso DIFERENTE em cada relatório.** É a armadilha mais
    cara já encontrada neste projeto, e depende de qual relatório você está portando:

    - **Relatório de estoque/fiscal** (`query.py` / `compras_estoque.py`): é **condição
      fixa e global**, aplicada a toda linha, tanto na consulta principal quanto no
      lookup base. Vale para o `int_cadastro_estoque` — se você **não** aplicar, entram
      produtos excluídos na base cadastral, e pela regra 5 a curva ABC muda para **todos
      os 8.772 SKUs**, não só para os que entraram.
    - **Relatório mensal** (`query_mensal.py` / `compras_mensal.py`): aparece **uma única
      vez**, dentro da CTE `produtos_incluir`, que decide só quem entra *sem ter vendido*.
      A CTE `produtos`, que controla toda linha da saída, **não** filtra — então produto
      excluído **com** movimento no período aparece no relatório de hoje. Se você aplicar
      globalmente, apaga linha que deveria existir.

    Aplicar nos dois ou em nenhum está errado das duas formas.

    **O padrão geral, que vale para qualquer filtro:** o mesmo predicado pode ter usos
    diferentes em pontos diferentes — e em queries diferentes. Antes de mover um filtro
    de lugar, conte quantas vezes ele aparece no SQL de origem e em quais CTEs. Por isso
    o staging não filtra: ele não tem como saber qual uso vale. Quem sabe é a camada
    intermediate, que é específica de cada relatório.

## 6.1 Decisões já tomadas sobre divergências do gabarito

> ⚠️ **As 5 divergências levantadas com o Diretor de Compras estão TODAS decididas** — 4
> em 21/08/2026 e a última (item 5, `PEDIDO_UNIDADES` com fator corrente x congelado) em
> 24/08/2026, **congelar**, aplicada como MELHORIA A5 (impacto hoje: 0 SKUs). Estão em
> **`PENDENCIAS_DIRETORIA.md`**, na raiz do projeto. **Quatro delas mudaram o código e nos
> fazem divergir da planilha de propósito — ver §6.4 e §6.0.** Novas divergências
> encontradas nas próximas etapas vão para lá, não são resolvidas por conta própria.

**Regras fiscais: implementar como estão na seção 8 do PDF e na planilha** (decidido pelo
usuário em 2026-08-20). Não travar a Etapa 4 esperando validação do Diretor de Compras.
Se ele quiser mudar alíquota, redução por filial, ajuste Ingrax ou fator de prazo, isso
entra depois como alteração — quando ele estiver usando o sistema e puder comparar com o
que conhece.

Consequência prática para quem implementa: **reproduza, não julgue.** Achou uma regra
estranha? Registre no relatório e siga o gabarito. A planilha é a especificação; o juízo
fiscal é de quem responde por ele.


**Fator de prazo do varejo (1,086435).** Na planilha, `ALT_PV_VAR_AP`, `PV_SUG_*_VAR_AP`
usam a constante **chumbada dentro da fórmula**, enquanto o atacado usa
`Parametros!$B$5`. Aqui o valor vai para `seed_parametros` como `FATOR_PRAZO_VAREJO`.

Isso **não** é divergir do gabarito: o número é o mesmo, então o aceite célula a célula
continua fechando. O que muda é só onde a constante mora — e o próprio "Leia-me" da
planilha diz que nenhuma constante fiscal deveria estar dentro de fórmula. Não trate isso
como um dilema.

## 6.0 Onde divergimos da planilha DE PROPÓSITO

Desde 21/08/2026 o gabarito é a **v11**. Ela corrige o cenário "ST s/Valor" (4 fórmulas
trocando a alíquota reduzida pela cheia) — o modelo bate com ela nesse ponto.

A planilha também deixou de ser alvo de **réplica exata** e passou a ser **ponto de
partida** (`MELHORIAS.md`). A regra de aceite não afrouxou por causa disso:

> **Toda divergência da planilha é defeito, exceto as registradas aqui e em
> `MELHORIAS.md`.**

Duas origens de divergência deliberada, e elas não se confundem:

**(a) Decisões do Diretor que ele ainda NÃO aplicou na planilha** — a v11 vai alcançá-las
um dia:

| O que | Onde | SKUs | Situação |
|---|---|---|---|
| `CAR80` → `CAR 80` no `seed_credito` | crédito, ICMS-ST e preço | 41 (20 medidos hoje em `BO`) | v11 ainda tem `CAR80` |
| `CHECK_TRIB` passa a pegar o código `0` | `CC`, e `D` por tabela | 5 | v11 ainda não dispara |

**(b) Melhorias aprovadas em 21/08/2026** — estas **não vão existir na planilha**, por
decisão registrada em `MELHORIAS.md`:

| Melhoria | Coluna(s) Excel | Células/SKUs afetados (medido em 21/08/2026) |
|---|---|---|
| **A3** — `FORA_DE_LINHA` do registro **mais recente**, não do mês corrente | `AP` (`CHECK_FORA_DE_LINHA`) | **71 SKUs** mudam `'N'`→`'S'` e passam a alertar (AP vai de 1 para 72); **0** no sentido contrário |
| **A4** — percentual do texto com **uma casa decimal e vírgula** (`"5,5%"` no lugar de `"05%"`) | `AV`, `CL`, `DB` | **2.182 células de texto**: `AV` 136, `CL` 1.632, `DB` 414 — 100% das não vazias. Nenhum número de cálculo muda |
| **D1** — `VD_ANT_3M` herda com `PESO_1` **e** `PESO_2` | `AQ` | **0 células** hoje (nenhuma linha de `seed_sucessao` tem `ANTIGO_2` e todas estão `ATIVO='NAO'`). `AR`/`AT`, que derivam de `AQ`, também não mudam |
| **A5** (24/08/2026) — `PEDIDO_UNIDADES` usa o `FATOR_EXIBICAO` **congelado** em `APP_DECISAO_PEDIDO`, não o corrente (`K`) | `BB`, e por consequência `BC`, `BD`, `BE`, `BF` | **0 células** hoje (`APP_DECISAO_PEDIDO` vazia — sem decisão não há congelado e vale `K`, que é a fórmula da planilha). `BG` **não** entra: é estoque, não pedido |
| consequência de A3 + A4 + `CHECK_TRIB` | `D` (`ALERTA`) | **1.793 linhas**: 1.749 por A4, 71 por A3 (34 pelos dois), 5 por `CHECK_TRIB`, 3 por componente volátil (`AO`), 1 por `AY` (renomeação de embalagem no cadastro) |

⚠ **A5 tem efeito ZERO hoje, e é justamente por isso que foi exercitada.** A
implementação certa e a errada produzem o mesmo resultado enquanto `APP_DECISAO_PEDIDO`
estiver vazia. A regra foi provada de ponta a ponta em 24/08/2026 com duas decisões de
teste gravadas e apagadas — SKU 3821 (MASTER, fator corrente 12, decisão gravada com fator
6, `PEDIDO=120`) saiu com `BB = 720` e `BD = 11.138,92`, contra `1.440` e `22.277,84` da
fórmula corrente; SKU 11 (fator 1) não mudou em nada. Tabela de volta a **0 linhas** e
modelo de volta ao estado anterior, dígito por dígito. Detalhe em `MELHORIAS.md` A5.
A regra é protegida pelo teste singular `compras_pedido_unidades_usa_fator_congelado`.
O A/B global das cinco colunas (fórmula nova × `$BA2*$K2` na mesma linha) deu **0 de
8.777** em todas — o `fat_pedido` é idêntico ao da implementação anterior.
⚠ `BF` aparece divergente no validador (524/3278) por **outra** causa: com `BB = 0`, `BF`
é numericamente idêntica a `AW` (`MESES_EST`) e herda a volatilidade de `EST+PEND`.

⚠ **A3 tem um limite conhecido, medido e NÃO corrigido:** SKU que não aparece em mês
NENHUM de `int_venda_mensal` continua saindo `'N'`. São **4.205 SKUs** do `fat_pedido`
marcados `OBS2='FL'` no cadastro que nunca entram naquele model (`produtos_incluir` só
admite quem está em linha). Ler o campo direto do cadastro alcançaria os 4.205 — é
mudança de escopo maior que a aprovada e está **pendente de decisão do Diretor de
Compras**, não implementada.

Diferença nessas colunas, **nesses SKUs e nessas contagens**, é esperada. Diferença nelas
**além** disso, ou em qualquer outra coluna, continua sendo defeito. Ver
`PENDENCIAS_DIRETORIA.md` e `MELHORIAS.md`.

## 6.0.1 Números de registro envelhecem — não os trate como verdade

Os efeitos medidos e anotados em `MELHORIAS.md`, `PENDENCIAS_DIRETORIA.md` e nos rótulos
do validador são **fotos do dia da medição**. Eles se movem sozinhos:

- `CL` (texto de margem) acompanha o custo, que muda com cada nota de compra
- `ALERTA` acompanha `CHECK_ESTOQUE_PARADO`, que depende de `TODAY()`
- a contagem de SKUs cresce com o catálogo (8.772 → 8.777 em cinco dias)

Medido: entre 21 e 24/08/2026, `ALERTA` foi de 1.793 para 2.146 divergências e `A4` de
2.182 para 2.187 células — **sem nenhuma mudança de código**.

**A consequência prática:** número defasado num registro **não invalida a decisão**, mas
não serve como critério. Ao verificar, **recalcule a atribuição**, não compare contra o
número anotado. O que precisa continuar valendo é a **atribuibilidade** (§6.1.0), não a
contagem.

E ao reportar, diga a data da medição junto com o número.

## 6.1.0 O critério de aceite do `fat_pedido` — ATRIBUIBILIDADE, não zero absoluto

O plano original exigia "zero divergência em `CLASSE`, `ALERTA`, `MODALIDADE` e
`CUSTO_TOT_GERENCIAL`". **Duas dessas quatro são impossíveis de cumprir**, e a razão é a
mesma que já derrubou o critério de `ALERTA`:

- `CUSTO_TOT_GERENCIAL` descende de `VL_ENT_UNIT` e `CUSTO_ULT_ENT` — **valor e custo da
  última entrada**, que mudam a cada nota de compra que chega.
- `MODALIDADE` descende de `COD_TRIBUTACAO`, que muda quando o fiscal reclassifica um item.

A aba `pedido` é uma **foto**; o `fat_pedido` é construído hoje. Medido em 21/08/2026: a
foto é de **2 dias antes** — `DIAS_SEM_VENDA` dá exatamente `+2` em **4.513 de 4.513** SKUs
que não venderam, e negativo em todos os que venderam (a data de última saída avançou).
Não existe um único SKU com diferença positiva diferente de +2.

### O critério que vale

**Toda célula divergente precisa ser ATRIBUÍVEL a um insumo que mudou.** Não "quantas
divergem", mas "alguma diverge sem explicação?".

Na prática:
1. Para cada coluna divergente, teste-a **contra os insumos que a fórmula dela lê**.
2. Divergência que some quando você usa os insumos da própria planilha = **defasagem**.
3. Divergência que **sobrevive** a isso = **defeito**, e reprova.
4. Aceite: **zero células não atribuíveis**.

`CLASSE` continua com exigência de zero absoluto — ela depende só de média de venda de
meses fechados e de embalagem, ambas estáveis.

**Sinal de defasagem, para reconhecer rápido:** a divergência **cresce com o relógio**.
Medido: entre duas execuções separadas por 25 minutos, `VL_ENT_UNIT` foi de 71 para 82
SKUs divergentes. Defeito não cresce sozinho.

## 6.1.1 O critério de aceite de `ALERTA` — corrigido

O plano dizia "zero divergência em `CLASSE`, `ALERTA`, `MODALIDADE` e
`CUSTO_TOT_GERENCIAL`". Para `ALERTA` isso **é contraditório e não vale**.

`ALERTA` (coluna D) concatena 14 colunas `CHECK_*`, e elas não são todas da mesma
natureza:

- **Estruturais** — `CHECK_RUPTURA`, `CHECK_DEVOLUCAO_ALTA`, `CHECK_LITRAGEM`,
  `CHECK_IMPORTADO`, `CHECK_TRIB`, `CHECK_MVA`, `CHECK_MARGEM_INSTAVEL`,
  `CHECK_MARGEM_INSTAVEL_VAREJO`, `CHECK_SUCESSAO`. Aqui divergência **é defeito**.
- **Voláteis** — `CHECK_ESTOQUE_PARADO` e `CHECK_FORA_DE_LINHA` dependem de estoque ao
  vivo e do mês corrente. ⚠ Desde a MELHORIA A3 (§6.0), `CHECK_FORA_DE_LINHA` **não vira
  mais com a virada do mês** — ele lê o registro mais recente do SKU. Continua no bucket
  volátil porque `OBS2='FL'` é cadastro editável, mas a divergência dele hoje tem número
  esperado: **71 linhas**, e só elas.
- **Dependentes de decisão humana** — `CHECK_FABRICA` e `CHECK_INATIVO` leem `PEDIDO`,
  que na planilha está digitado e no dbt vem vazio de `APP_DECISAO_PEDIDO`.

**Critério correto:** exigir zero divergência **em cada `CHECK_*` estrutural,
individualmente**. A coluna `ALERTA` é derivada — reporte as divergências dela, mas cada
uma tem de ser **atribuível** a um componente volátil ou de decisão humana. Divergência de
`ALERTA` que não se explique por um componente dessas duas classes é defeito.

Zero divergência obrigatória continua valendo, sem ressalva, para `CLASSE`, `MODALIDADE`
e `CUSTO_TOT_GERENCIAL` — essas três são estruturais puras.

## 6.2 Armadilhas medidas no banco — não "conserte" nenhuma delas

Cada item aqui foi verificado contra o dado real. Todas parecem defeito e **não são**:
são o comportamento que a planilha tem hoje, e o aceite célula a célula depende de
reproduzi-las.

- ~~**`CAR80` no seed_credito × `CAR 80` no departamento (com espaço).**~~
  **REVOGADO em 21/08/2026 — agora é para normalizar.** A instrução anterior era "não
  normalize", e ela valia **enquanto a divergência estava aberta**. O Diretor de Compras
  decidiu (PENDENCIAS_DIRETORIA.md item 3): a grafia do **seed** passa a ser `CAR 80`,
  com espaço, para casar com o departamento da base.
  Registro do que era, para quem for ler código antigo: a chave de busca é
  `FORNECEDOR|COD_ICMS`, e `FORNECEDOR` é o texto do departamento; com `CAR80` sem espaço
  a busca **falhava na própria planilha** e caía no crédito empírico
  `MAX(0, 1 − custo/valor)`. Com a grafia corrigida, **41 SKUs** passam a usar o crédito
  **tabelado**. Efeito medido: `CRED_TOTAL` muda em **39** dos 41 (nos outros 2 o empírico
  já dava exatamente o valor tabelado); ICMS-ST, custo, margem, preço e `ALERTA` **não
  mudam em nenhum** — ver §6.4 para o porquê.
  **Motivo da decisão:** a tabela `dCredito` existe para ser consultada; manter um erro de
  digitação para preservar o resultado de uma busca que falha é preservar o defeito, não a
  regra. Ver §6.4.
  ⚠ O que **continua proibido** é `trim()` no join de crédito e no de embalagem: a
  correção foi no **dado do seed**, não na regra de comparação. O espaço segue
  significativo.

- **Embalagem: o join precisa de `upper()`, NÃO pode ter `trim()`, e precisa de dedupe.**
  Três coisas ao mesmo tempo:
  1. **`upper()` é obrigatório.** Medido em 20/08/2026: **158 SKUs** só casam ignorando
     caixa. O `MATCH` do Excel ignora caixa, então a planilha os encontra. Sem `upper()`,
     `L_POR_UNIDADE` vira 0, o SKU cai no universo errado e — pela regra 5 — **a classe
     ABC muda para todos os 8.777**, não só para os 158.
  2. **`trim()` é proibido.** 13 valores têm espaço à direita (`TAMBOR `, `10X1 `,
     `BALDE `, `12X250 ML `, `24 X1KG `, `1LT `) que **nem o Excel casa**. Aplicar `trim()`
     seria divergir do gabarito.
  3. **`upper()` sozinho causa FAN-OUT.** O `seed_embalagem` tem **10 pares que diferem só
     na caixa** (`10X1`/`10x1`, `6X4 LTS`/`6x4 LTS`...). Um join direto com `upper()`
     duplica **4.105 SKUs**. Agrupe por `upper()` antes de juntar, pegando um valor — é o
     que o `MATCH` faz ao devolver a primeira ocorrência. Hoje os 10 pares têm litragem
     idêntica, e o teste `compras_embalagem_upper_sem_conflito` quebra o build no dia em
     que deixarem de ter.

- **5 linhas de `PCTABTRIB` (BA, filial 2) têm `codst = 0`**, sem correspondência no
  `seed_icms`. Na planilha isso não cai no código padrão (a fórmula só usa o padrão quando
  a célula é **vazia**, e 0 não é vazio): `MODALIDADE` e `ICMS_SAIDA_EF` ficam em branco e
  as margens desses 5 SKUs saem vazias. **Isso continua reproduzido de propósito** — o que
  mudou em 21/08/2026 foi só o ALERTA: `CHECK_TRIB` passa a disparar para eles (§6.4,
  decisão 3). O cálculo em branco permanece; o que deixou de existir é o silêncio.

- **`PCNFENT.CODFORNEC` é o CLIENTE que devolveu**, não um fornecedor. Das 5.241 notas de
  devolução de 2026, 5.241 (100%) casam com `PCCLIENT.CODCLI` e 1.779 (34%) casam **também**
  com `PCFORNEC.CODFORNEC`, por coincidência de código. Um join com fornecedor "funciona"
  em um terço das linhas e infla o líquido. No staging a coluna chama
  `id_cliente_devolucao` justamente para tornar o erro impossível de cometer por descuido.

- **`dbt seed` NÃO aplica mudança de `+column_types`.** Ele faz truncate+insert na tabela
  existente; o tipo antigo continua e trunca em silêncio. Mexeu em `column_types`, rode
  **`dbt seed --full-refresh`**. Foi assim que `ICMS_EF_SAIDA` ficou gravado como
  `0.120589` em vez de `0.1205892`.

### Mais duas medidas no dado (Etapa 3)

- ~~**71 SKUs saem com `FORA_DE_LINHA = 'N'` mesmo tendo `'S'` em mês fechado.**~~
  **REVOGADO em 21/08/2026 — agora é para ler do registro mais recente** (MELHORIAS.md
  A3, §6.0 desta lista). A instrução anterior era "é fiel — não conserte", e ela valia
  **enquanto a planilha era alvo de réplica exata**.
  Registro do que era, para quem for ler código antigo: o campo vinha **só da linha do mês
  corrente**, e produto fora de linha sem movimento não tem linha no mês corrente — o
  Power Query faz exatamente isso, e `CHECK_FORA_DE_LINHA` (AP) não disparava para esses
  71. Agora `int_venda_mensal_pivot` lê o registro **mais recente** em que o SKU aparece e
  os 71 passam a alertar (AP: de 1 para 72 SKUs).
  ⚠ O que **continua valendo**: o campo é lookup do estado ATUAL do cadastro colado em
  linha mensal (ver §6.3), então todas as linhas do mesmo SKU trazem o mesmo valor — e
  **4.205 SKUs marcados `FL` que não aparecem em mês nenhum seguem `'N'`**, porque não há
  registro de onde ler. Esse resto é pergunta ao Diretor, não conserto.

- **O mesmo antecessor é reivindicado por vários sucessores.** No `seed_sucessao`: o
  produto 7095 aparece como antecessor de **4** SKUs, cada um com `PESO_1 = 1`; o 2096 de
  3; os produtos 9, 6575, 6719 e 7091 de 2 cada. Se todos forem ativados, cada sucessor
  herda 100% do histórico do antecessor — 400% da demanda no caso do 7095. O Excel também
  soma sem checar (cada `MATCH` é independente), então a aritmética é fiel; o que ele
  tinha e o seed perdeu era a coluna `SOMA_PESOS_DO_ANTIGO_1`, que **mostrava isso ao
  humano**. A proteção voltou como teste `warn`, não como mudança de cálculo.

- ~~**A sucessão não é uniforme entre colunas.**~~ **FECHADO em 21/08/2026 pela MELHORIA
  D1** (MELHORIAS.md; §6.0 desta lista). Registro do que era: `MEDIA_JANELA` (AG) e
  `VD M-1/M-2/M-3` (AD/AE/AF) herdavam com `PESO_1` **e** `PESO_2`, mas `VD_ANT_3M` (AQ)
  herdava **só com `PESO_1`** — a fórmula da planilha simplesmente não escreveu o segundo
  termo. Agora AQ herda com os dois pesos, como as irmãs. **Impacto medido: 0 células**
  (nenhuma linha de `seed_sucessao` tem `ANTIGO_2`); provado com uma linha ativada
  temporariamente e revertida — ver MELHORIAS.md D1.
  ⚠ O que **continua valendo**: na planilha a sucessão é aplicada na aba `pedido`, fórmula
  por fórmula (o `fVendaMes` não conhece o `dSucessao`), e por isso `int_venda_mensal_sucessao`
  mantém `vd_ant_3m` como coluna PRÓPRIA, separada de `q03/q04/q05`. Quem pré-aplicar
  sucessão numa coluna intermediária precisa saber que um valor único pode não servir aos
  dois consumidores.

## 6.3 Como validar contra o original — e o erro que já cometemos

**Não compare tabela materializada contra consulta ao vivo.** Foi assim que a Etapa 2
"reprovou" duas vezes sem ter defeito nenhum.

O que acontece: o model do dbt é uma foto do instante do `dbt run`; o SQL original roda
agora. Entre um e outro a CEDEP vendeu, reservou e faturou. A divergência é real no dado
e falsa como defeito.

Como isso apareceu, e como reconhecer:

- **Estoque:** `qtreserv` subiu 24 unidades e `qtdisp` desceu exatamente 24 nos **mesmos
  6 produtos** — uma reserva de pedido entre o build e a consulta. `dt_ult_saida` de um
  produto virou de 18/08 para 19/08. As outras 38 colunas idênticas.
- **Mensal:** 100% das divergências no **mês corrente**, zero nos 23 meses fechados.

Quando a divergência se concentra nas colunas voláteis, ou só no mês em andamento, e as
diferenças são fisicamente coerentes entre si, é defasagem — não erro de porte.

### O método que vale

- **Model cujo upstream é só view de staging** (ex.: `int_cadastro_estoque`): rode o **SQL
  compilado** do model (`target/compiled/...`) ao vivo, contra o SQL original ao vivo. Os
  dois lados enxergam o mesmo instante e você testa **lógica**, não sincronia. Foi assim
  que a Etapa 2 provou 41/41 colunas, 8.776 linhas, zero divergência.
- **Model cujo upstream é tabela** (ex.: `int_venda_mensal`): reconstrua a cadeia e
  compare **só meses fechados**. O mês corrente vai divergir sempre, por construção — e a
  planilha também só usa meses fechados em `Q00..Q11` e `V00..V05`.
- Divergência de mês fechado, ou em coluna não volátil, **é defeito de verdade**. Aí não
  tem desculpa de sincronia.

### Uma exceção que custou tempo: coluna de CADASTRO num fato mensal

`produto`, `departamento`, `secao` e `fora_de_linha` **não são campos históricos** — são
lookup do estado ATUAL do cadastro, colados numa linha de mês fechado. Elas derivam
sempre que alguém renomeia um produto ou troca um departamento no WinThor, mesmo em mês
fechado, e isso **não é erro de porte**.

Caso real: o produto 1826 virou de `TECBRIL TEC COOL TROP ORG ROSA 1 LT` para
`... P/USO 1L` no cadastro, e as 23 linhas de mês fechado desse SKU passaram a divergir.

**Por isso o protocolo é: reconstrua a cadeia imediatamente antes de validar.** Um
`dbt run --select intermediate` fecha a janela para segundos. Divergência que sobrevive a
um rebuild fresco é defeito de verdade — em qualquer coluna, em qualquer mês.

## 6.4 Divergências DELIBERADAS da planilha — decididas, não toleradas

> Esta seção existe porque, a partir de **21/08/2026**, o `fat_pedido` **não é mais uma
> réplica fiel** do arquivo em `referencia/MODELO_COMPRAS_CEDEP_v10.xlsx`. Ele reproduz a
> planilha **corrigida** pelo Diretor de Compras; o arquivo que temos aqui é a versão
> **anterior** às correções. Divergência nas colunas abaixo é **esperada**. Reverter
> qualquer uma delas para "fechar o validador" desfaz decisão de negócio.

Isso **não** contradiz o "reproduza, não julgue" da §6.1. A regra continua: quem implementa
não conserta regra fiscal por conta própria. O que mudou é a montante — quem responde pelo
fiscal olhou, decidiu e mandou mudar (PDF §14). O caminho foi o previsto, não uma exceção
a ele.

| Coluna(s) | O que mudou | Decisão | Desde |
|---|---|---|---|
| `CH` `MARGEM_ST_s/VALOR` | `ICMS_SAIDA_EF` → `ICMS_SEM_RED` | PENDENCIAS item 1 | 21/08/2026 |
| `CY` `MARGEM_ST_s/VALOR_VAREJO` | `ICMS_SAIDA_EF` → `ICMS_SEM_RED` | PENDENCIAS item 1 | 21/08/2026 |
| `CO` `PV_SUG_ST_s/VALOR_AV` | `ICMS_SAIDA_EF` → `ICMS_SEM_RED` | PENDENCIAS item 1 | 21/08/2026 |
| `DE` `PV_SUG_ST_s/VALOR_VAR_AV` | `ICMS_SAIDA_EF` → `ICMS_SEM_RED` | PENDENCIAS item 1 | 21/08/2026 |
| `CP` `PV_SUG_ST_s/VALOR_AP` | muda por **consequência** de `CO` (fator de prazo) | idem | 21/08/2026 |
| `DF` `PV_SUG_ST_s/VALOR_VAR_AP` | muda por **consequência** de `DE` (fator de prazo) | idem | 21/08/2026 |
| `BO` `CRED_TOTAL` | grafia do seed `CAR80` → `CAR 80` (39 dos 41 SKUs mudam de valor) | PENDENCIAS item 3 | 21/08/2026 |
| `CC` `CHECK_TRIB` | dispara com código vazio **ou zero** | PENDENCIAS item 4 | 21/08/2026 |
| `D` `ALERTA` | muda nos 5 SKUs que agora recebem `CHECK_TRIB` | consequência do item 4 | 21/08/2026 |

**Decisão 1 — "ST s/Valor" usa a alíquota SEM redução.** Era erro na planilha, confirmado
pelo Diretor, que já corrigiu a fórmula lá e atualizou a **§9.1 do PDF**. O regime de
substituição tributária é mecânica separada do **benefício** de redução de base; um não
carrega o outro. **Não** foram tocados os cenários "Oficial" (`CI`, `CQ`, `CR`) nem "Sem
Redução" (`CJ`, `CZ`, `CS`, `CT`, `DG`, `DH`).
Efeito medido no banco: **zero** mudança nos itens em regime ST — `ICMS_SAIDA_EF` e
`ICMS_SEM_RED` já eram idênticas em 100% dos 4.731 `ST_SUBSTITUTO` e dos 514
`ST_RECOLHIDO`, porque a maioria dos itens ST não tem redução disponível. Quem muda são os
`NORMAL`. Consequência aritmética a conhecer: **fora do regime ST, `CH` passa a ser
idêntica a `CJ`, `CY` a `CZ`, `CO` a `CS` e `DE` a `DG`** — ali as duas escolhas que
separavam os cenários (alíquota e base de custo) colapsam, porque sem ST o `ICMS_ST` é 0 e
`BV + BX = BY`. Isso é o resultado correto, não um bug de colagem.

**Decisão 2 — grafia `CAR 80`.** Ver §6.2, onde a instrução antiga ("não normalize") está
marcada como revogada, com data e motivo. Os 41 SKUs do departamento saem do crédito
empírico e passam ao tabelado.
⚠ **O efeito medido é menor do que a nota do Diretor previa** ("muda crédito, ICMS-ST e
preço desses 41"). No banco, em 21/08/2026: muda **`BO` (CRED_TOTAL) em 39 dos 41** — nos
outros 2 o empírico já calhava de dar o valor tabelado —, e **não muda ICMS-ST, custo,
margem, preço nem `ALERTA` em nenhum**. A razão é a decisão 2 das pendências, confirmada
como **intencional**: `BQ` (`CRED_ICMS`) lê `DR` (o crédito **empírico**), não `BO`. `BO`
não está na cadeia de custo; seu único consumidor é `BS` (`CHECK_IMPORTADO`), e nos 41 o
limiar não virou de lado.
Isso **não** desfaz a decisão — a grafia certa é a grafia certa, e ela passa a valer preço
no dia em que a TI expuser a tributação de entrada/saída por item e o crédito real
substituir o proxy (PDF §14). É só motivo para não prometer ao Diretor um efeito em preço
que o dado não mostra.

**Decisão 3 — `CHECK_TRIB` pega o código `0`.** O alerta era fórmula morta (testava só
"vazio", e vazio nunca acontece). Passa a cobrir os 5 SKUs de `codst = 0`, que saem sem
`MODALIDADE`, sem alíquota e com margem em branco — e saíam sem alerta nenhum. O **cálculo**
desses 5 não mudou (§6.2 segue valendo); o que mudou é que eles deixam de sair calados.

### Efeito no critério de aceite

O validador (`validar/validar_pedido.py`) continua comparando **todas** as colunas, sem
exceção: nenhuma verificação foi desligada. O que ele ganhou foi um registro explícito,
`LETRAS_DIVERGENCIA_POR_DECISAO`, que **rotula** essas colunas no relatório e as separa das
demais no resumo executivo. Uma coluna rotulada continua sendo medida, contada e impressa —
a etiqueta muda quem precisa explicar a divergência, não se ela é medida.

Desde 21/08/2026 o dicionário também cobre as **melhorias aprovadas** (§6.0 (b)): `AP`
(A3), `AV`/`CL`/`DB` (A4), `AQ` (D1) e, desde 24/08/2026, `BB`/`BC`/`BD`/`BE`/`BF` (A5).
`AQ` e as cinco de A5 têm expectativa de **zero** divergência hoje — qualquer divergência
nelas neste build é DEFEITO, não a melhoria. Cada rótulo carrega o número **esperado** de
linhas divergentes, justamente para que "além disso" continue sendo defeito. O rótulo de
`BF` é o único que declara divergência hoje, e declara também que ela **não é** de A5:
com `BB = 0`, `BF` é idêntica a `AW` e herda a volatilidade de `EST+PEND`.

⚠ O padrão do arquivo de referência do validador é a **v11**
(`XLSX_PATH_PADRAO`). Apontar para a v10 faria as seis colunas do cenário "ST s/Valor"
(`CH`/`CY`/`CO`/`CP`/`DE`/`DF`) aparecerem divergentes sem nada estar errado — a v11 já
traz a correção do Diretor, e contra ela essas seis fecham.

`D` (`ALERTA`) é **crítica** e continua exigindo zero divergência **não atribuível**
(§6.1.0/§6.1.1). Medido em 21/08/2026: **1.793 linhas divergentes, 1.793 atribuíveis
componente a componente, zero sobra** — 1.749 por A4, 71 por A3 (34 pelos dois), 5 por
`CHECK_TRIB`, 3 por `CHECK_ESTOQUE_PARADO` (volátil) e 1 por `CHECK_LITRAGEM` (o produto
6433 teve a embalagem renomeada no cadastro). Divergência em `ALERTA` que não caia em
nenhuma dessas caixas continua sendo defeito.

