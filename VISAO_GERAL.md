# App Compras — Visão Geral do Projeto

> Documento informativo para a equipe de TI e para a gerência.
> Descreve o que é o sistema, as regras de negócio, a stack, a estrutura e o
> estágio de desenvolvimento. O detalhe operacional está em `STATUS.md`,
> `CONTEXTO.md` e `REGRAS.md`.

| | |
|---|---|
| **Nome** | App Compras CEDEP — modelo de compras e precificação |
| **Pasta** | `C:\Users\Administrator\Desktop\app_compras` |
| **Status** | 🟡 **Em desenvolvimento — pausado em 26/08/2026** com fila de ajustes definida |
| **Onde roda** | Ambiente de teste, `teste.bat` na porta **8020** (ainda não é serviço) |
| **Público** | Diretoria de Compras e compradores |
| **Última atividade registrada** | 27/08/2026 |

---

## 1. O que é o projeto

A **versão online do modelo de compras e precificação da diretoria de Compras**,
hoje uma planilha Excel de **8.772 SKUs e ~980 mil fórmulas**
(`MODELO_COMPRAS_CEDEP_v11.xlsx`).

A planilha decide, por SKU: quanto comprar, a que custo, com qual margem, a que
preço vender, em que curva ABC o produto está e quais alertas ele dispara. É o
instrumento central da área — e hoje depende de uma pessoa abrir um arquivo de
25 MB e recalcular 980 mil fórmulas.

**Dois entregáveis:**
1. Um fluxo **dbt** que reproduz toda a lógica da planilha em SQL.
2. Um **dashboard** que lê o resultado e permite ao comprador decidir e exportar
   o pedido.

---

## 2. Status de desenvolvimento

O projeto é dividido em 9 etapas, e **nenhuma começa antes de a anterior ser
aprovada**. Cada etapa passa por revisão antes da aprovação.

| | Etapa | Situação |
|---|---|---|
| A | Agentes de desenvolvimento | ✅ concluída |
| 0 | Infraestrutura Oracle (schema `COMPRAS`, tabelas `APP_*`) | ✅ concluída |
| 1 | dbt: esqueleto, 21 staging, 9 seeds | ✅ concluída |
| 2 | Intermediate: porte dos dois relatórios | ✅ concluída |
| 3 | Consolidação por SKU (pivot mensal + sucessão) | ✅ concluída |
| 4 | As 122 colunas da aba `pedido` | ✅ **aceite PASSOU** |
| 5 | Camada de contrato `COMPRAS_*` | ✅ concluída |
| 6 | Dashboard FastAPI + Jinja2 + HTMX | ✅ concluída |
| 7 | **Produção: nginx + NSSM + Tarefa Agendada** | ⏳ **próxima** |
| 8 | Acesso externo via Fortigate | fora de escopo até validar o resto |

### O que já está no ar (schema `COMPRAS`, Oracle)

- **50 models dbt** — 21 views de staging, 9 seeds, 15 tabelas intermediárias,
  5 marts e **4 tabelas de contrato**: `COMPRAS_PEDIDO` (122 colunas, 8.777
  linhas), `COMPRAS_ALERTA` (6.607), `COMPRAS_VENDA_MENSAL` (78.979) e
  `COMPRAS_IND_FORNECEDOR` (60).
- **6 tabelas `APP_*`** escritas pela aplicação — hoje vazias.
- **262 testes** passando (1 aviso documentado e real).
- O build completo roda em ~70 s (`dbt\rodar_dbt.bat`).
- Dashboard com **4 telas** (compra, preço, indicadores, exportação), login por
  sessão e exportação do pedido em Excel por fornecedor.

**Critério de aceite final:** `fat_pedido` comparado célula a célula com a aba
`pedido` da planilha — 122 colunas × 8.772 linhas, tolerância 0,01. **Passou.**

### Fila de retomada (ajustes pedidos em 26/08/2026)

| # | Ajuste | Peso |
|---|---|---|
| 1 | Trocar o rótulo "Fornecedor" por "Departamento" na interface | pequeno |
| 2 | Comprador "A DEFINIR" → Washington (editar o seed e rodar `dbt seed`) | pequeno |
| 3 | Filtro de ativo/inativo e fora de linha na tela de compra | pequeno |
| 4 | Botão único para gravar os itens editados (hoje é um POST por linha) | médio |
| 5 | Mostrar a tabela do pedido antes de exportar | médio |
| 6 | **Fluxo de pedido como documento** (número, itens congelados, status) | ⚠️ **escopo novo** |
| 7 | Fluxo guiado de precificação | ⚠️ escopo a levantar |

