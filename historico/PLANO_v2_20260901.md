# PLANO v2 — do protótipo ao MVP ligado no banco

Documento de planejamento do ciclo v2, aberto em 01/09/2026. A referência de escopo é
`v2/prototipo/PROTOTIPO.md`, escrito pelo Diretor de Compras a partir do protótipo
`.jsx` que ele mesmo construiu. Este arquivo não repete o que está lá — ele decide
**em que ordem** aquilo vira sistema real, e registra o que falta no banco para isso.

---

## 1. As duas decisões que abrem o ciclo

**Stack: React + Vite, com o FastAPI virando API JSON.**
O protótipo tem 3.660 linhas de React já escritas, com as fórmulas de margem/MKP/cenário
conferidas contra a `MODELO_COMPRAS_CEDEP_V10.xlsx` e o layout já resolvido. Reescrever
isso em Jinja2 seria reinterpretar o desenho e reimplementar cada fórmula — trabalho
grande cujo melhor resultado possível é empatar com o que já existe. Some-se que as telas
do v2 recalculam margem **a cada tecla digitada**: em HTMX isso é uma ida ao servidor por
caractere.

O FastAPI continua dono de tudo que grava: sessão, permissão, auditoria, e as regras que
tocam o banco. Ele passa a devolver JSON em `/api/*` em vez de HTML.

**Ordem: tudo será feito.** A sequência abaixo é por dependência técnica, não por
preferência — cada etapa só depende do que já foi entregue antes dela.

---

## 2. O que o banco já tem, e o que falta

Levantamento feito coluna a coluna do `PROTOTIPO.md` §3/§4 contra `COMPRAS_PEDIDO`
(122 colunas), `COMPRAS_ALERTA`, `COMPRAS_VENDA_MENSAL` e `COMPRAS_IND_FORNECEDOR`.

### 2.1 Já existe, pronto para usar

A maior parte do protótipo já tem lastro. Os campos fiscais e de margem — a parte cara —
estão todos lá:

| Campo do protótipo | Coluna em `COMPRAS_PEDIDO` |
|---|---|
| `custoStValor` / `custoGerencial` / `custoUltimaEntrada` | `CUSTO_TOT_S_VALOR` / `CUSTO_TOT_GERENCIAL` / `CUSTO_ULT_ENT` |
| as 5 variantes de margem | `MARGEM_ST_S_VALOR`, `MARGEM_OFICIAL`, `MARGEM_SEM_RED`, `MARGEM_ST_S_VALOR_VAREJO`, `MARGEM_SEM_RED_VAREJO` |
| `modalidade`, `icmsEfSaida`, `icmsEfSemReducao` | `MODALIDADE`, `ICMS_SAIDA_EF`, `ICMS_SEM_RED` |
| `creditoICMS`, `creditoPisCofins` | `CRED_ICMS`, `CRED_PISCOF` |
| `pvAtacado`, `pvVarejo`, `mkpAtacado`, `mkpVarejo` | `PV_ATACADO`, `PV_VAREJO`, `MKP_ATACADO`, `MKP_VAREJO` |
| `margemAlvo`, `margemAlvoVarejo` | `MARGEM_ALVO`, `MARGEM_ALVO_VAREJO` |
| sugestões de preço por cenário | `PV_SUG_*_AV` / `PV_SUG_*_AP` (6 colunas) |
| `vendaHistorico` (4 meses) | `VD_MES_ATUAL`, `VD_M_1`, `VD_M_2`, `VD_M_3` |
| `estDisp`, `estPend`, `mediaJanela` | `EST_DISP`, `EST_PEND`, `MEDIA_JANELA` |
| `mesesCobertura`, `diasSemVenda`, `classe` | `MESES_EST`, `DIAS_SEM_VENDA`, `CLASSE` |
| `clientesAtacado`, `clientesVarejo` | `QT_CLI_ATACADO`, `QT_CLI_VAREJO` |
| `litragemUnidade`, `pesoUnidade` | `L_POR_UNIDADE`, `PESO_UNITARIO_KG` |
| `embalagem`, `embalCompra`, `codFab`, `status` | `EMBALAGEM`, `EMBAL_COMPRA`, `COD_FAB`, `STATUS` |
| `sucessaoPara` | `ANT_1`/`PESO_1`, `ANT_2`/`PESO_2`, `CHECK_SUCESSAO` |
| `alertas[]` | `COMPRAS_ALERTA` (já despivotado, 1 linha por tipo) |
| `valorEstoque` | `VALOR_ESTOQUE` |

