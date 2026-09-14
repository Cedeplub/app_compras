# REGRAS — App Compras CEDEP

As **regras de negócio** do projeto: o que foi decidido, por quem, com que número, e qual
armadilha cada regra evita. Não há uma linha de convenção de código aqui — convenção de
dbt, de nome de model e de estilo de SQL mora no `CONTEXTO.md` §5.

**Leia este arquivo se** você vai mexer em model `int_*`/`fat_*`, em seed, em fórmula de
custo/margem/preço, na curva ABC, na coluna `ALERTA`, na tela de Alertas ou em qualquer
script de `validar/`.

**Não precisa ler se** seu trabalho é serviço, DDL de tabela `APP_*`, rota, template ou
empacotamento — nesses casos o `CONTEXTO.md` basta.

> **Nota de numeração.** As seções continuam sendo §6, §6.0, §6.0.1, §6.1, §6.1.0, §6.1.1,
> §6.2, §6.3 e §6.4, como eram quando moravam no `CONTEXTO.md`. `validar/validar_pedido.py`
> cita "§6.2", "§6.3", "§6.1.0" e "§6.1.1" **pelo número**, e ~80 arquivos citam este
> documento pelo nome. A numeração foi preservada de propósito; o conteúdo novo entra
> como §7 em diante.

> **Este documento absorve e substitui os quatro arquivos** que antes reuniam,
> separadamente, as melhorias sobre a planilha, as pendências levadas à diretoria, as
> divergências de cadastro no Winthor e as decisões do Diretor sobre a tela de Alertas —
> todos descontinuados na Etapa 14 (histórico da migração em
> `historico/PROMPT_ETAPA_14_MIGRACAO_REPOSITORIO.md`). Eles guardavam a **discussão**;
> aqui fica o **que ficou valendo**.

> ⚠ **Todo número deste arquivo foi RECALCULADO em 12/09/2026**, contra o build das 06:00
> (570 s, `APP_ATUALIZACAO` id 201). Onde o recálculo divergiu do que os `.md` de agosto
> escreviam, **vale o recálculo** — e a divergência está registrada em uma linha no §11.
> Os poucos números que não dava para remedir sem rodar o validador contra o `.xlsx` estão
> marcados com a data da medição original, como o §6.0.1 exige.

---

## 6. As 11 regras que não podem escorregar

Cada uma já causou ou pode causar erro de preço real. Fonte: PDF §8–§12 e as fórmulas do
gabarito de 122 colunas.

1. **Quantidade e valor são sempre LÍQUIDOS** (faturado − devolvido). A única exceção é
   `TX_DEVOLUCAO_3M`, que por definição precisa do bruto no denominador.
   *Armadilha medida:* `PCNFENT.CODFORNEC` é o **cliente que devolveu**, não um fornecedor.
   Das notas de devolução, 100% casam com `PCCLIENT.CODCLI` e ~34% casam **também** com
   `PCFORNEC.CODFORNEC`, por coincidência de código — um join com fornecedor "funciona" em
   um terço das linhas e infla o líquido. No staging a coluna chama `id_cliente_devolucao`
   justamente para tornar o erro impossível por descuido.

2. **Ajuste Ingrax (80/20)** entra em margem e preço via `CUSTO_TOT_GERENCIAL`, e **nunca**
   na base fiscal de ICMS-ST, que usa só o custo oficial.
   `CUSTO_ADICIONAL_IMAGEM = VL_ENT_UNIT × (1/PERC_NF_NORMAL − 1) × (1 − PISCOF_EF)`.
   *Armadilha:* confundir as duas bases erra o imposto efetivamente recolhido, não só um
   número de tela.

3. **Redução de base de ICMS vale só para as filiais de atacado.** O varejo usa sempre a
   alíquota cheia (`ICMS_SEM_RED`).
   *Armadilha medida:* o código de filial no banco é `'1'`, `'2'`, `'9'` — **sem zero à
   esquerda**. `PCEST.CODFILIAL` e `PCFILIAL.CODIGO` são `VARCHAR2(2)`. Escrever
   `in ('02','09')` retorna zero linhas, a redução nunca é aplicada e o atacado sai com
   alíquota cheia, calado. A documentação de negócio fala "02/09"; o dado diz "2"/"9".

4. **Crédito de PIS/COFINS** é sobre a NF **sem IPI**, descontado o crédito de ICMS.

5. **Curva ABC recalcula o total a cada build** — `sum() over (partition by ...)`, nunca um
   total fixo. Esse bug já aconteceu de verdade neste modelo. E são **dois universos
   separados**: com litragem (`L_POR_UNIDADE > 0`) e sem, cada um com seu denominador.
   *Armadilha medida:* qualquer erro que mova um SKU de universo muda a classe de **todos**
   os 8.841, não só do SKU movido. Distribuição de hoje: A 136, B/C 3.241, S/VEND 5.464.

6. **`FATOR_EXIBICAO`** (= `EMBAL_COMPRA` quando o fornecedor tem `PEDIDO_EM = 'MASTER'`,
   senão 1) divide praticamente toda quantidade exibida.
   ⚠ **Exceção decidida (A5, 24/08/2026):** onde existe decisão de pedido gravada, o fator
   é o **congelado naquela decisão**, não o corrente. Ver §6.4 e §9.2.
   *Armadilha medida:* o `EMBAL_COMPRA` muda na atualização **diária** de cadastro — não só
   numa reconfiguração manual. Recalcular faria a quantidade em unidades, e o dinheiro do
   pedido, mudarem sozinhos numa decisão que ninguém redigitou.

7. **`FORNECEDOR` é o texto do DEPARTAMENTO**, não o fornecedor legal da nota fiscal.
   *Armadilha:* a chave de crédito é `FORNECEDOR|COD_ICMS`; um espaço a mais ou a menos na
   grafia faz a busca falhar em silêncio e cair no crédito empírico (foi o caso `CAR80`,
   §6.2).

8. **`VL_ULT_ENT` nunca é dividido pela embalagem de compra** — já vem unitário.

9. **A base mensal inclui todo SKU que apareceu em QUALQUER mês**, inclusive o corrente.
   Produto de primeira venda no mês corrente tem de aparecer, com os meses fechados zerados.

