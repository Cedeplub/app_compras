# Melhorias sobre a planilha

**Decisão do usuário (21/08/2026):** a planilha v11 é o **ponto de partida**, não um alvo
de réplica exata. Melhorias são bem-vindas; o Diretor de Compras valida tudo na v1 do
sistema.

## A regra que sustenta o aceite

Permitir melhoria **não** significa abandonar a verificação — significa registrar.

> **Toda divergência da planilha é defeito, exceto as registradas aqui.**

Sem registro, uma melhoria intencional e um bug ficam indistinguíveis, e a comparação de
122 colunas × 8.777 linhas deixa de valer como prova. Cada item abaixo tem: o que a
planilha faz, o que passamos a fazer, quantos SKUs mudam e por que vale a pena.

Status: `APLICADA` · `APROVADA` (decidida, a implementar) · `PROPOSTA` (aguardando
decisão) · `RECUSADA`

## Decisão de 21/08/2026

**Aprovadas: A1, A2 (Diretor) + A3, A4, D1 (usuário).** O critério que separou: nenhuma
das três novas muda decisão de compra nem preço — corrigem alerta que falha em silêncio,
devolvem casa decimal perdida, e fecham assimetria de impacto zero hoje.

**Decisão de 24/08/2026:** **A5 aprovada e `APLICADA`** (item 5 das pendências — a
última que estava em aberto). Efeito hoje: **0 SKUs**, porque `APP_DECISAO_PEDIDO` está
vazia; exercitada de ponta a ponta com decisões de teste gravadas e apagadas, e protegida
pelo teste singular `compras_pedido_unidades_usa_fator_congelado`.

**Status em 21/08/2026: A1, A2, A3, A4 e D1 estão `APLICADA`.** Efeito total das três
últimas, medido no build de produção: **71 SKUs** passam a disparar `CHECK_FORA_DE_LINHA`
(A3), **2.182 células de texto** ganham a casa decimal (A4) e **0 células** mudam por D1 —
que é o resultado esperado, não uma falha. `ALERTA` (D) diverge da planilha em **1.793
linhas**, e as **1.793 são atribuíveis** componente a componente, sem nenhuma sobra sem
explicação. As colunas afetadas estão registradas em `CONTEXTO.md` §6.0 e rotuladas em
`validar/validar_pedido.py` (`LETRAS_DIVERGENCIA_POR_DECISAO`) — **sem que nenhuma
verificação tenha sido desligada**.

**Mantidas como proposta: B1 e B2.** As duas mudam a **sugestão de quantidade a comprar**.
São decisão do Diretor de Compras vendo o sistema funcionando, não de implementação.

**C1 e C2** seguem no roadmap: C1 é etapa prevista do plano, C2 depende de a TI expor a
tributação por item.

---

## A. Defeitos da planilha — correção de baixo risco

### A1. `CHECK_TRIB` não pega o código de tributação `0` — `APLICADA`
**Planilha:** testa só se o código é vazio; nunca dispara, porque há valor padrão.
**Nós:** dispara também quando o código é `0`.
**Impacto:** 5 SKUs que hoje saem sem modalidade, sem alíquota e com margem em branco,
sem alerta nenhum. *(Decidido pelo Diretor, item 4.)*

### A2. Grafia `CAR80` × `CAR 80` — `APLICADA`
**Planilha:** a busca de crédito falha e cai no proxy empírico.
**Nós:** grafia corrigida, a busca casa.
**Impacto:** 41 SKUs. *(Decidido pelo Diretor, item 3.)*

### A3. `FORA_DE_LINHA` lido só do mês corrente — `APLICADA` (21/08/2026)
**Planilha:** o campo vem apenas da linha do mês corrente. Produto fora de linha **sem
movimento no mês** não tem linha, então sai marcado como "em linha".
**Consequência:** **71 SKUs** estão fora de linha e **não disparam** `CHECK_FORA_DE_LINHA` —
exatamente os produtos parados, que são os que mais interessam ao alerta.
**Nós:** derivar do registro mais recente em que o SKU aparece.
**Risco:** baixo. Aumenta a cobertura de um alerta que hoje falha silenciosamente.

