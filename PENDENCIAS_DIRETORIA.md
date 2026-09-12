# Pendências para o Diretor de Compras

Divergências entre a documentação técnica (PDF) e a planilha v10, encontradas ao portar o
modelo para SQL.

**Retorno do Diretor em 21/08/2026: itens 1 a 4 decididos. Item 5 decidido em 24/08/2026.**

**Status de implementação:** itens 1, 3 e 4 **APLICADOS NO CÓDIGO** em 21/08/2026 e item 5
em **24/08/2026** (MELHORIAS.md A5 — efeito hoje 0 SKUs, exercitado de ponta a ponta com
decisões de teste gravadas e apagadas); item 2 não exigia mudança. As colunas afetadas divergem do xlsx em `referencia/` **de propósito** —
o registro canônico dessa divergência é **`CONTEXTO.md` §6.4**, e o validador as rotula
como `DIVERGENCIA ESPERADA POR DECISAO` sem deixar de compará-las.

---

## 1. ✅ RESOLVIDO — APLICADO 21/08/2026 — Cenário "ST s/Valor" usa alíquota SEM redução

**Decisão:** era **erro na planilha**. O regime de substituição tributária é mecânica
separada do benefício de redução de base — o cenário "ST s/Valor" nunca deveria usar a
alíquota reduzida, nem no atacado nem no varejo.

O Diretor já corrigiu a fórmula na planilha (4 colunas) e atualizou a **seção 9.1** do PDF.

**Aplicado — `ICMS_SAIDA_EF` trocado por `ICMS_SEM_RED` em 4 colunas**
(`int_produto_margem` para CH/CY, `int_produto_preco_sugerido` para CO/DE):

| Coluna | Nome |
|---|---|
| `CH` | `MARGEM_ST_s/VALOR` (atacado) |
| `CO` | `PV_SUG_ST_s/VALOR_AV` (atacado) → e `CP`, que deriva dela |
| `CY` | `MARGEM_ST_s/VALOR_VAREJO` |
| `DE` | `PV_SUG_ST_s/VALOR_VAR_AV` → e `DF`, que deriva dela |

**Efeito medido pelo Diretor:**
- Itens de fato em regime ST: **nenhum número muda** — as duas alíquotas já eram idênticas
  em 100% dos casos, porque a maioria dos itens ST não tem redução disponível.
- ~**1.240 SKUs** fora do regime ST (modalidade normal): a margem muda de verdade.
- ~**2.095 SKUs** no preço sugerido (atacado + varejo).
- **Nenhuma decisão de preço já tomada foi baseada no número antigo.**

Resultado esperado: fora do regime ST, "ST s/Valor" passa a ser **matematicamente idêntica**
a "Sem Redução" — que é o correto, já que ali não existe distinção real entre os cenários.

⚠️ **Consequência para o aceite:** o arquivo em `referencia/` é a versão ANTIGA. Nestas 4
colunas (mais as 2 derivadas), o nosso modelo passa a divergir dele **de propósito**.

---

## 2. ✅ RESOLVIDO — `dCredito` fora do cálculo é INTENCIONAL

**Decisão:** não é bug. Documentado pelo Diretor na nova **seção 8.5** do PDF.

O Winthor não expõe a tributação de entrada e saída por item de forma acessível. Para
contornar, o modelo usa a diferença entre custo e valor do produto como **proxy** para
inferir o tratamento tributário — e é esse valor empírico que alimenta o cálculo real de
crédito de ICMS-ST.

A `dCredito`, calibrada por fornecedor e tributação, é **referência**: serve só ao alerta
de possível produto importado, quando o crédito calculado foge do esperado.

**Nada a mudar no código.** O comportamento atual já está correto.

### 📌 Pedido do Diretor à TI (seção 14 do PDF)

> Se a TI conseguir disponibilizar a **tributação de entrada e saída por item** direto do
> Winthor, o proxy deixa de ser necessário e o crédito passa a usar o dado real — o
> dashboard ficaria **mais preciso que a planilha atual**, não só uma réplica dela.

Fora do escopo das etapas atuais. Vale avaliar depois que o sistema estiver no ar.

---

## 3. ✅ RESOLVIDO — APLICADO 21/08/2026 — Grafia `CAR80` → `CAR 80`

**Decisão:** corrigir a grafia para bater com o departamento da base (`CAR 80`, com espaço).

**Aplicado:** `seeds/seed_credito.csv` agora traz `CAR 80` nas duas linhas (COD_ICMS 24 e
26). A busca passa a casar, e **41 SKUs** deixam de cair no crédito empírico. A instrução
antiga do `CONTEXTO.md` §6.2 ("não normalize") foi marcada como **revogada**, com data e
motivo.

