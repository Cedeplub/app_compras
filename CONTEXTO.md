# CONTEXTO — App Compras CEDEP

Documento canônico do projeto. **Todo agente lê este arquivo antes de trabalhar.**
Ele existe para que ninguém precise redescobrir convenção, caminho ou regra de negócio
a cada invocação.

O detalhe das regras de negócio mora em **`REGRAS.md`**, um arquivo à parte. A divisão é
deliberada e econômica: este arquivo (~190 linhas) é obrigatório para todo mundo; o
`REGRAS.md` (~460 linhas) só é carregado por quem escreve ou revisa cálculo fiscal,
margem, preço, curva ABC, alerta ou script de validação. O índice da seção 6 abaixo lista
todas as regras em uma linha cada, para que ninguém ignore uma regra por não saber que
ela existe.

---

## 1. O que estamos construindo

A versão online do modelo de compras e precificação da CEDEP, hoje uma planilha Excel
(`MODELO_COMPRAS_CEDEP_v10.xlsx`): 8.772 SKUs, ~980 mil fórmulas, 122 colunas de
decisão. Dois entregáveis:

1. **Fluxo dbt** (dbt-oracle) que reproduz toda a lógica da planilha em SQL.
2. **Dashboard** FastAPI + Jinja2 + HTMX + Tailwind que lê o resultado desse fluxo.

## 2. A fronteira de acesso — regra estrutural, sem exceção

```
CEDEP (WinThor)  --SELECT-->  dbt  --cria/atualiza-->  schema COMPRAS  <--le/escreve--  dashboard
   somente leitura                                     ^                                    |
   nunca escrito                                       +---------- APP_* -------------------+
```

- O **dbt** é o único que enxerga o `CEDEP` no fluxo de dados, e só com `SELECT`.
- **Exceção nominal, única:** os scripts de `validar/` também leem o `CEDEP`, porque a
  validação consiste justamente em rodar o SQL original e o do dbt lado a lado. É
  leitura, nunca escrita, e **não é precedente para a aplicação** — o dashboard segue
  proibido de consultar o CEDEP por qualquer caminho.
- O **dashboard** conecta apenas no schema `COMPRAS`. Não existe caminho da aplicação
  para o `CEDEP` — nem para preencher filtro, nem para "só conferir um campo".
  Dado que falta no dashboard vira model dbt novo.
- Tudo que o sistema **cria e registra** mora no mesmo schema `COMPRAS`, prefixo `APP_`.
- **O dbt LÊ as `APP_*`** (nunca escreve). Elas entram como `source` e são juntadas em
  `fat_pedido` — é assim que a decisão humana de preço volta para o modelo. Consequência
  prática que precisa estar clara desde já: **uma decisão gravada no dashboard só aparece
  no `fat_pedido` depois do próximo `dbt run`.** O dashboard mostra o valor gravado
  lendo `APP_*` direto; o modelo recalculado só chega no próximo build.
### Autorização de escrita (decidida pelo usuário em 2026-08-19)

- **Schema `COMPRAS`: autorização total.** Criar, alterar e derrubar objetos, gravar e
  apagar dados — sem precisar confirmar a cada vez. Continua valendo o bom senso de
  conferir se há dado a perder antes de derrubar algo.
- **`CEDEP`: proibido mexer, de qualquer jeito.** Só `SELECT`. Não é "evitar", é proibido.
  Não existe cenário neste projeto que justifique escrita no CEDEP; se algum caminho
  parecer exigir isso, o caminho está errado — pare e reporte.

- Prefixos definem o dono. **dbt:** `stg_`, `int_`, `dim_`, `fat_`, `seed_` e, na camada
  de contrato, `COMPRAS_*`. **Aplicação:** `APP_*`. O dbt nunca cria nem derruba nada
  com prefixo `APP_`; a aplicação nunca escreve em nada que não seja `APP_`.

## 3. Banco

| Item | Valor |
|---|---|
| Servidor | Oracle 19c, `192.168.0.98:1521`, `SERVICE_NAME=WINT` |
| Schema de origem | `CEDEP` (WinThor/TOTVS), somente leitura |
| Schema de destino | `COMPRAS` (usuário dedicado criado na etapa 0) |
| Adapter | `dbt-oracle` 1.9.x sobre `dbt-core` 1.9.x, driver `oracledb` |
| Modo do driver | **thick, obrigatório** |
| Credenciais | `~/.dbt/profiles.yml`, fora do repositório |

**Modo thick não é opcional neste servidor.** As contas usam verificador de senha legado
`0x939`, que o python-oracledb recusa em modo thin (`DPY-3015`) — vale para o usuário
`COMPRAS` e também para o `dbt` que o `powerbi_dbt` já usa. Não é problema do usuário
novo, é característica do servidor.

Há **dois caminhos diferentes** para ligar o thick, e confundi-los custa tempo:

**dbt** — já resolvido pelo ambiente, nada a fazer no projeto:

- variável de sistema `ORA_PYTHON_DRIVER_TYPE=thick` (registro, HKLM)
- Oracle Client 12.1 em `C:\Oracle\product\12.1.0\client_1\BIN`, no PATH
- `TNS_ADMIN=C:\Oracle\product\12.1.0\client_1\network\admin`

**Python comum** (dashboard, scripts de `validar/`, qualquer utilitário) — o
`ORA_PYTHON_DRIVER_TYPE` **não vale aqui**: é convenção do dbt-oracle, não do driver.
O `oracledb` abre em thin por padrão e falha com `DPY-3015`. É obrigatório chamar,
antes da primeira conexão:

```python
import oracledb
oracledb.init_oracle_client(lib_dir=r"C:\Oracle\instantclient_21_17")
```

O client `instantclient_21_17` é o que está validado — é o mesmo que
`relatorios_compras` e `app_solicitacao_pagamentos` usam.

Se aparecer `DPY-3015`, é uma dessas duas configurações que faltou. Não invente outro
caminho: conserte a que falta.

## 4. Arquivos de referência — leia antes de perguntar

| Caminho | O que é |
|---|---|
| `docs/gabarito_pedido_formulas.txt` | **As 122 colunas da aba `pedido`**, com cabeçalho e a fórmula Excel de cada uma. É o gabarito do motor de decisão. |
| `docs/gabarito_tabelas_apoio.txt` | Conteúdo das abas Parametros, dFornecedor, dICMS, dCredito, dICMS_Origem, dPISCOFINS, dSucessao, dEmbalagem, fEstFabrica. Vira seed. |
| `docs/gabarito_powerquery.m` | O Power Query do xlsx: como os 2 relatórios viram `dCadastroTI` e `fVendaMes`. Gabarito da camada intermediária. |
| `docs/documentacao_tecnica_v10.txt` | O PDF da diretoria, em texto. Regras de negócio e premissas. |
| `referencia/MODELO_COMPRAS_CEDEP_v11.xlsx` | **A planilha de referência ATUAL** (25 MB). Só abrir com leitura em streaming. |
| `referencia/MODELO_COMPRAS_CEDEP_v10.xlsx` | Versão anterior, mantida só para histórico. **Não use como gabarito.** |
| `C:\Users\Administrator\Desktop\relatorios_compras\query.py` | SQL do relatório de estoque/fiscal (41 colunas). |
| `C:\Users\Administrator\Desktop\relatorios_compras\query_mensal.py` | SQL do relatório mensal (19 colunas), validado contra a rotina 1464. |
| `C:\Users\Administrator\Desktop\app_relatorios\relatorios\` | Os mesmos SQLs, versão refatorada e mais legível. |
| `C:\Users\Administrator\Desktop\powerbi_dbt\powerbi\` | **O padrão de projeto dbt a copiar.** |
| `C:\Users\Administrator\Desktop\app_relatorios\teste.bat` | Molde do `teste.bat`. |
| `C:\Users\Administrator\Desktop\app_solicitacao_pagamentos\` | Padrão FastAPI + Jinja2 + HTMX + Tailwind. |

## 5. Convenções dbt (copiadas de `powerbi_dbt/powerbi`)

- Camadas: `staging` (view) -> `intermediate` (table) -> `marts` (table) -> `app` (table).
- Prefixos: `stg_`, `int_`, `dim_`, **`fat_`** (não `fct_`), `seed_`. Na camada `app`, o
  nome do arquivo **é** o nome físico da tabela, e os aliases saem em MAIÚSCULAS.
  ⚠ O Oracle já sobe identificador não-aspado para maiúscula, então `compras_pedido.sql`
  cria `COMPRAS_PEDIDO` e `x as CODIGO` grava `CODIGO` de qualquer forma. Escrever o
  alias em MAIÚSCULA é **convenção de legibilidade** — sinaliza "isto é contrato
  público". **Nunca use aspas duplas em identificador**; aspas criam nome
  case-sensitive, e aí toda consulta da aplicação passa a exigir aspas também.
- Materialização fica no `dbt_project.yml`. `{{ config() }}` por arquivo só para desvio
  ou tag — e desvio pede comentário explicando por quê.
- Estilo de SQL: uma CTE por upstream, `with x as (select * from {{ ref(...) }})`, e o
  arquivo termina em `select * from <ultima cte>`.
- **Nome da última CTE**, para os agentes não divergirem (no `powerbi_dbt` convivem os
  dois estilos, 64 arquivos com `final` e 31 com `renamed` — aqui a escolha é semântica):
  - `staging` → **`renamed`**, porque a camada só renomeia;
  - `intermediate`, `marts`, `app` → **`final`**.
  - **Exceção declarada na camada `app`:** model que é PROJEÇÃO PURA (só renomeia
    colunas de um `ref` único, sem join, cálculo ou filtro) dispensa CTE e sai como
    `select ... from {{ ref(...) }}` direto. Envolver uma projeção numa CTE que não faz
    nada é cerimônia, e é o que o molde `dre_contabil/app/dre_estrutura.sql` do
    `powerbi_dbt` já faz. Model da camada `app` que tenha join ou agregação segue a regra
    normal e termina em `final` — é o caso do `compras_ind_fornecedor`.
- **Nome de model no singular**: `stg_produto`, `dim_produto`, `int_produto_custo` — não
  `stg_produtos`. Vale mesmo onde o `powerbi_dbt` usa plural; consistência interna aqui
  vale mais que simetria com o outro projeto.
- **Vocabulário da planilha ganha do vocabulário do `powerbi_dbt`** quando os dois
  divergirem: `embal_compra` (e não `quantidade_por_caixa`), porque é o nome que o
  Diretor de Compras usa e o que aparece no gabarito.
- Palavras-chave minúsculas. Identificadores em **pt-BR** (`id_produto`, `valor_liquido`).
- Colunas de origem escritas em MAIÚSCULAS no staging (é como o Oracle as expõe),
  renomeadas para snake_case pt-BR.
- Model de regra fiscal ou de negócio leva cabeçalho em caixa `-- ────` explicando
  **o porquê**, citando a coluna Excel que reproduz. Comentário que só repete o código
  não serve.
- Seeds: delimitador `;`, `+column_types` explícito onde a coluna for esparsa.
- Testes singulares em `tests/`, nome `compras_<invariante>.sql`, cada um com comentário
  dizendo qual falha ele previne.
- `dbt run` NÃO roda `dbt seed`. Editar CSV sem rodar seed deixa o modelo com estrutura
  antiga, silenciosamente.

## 6. Regras de negócio — índice

O detalhe está em **`REGRAS.md`** (445 linhas), separado daqui por custo de token: só
quem escreve ou revisa regra de negócio, cálculo fiscal ou validação numérica precisa
carregá-lo. Este índice existe para que todo agente saiba **que a regra existe**, mesmo
sem ler o detalhe — se o seu trabalho encosta em qualquer linha abaixo, abra o
`REGRAS.md` antes de escrever código.

| # | Regra, em uma linha |
|---|---|
| 1 | Quantidade e valor são sempre **líquidos**. Única exceção: `TX_DEVOLUCAO_3M`. |
| 2 | **Ajuste Ingrax** entra em margem/preço, **nunca** na base de ICMS-ST. |
| 3 | Redução de base de ICMS só no atacado. Código de filial é `'1'`,`'2'`,`'9'` — **sem zero à esquerda**. |
| 4 | Crédito de PIS/COFINS é sobre a NF **sem IPI**, descontado o crédito de ICMS. |
| 5 | **Curva ABC** recalcula o total a cada build (`sum() over`), em **dois universos** (com e sem litragem). |
| 6 | **`FATOR_EXIBICAO`** divide quase toda quantidade — e **congela** onde há decisão gravada (MELHORIA A5). |
| 7 | `FORNECEDOR` é o **texto do departamento**, não o fornecedor da NF. |
| 8 | `VL_ULT_ENT` **nunca** é dividido pela embalagem de compra. |
| 9 | A base mensal inclui **todo SKU que apareceu em qualquer mês**, inclusive o corrente. |
| 10 | **`ALT_PV_*` é decisão humana** — nunca preenchido por cálculo. `MARGEM_ALVO` cai em 20% na ausência. |
| 11 | **`dtexclusao is null` tem uso diferente em cada relatório.** Global no de estoque, pontual no mensal. |

E as seções que dizem **como se prova que o modelo está certo**, todas em `REGRAS.md`:

| Seção | Assunto |
|---|---|
| §6.1 | Divergências já decididas com o Diretor de Compras |
| §6.0 | Onde divergimos da planilha **de propósito** |
| §6.0.1 | Número de registro envelhece — não trate contagem antiga como verdade |
| §6.1.0 | O critério de aceite é **atribuibilidade**, não zero absoluto |
| §6.1.1 | O critério de aceite de `ALERTA`, componente a componente |
| §6.2 | Armadilhas **medidas no banco** — não "conserte" nenhuma delas |
| §6.3 | Como validar contra o original, e o erro que já cometemos |
| §6.4 | Divergências deliberadas da planilha |

## 7. Como o trabalho é entregue

Em etapas (ver o plano aprovado). Nenhuma etapa começa antes de a anterior ser aprovada
pelo usuário, e cada etapa passa pelo agente `revisor` antes de ir para aprovação.

Critério de aceite final: `fat_pedido` comparado célula a célula com a aba `pedido`,
122 colunas × 8.772 linhas, tolerância 0,01.