**Onde:** `models/intermediate/int_venda_mensal_pivot.sql`, CTE `fora_de_linha_recente`
(`row_number() over (partition by codigo_produto order by mes desc)`). A fórmula de AP em
`int_produto_alerta` **não mudou uma letra** — mudou o insumo.

**EFEITO MEDIDO (21/08/2026, método A/B do CONTEXTO.md §6.3: fórmula nova × fórmula antiga
recalculada na MESMA linha, no MESMO build):**
- **71 SKUs** mudam de `'N'` para `'S'`; **0** no sentido contrário.
- `CHECK_FORA_DE_LINHA` (AP) vai de **1 para 72 SKUs alertados** — os 71 são exatamente os
  que passam a disparar.
- `fat_alerta` ganha 71 linhas de `tipo_alerta = 'FORA_DE_LINHA'` (de 1 para 72).
- `ALERTA` (D) muda em 71 SKUs por esta melhoria; 34 deles também mudam por A4.
- Validador: `[AP] CHECK_FORA_DE_LINHA: 71/8772 divergem`, rotulada como divergência por
  decisão — e nenhuma divergência além dessas 71.

⚠ **Limite medido e NÃO corrigido:** SKU que não aparece em mês NENHUM de
`int_venda_mensal` continua saindo `'N'`. São **4.205 SKUs** do `fat_pedido` marcados
`OBS2='FL'` no cadastro que nunca entram naquele model — a CTE `produtos_incluir` de lá só
admite quem está **em linha**, e sem movimento não há linha por movimento. Ler o campo
direto do cadastro alcançaria os 4.205, mas é mudança de escopo muito maior que a
aprovada. **Fica como pergunta ao Diretor de Compras**, não implementada por conta
própria.

### A4. Texto de margem perde a casa decimal — `APLICADA` (21/08/2026)
**Planilha:** `TEXT(x,"0.0%")` num arquivo pt-BR imprime percentual **inteiro** — margem de
10,5% aparece como `"10%"`, e 5,49% como `"05%"`.
**Consequência:** o alerta de margem crítica esconde a diferença entre 5,0% e 5,9%.
**Nós:** exibir uma casa decimal.
**Risco:** baixo, mas muda o texto de ~2.157 células. É melhoria de leitura, não de cálculo.

**Onde:** `macros/compras_texto_percentual.sql` — um lugar só, para os três alertas (AV,
CL, DB). Máscara `FM999999990D0` com `NLS_NUMERIC_CHARACTERS` **explícito na chamada**:
sem isso o separador decimal seguiria o NLS da sessão e o mesmo build sairia `"10.5%"` ou
`"10,5%"` conforme quem conectou.

**Separador: VÍRGULA**, conferido antes de decidir. O arquivo é pt-BR (é justamente por
isso que o Excel leu a máscara errado) e o público é brasileiro; nenhum outro texto da aba
imprime número decimal — AL e AO só carregam inteiros ("RUPTURA RECORRENTE - 7 DIAS"), e
CE carrega data. Não havia convenção concorrente a respeitar.

⚠ **São DUAS mudanças de texto, e as duas são propositais:**
1. ganha a casa decimal (o objetivo);
2. **perde o zero à esquerda** (`"05%"` → `"5,5%"`). O padding de dois dígitos era o
   *mesmo* artefato da máscara mal lida — os dois `0` de `"0.0"` viravam dois dígitos
   INTEIROS. Nenhuma leitura de `"0.0"` produz `"05,5%"`. Manter o padding seria preservar
   metade do defeito.

**EFEITO MEDIDO (21/08/2026, A/B na mesma linha e no mesmo build: texto novo × texto
antigo recalculado a partir do MESMO número):**
- **2.182 células de texto** mudam, e são **100%** das células não vazias das três
  colunas: `AV` **136**, `CL` **1.632**, `DB` **414**.
