# Status do projeto

Atualizado em 24/08/2026. **Leia junto com `CONTEXTO.md`** — este arquivo diz *onde
estamos*; o CONTEXTO diz *como trabalhar*.

## Etapas

| | Etapa | Situação |
|---|---|---|
| A | Agentes de desenvolvimento | ✅ concluída |
| 0 | Infraestrutura Oracle (schema `COMPRAS`, tabelas `APP_*`) | ✅ concluída |
| 1 | dbt: esqueleto, 21 staging, 9 seeds | ✅ concluída |
| 2 | Intermediate: porte dos dois relatórios | ✅ concluída |
| 3 | Consolidação por SKU (pivot mensal + sucessão) | ✅ concluída |
| 4 | As 122 colunas da aba `pedido` (`fat_pedido`) | ✅ **aceite PASSOU** |
| 5 | Camada de contrato `COMPRAS_*` | ✅ concluída |
| 6 | Dashboard FastAPI + Jinja2 + HTMX (CSS próprio) | ✅ concluída |
| 7 | Produção: nginx + NSSM + Tarefa Agendada | ⏳ próxima |
| 8 | Acesso externo via Fortigate | fora de escopo até validar o resto |

## O que está no ar

Schema `COMPRAS` no Oracle (`192.168.0.98:1521/WINT`):
- **50 models dbt** — 21 views `stg_`, 9 seeds, 15 tabelas `int_`, 5 marts (`fat_pedido`
  com as 122 colunas, `fat_alerta`, `dim_produto`, `dim_fornecedor`, `dim_tributacao`)
  e **4 tabelas de contrato** `COMPRAS_PEDIDO` (122 col., 8.777 linhas), `COMPRAS_ALERTA`
  (6.607), `COMPRAS_VENDA_MENSAL` (78.979) e `COMPRAS_IND_FORNECEDOR` (60)
- **6 tabelas `APP_*`** escritas pela aplicação — hoje **vazias**
- **262 testes** passando, 1 warn documentado (`tx_devolucao_3m > 1` em 3 SKUs, real)
- `dbt\rodar_dbt.bat` sobe tudo em ~70s e **propaga código de saída de verdade**

Aceite da Etapa 4: **PASSOU**. `CLASSE`/`MODALIDADE`/`CUSTO_TOT_GERENCIAL` em zero, os 10
preços sugeridos em zero, `ALERTA` com 2.146 divergências e **zero não atribuíveis**.

## Dashboard (Etapa 6) — o que está no ar

`app/` com 1.4k linhas: 4 telas (compra, preço, indicadores, exportação), login por
sessão com token opaco, e exportação de pedido em Excel por fornecedor.
Sobe com `teste.bat` (porta 8020, escuta em `0.0.0.0` para permitir teste por celular).

**Desvio do plano, deliberado: NÃO usa Tailwind.** CSS próprio em `app/static/app.css`,
sem build, e htmx vendorizado em `app/static/js/`. Motivo: não há toolchain Node neste
projeto (a implantação é `.bat` + NSSM), e as alternativas — CDN em runtime ou Tailwind
Play — fazem a tela depender de internet ou gerar CSS no navegador, justamente no
celular dentro da rede interna que é o dispositivo alvo. **Não há uma única URL externa
em template ou CSS** (verificado por grep e no HTML renderizado).

**A fórmula do pedido está duplicada de propósito**, e é a dívida conhecida da etapa:
`pedido_unidades = pedido × fator congelado` e `valor_pedido = unidades × custo_tot_oficial`
existem em `dbt/.../int_produto_pedido.sql` **e** em `app/servicos/compra.py`. Sem isso,
a tela mostraria o valor do último build (zero) e a decisão sumia num F5. Não há teste
comparando as duas — se divergirem, a tela e o `fat_pedido` mostram números diferentes,
os dois plausíveis, e ninguém percebe. **Achado do revisor, em aberto.**

## Ajustes pedidos pelo usuário em 26/08/2026 — fila da retomada

O desenvolvimento foi pausado nesta data. Estes são os pontos a tratar quando voltar,
na ordem em que o usuário os listou. Os três primeiros são pequenos; os dois últimos
mudam o modelo de dados.