⚠️ Passa a divergir da planilha antiga nesse ponto, de propósito.

**⚠️ Efeito MEDIDO no banco (21/08/2026) — menor do que esta nota previa.** Muda **`BO`
(CRED_TOTAL) em 39 dos 41** SKUs (nos outros 2 o crédito empírico já dava exatamente o
valor tabelado, 0,0925). **Não muda ICMS-ST, custo, margem, preço nem `ALERTA` em nenhum
dos 41.** A razão é o item 2 acima, confirmado como intencional: `BQ` (`CRED_ICMS`) lê
`DR`, o crédito **empírico**, e não `BO`. `BO` não entra na cadeia de custo — seu único
consumidor é `BS` (`CHECK_IMPORTADO`), e nos 41 o limiar não virou de lado.
A correção continua valendo (a grafia certa é a grafia certa, e ela passa a valer preço
quando a TI expuser a tributação por item — §14 do PDF). Fica registrado para que a
diretoria não espere movimento de preço que não vai acontecer.

---

## 4. ✅ RESOLVIDO — APLICADO 21/08/2026 — `CHECK_TRIB` pega o código `0`

**Decisão:** incluir o `0` na verificação.

**Aplicado:** em `int_produto_alerta`, `CHECK_TRIB` passa a disparar quando o código de
tributação é vazio **ou zero**. O teste `compras_check_trib_formula_morta` foi substituído
por `compras_check_trib_pega_codigo_zero` (severity **error**, bicondicional: alerta dispara
para vazio/zero e só para eles) mais `compras_check_trib_sem_modalidade_alertado`
(severity warn, o buraco residual). Deixa de ser fórmula morta e passa a cobrir os **5 SKUs** que hoje saem sem
modalidade, sem alíquota e com margem em branco, sem alerta nenhum.

⚠️ Diverge da planilha antiga de propósito: lá esses 5 SKUs não têm alerta.

---

## 5. ✅ RESOLVIDO — `FATOR_EXIBICAO` de decisão tomada deve CONGELAR

**Decisão do Diretor (24/08/2026): congelar, não recalcular.** O fator gravado em
`APP_DECISAO_PEDIDO` é a **fonte de verdade** para unidades, valor e cobertura de uma
decisão já tomada.

**O raciocínio dele, que vale registrar:**

> O que importa para o negócio (`VALOR_PEDIDO`, `MESES_EST+PED`) é sempre a conta **em
> unidades** — caixa é só a forma de digitar quando o fornecedor está configurado em
> MASTER. Se o `EMBAL_COMPRA` de um SKU mudar entre a decisão e o build — e isso acontece
> na **atualização diária de cadastro**, não só numa reconfiguração manual de fornecedor —
> recalcular faria a quantidade de unidades, e o valor gasto, mudarem sozinhos, sem
> ninguém ter redigitado nada.
>
> Uma decisão já tomada não deveria mudar de tamanho por conta de um cadastro que
> atualizou depois. Se a embalagem mudou de verdade, o certo é **gerar uma nova decisão**
> vendo o número atualizado, não reinterpretar a antiga.

**A implementar:** `PEDIDO_UNIDADES` e tudo que descende dele (`VALOR_PEDIDO`,
`PEDIDO_NA_MEDIDA`, `SUG_PALETE`, `MESES_EST+PED`) usam o **fator congelado**. A
quantidade em caixas pode ser mantida como referência visual de contexto, mas **não
recalcula** a quantidade real.

**Impacto hoje: 0 SKUs** — `APP_DECISAO_PEDIDO` está vazia. Passa a valer na primeira
decisão gravada.

**APLICADO em 24/08/2026** em `models/intermediate/int_produto_pedido.sql` (coluna
`fator_exibicao_pedido`), com fallback para o fator corrente quando não há decisão, teste
singular `compras_pedido_unidades_usa_fator_congelado` e prova de ponta a ponta registrada
em `MELHORIAS.md` A5: SKU 3821 (fator corrente 12, decisão com fator 6, `PEDIDO=120`) saiu
com `BB=720` / `BD=11.138,92` / `BF=4,1165`, contra `1.440` / `22.277,84` / `5,7146` da
fórmula da planilha; SKU 11 (fator 1) não mudou. Linhas de teste apagadas e tabela de volta
a 0.

⚠️ **Diverge da planilha de propósito** — lá `BB = $BA2 * $K2` usa o fator corrente.
Registrado em `MELHORIAS.md` como **A5**.

---

## Nenhuma pendência em aberto

As 5 pendências foram decididas. Novas divergências encontradas nas próximas etapas devem
ser acrescentadas aqui, não resolvidas por conta própria.