10. **`ALT_PV_*` e `PEDIDO` são DECISÃO HUMANA.** Nunca preencher automaticamente com uma
    sugestão calculada. `MARGEM_ALVO` cai no padrão 20% (`MARGEM_ALVO_PADRAO`) quando não
    há decisão gravada.
    *Diferença deliberada entre as duas:* ausência de decisão de **preço** vale **nulo**;
    ausência de decisão de **pedido** vale **zero**, porque BB/BC/BF usam a coluna em
    aritmética e um nulo apagaria `MESES_EST+PED` de todo SKU sem decisão.

11. **`dtexclusao is null` tem uso DIFERENTE em cada relatório** — a armadilha mais cara já
    encontrada neste projeto:
    - **Estoque/fiscal:** condição **fixa e global**, em toda linha e no lookup base. Não
      aplicar deixa entrar produto excluído na base cadastral e, pela regra 5, muda a curva
      ABC de **todos** os SKUs.
    - **Mensal:** aparece **uma única vez**, dentro da CTE `produtos_incluir`, que decide só
      quem entra *sem ter vendido*. A CTE que controla a saída **não** filtra — produto
      excluído **com** movimento no período aparece. Aplicar globalmente apaga linha que
      deveria existir.

    Aplicar nos dois, ou em nenhum, está errado das duas formas. O padrão geral: antes de
    mover um filtro de lugar, conte quantas vezes ele aparece no SQL de origem e em quais
    CTEs. Por isso o staging não filtra — ele não tem como saber qual uso vale.

### Fórmulas centrais

```
margem  = (PV − PV × (aliq_icms + piscof + comissao) − custo) / PV
pv_sug  = custo / (1 − aliq_icms − piscof − comissao − margem_alvo)
a prazo = a vista × fator     (atacado 1,0317 | varejo 1,086435)
```

Os três cenários de atacado diferem **só** em qual alíquota e qual base de custo usam:
`ST s/Valor` (alíquota sem redução + custo s/valor + ajuste Ingrax), `Oficial` (oficial com
redução + custo gerencial), `Sem Redução` (sem redução + custo gerencial). O varejo tem
dois: `ST s/Valor` e `Sem Redução`.

**Constante em fórmula é defeito.** Alíquota, fator, corte e limiar saem de `int_parametro`
(o seed pivotado em uma linha larga, para `cross join`). É requisito explícito da planilha,
que registra em que fórmula cada constante estava chumbada antes — `FATOR_PRAZO_VAREJO`,
`DIAS_ESTOQUE_PARADO`, `TEND_LIMIAR` e `PALETE_LIMIAR` são os casos nomeados.

## 6.0 Onde divergimos da planilha DE PROPÓSITO

O gabarito é a **v11** (`referencia/MODELO_COMPRAS_CEDEP_v11.xlsx`), que já traz a correção
do cenário "ST s/Valor". A planilha deixou de ser alvo de **réplica exata** e passou a ser
**ponto de partida**. A regra de aceite não afrouxou por isso:

> **Toda divergência da planilha é defeito, exceto as registradas aqui.**

Duas origens de divergência deliberada, e elas não se confundem:

**(a) Decisões do Diretor que ele ainda NÃO aplicou na planilha** — a v11 vai alcançá-las:

| O que | Onde | SKUs | Situação |
|---|---|---|---|
| `CAR80` → `CAR 80` no `seed_credito` | crédito, ICMS-ST e preço | **41** (recalculado 12/09) | v11 ainda tem `CAR80` |
| `CHECK_TRIB` passa a pegar o código `0` | `CC`, e `D` por tabela | **5** | v11 ainda não dispara |

**(b) Melhorias aprovadas** — estas **não vão existir na planilha**:

| Melhoria | Coluna(s) | Efeito, recalculado em 12/09/2026 |
|---|---|---|
| **A3** — `FORA_DE_LINHA` do registro **mais recente**, não do mês corrente | `AP` | `CHECK_FORA_DE_LINHA` alerta **74** SKUs (eram 72 em 21/08); sem A3 alertaria 1 |
| **A4** — percentual com **uma casa decimal e vírgula** (`"5,5%"` no lugar de `"05%"`) | `AV`, `CL`, `DB` | **2.196 células de texto** não vazias: `AV` 113, `CL` 1.664, `DB` 419. Nenhum número de cálculo muda |
| **D1** — `VD_ANT_3M` herda com `PESO_1` **e** `PESO_2` | `AQ` | **0 células**: as 25 linhas de `seed_sucessao` seguem sem `ANTIGO_2` e **0** estão ativas |
| **A5** — `PEDIDO_UNIDADES` usa o `FATOR_EXIBICAO` **congelado** na decisão, não o corrente (`K`) | `BB`, e por consequência `BC`, `BD`, `BE`, `BF` | Deixou de ser zero: **66 SKUs** têm decisão de pedido gravada desde a troca de fonte de 12/09 (§9.2). `BG` **não** entra: é estoque, não pedido |

⚠ **A5 foi exercitada de ponta a ponta em 24/08/2026, com decisões de teste gravadas e
apagadas**, justamente porque na época o efeito era zero e a implementação certa e a errada
davam o mesmo resultado. SKU 3821 (MASTER, fator corrente 12, decisão gravada com fator 6,
`PEDIDO=120`) saiu com `BB = 720` e `BD = 11.138,92`, contra `1.440` e `22.277,84` da
fórmula corrente; SKU 11 (fator 1) não mudou em nada. A regra é protegida pelo teste
singular `compras_pedido_unidades_usa_fator_congelado`.

⚠ **A3 tem um limite conhecido, medido e NÃO corrigido:** SKU que não aparece em mês NENHUM
da base mensal continua saindo `'N'`. São **4.209 SKUs** marcados `OBS2='FL'` no cadastro
(de 4.283 no total) que nunca entram naquele model. Ler o campo direto do cadastro
alcançaria os 4.209 — é mudança de escopo maior que a aprovada e segue **pendente de
decisão do Diretor de Compras**.

## 6.0.1 Números de registro envelhecem — não os trate como verdade