- `ALERTA` (D) muda em **1.749 SKUs** por esta melhoria.
- **Nenhum número de cálculo muda.** `AU`, `CJ` e `CZ` — as razões que alimentam os três
  textos — seguem idênticas à planilha no validador. É melhoria de leitura.
- Exemplos reais do build: `"MARGEM CRITICA - pior cenario 08%"` → `"... 8,1%"`;
  `"DEVOLUCAO ACIMA DO PADRAO - 17%"` → `"... 16,7%"`;
  `"... pior cenario varejo -15%"` → `"... varejo -15,1%"`.
- 2.182 e não os ~2.157 estimados porque `CL`/`DB` dependem da margem, que se move com o
  custo da última entrada entre um build e outro (CONTEXTO.md §6.1.0).

### A5. `FATOR_EXIBICAO` de decisão tomada deve congelar — `APLICADA` (24/08/2026)
**Planilha:** `BB = $BA2 * $K2` — `PEDIDO_UNIDADES = PEDIDO × FATOR_EXIBICAO` usa o fator
**corrente**.
**Problema:** o `EMBAL_COMPRA` muda na atualização **diária** de cadastro. Recalcular faz
a quantidade em unidades — e o valor gasto — mudarem sozinhas numa decisão que ninguém
redigitou.
**Nós:** usar o fator **congelado** em `APP_DECISAO_PEDIDO` como fonte de verdade para
unidades, valor e cobertura. Propaga para `BB`, `BC`, `BD`, `BE` e `BF`. **Não** propaga
para `BG` (`VALOR_ESTOQUE`), que é estoque e não pedido — ali o fator corrente continua
certo, porque `EST+PEND` é lido do cadastro de hoje.
**Fallback:** sem decisão gravada não existe fator congelado, e vale o corrente (`K`).
*(Decidido pelo Diretor — item 5 das pendências.)*

**Onde:** `models/intermediate/int_produto_pedido.sql`, CTE `quantidade` — o fator do
pedido virou coluna própria, `fator_exibicao_pedido`:

```sql
case when dp.id_produto is not null then dp.fator_exibicao else b.fator_exibicao end
```

O teste é `dp.id_produto is not null`, e **não** um `nvl` sobre o fator: se um dia a
coluna admitir nulo, um `nvl` cairia calado no corrente e desfaria a decisão do Diretor
sem ninguém perceber.

**Referência visual em caixas: não foi criada coluna nova**, porque ela já existe — `BA`
(`pedido`) **é** a quantidade como a pessoa digitou, na unidade de exibição do instante da
decisão. Uma segunda coluna "em caixas" seria a mesma informação com outro nome, e nome
duplicado é onde o recálculo volta por descuido. O que foi exposto é o **fator**
(`fator_exibicao_pedido`), para que a divergência contra `K` seja auditável sem abrir a
`APP_*`.

**EFEITO MEDIDO no build de produção de 24/08/2026: ZERO células**, nas cinco colunas.
`APP_DECISAO_PEDIDO` está vazia, então nenhum SKU tem fator congelado e todos caem no
fallback:

| medida sobre os 8.777 SKUs | valor |
|---|---|
| SKUs com `fator_exibicao_pedido <> fator_exibicao` (K) | **0** |
| SKUs com `pedido_unidades <> pedido × K` (a fórmula da planilha) | **0** |
| SKUs com `pedido <> 0` | **0** |

E o A/B global das cinco colunas — fórmula nova (A5) × fórmula antiga (`$BA2*$K2`)
recalculada na mesma linha, no mesmo build — deu **0 de 8.777** em `BB`, `BC`, `BD`, `BE`
e `BF`. O `fat_pedido` de hoje é **idêntico** ao que a implementação anterior produziria:
nenhuma divergência do validador é atribuível a A5.