> ⚠️ **O item 6 muda o modelo de dados.** Hoje `APP_DECISAO_PEDIDO` tem uma linha
> por SKU, sem histórico e sem a entidade "pedido": criar um pedido hoje e outro
> amanhã para o mesmo fornecedor **sobrescreve** — não agrupa nem gera um novo.

### Decisões abertas — pendentes da Diretoria

1. **4.277 produtos marcados fora de linha no cadastro não recebem alerta.**
   Alcançá-los exige ler o campo direto do cadastro — escopo maior que o aprovado.
2. **Sucessão múltipla de produto** (o SKU 7095 é antecessor de 4 outros; se todos
   ativarem, a demanda soma 400%) e **média negativa por devolução fora da
   janela**. As duas mudam a **sugestão de compra**.
3. **Pedido do Diretor à TI:** expor a tributação real de entrada e saída por item
   direto do WinThor. Hoje o modelo usa um proxy empírico; com o dado real o
   dashboard ficaria **mais preciso que a planilha** — deixaria de ser réplica.

### Dívida técnica conhecida

**A fórmula do pedido está duplicada de propósito**, no dbt e na aplicação
(`app/servicos/compra.py`). Sem isso, a tela mostraria o valor do último build
(zero) e a decisão do comprador sumiria num F5. **Não há teste comparando as
duas** — se divergirem, a tela e a tabela mostram números diferentes, os dois
plausíveis, e ninguém percebe. Achado do revisor, em aberto.

---

## 3. Regra estrutural — fronteira de acesso a dados

```
CEDEP (WinThor)  --SELECT-->  dbt  --cria/atualiza-->  COMPRAS  <--lê/escreve--  dashboard
   somente leitura                                        ^                          |
   nunca escrito                                          +-------- APP_* -----------+
```

- O **dbt é o único que enxerga o `CEDEP`**, e só com `SELECT`.
- O **dashboard conecta apenas no schema `COMPRAS`**. Não existe caminho da
  aplicação para o WinThor — nem para preencher um filtro, nem "só para conferir
  um campo". Dado que falta no dashboard vira model dbt novo.
- **Prefixo define o dono:** `stg_ int_ dim_ fat_ COMPRAS_` é do dbt; `APP_` é da
  aplicação. O dbt **lê** as `APP_*` (nunca escreve) — é assim que a decisão
  humana de preço volta para o modelo.
- **Consequência prática:** uma decisão gravada no dashboard só aparece no
  `fat_pedido` **depois do próximo `dbt run`**. A tela mostra o valor gravado
  lendo `APP_*` direto.
- **Escrever no `CEDEP` é proibido**, não "evitado".

---

## 4. Regras de negócio

O detalhe completo está em `REGRAS.md` (~460 linhas). Índice:

| # | Regra |
|---|---|
| 1 | Quantidade e valor são sempre **líquidos**. Única exceção: a taxa de devolução de 3 meses. |
| 2 | **Ajuste Ingrax** entra em margem e preço, **nunca** na base de ICMS-ST. |
| 3 | Redução de base de ICMS **só no atacado**. Código de filial é `'1'`, `'2'`, `'9'` — **sem zero à esquerda**. |
| 4 | Crédito de PIS/COFINS é sobre a NF **sem IPI**, descontado o crédito de ICMS. |
| 5 | **Curva ABC** recalcula o total a cada build, em **dois universos** (com e sem litragem). |
| 6 | **`FATOR_EXIBICAO`** divide quase toda quantidade — e **congela** onde há decisão gravada. |
| 7 | ⚠️ **`FORNECEDOR` é o texto do departamento**, não o fornecedor legal da NF. |
| 8 | O valor da última entrada **nunca** é dividido pela embalagem de compra. |
| 9 | A base mensal inclui **todo SKU que apareceu em qualquer mês**, inclusive o corrente. |
| 10 | **Alteração de preço de venda é decisão humana** — nunca preenchida por cálculo. A margem alvo cai em 20% na ausência. |
| 11 | O filtro de exclusão de cadastro **tem uso diferente em cada relatório**: global no de estoque, pontual no mensal. |

> A regra 7 é a origem do ajuste #1 da fila de retomada: o nome herdado da
> planilha confunde quem lê a tela.

### Divergências deliberadas em relação à planilha

Registradas em `MELHORIAS.md`, com efeito medido. E as 5 divergências entre o PDF
da diretoria e a planilha estão em `PENDENCIAS_DIRETORIA.md` — **todas já
decididas**.