Os efeitos anotados são **fotos do dia da medição**. Eles se movem sozinhos:

- o texto de margem (`CL`) acompanha o custo, que muda com cada nota de compra;
- `ALERTA` acompanha `CHECK_ESTOQUE_PARADO`, que depende de `TODAY()`;
- a contagem de SKUs cresce com o catálogo: **8.772 → 8.777 → 8.841** entre 19/08 e 12/09.

Medido entre 21 e 24/08/2026: `ALERTA` foi de 1.793 para 2.146 divergências e `A4` de 2.182
para 2.187 células — **sem nenhuma mudança de código**.

**A consequência prática:** número defasado não invalida a decisão, mas não serve como
critério. Ao verificar, **recalcule a atribuição**, não compare contra o número anotado. O
que precisa continuar valendo é a **atribuibilidade** (§6.1.0). E ao reportar, diga a data
da medição junto com o número.

## 6.1 As 5 divergências PDF × planilha — todas decididas

Levantadas ao portar o modelo para SQL; **4 decididas em 21/08/2026 e a 5ª em 24/08/2026**.
Nenhuma segue em aberto. Novas divergências vão para cá, não são resolvidas por conta
própria — é o que o PDF §14 manda.

| # | Divergência | Decisão | Efeito recalculado |
|---|---|---|---|
| 1 | Cenário "ST s/Valor" usava a alíquota **reduzida** | **Era erro da planilha.** Passa a usar `ICMS_SEM_RED` em `CH`, `CO`, `CY`, `DE` (e `CP`/`DF` por consequência do fator de prazo). O Diretor já corrigiu a planilha e a §9.1 do PDF | **Zero** mudança nos itens em regime ST: `ICMS_SAIDA_EF` e `ICMS_SEM_RED` já eram idênticas nos 4.750 `ST_SUBSTITUTO` e nos 515 `ST_RECOLHIDO`. Quem muda são os **3.571 `NORMAL`** |
| 2 | `dCredito` fora do cálculo de custo | **Intencional**, documentado na §8.5 do PDF. O Winthor não expõe tributação de entrada/saída por item; o modelo usa a diferença custo × valor como **proxy**. A `dCredito` é referência, e só alimenta o alerta de importado | Nada a mudar no código |
| 3 | Grafia `CAR80` × departamento `CAR 80` | **Corrigir o seed.** A tabela existe para ser consultada; manter o erro de digitação preservaria o defeito, não a regra | **41 SKUs** saem do crédito empírico. Muda `BO` em 39 deles; **não** muda ICMS-ST, custo, margem, preço nem `ALERTA` em nenhum — porque `BQ` lê o crédito empírico (`DR`), não `BO`. O efeito é menor do que a nota do Diretor previa, e isso fica registrado para não prometer movimento de preço que o dado não mostra |
| 4 | `CHECK_TRIB` era fórmula morta (testava só "vazio", e vazio nunca acontece) | **Passa a disparar com vazio OU zero** | **5 SKUs** de `codst = 0`, que saem sem `MODALIDADE`, sem alíquota e com margem em branco. O cálculo deles **não** mudou; o que deixou de existir foi o silêncio |
| 5 | `FATOR_EXIBICAO` de decisão tomada: corrente ou congelado | **Congelar.** O fator gravado na decisão é a fonte de verdade para unidades, valor e cobertura | Aplicado como A5 (§6.0 (b)). Hoje alcança **66 SKUs** |

**A regra de conduta que continua valendo:** *reproduza, não julgue.* Quem implementa não
conserta regra fiscal por conta própria — registra a divergência e segue o gabarito. O que
mudou nestes 5 casos é a montante: quem responde pelo fiscal olhou, decidiu e mandou mudar.

**O raciocínio do Diretor na decisão 5, que vale registrar:** o que importa para o negócio
(`VALOR_PEDIDO`, `MESES_EST+PED`) é sempre a conta **em unidades** — caixa é só a forma de
digitar quando o fornecedor está em MASTER. Uma decisão já tomada não deveria mudar de
tamanho por conta de um cadastro que atualizou depois; se a embalagem mudou de verdade, o
certo é **gerar uma decisão nova** vendo o número atualizado, não reinterpretar a antiga.

**Fator de prazo do varejo (1,086435).** Na planilha é constante **chumbada dentro da
fórmula**, enquanto o atacado usa `Parametros!$B$5`. Aqui vai para `seed_parametros` como
`FATOR_PRAZO_VAREJO`. Isso **não** é divergir do gabarito: o número é o mesmo. Muda só onde
a constante mora.

## 6.1.0 O critério de aceite — ATRIBUIBILIDADE, não zero absoluto

O plano original exigia "zero divergência em `CLASSE`, `ALERTA`, `MODALIDADE` e
`CUSTO_TOT_GERENCIAL`". **Duas dessas quatro são impossíveis de cumprir:**

- `CUSTO_TOT_GERENCIAL` descende de `VL_ENT_UNIT` e `CUSTO_ULT_ENT` — valor e custo da
  última entrada, que mudam a cada nota de compra que chega.
- `MODALIDADE` descende de `COD_TRIBUTACAO`, que muda quando o fiscal reclassifica um item.

A aba `pedido` é uma **foto**; o `fat_pedido` é construído hoje. Medido em 21/08/2026: a
foto era de 2 dias antes — `DIAS_SEM_VENDA` deu exatamente `+2` em **4.513 de 4.513** SKUs
que não venderam, e negativo em todos os que venderam. Nenhum SKU com diferença positiva
diferente de +2.

### O critério que vale

**Toda célula divergente precisa ser ATRIBUÍVEL a um insumo que mudou.** Não "quantas
divergem", mas "alguma diverge sem explicação?".

1. Para cada coluna divergente, teste-a contra os insumos que a fórmula dela lê.
2. Divergência que some quando você usa os insumos da própria planilha = **defasagem**.
3. Divergência que **sobrevive** a isso = **defeito**, e reprova.
4. Aceite: **zero células não atribuíveis**, e ≤ 0,01 de diferença nas numéricas.

`CLASSE` continua com exigência de zero absoluto — depende só de média de venda de meses
fechados e de embalagem, ambas estáveis.