**1. Trocar "Fornecedor" por "Departamento" na interface.** O campo sempre foi o texto do
departamento, não o fornecedor legal da NF (§6 regra 11 do `REGRAS.md`) — o nome herdado
da planilha confunde quem lê a tela. ⚠️ Decidir o alcance antes de mexer: rótulo de tela e
cabeçalho do Excel são seguros; **renomear a coluna física em `COMPRAS_*` quebra o
contrato com o dashboard** e é outra conversa. Recomendação: mudar só o que o usuário lê.

**2. Comprador "A DEFINIR" → Washington.** ✅ **Verificado em 26/08: NÃO vem do WinThor.**
`A DEFINIR` está gravado no próprio `seed_fornecedor.csv` (aba `dFornecedor` da planilha)
em **45 das 60 linhas**, alcançando **5.964 dos 8.777 SKUs**. Hoje só existem dois
compradores: `A DEFINIR` e `FELIPE`. Portanto o ajuste é **editar o CSV do seed e rodar
`dbt seed`** — nenhum cadastro no ERP. Confirmar com o usuário se Washington assume as 45
linhas ou só parte delas.

**3. Filtro de FL / ativo-inativo na tela de compra.** ✅ O dado **já existe** em
`COMPRAS_PEDIDO.STATUS` (4.500 Ativo, 4.277 Inativo) e em `CHECK_FORA_DE_LINHA`. É
trabalho só de interface — mais um `<select>` ao lado dos filtros atuais e a condição no
`listar_pedidos`. Nada de dbt.

**4. Um botão único para gravar os itens editados.** Hoje cada linha tem seu próprio
"Gravar" e cada gravação é um POST. Vira um formulário de página com um botão só.
Implica: marcar quais linhas mudaram, um endpoint que receba o lote, e **uma transação
por lote** — decidir se um item inválido derruba o lote inteiro ou só ele.

**5. Mostrar a tabela do pedido antes de exportar.** Hoje `/pedidos` lista fornecedores e
baixa o `.xlsx` direto, sem o comprador ver o conteúdo. Acrescentar a pré-visualização dos
itens — as mesmas 9 colunas do arquivo — antes do botão de baixar.