⚠ `BF` (`MESES_EST+PED`) **aparece divergente no validador (524/3278) e não é por A5.**
Com `BB = 0` em 100% das linhas, `BF` fica numericamente idêntica a `AW` (`MESES_EST`) —
medido: **0 de 8.777** linhas com `BF <> AW` — e herda a divergência **volátil** de `AW`,
que vem de `EST+PEND` (estoque ao vivo, 599 SKUs divergentes). É a mesma causa contada
duas vezes. O rótulo em `validar/validar_pedido.py` diz isso com todas as letras.

**PROVA de ponta a ponta — feita em 24/08/2026 e revertida.** Como o impacto é zero, um
build normal não prova nada: a implementação certa e a errada produzem o mesmo resultado
hoje. Foram gravadas duas decisões de teste em `APP_DECISAO_PEDIDO`
(`ATUALIZADO_POR = 'TESTE_A5'`), seguidas de `dbt run --select int_produto_pedido
fat_pedido fat_alerta` e A/B na mesma linha, no mesmo build (método do `CONTEXTO.md` §6.3):

**SKU 3821** (INGRAX, `PEDIDO_EM = 'MASTER'`, `EMBAL_COMPRA = 12`) — fator corrente **12**,
decisão gravada com fator **6**, `PEDIDO = 120`:

| Coluna | CONGELADO (nosso) | CORRENTE (a planilha) |
|---|---|---|
| `BB` `PEDIDO_UNIDADES` | **720** | 1.440 |
| `BC` `PEDIDO_NA_MEDIDA` | **720** | 1.440 |
| `BD` `VALOR_PEDIDO` | **11.138,917546** | 22.277,835091 |
| `BE` `SUG_PALETE` | **`COMPLETAR PALETE: +12 CAIXAS`** | *(vazio)* |
| `BF` `MESES_EST+PED` | **4,116526** | 5,714603 |
| `BG` `VALOR_ESTOQUE` | 210.649,307362 | 210.649,307362 *(igual — é estoque)* |

Recalcular teria **dobrado** as unidades e o dinheiro do pedido sem ninguém ter redigitado
nada — é exatamente o que o Diretor descreveu.

**SKU 11** (PETROBRAS, `PEDIDO_EM` ≠ MASTER) — fator corrente **1**, decisão gravada com
fator **1**, `PEDIDO = 30`: `BB` = 30, `BC` = 30, `BD` = 445,863672, `BE` vazia,
`BF` = 12,857143 — **idênticos** aos da fórmula corrente, nas cinco colunas. Congelar não
mexe em quem não tem o que congelar.

**O teste singular morde.** Com as duas decisões gravadas,
`compras_pedido_unidades_usa_fator_congelado` **passa**; o mesmo predicado rodado contra a
implementação ERRADA (fator corrente), simulada na mesma linha, retorna **1 linha** — o
SKU 3821, com `1440` onde o esperado é `720`. Não é teste decorativo.

**Revertido e conferido:** `delete ... where atualizado_por = 'TESTE_A5'` apagou **2**
linhas, `select count(*) from compras.app_decisao_pedido` voltou a **0**, e depois de
`dbt run --select int_produto_pedido int_produto_alerta fat_pedido fat_alerta` os dois SKUs
voltaram **exatamente** ao estado anterior — inclusive `MESES_EST+PED` do 3821 em
`2.518450013872191`, dígito por dígito.

---

## B. Riscos que a planilha não protege

### B1. Vários sucessores herdando 100% do mesmo antecessor — `PROPOSTA`
**Planilha:** cada busca é independente e soma sem verificar. O produto **7095 é antecessor
de 4 SKUs**, cada um com peso 1 — se todos forem ativados, a demanda dele é contada
**400%**. A planilha tinha uma coluna que *mostrava* a soma ao humano; ela se perdeu.
**Nós:** hoje há teste de aviso. **Proposta:** normalizar o peso, ou bloquear ativação com
soma acima de 1.
**Risco:** médio — muda a aritmética da sucessão. Precisa do Diretor.