**Sinal de defasagem, para reconhecer rápido:** a divergência **cresce com o relógio**.
Medido: entre duas execuções separadas por 25 minutos, `VL_ENT_UNIT` foi de 71 para 82 SKUs
divergentes. Defeito não cresce sozinho.

## 6.1.1 O critério de aceite de `ALERTA`, componente a componente

`ALERTA` (coluna D) concatena 14 colunas `CHECK_*`, e elas não são da mesma natureza:

- **Estruturais** — `CHECK_RUPTURA`, `CHECK_DEVOLUCAO_ALTA`, `CHECK_LITRAGEM`,
  `CHECK_IMPORTADO`, `CHECK_TRIB`, `CHECK_MVA`, `CHECK_MARGEM_INSTAVEL`,
  `CHECK_MARGEM_INSTAVEL_VAREJO`, `CHECK_SUCESSAO`. Divergência aqui **é defeito**.
- **Voláteis** — `CHECK_ESTOQUE_PARADO` (depende de `TODAY()`) e `CHECK_FORA_DE_LINHA`
  (cadastro editável). ⚠ Desde A3, `CHECK_FORA_DE_LINHA` **não vira mais com a virada do
  mês** — ele lê o registro mais recente do SKU.
- **Dependentes de decisão humana** — `CHECK_FABRICA` e `CHECK_INATIVO`, que leem `PEDIDO`.
  ⚠ Os dois saíam **100% vazios** enquanto `PEDIDO` vinha da tabela morta; desde 12/09/2026
  (§9.2) passam a ter valor para os 66 SKUs com pedido gravado. Divergir da planilha neles
  é **esperado** — a planilha não tem a decisão.

**Ordem da coluna `ALERTA` é a do Excel, não alfabética:** FABRICA, INATIVO, RUPTURA,
DEVOLUCAO, PARADO, FORA_DE_LINHA, LITRAGEM, IMPORTADO, TRIB, MVA, CUSTO, MARGEM_INSTAVEL,
SUCESSAO, MARGEM_INSTAVEL_VAREJO.

**Critério correto:** exigir zero divergência **em cada `CHECK_*` estrutural,
individualmente**. `ALERTA` é derivada — reporte as divergências dela, mas cada uma tem de
ser atribuível a um componente volátil ou de decisão humana.

Contagem de hoje, para referência (`fat_pedido`, 12/09/2026): `ALERTA` não vazio em
**4.889** SKUs de 8.841. Por componente: IMPORTADO 2.285 · MARGEM_INSTAVEL 1.664 ·
LITRAGEM 1.016 · RUPTURA 468 · PARADO 458 · MARGEM_INSTAVEL_VAREJO 419 · MVA 174 ·
DEVOLUCAO 113 · FORA_DE_LINHA 74 · CUSTO 20 · SUCESSAO 16 · TRIB 5 · FABRICA 0 · INATIVO 0.

## 6.2 Armadilhas medidas no banco — não "conserte" nenhuma delas

Cada item foi verificado contra o dado real. Todas parecem defeito e **não são**.

- **Embalagem: o join precisa de `upper()`, NÃO pode ter `trim()`, e precisa de dedupe.**
  Três coisas ao mesmo tempo:
  1. **`upper()` é obrigatório** — 158 SKUs (20/08/2026) só casam ignorando caixa, e o
     `MATCH` do Excel ignora caixa. Sem ele, `L_POR_UNIDADE` vira 0, o SKU cai no universo
     errado e, pela regra 5, a classe ABC muda para **todos**.
  2. **`trim()` é proibido** — 13 valores têm espaço à direita (`TAMBOR `, `10X1 `,
     `BALDE `, `1LT `) que **nem o Excel casa**. Aplicar `trim()` seria divergir do gabarito.
  3. **`upper()` sozinho causa FAN-OUT** — o `seed_embalagem` tem **145 linhas e só 135
     valores distintos em `upper()`**: são **10 pares** que diferem apenas na caixa. Um join
     direto duplica milhares de SKUs. Agrupe por `upper()` antes de juntar, pegando um
     valor — é o que o `MATCH` faz. Os 10 pares hoje têm litragem idêntica, e o teste
     `compras_embalagem_upper_sem_conflito` quebra o build no dia em que deixarem de ter.

- **5 linhas de `PCTABTRIB` (BA, filial 2) têm `codst = 0`**, sem correspondência no
  `seed_icms`. Na planilha isso **não** cai no código padrão (a fórmula só usa o padrão
  quando a célula é *vazia*, e 0 não é vazio): `MODALIDADE` e `ICMS_SAIDA_EF` ficam em
  branco e as margens desses 5 saem vazias. Recalculado hoje: exatamente **5** linhas de
  `fat_pedido` com `MODALIDADE` vazia. Isso continua reproduzido de propósito; o que mudou
  em 21/08 foi só o alerta (§6.1, item 4).

- **A grafia do seed de crédito foi normalizada** (`CAR80` → `CAR 80`), e isso **revogou**
  a instrução antiga "não normalize". ⚠ O que **continua proibido** é `trim()` no join de
  crédito e no de embalagem: a correção foi no **dado do seed**, não na regra de comparação.
  O espaço segue significativo.

- **O mesmo antecessor é reivindicado por vários sucessores.** No `seed_sucessao` (25
  linhas, **0 ativas** hoje): o produto 7095 aparece como antecessor de **4** SKUs, cada um
  com `PESO_1 = 1`; o 2096 de 3; os produtos 9, 6575, 6719 e 7091 de 2 cada. Se todos forem
  ativados, cada sucessor herda 100% do histórico — 400% da demanda no caso do 7095. O
  Excel também soma sem checar (cada `MATCH` é independente), então a aritmética é fiel; o
  que ele tinha e o seed perdeu era a coluna que **mostrava isso ao humano**. A proteção
  voltou como teste `warn`, não como mudança de cálculo.

- **A sucessão não é uniforme entre colunas** — fechado pela melhoria D1. O que **continua
  valendo**: na planilha a sucessão é aplicada na aba `pedido`, fórmula por fórmula, e por
  isso `vd_ant_3m` é coluna PRÓPRIA, separada de `q03/q04/q05`. Quem pré-aplicar sucessão
  numa coluna intermediária precisa saber que um valor único pode não servir aos dois
  consumidores.