**Consequência prática:** a tela de Precificação e a de Decisão do SKU — as duas mais
densas em regra fiscal — não precisam de nenhum model dbt novo.

### 2.2 Existe no dbt, mas não chega em `COMPRAS_PEDIDO`

Correção pequena, só projetar na camada de contrato:

| Campo | Onde já está |
|---|---|
| `coberturaAlvo` (por produto) | `int_produto_demanda.cobertura_alvo` — resolve fornecedor × padrão |
| `qtdUltimaSaida` | `int_cadastro_estoque.qt_ult_saida` |
| `regimeFiscal` (texto descritivo) | `dim_tributacao.descricao` |

### 2.3 Não existe em lugar nenhum — precisa de decisão

| Campo | Situação | Encaminhamento |
|---|---|---|
| `secao`, `linha`, `categoria` | O `PROTOTIPO.md` §8 diz: existe no Winthor, **em fase de cadastro**. Hoje é ilustrativo. | Único bloqueio externo do ciclo. Empurra Monitoramento/Entradas para o fim. |
| `prazoEntregaDias` | Não existe | Vira `seed_fornecedor.PRAZO_ENTREGA_DIAS`, no mesmo molde de `MESES_MEDIA`/`COBERTURA_ALVO`. |
| `pedidoMinimo` | Não existe | Idem — atributo de fornecedor, vai para o mesmo seed. |
| `sazonalidade`, `campanhaAtiva` | Não existe. São textos livres de aviso. | Tabela `APP_AVISO_PRODUTO`, editável pelo comprador. Não é dado de ERP. |
| `vendaAnoPassado` | Derivável | Coluna nova em `COMPRAS_PEDIDO`, a partir de `COMPRAS_VENDA_MENSAL` (mesmo mês, ano −1). |
| lista de entradas | `stg_nota_entrada` existe, sem model acima | Cadeia nova `int_entrada_*` → `COMPRAS_ENTRADA`. |
| agregação por período/métrica | `COMPRAS_VENDA_MENSAL` tem grão mensal | Falta peso/litros agregados e o comparativo ano a ano de verdade. |

### 2.4 A entidade que falta: **pedido**

Hoje `APP_DECISAO_PEDIDO` tem PK em `ID_PRODUTO`. Gravar o mesmo produto de novo
**sobrescreve** — não existe "um pedido", não existe fornecedor dono, não existe status,
não existe histórico. O protótipo assume os quatro. É a maior mudança de banco do ciclo,
e está na Etapa 9.

---

## 2.5 Regra de fidelidade ao protótipo

**O ponto de partida de cada tela é o JSX do Diretor, não uma tela minha.** Troca-se o
array de mock pela chamada de API e ajusta-se só onde o dado real ou um defeito real
obriga. A fidelidade é consequência do método, não uma fase no fim.

O motivo é concreto: o `PROTOTIPO_CEDEP.pdf` é o `.md` impresso — 27 páginas, zero
imagens. **O mockup não é um desenho, é código React que roda.** Portar sai mais barato
que reinterpretar e depois refazer; e toda tela construída "provisoriamente" é uma tela
construída duas vezes.

Reaproveitável tal e qual: `fmtR$`, `calcMKP`, `classeChip`, `badgeComNumero`,
`badgeStatus`, `CenarioCard`, `FaixaAviso`, `Segmented`, `SeletorPeriodo`,
`SeletorOrdenacao`, e o logo embutido no `.jsx`.

**Fidelidade não é copiar os defeitos.** Diverge-se, sempre com o motivo escrito no ponto:
fórmulas vêm do banco e não de constantes no JavaScript; responsividade de CSS em vez do
botão mobile/desktop; URL, carregando, erro e permissão, que lá não existem; e o que
quebra na escala real — a tela dele tem 8 produtos, a nossa tem 8.772.

---

## 3. A ordem, e o porquê dela

### Etapa 7 — Fundação: API JSON + esqueleto React
Nada roda sem isso, então vem primeiro.

- `/api/*` no FastAPI devolvendo JSON, com a sessão, o perfil e a auditoria que já
  existem — não se reescreve autenticação que já funciona.
- Vite + React, com os tokens de design de `PROTOTIPO.md` §6 (as 11 cores, a escala de
  espaçamento, os tamanhos de fonte) extraídos para um lugar só.
- Os componentes compartilhados do protótipo: `Segmented`, `classeChip`, `badgeStatus`,
  `badgeComNumero`, `SeletorPeriodo`, `SeletorOrdenacao`, inputs e selects.