**6. Fluxo de pedido: analisar tabela → selecionar produtos → simular pedido → editar
quantidades → editar preços (talvez) → exportar.** ⚠️ **É o item que muda o modelo.**
Ele responde a pergunta que o usuário fez em 25/08 ("se eu criar um pedido hoje e outro
amanhã para o mesmo fornecedor, agrupa ou gera outro?"), cuja resposta hoje é
constrangedora: **nem uma coisa nem outra — sobrescreve**. `APP_DECISAO_PEDIDO` tem PK em
`ID_PRODUTO`, uma linha por SKU, sem histórico e sem entidade "pedido". Este fluxo implica
criar o pedido como documento (número, itens congelados no fechamento, status), que é a
opção 3 das três que apresentei ao usuário. **Escopo novo, não é ajuste.**

**7. Criar fluxo de precificação.** Análogo ao 6, para a tela de preço: hoje ela é
consulta de um SKU por vez. Falta o passo a passo guiado. Escopo a levantar com o usuário.

## Decisões abertas — não perder

### Do usuário / Diretor de Compras
1. **4.277 produtos marcados fora de linha no cadastro não recebem alerta.** A melhoria A3
   alcançou 71; os outros não aparecem em mês nenhum (a consolidação mensal só admite
   produto em linha), então não há registro de onde ler. Alcançá-los exige ler o campo
   direto do cadastro — escopo maior que o aprovado. **Decisão do Diretor.**
2. **`B1` e `B2` do `MELHORIAS.md`** seguem como proposta: sucessão múltipla (7095 é
   antecessor de 4 SKUs, 400% de demanda se todos ativarem) e média negativa por devolução
   fora da janela. As duas mudam **sugestão de compra**.

### Técnicas, para decidir antes da etapa indicada
3. **`TEND` na fronteira** — produto 7275 tem `tend_pct` exatamente `-0,15` contra o limiar
   de 0,15: Oracle devolve `QUEDA`, Excel devolve `ESTAVEL`. Decidir `>` vs `>=`. 1 SKU hoje.
4. **Medir a duração real do build antes da Etapa 7.** `int_faturamento_mensal` já variou
   de 42s a 187s entre execuções, e a explicação de cache do Oracle é plausível mas **não
   foi medida**. Isso vira Tarefa Agendada diária.
5. **`threads: 1` no profile** — `int_faturamento_mensal` (34s) e `int_cadastro_estoque`
   (17s) são independentes e somam 74% do build. Com 4 threads o `dbt run` cairia de ~70s
   para ~45s. Ajuste em `~/.dbt/profiles.yml`, fora do repositório.
6. **Pedido do Diretor à TI (PDF §14):** expor a tributação de entrada e saída por item
   direto do Winthor. Hoje o modelo usa um proxy empírico. Com o dado real, o dashboard
   ficaria **mais preciso que a planilha** — deixa de ser réplica. Avaliar depois do ar.

## Como invocar os agentes (revisão de 24/08/2026)

Os 9 agentes continuam com o mesmo nível de instrução; o que mudou foi **o que cada um
carrega**. Duas regras valem para **quem chama**, não para o agente:

1. **`model:` na invocação sobrescreve o `model:` do arquivo do agente.** Use isso.
   `dbt-regras` e `revisor` nascem em `opus` porque erro fiscal é caro — mas etapa sem
   cálculo fiscal (camada de contrato, `.bat`, serviço, rota, template) deve ser invocada
   com `model: sonnet`. O critério: **se a tarefa muda um número, é opus; se só muda onde
   o número aparece, é sonnet.**
2. **A tarefa nomeia os arquivos.** Agente que precisa descobrir onde as coisas estão
   gasta mais token procurando do que trabalhando — e uma varredura já rodou 32 minutos
   aqui sem produzir nada.

Custo de leitura inicial por invocação, depois da separação `CONTEXTO.md`/`REGRAS.md`:

| Agente | Lê | Antes | Depois |
|---|---|---|---|
| `oracle-dba`, `dbt-staging`, `backend-fastapi`, `frontend-htmx`, `infra-windows` | só `CONTEXTO.md` | ~44 KB | **~16 KB** |
| `dbt-relatorios`, `dbt-regras`, `validador`, `revisor` | `CONTEXTO.md` + `REGRAS.md` | ~44 KB | ~48 KB |

Os cinco primeiros economizam ~7,6 mil tokens **por invocação** — e são justamente os das
etapas 6 e 7, as de maior número de chamadas. Os quatro últimos pagam ~1,1 mil a mais,
compensados pelas regras de economia (sem varredura ampla, sem abrir o xlsx, relatório
final em até 25 linhas).

## Onde procurar o quê

| Arquivo | Para quê |
|---|---|
| `CONTEXTO.md` | **Leia primeiro.** Convenções, fronteira de acesso, banco, e o índice das 11 regras de negócio |
| `REGRAS.md` | O detalhe das regras (§6.x): fiscal, ABC, alerta, armadilhas medidas, critério de aceite. Só quem mexe em cálculo ou validação precisa |
| `MELHORIAS.md` | Divergências deliberadas da planilha, com status e efeito medido |
| `PENDENCIAS_DIRETORIA.md` | As 5 divergências PDF × planilha — todas decididas |
| `docs/gabarito_pedido_formulas.txt` | As 122 fórmulas da v11 (regenerado do xlsx) |
| `docs/dicionario_cedep.txt` | Colunas reais das 19 tabelas do CEDEP |
| `validar/*.py` | Os três validadores, com autoteste |
| `.claude/agents/*.md` | Os 9 agentes, com as lições que cada um aprendeu errando |

## Lições que custaram caro (resumo; detalhe no CONTEXTO)

- **Não compare tabela materializada com consulta ao vivo.** Reprovou 4 vezes sem defeito.
- **Divergência que cresce com o relógio é defasagem, não bug.**
- **Critério de aceite impossível de cumprir é pior que critério nenhum** — foi preciso
  corrigir o de `ALERTA` e o de `CUSTO_TOT_GERENCIAL` depois de escritos.
- **Número de registro envelhece.** Recalcule a atribuição; não compare contra o anotado.
- **Teste que nunca falhou não prova nada.** Todo teste novo é exercitado com defeito
  injetado antes de valer.