- **Quantidade líquida negativa contamina a média.** Devolução de unidades vendidas antes
  da janela produz líquido negativo — medido: produto 7095 faturou 4 e recebeu 24 de volta,
  e a média de venda fica negativa. **Hoje reproduzimos.** Pôr um piso em zero muda
  sugestão de compra e é decisão do Diretor (§10).

- **`dbt seed` NÃO aplica mudança de `+column_types`.** Faz truncate+insert na tabela
  existente; o tipo antigo continua e trunca em silêncio. Foi assim que `ICMS_EF_SAIDA`
  ficou gravado como `0.120589` em vez de `0.1205892`. Mexeu em tipo, rode
  `dbt seed --full-refresh`.

## 6.3 Como validar contra o original — e o erro que já cometemos

**Não compare tabela materializada contra consulta ao vivo.** Foi assim que a Etapa 2
"reprovou" duas vezes sem ter defeito nenhum. O model é uma foto do instante do `dbt run`;
o SQL original roda agora. Entre um e outro a CEDEP vendeu, reservou e faturou.

Como isso apareceu: `qtreserv` subiu 24 unidades e `qtdisp` desceu exatamente 24 nos
**mesmos 6 produtos**; `dt_ult_saida` de um produto virou de 18/08 para 19/08; as outras 38
colunas idênticas. No mensal, 100% das divergências no **mês corrente**, zero nos 23 meses
fechados.

### O método que vale

- **Model cujo upstream é só view de staging:** rode o **SQL compilado** do model ao vivo,
  contra o SQL original ao vivo. Os dois lados enxergam o mesmo instante e você testa
  **lógica**, não sincronia. Foi assim que a Etapa 2 provou 41/41 colunas, zero divergência.
- **Model cujo upstream é tabela:** reconstrua a cadeia e compare **só meses fechados**. O
  mês corrente diverge sempre, por construção.
- Divergência de mês fechado, ou em coluna não volátil, **é defeito de verdade**.

### Uma exceção que custou tempo: coluna de CADASTRO num fato mensal

`produto`, `departamento`, `secao` e `fora_de_linha` **não são campos históricos** — são
lookup do estado ATUAL do cadastro, colados numa linha de mês fechado. Caso real: o produto
1826 virou de `TECBRIL TEC COOL TROP ORG ROSA 1 LT` para `... P/USO 1L` no cadastro, e as
23 linhas de mês fechado desse SKU passaram a divergir. **Por isso o protocolo é:
reconstrua a cadeia imediatamente antes de validar.**

⚠ **O rebuild não é rápido, e planejar com o número errado atrasa validação.** Recalculado
sobre as 15 execuções registradas em `APP_ATUALIZACAO`: **158 s no mínimo, 577 s no máximo,
mediana 411 s (~7 min)**. A documentação de agosto repetia "~70 s"; esse número não existe
mais.

### O critério de aceite final

`fat_pedido` comparado célula a célula com a aba `pedido` da v11, 122 colunas × todas as
linhas, via `validar/validar_pedido.py`:

- divergência ≤ 0,01 em ≥ 99,9% das células numéricas;
- **zero divergência não atribuível** em `CLASSE`, `ALERTA`, `MODALIDADE` e
  `CUSTO_TOT_GERENCIAL` (com a ressalva do §6.1.0 para as duas que descendem de insumo
  volátil).

O que sobrar vira lista de exceções para o Diretor de Compras validar. **Não ajuste fórmula
para fechar número.**

⚠ O padrão do arquivo de referência do validador é a **v11**. Apontar para a v10 faria as
seis colunas do cenário "ST s/Valor" aparecerem divergentes sem nada estar errado.

## 6.4 Divergências deliberadas da planilha — decididas, não toleradas

| Coluna(s) | O que mudou | Decisão | Desde |
|---|---|---|---|
| `CH` `MARGEM_ST_s/VALOR` | `ICMS_SAIDA_EF` → `ICMS_SEM_RED` | §6.1 item 1 | 21/08/2026 |
| `CY` `MARGEM_ST_s/VALOR_VAREJO` | idem | §6.1 item 1 | 21/08/2026 |
| `CO` `PV_SUG_ST_s/VALOR_AV` | idem | §6.1 item 1 | 21/08/2026 |
| `DE` `PV_SUG_ST_s/VALOR_VAR_AV` | idem | §6.1 item 1 | 21/08/2026 |
| `CP` / `DF` | mudam por **consequência** de `CO`/`DE` (fator de prazo) | idem | 21/08/2026 |
| `BO` `CRED_TOTAL` | grafia do seed `CAR80` → `CAR 80` | §6.1 item 3 | 21/08/2026 |
| `CC` `CHECK_TRIB` | dispara com código vazio **ou zero** | §6.1 item 4 | 21/08/2026 |
| `AP` `CHECK_FORA_DE_LINHA` | registro mais recente, não mês corrente (A3) | melhoria | 21/08/2026 |
| `AV` `CL` `DB` | percentual com uma casa decimal e vírgula (A4) | melhoria | 21/08/2026 |
| `AQ` `VD_ANT_3M` | herda com `PESO_1` **e** `PESO_2` (D1) | melhoria | 21/08/2026 |
| `BB` `BC` `BD` `BE` `BF` | fator de exibição **congelado** na decisão (A5) | §6.1 item 5 | 24/08/2026 |
| `BA` `PEDIDO` | fonte trocada para `APP_PEDIDO_ITEM` (§9.2) | correção de lacuna | 12/09/2026 |
| `D` `ALERTA` | muda por consequência de `CHECK_TRIB`, A3, A4 e agora de `BA` | consequência | 21/08/2026 |

**Consequência aritmética a conhecer, e que não é bug de colagem:** fora do regime ST, `CH`
passa a ser idêntica a `CJ`, `CY` a `CZ`, `CO` a `CS` e `DE` a `DG` — ali as duas escolhas
que separavam os cenários (alíquota e base de custo) colapsam, porque sem ST o `ICMS_ST` é
0 e `BV + BX = BY`.