### B2. Quantidade líquida negativa contamina a média — `PROPOSTA`
**Planilha:** devolução de unidades vendidas antes da janela produz líquido negativo
(medido: produto 7095 faturou 4 e recebeu 24 de volta). A média de venda fica negativa.
**Nós:** hoje reproduzimos. **Proposta:** piso em zero na média, com alerta próprio.
**Risco:** médio — muda sugestão de compra. Precisa do Diretor.

---

## C. O que a planilha não consegue fazer

### C1. Histórico de alertas ao longo do tempo — `PROPOSTA`
A planilha é uma foto: não responde "quantos SKUs tinham alerta de ruptura no mês passado".
O PDF §13.3 pede esse gráfico. Já previsto no plano como `fat_pedido_historico`.

### C2. Tributação real em vez do proxy — `PROPOSTA` (depende da TI)
Pedido do próprio Diretor (PDF §14): se a TI expuser a tributação de entrada e saída por
item, o proxy empírico deixa de ser necessário e **o dashboard fica mais preciso que a
planilha**. Fora do escopo das etapas atuais.

---

## D. Assimetrias que parecem descuido

### D1. `VD_ANT_3M` herda só com o primeiro peso — `APLICADA` (21/08/2026)
**Planilha:** `MEDIA_JANELA` e `VD M-1/M-2/M-3` herdam com `PESO_1` **e** `PESO_2`;
`VD_ANT_3M` herda **só com `PESO_1`**.
**Nós:** `vd_ant_3m` passa a herdar com os **dois** pesos, como as colunas irmãs.
**Impacto hoje:** zero — nenhuma linha de sucessão tem segundo antecessor.
**Risco:** baixo hoje, mas contamina tendência e variação de preço quando alguém usar.

**Onde:** `models/intermediate/int_venda_mensal_sucessao.sql`, CTE `vd_ant` — ganhou
`+ nvl(a2.peso_2,0) * (nvl(a2.q03,0)+nvl(a2.q04,0)+nvl(a2.q05,0))`, simétrico ao termo de
`peso_1` que já existia.

**EFEITO MEDIDO no build de produção: ZERO células.** Nenhuma das 25 linhas de
`seed_sucessao` tem `ANTIGO_2` e todas estão `ATIVO='NAO'`; o segundo termo vale 0 em 100%
das linhas. Validador: `[AQ] VD_ANT_3M: 0/8772 divergem`. `AR` (TEND %) e `AT` (VAR_PV),
que derivam de `AQ`, também não mudam — por isso não foram rotuladas no validador.

**PROVA de que a herança funciona — feita em 21/08/2026 e revertida.** Como o impacto é
zero, um build normal não prova nada. Foi ativada temporariamente uma linha com **dois**
antecessores, `8581;9;1;2096;0.5;SIM` (o segundo antecessor foi inventado para o teste,
já que nenhuma linha do seed tem um), seguida de `dbt seed` + `dbt run --select
int_venda_mensal_sucessao` e A/B na mesma linha, no mesmo build:

| | valor |
|---|---|
| Q03+Q04+Q05 do antecessor 1 (produto 9) × `PESO_1` = 1 | 2.233 |
| Q03+Q04+Q05 do antecessor 2 (produto 2096) × `PESO_2` = 0,5 | 14,5 |
| `vd_ant_3m` **fórmula NOVA** (dois pesos) | **749,1667** |
| `vd_ant_3m` **fórmula ANTIGA** (só `PESO_1`), recalculada na mesma linha | 744,3333 |
| diferença | **4,8333** — exatamente o termo de `PESO_2` (0,5 × 29 ÷ 3) |

**Revertido e conferido dos dois lados:** `seeds/seed_sucessao.csv` restaurado **byte a
byte** (`diff` vazio contra a cópia do original; sha256
`657b9a356aa50b4da2b09d0bce2697774110fefdcf51080aa50fff08dc4ca9f0`) e `dbt seed`
reaplicado — `compras.seed_sucessao` voltou a ter 25 linhas, **0** com `ATIVO='SIM'`,
**0** com `ANTIGO_2` e **0** com `PESO_2`.