Um caso de fronteira segue em aberto: o SKU 7275 tem tendência exatamente no
limiar (`-0,15`) — o Oracle devolve `QUEDA`, o Excel devolve `ESTAVEL`. Falta
decidir se a comparação é `>` ou `>=`. Afeta 1 SKU hoje.

---

## 5. Stack

| Camada | Tecnologia |
|---|---|
| Transformação | **dbt-core 1.9.x** + adapter **dbt-oracle 1.9.x** |
| Banco | **Oracle 19c** (`192.168.0.98:1521/WINT`) — origem `CEDEP`, destino `COMPRAS` |
| Driver | `oracledb` em **modo thick** (obrigatório) |
| Backend | **FastAPI** + uvicorn (porta 8020) |
| Frontend | **Jinja2 + HTMX**, com **CSS próprio** |
| Autenticação | Sessão com token opaco, `bcrypt` |
| Excel | `openpyxl` |
| Automação | `.bat` + NSSM + Tarefa Agendada do Windows |

> **Desvio deliberado do plano: NÃO usa Tailwind.** CSS próprio, sem build, e HTMX
> vendorizado. Motivo: não há toolchain Node neste projeto (a implantação é `.bat`
> + NSSM), e CDN em runtime faria a tela depender de internet — justamente no
> celular dentro da rede interna, que é o dispositivo alvo.
> **Não há uma única URL externa** em template ou CSS (verificado por grep e no
> HTML renderizado).

> ⚠️ **Modo thick tem dois caminhos diferentes** nesta máquina, e confundi-los
> custa tempo: o **dbt** usa a variável de sistema `ORA_PYTHON_DRIVER_TYPE=thick`
> com o client 12.1 no PATH; **Python comum** (dashboard, scripts de validação)
> precisa chamar `oracledb.init_oracle_client(lib_dir=r"C:\Oracle\instantclient_21_17")`
> antes da primeira conexão. Se aparecer `DPY-3015`, é uma dessas duas que faltou.

---

## 6. Estrutura

```
app_compras/
├── STATUS.md                  onde estamos: etapas, o que está no ar, decisões abertas
├── CONTEXTO.md                documento canônico — convenções, fronteira de acesso, banco
├── REGRAS.md                  o detalhe das regras de negócio, fiscais e de validação
├── MELHORIAS.md               divergências deliberadas da planilha, com efeito medido
├── PENDENCIAS_DIRETORIA.md    as 5 divergências PDF × planilha (decididas)
├── .claude/agents/            os 9 agentes de desenvolvimento
├── docs/                      gabaritos extraídos da planilha e do PDF
├── referencia/                a planilha e o PDF originais
├── sql/                       DDL do schema Oracle COMPRAS
├── dbt/compras/               o projeto dbt (50 models)
├── app/                       o dashboard (~1,4 mil linhas)
│   ├── main.py · config.py
│   ├── core/ · servicos/
│   ├── templates/ · static/
└── validar/                   scripts que comparam o dbt com a planilha
```

### Convenções dbt (copiadas do projeto `powerbi_dbt`)

- Camadas: `staging` (view) → `intermediate` (table) → `marts` (table) → `app`.
- Prefixos: `stg_`, `int_`, `dim_`, **`fat_`** (não `fct_`), `seed_`, `COMPRAS_`.
- **Nome de model no singular** (`stg_produto`, não `stg_produtos`).
- Identificadores em **pt-BR**; **nunca use aspas duplas** em identificador
  Oracle.
- **O vocabulário da planilha ganha do vocabulário do outro projeto dbt** — é o
  nome que o Diretor de Compras usa.
- ⚠️ **`dbt run` NÃO roda `dbt seed`.** Editar um CSV sem rodar o seed deixa o
  modelo com estrutura antiga, silenciosamente.

---

## 7. Como o desenvolvimento é conduzido

O projeto usa **9 agentes especializados**, um por função, cada um no modelo
adequado ao peso da tarefa — modelos menores para o repetitivo com gabarito,
modelos maiores só para regra fiscal e revisão.

O critério de escolha: **se a tarefa muda um número, é o modelo mais forte; se só
muda onde o número aparece, é o intermediário.**

### Lições registradas (que custaram caro)

- **Não compare tabela materializada com consulta ao vivo** — reprovou 4 vezes sem
  haver defeito.
- **Divergência que cresce com o relógio é defasagem, não bug.**
- **Critério de aceite impossível de cumprir é pior que critério nenhum.**
- **Número de registro envelhece** — recalcule, não compare contra o anotado.
- **Teste que nunca falhou não prova nada** — todo teste novo é exercitado com
  defeito injetado antes de valer.