⚠ `BF` aparecia divergente no validador por **outra** causa que não A5: com `BB = 0`, `BF`
era numericamente idêntica a `AW` (`MESES_EST`) e herdava a volatilidade de `EST+PEND`. Com
os 66 SKUs de pedido gravado, isso deixa de valer para eles.

### Efeito no critério de aceite

O validador continua comparando **todas** as colunas: nenhuma verificação foi desligada. O
que ele ganhou foi `LETRAS_DIVERGENCIA_POR_DECISAO`, que **rotula** essas colunas no
relatório e as separa no resumo. Uma coluna rotulada continua sendo medida, contada e
impressa — a etiqueta muda **quem precisa explicar** a divergência, não se ela é medida.

## 7. Decisões do Diretor de Compras sobre a tela de Alertas

Oito perguntas levadas em 01/09/2026, respondidas e implementadas em 02/09/2026, com uma
**segunda rodada** no mesmo dia que ajustou três delas. Abaixo está **o que ficou
valendo** — a discussão está em `historico/`.

### 7.1 Taxonomia: 10 tipos de DECISÃO + 5 de CADASTRO

`PARADO` foi **dividido em dois níveis**, `SEM_GIRO` e `BAIXO_GIRO`; as margens foram
renomeadas; `OPORTUNIDADE_DE_GIRO` e `MARGEM_ALTA` foram **criados** — os dois são alertas
novos, **sem coluna na planilha**.

| Categoria | Tipo | Linhas | Ativos |
|---|---|---|---|
| DECISAO | `MARGEM_BAIXA` | 1.664 | 1.005 |
| DECISAO | `MARGEM_ALTA` | 1.308 | 846 |
| DECISAO | `RUPTURA` | 468 | 467 |
| DECISAO | `SEM_GIRO` | 328 | 306 |
| DECISAO | `MARGEM_BAIXA_VAREJO` | 419 | 167 |
| DECISAO | `BAIXO_GIRO` | 130 | 130 |
| DECISAO | `DEVOLUCAO` | 113 | 113 |
| DECISAO | `FORA_DE_LINHA` | 74 | 0 |
| DECISAO | `OPORTUNIDADE_DE_GIRO` | 33 | 33 |
| DECISAO | `CUSTO` | 20 | 2 |
| CADASTRO | `IMPORTADO` | 2.285 | 1.133 |
| CADASTRO | `LITRAGEM` | 1.016 | 339 |
| CADASTRO | `MVA` | 174 | 24 |
| CADASTRO | `SUCESSAO` | 16 | 16 |
| CADASTRO | `TRIB` | 5 | 0 |

`FORA_DE_LINHA` é **etiqueta que não pontua** (`PONTUA='N'`), por decisão do item 7: FL e
Inativo **nunca divergem** no nosso modelo — os dois derivam da mesma expressão
`upper(trim(OBS2))='FL'`, e todo produto fora de linha já é inativo. Inventar dois sinais
para depois unificá-los seria pior. Efeito colateral a saber: com o filtro em "Ativo", o
botão "Fora de linha" mostra sempre **0**.

### 7.2 A separação DECISÃO × CADASTRO

Alerta de cadastro diz *"confira este cadastro"*, não *"decida esta compra"*. A coluna
`CATEGORIA` de `COMPRAS_ALERTA` separa os dois, e a tela de Alertas mostra só `DECISAO`.

**Recalculado em 12/09/2026: 2.070 SKUs** têm **apenas** alerta de cadastro e portanto
saíram da tela de Alertas (o `.md` de 02/09 registrava 1.871). São 8.053 linhas de alerta
em 5.656 SKUs no total.

### 7.3 Os limiares que o Diretor mudou na segunda rodada

| Parâmetro | Valor **vigente** | Era | Por quê |
|---|---|---|---|
| `MARGEM_ALTA_MIN` | **0,25** | 0,20 | Com 20% o alerta pegava 1.634 SKUs ativos e era o segundo maior da tela; com 25% caiu para 874 na medição de 02/09 (846 hoje) |
| `MARGEM_ALTA_MIN_VAREJO` | **0,50** | 0,45 | Limiar propositalmente **maior** que o do atacado: o varejo opera com margem naturalmente mais alta |
| `OPORTUNIDADE_GIRO_MESES` | **3** | — | Dispara com cobertura acima de 3 meses (90 dias) de venda |

Se o volume ainda parecer grande, o próximo corte natural é 30%/55% — é **uma linha de
seed**, não código.

**Classe B em `OPORTUNIDADE_DE_GIRO`: recomendado NÃO**, e mantido fora. A curva do modelo
não tem `B` isolado — é `A`, `B/C`, `S/VEND`, com B e C fundidos desde a planilha. Abrir
para `B/C` levaria o alerta de 33 para ~1.900 SKUs. Se quiser B, o caminho é separar B de C
na curva antes.

### 7.4 Pesos, ordenação e os dois indicadores

**Pesos** (registro único em `app/api/alertas.py`, que gera tanto o SQL da ordenação quanto
a legenda da tela — uma fonte só, para os dois não divergirem):

`RUPTURA` 5 · `SEM_GIRO`, `MARGEM_BAIXA`, `MARGEM_BAIXA_VAREJO`, `CUSTO` 4 ·
`BAIXO_GIRO`, `OPORTUNIDADE_DE_GIRO` 3 · `DEVOLUCAO` 2 · `MARGEM_ALTA` 1 ·
`FORA_DE_LINHA` 0 (não pontua). Curva: `A` 3, `B/C` 2, `S/VEND` 1.

**Ordenação: severidade máxima → curva ABC → soma dos pesos.** A ordem dos dois últimos
critérios foi invertida na segunda rodada, e resolveu o problema que a motivou:

| Regra | Onde caíam os classe A em ruptura |
|---|---|
| soma pura (protótipo) | 18, 52, 57, 158, 307, 331 |
| severidade → soma → curva | 89, 111, 112 |
| **severidade → curva → soma** (vigente) | **1 a 7** |