- **Correção estrutural:** o protótipo troca mobile/desktop por um booleano manual
  (`modoDesktop`) e mantém dois blocos de JSX por tela — o próprio `PROTOTIPO.md` §6
  registra que "toda mudança de campo/coluna precisa ser feita duas vezes" e que as duas
  versões já divergiram. No MVP isso vira responsividade de CSS de verdade, uma marcação
  só. As três assimetrias listadas em §8 desaparecem por construção.
- **Correção estrutural:** navegação por URL. O protótipo não muda URL nenhuma, o botão
  voltar do navegador sai do app e F5 perde tudo (§7). Rota de verdade, deep-link,
  voltar funcionando.

### Etapa 8 — Precificação + Decisão do SKU
Segunda porque **não precisa de tabela nova**: §2.1 mostra que o banco já tem tudo.
É a entrega mais rápida que o Diretor consegue julgar de verdade, e serve de prova da
fundação com número real.

- Tela de Precificação: filtros, ordenação, cenário de margem, atacado e varejo lado a
  lado, preço digitado recalculando MKP/margem/preço a prazo ao vivo.
- Tela de Decisão do SKU (Nível 2): contexto de estoque, gráfico de 4 meses + ano
  anterior, avisos condicionais, blocos de preço por cenário, decisão de compra.
- **Diferença deliberada em relação ao protótipo:** lá o preço digitado não é salvo em
  lugar nenhum (§8). Aqui grava em `APP_DECISAO_PRECO`, com histórico em
  `APP_DECISAO_PRECO_HIST` e restrição de perfil — que já existem e já funcionam.
- Ajustes de dbt: os três campos de §2.2 mais `vendaAnoPassado`.
- **Aceite:** os 8 SKUs que o `PROTOTIPO.md` §4.1 oferece como casos de regressão
  (6771, 2549, 7019, 8761, 2720, 4717, 574, 8825) batem na tela com os números da V10.

### Etapa 9 — Pedido de ponta a ponta
Terceira porque é a que mexe no schema, e convém mexer com a fundação já provada.

- Tabelas novas: `APP_PEDIDO` (fornecedor, data, status, autor), `APP_PEDIDO_ITEM`
  (produto, quantidade, preço unitário), `APP_PEDIDO_STATUS_HIST` (quem mudou o quê,
  quando — a máquina de estados é reversível e precisa deixar rastro).
- Carrinho → "Salvar pedido(s)", criando **um pedido por fornecedor** (exigência da
  rotina 220 do Winthor, §5).
- Lista de Pedidos Salvos, detalhe editável, adicionar produtos, e a máquina de estados
  Rascunho → Orçamento Enviado → Fechado → Exportado, com desfazer de um passo.
- Exportação: Excel, PDF e o formato Winthor (3 colunas, sem cabeçalho, §5).
- **Diferenças deliberadas em relação ao protótipo:** exclusão passa a pedir confirmação;
  sair do detalhe com edição pendente avisa; o carrinho sobrevive à troca de tela; e
  `dataCriacao` é a data real, não a string fixa `"28/08/26"` (§8).
- **A decidir com o Diretor:** quem pode avançar um pedido para "Fechado" e quem pode
  exportar. O protótipo não tem conceito de usuário; o sistema real tem.

### Etapa 10 — Monitoramento e Entradas
Por último, porque é a única parte com bloqueio **externo**: Seção/Linha/Categoria ainda
estão em cadastro no Winthor. Começar por aqui seria travar na primeira semana.

- Cadeia dbt nova para entradas, e a agregação por período/métrica com o comparativo
  ano a ano **calculado de verdade** — no protótipo o "+6,4%" é fixo e não reage a nada
  (§8), e o próprio documento registra que isso não é comportamento pretendido.
- O filtro de período passa a filtrar de fato. No protótipo ele é decorativo (§8).
- "Hoje" passa a ser a data real; no protótipo é `new Date(2026, 7, 28)` fixo (§8).
- Entra a navegação para o produto, que hoje falta só nesta tela (§8).
- Enquanto Seção/Linha/Categoria não chegam, as telas sobem com Departamento/Fornecedor,
  que já existem, e as outras dimensões entram sem refação quando o cadastro fechar.

### Etapa 11 — Produção
NSSM, nginx com HTTPS, build do Vite servido pelo FastAPI, Tarefa Agendada do dbt.
Era a antiga Etapa 7 do plano v1; continua igual, só passa para o fim da fila.

---

## 4. O que o v2 absorve do backlog de 26/08

Os 7 pontos deixados na pausa, e onde cada um cai:

| # | Ponto | Onde resolve |
|---|---|---|
| 1 | "Fornecedor" → "Departamento" | Etapa 7 (vocabulário da interface nova) |
| 2 | Comprador "A DEFINIR" → Washington | Ajuste em `seed_fornecedor.csv` + `dbt seed`. Independe do v2, pode sair a qualquer momento — o dado vem do seed, **não do WinThor** |
| 3 | Filtro de FL / ativo-inativo | Etapa 8. O dado já existe em `COMPRAS_PEDIDO.STATUS`; é só interface |
| 4 | Botão único para gravar o lote | Resolvido por construção: no React o estado é local e a gravação é explícita |
| 5 | Mostrar a tabela antes de exportar | Etapa 9 (é a tela de detalhe do pedido salvo) |
| 6 | Fluxo de pedido completo | **É a Etapa 9.** Era escopo novo em aberto; o protótipo é a resposta |
| 7 | Fluxo de precificação | **É a Etapa 8.** Idem |

Os itens 6 e 7 estavam registrados como "escopo a dimensionar com o usuário". O
protótipo do Diretor é esse dimensionamento — deixaram de ser pergunta.

---

## 5. Dívidas e riscos que este ciclo carrega

1. **A fórmula do valor do pedido está em dois lugares** (`int_produto_pedido.sql` e
   `app/servicos/compra.py`), sem teste comparando os dois. O modo de falha é silencioso:
   tela e `fat_pedido` mostram números diferentes, os dois plausíveis. Fechar na Etapa 8,
   quando o serviço for reescrito como API.
2. **Números mágicos do protótipo que precisam virar parâmetro**: cobertura crítica em
   60% do alvo (repetida em 3 lugares), comissão de 4% fixa, e a lista de 5 fornecedores
   MASTER (repetida literalmente 6 vezes, §5/§9). No MVP, um lugar só — os dois primeiros
   já têm casa em `seed_parametros`.
3. **`custoGerencial` é sinônimo do custo no cenário "Oficial"**, não um quarto valor
   (§9). Vale repetir na implementação, porque é exatamente o tipo de coisa que alguém
   "conserta" errado depois.
4. **Seção/Linha/Categoria dependem de cadastro alheio.** Se o cadastro não fechar, a
   Etapa 10 entrega com as dimensões que existem, e não fica bloqueada.
5. **Permissão não existe no protótipo** (§8): nenhuma tela trata "sem permissão", não há
   conceito de usuário. O sistema real tem perfil e sessão. Cada tela do v2 precisa dizer
   quem pode gravar o quê — sobretudo preço e mudança de status de pedido.
6. **Estados de carregando e de erro não existem no protótipo** (§8), porque não existe
   rede. No MVP existe rede em toda tela, e toda tela precisa dos dois.

---

## 6. Acesso pela rede interna (01/09/2026)

| O quê | Endereço | Porta liberada |
|---|---|---|
| **Front v2 (React)** | `http://192.168.0.50:5173` | 5173 — regra nova, restrita à sub-rede local |
| Dashboard v1 (HTML) | `http://192.168.0.50:8020` | 8020 — já liberada em 25/08 |

A regra da 5173 é **restrita à sub-rede local** de propósito: é um servidor de
desenvolvimento, serve código-fonte e *source maps*, e não tem por que sair da LAN. Em
produção (Etapa 11) ele deixa de existir — o `npm run build` gera estáticos que o próprio
FastAPI serve.

### Um defeito da máquina que precisa ser conhecido

Existe um **socket órfão** escutando em `0.0.0.0:8020` desde **25/08/2026 08:34**. O
processo dono (PID 2240) não existe mais; o socket não responde a nada e mesmo assim
segura a porta. Sintoma: `--host 0.0.0.0` falha com `WinError 10048`, e requisições a
`127.0.0.1:8020` caem no órfão e ficam penduradas até o *timeout*.

Contorno em vigor, em três lugares: o uvicorn sobe preso ao **IP específico**
(`--host 192.168.0.50`), que convive com o órfão; o `teste.bat` descobre o IPv4 da máquina
em vez de usar `0.0.0.0`; e o proxy do Vite aponta para o IP da rede, não para o loopback.

**A correção de verdade é liberar o socket**, o que na prática pede um reinício da
máquina. Isso não foi feito porque este servidor hospeda outros serviços em produção
(`relatorio_compras` na 8010, e mais uvicorns nas portas 8000, 8077 e 8100) — derrubá-los
é decisão do usuário, não minha. Depois do reinício, os três contornos podem voltar a
`0.0.0.0` / `127.0.0.1`, e cada um está comentado dizendo isso.