**Dois indicadores, não um.** O protótipo tinha só "valor em risco" = soma do valor de
estoque de quem tem alerta — e **ruptura é, por definição, não ter estoque**: recalculado
hoje, **191 dos 468** SKUs em ruptura têm valor de estoque zero. O pior problema da
operação contribuía com R$ 0 para o indicador que deveria medi-lo. Ficaram dois:

- **CAPITAL PARADO** — valor de estoque de quem tem alerta: **R$ 77,1 milhões** (12/09/2026).
- **VENDA EM RISCO** — para quem está em ruptura, média mensal × preço de atacado:
  **R$ 2,3 milhões**.

**Somar os dois é erro de leitura:** um é estoque, o outro é faturamento.

### 7.5 Compradores, e os dois departamentos que faltavam

Washington assume os departamentos sem comprador definido. Recalculado em 12/09/2026:
**WASHINGTON 5.973 SKUs**, FELIPE 2.868, e **zero** SKUs com "A DEFINIR" (eram 38).

`ROBUST` (36 SKUs) e `ADIBRAX` (2 SKUs) **não tinham linha nenhuma** em `seed_fornecedor` e
caíam no `COBERTURA_ALVO_PADRAO`. Os três parâmetros que faltavam eram decisão do Diretor, e
ele decidiu: `MESES_MEDIA` 3 para os dois, `COBERTURA_ALVO` **2,0** (ROBUST) e **1,5**
(ADIBRAX), `PEDIDO_EM` UNIDADE, comprador WASHINGTON.

⚠ **Recalculado: os dois já têm linha própria no seed** (61 departamentos no total) e
**nenhum departamento do `fat_pedido` cai mais no `COBERTURA_ALVO_PADRAO`** — o fallback
existe e está correto, mas hoje não tem consumidor. A observação do `seed_parametros` que
ainda diz "hoje ADIBRAX, ROBUST e TODOS OS DEPARTAMENTOS" está **desatualizada**.

### 7.6 O que o Diretor decidiu NÃO mudar

- **Custo, margem e MKP mudam com o cenário; o preço praticado hoje, não.** O texto da tela
  dizia o contrário do que o código fazia; venceu o **código**, e o texto foi reescrito.
- **Fora de linha não vira status.** Ver §7.1.

## 8. Divergências de cadastro no Winthor — 63 produtos

Levantadas em 11/09/2026 e **recalculadas em 12/09/2026 sobre os 4.558 SKUs ativos**, com
os mesmos números. Viraram consequência financeira quando o sistema passou a gerar a
planilha de importação da **rotina 201**: ela aceita quatro formas de identificar o produto,
e **o código interno da CEDEP não é nenhuma delas**. A única que existe no nosso cadastro é
o **código de fábrica**.

| Grupo | Produtos | Urgência |
|---|---|---|
| A — código de fábrica **repetido** (6 códigos) | **14** | **Alta** — 4 deles vendem |
| B — produto **sem** código de fábrica | **49** | Baixa — 46 não vendem |
| C — código com espaço/tabulação invisível | 11 (5 inativos nas pontas, **4 ativos** com espaço duplo no meio) | Média |
| D — **Seção** não cadastrada | 39 de 47 departamentos | Baixa — não afeta preço |

**O risco do grupo A:** a importação casa pelo código. Dois produtos com o mesmo código
significam que importar o preço de um **altera o preço de todos**, sem aviso — o arquivo
importa "com sucesso". Os casos: `000019` (flanela R$ 3,10 × rayon R$ 19,30 — 6× de
diferença), `2` (36× de diferença), `PSD160` (dois filtros parecidos, 10% — o mais difícil
de perceber), `120717.0.02` (quatro equipamentos GREE), `0000010` (produto duplicado — aqui
o certo é inativar um), `7898578852335` (um EAN-13 no campo errado, repetido).

**O grupo C.2 pede verificação, não decisão:** o sistema **preserva** o espaço duplo interno
de propósito, porque mexer no meio do código mudaria o identificador. A pergunta para quem
opera a 201 é se ela encontra esses 4 produtos assim.

**O que o sistema faz enquanto o cadastro não é corrigido** — e isto é regra, não paliativo:
esses produtos **entram** no lote de preços da diretoria (a decisão é válida), **não entram**
no arquivo de importação automática (para não alterar preço que ninguém decidiu),
**aparecem no Excel de conferência** com o motivo escrito, e a tela do lote **conta e nomeia**
quantos ficaram de fora. O sistema não trava e não erra — exige trabalho manual para esses
63, que deixa de ser necessário assim que o cadastro for corrigido.

## 9. Dívidas e lacunas fechadas

### 9.1 A fórmula do valor do pedido deixou de existir em dois lugares — 12/09/2026

A fórmula do valor do pedido vivia **duas vezes**: em `int_produto_pedido.sql` (o modelo) e
em `app/servicos/compra.py` (a tela v1), **sem nenhum teste comparando as duas**. Duas
cópias sem teste divergem — é questão de quando, e a divergência apareceria como "o sistema
mostra um valor e o relatório mostra outro", que é o modo de falha mais caro de
diagnosticar.

Com a v1 fora do repositório novo, **sobra uma**: a do dbt. **Dívida fechada em
12/09/2026.** A regra que fica: o valor do pedido é calculado no modelo, e a tela exibe o
que o modelo calculou.

### 9.2 A decisão de pedido da v2 não chegava ao `FAT_PEDIDO` — fechada em 12/09/2026

Até 12/09/2026, `stg_decisao_pedido` lia `APP_DECISAO_PEDIDO`, escrita **só** pela tela v1 —
último evento em 25/08/2026, 18 dias parada. A v2 grava em `APP_PEDIDO` + `APP_PEDIDO_ITEM`,
que **não entravam em model nenhum** da cadeia do `fat_pedido`. Resultado medido em
12/09/2026: **`FAT_PEDIDO` com 4 linhas de `PEDIDO <> 0`, de 8.841** — as quatro da tabela
morta, enquanto os pedidos reais da v2 somavam 66 itens em 4 pedidos.

A coluna `BA` do gabarito de 122 colunas estava sendo alimentada por uma tabela morta.

**`stg_decisao_pedido` passou a ler `APP_PEDIDO_ITEM`**, e três regras vêm junto:

1. **O fator congelado sobrevive.** `APP_PEDIDO_ITEM.FATOR_EXIBICAO` é `NOT NULL` e é
   snapshot do instante da gravação — a mesma garantia que a tabela velha dava. A regra 6 e
   a melhoria A5 continuam valendo **sem alteração**; mudou a referência, não a regra.
2. **⚠ A agregação soma em unidade REAL.** O grão mudou: a tabela velha tinha PK em
   `ID_PRODUTO`; a nova é `PEDIDO × PRODUTO`, e o mesmo SKU pode estar em dois pedidos
   **com fatores diferentes**. Somar `QUANTIDADE` entre itens de fatores diferentes soma
   **caixa com unidade** e produz um número que não é nada. Medido hoje: a soma ingênua dá
   **12.233**; a soma correta, `sum(QUANTIDADE × FATOR_EXIBICAO)`, dá **99.449 unidades** —
   8× de diferença, em 66 itens que convivem com fatores 1, 6 e 12. `BA` passa a ser o
   total reexpresso no fator do item **mais recente**, e o fator serve só para reexibir.
3. **Todos os status contam.** `APP_PEDIDO.STATUS` percorre Rascunho → Orçamento Enviado →
   Fechado → Exportado. `BA` significa *"quanto o comprador decidiu comprar"*, não *"quanto
   foi aprovado"* — e a tabela velha não tinha status nenhum. Contar todos **preserva** o
   significado; restringir seria **regra nova**. Confirmado com o usuário em 12/09/2026.
   Hoje os 4 pedidos estão em Rascunho: filtrar por status devolveria zero e a lacuna
   continuaria aberta com outra cara.

`APP_DECISAO_PEDIDO` **deixa de existir** no schema novo.

## 10. O que segue em aberto

| # | Pendência | De quem depende |
|---|---|---|
| 1 | **Seção / Linha / Categoria** não cadastradas no WinThor (39 de 47 departamentos repetem o nome do departamento na Seção). Os filtros ficam desabilitados até lá, e se habilitam sozinhos quando o dado chegar — a checagem é sobre o dado, não sobre uma lista fixa | **Terceiros (TI/cadastro)** — único bloqueio externo |
| 2 | **Código de fábrica** dos 63 produtos do §8, com prioridade para os 3 que vendem e os 6 códigos repetidos | Diretoria / cadastro |
| 3 | **`FORA_DE_LINHA` para os 4.209 SKUs** que não aparecem em mês nenhum da base mensal: ler o campo direto do cadastro os alcançaria, mas é mudança de escopo maior que a aprovada (§6.0) | Diretor de Compras |
| 4 | **Vários sucessores herdando 100% do mesmo antecessor** (§6.2): normalizar o peso ou bloquear ativação com soma acima de 1. Muda a aritmética da sucessão | Diretor de Compras |
| 5 | **Piso em zero na média de venda negativa** (§6.2). Muda sugestão de compra | Diretor de Compras |
| 6 | **Tributação real de entrada/saída por item**, para substituir o proxy empírico de crédito. Pedido do próprio Diretor no PDF §14 — com ele, o dashboard fica **mais preciso que a planilha**, não uma réplica dela | TI do WinThor |
| 7 | **Histórico de alertas ao longo do tempo** (PDF §13.3): a planilha é uma foto e não responde "quantos SKUs tinham ruptura no mês passado" | Previsto no plano |

## 11. Onde o recálculo divergiu do que estava escrito

Uma linha por número que **mudou** ao ser remedido em 12/09/2026. Vale o da direita.

| Número | Escrito nos `.md` | Recalculado 12/09 | Por quê |
|---|---|---|---|
| SKUs do catálogo | 8.772 / 8.777 | **8.841** | o catálogo do WinThor cresce (§6.0.1) |
| Tempo de rebuild | "~70 s" | **158–577 s, mediana 411 s** | 15 execuções registradas em `APP_ATUALIZACAO`; o número antigo não existe mais |
| Capital parado | R$ 71,4 mi | **R$ 77,1 mi** | estoque e custo se movem |
| Venda em risco | R$ 2,3 mi | **R$ 2,3 mi** | confere |
| Washington | 5.932 SKUs | **5.973** | catálogo |
| `SEM_GIRO` | 315 | **328 linhas / 306 ativos** | depende de `TODAY()` |
| `BAIXO_GIRO` | 123 | **130 / 130** | idem |
| `MARGEM_ALTA` (25%/50%) | 1.336 / 874 ativos | **1.308 / 846** | margem se move com o custo |
| `MARGEM_BAIXA` | 947 ativos | **1.005** | idem |
| `OPORTUNIDADE_DE_GIRO` | 39 | **33** | cobertura se move |
| SKUs só com alerta de cadastro | 1.871 | **2.070** | catálogo + cadastro |
| Ruptura com estoque zero | 201 de 421 | **191 de 468** | estoque ao vivo |
| Células de texto de A4 | 2.182 (AV 136 · CL 1.632 · DB 414) | **2.196 (AV 113 · CL 1.664 · DB 419)** | A4 acompanha a margem |
| `CHECK_FORA_DE_LINHA` | 72 SKUs | **74** | cadastro editável |
| SKUs `FL` fora da base mensal | 4.205 | **4.209** | catálogo |
| ROBUST / ADIBRAX | "caem no `COBERTURA_ALVO_PADRAO`" | **têm linha própria no seed desde 02/09; o fallback não tem consumidor hoje** | a 2ª rodada do Diretor resolveu, e a observação do seed ficou para trás |
| `PEDIDO <> 0` no `fat_pedido` | — | **4 de 8.841 antes da troca de fonte; 66 SKUs / 99.449 unidades depois** | §9.2 |

**Não remedidos nesta rodada**, e por quê: as contagens de divergência do validador contra o
`.xlsx` (1.793 linhas de `ALERTA` atribuíveis, `AP` 71/8.772, `AQ` 0/8.772, A/B de A5
0/8.777) são de **21 e 24/08/2026** e exigem rodar `validar/validar_pedido.py` contra a v11.
Pelo §6.0.1, o que precisa continuar valendo nelas é a **atribuibilidade**, não a contagem —
e é ela que a próxima execução do validador tem de reproduzir.
