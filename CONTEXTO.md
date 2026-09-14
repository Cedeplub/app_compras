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

## 0. Ponto de partida — para quem não leu nada

Esta seção existe para uma sessão nova ou um desenvolvedor novo conseguirem colocar o
sistema no ar **sem abrir mais nenhum arquivo além deste**. Ela entra como `§0`, antes do
`§1`, para não renumerar as seções `§1`–`§7` que já existem — `validar/validar_pedido.py:6`
cita `§6.2` e `§6.3` pelo número, e ~80 arquivos citam este documento pelo nome.

### 0.1 O que é este projeto

A CEDEP decide compra e preço de **8.841 SKUs** hoje numa planilha Excel
(`MODELO_COMPRAS_CEDEP_v11.xlsx`, 122 colunas de decisão, ~980 mil fórmulas) mantida à
mão. Este projeto reproduz essa planilha em dois entregáveis:

1. **Um fluxo dbt** (`dbt/compras/`) que lê o ERP (WinThor/CEDEP), reproduz toda a lógica
   fiscal, de margem, preço e alerta em SQL, e grava o resultado no schema Oracle
   `COMPRAS` — as 122 colunas viram a tabela `FAT_PEDIDO`/`COMPRAS_PEDIDO`.
2. **Um dashboard** (FastAPI + React) que lê esse resultado, deixa o comprador montar e
   exportar pedidos por fornecedor, e deixa o **Diretor de Compras** decidir preço.

Quem usa: o **Diretor de Compras** (decisão de preço, tela de Alertas, celular pela rede
interna) e os **compradores por departamento** (ex.: Washington, Felipe — ver
`seed_fornecedor.csv`), que analisam a tela de Alertas/Monitoramento e montam pedidos.

### 0.2 A fronteira de acesso

```
CEDEP (WinThor)  --SELECT-->  dbt  --cria/atualiza-->  schema COMPRAS  <--le/escreve--  dashboard
   somente leitura                                     ^                                    |
   nunca escrito                                       +---------- APP_* -------------------+
```

O dbt é o único que enxerga o `CEDEP`, e só com `SELECT` (exceção nominal: `validar/`, que
lê os dois lados para comparar — nunca escreve). O dashboard só enxerga o schema
`COMPRAS`, e escreve exclusivamente nas tabelas `APP_*`; o dbt lê essas `APP_*` de volta
como `source` para fechar o ciclo. A frase que resume a consequência prática, e que
precisa estar na cabeça de quem mexe em qualquer uma das duas pontas:

> **Uma decisão gravada no dashboard só chega ao `fat_pedido` no próximo `dbt run`.** O
> dashboard mostra o que está gravado em `APP_*` direto, na hora; o modelo recalculado
> (e, com ele, alertas e indicadores derivados) só reflete essa decisão depois do
> próximo build.

Detalhe completo, com autorização de escrita e prefixos, em `§2` abaixo.

### 0.3 Como subir

**Desenvolvimento** — duas janelas de terminal, a partir da raiz do repositório
(`C:\Users\Administrator\Desktop\app_compras_v2`):

1. Duplo clique em **`teste.bat`**. Ele confere Python, dependências e `.env`, descobre o
   IPv4 da máquina (`IP_LAN`) e sobe `uvicorn app.main:app --host <IP_LAN> --port 8020
   --reload`. Fica em `http://<IP_LAN>:8020`.
   ⚠ **O `--host` é o IP da máquina (ex. `192.168.0.50`), nunca `0.0.0.0`**, por dois
   motivos: (a) o socket órfão de `0.0.0.0:8020` (§0.4) faz o bind em `0.0.0.0` falhar
   com `WinError 10048`; (b) o Diretor de Compras precisa abrir a tela **pelo celular**,
   na rede interna — acesso só por `127.0.0.1` não atende esse requisito.
2. Duplo clique em **`teste_front.bat`**. Confere `npm`/`node_modules`, sobe `npm run dev`
   (Vite) em `http://<IP_LAN>:5173`, com proxy de `/api` para `192.168.0.50:8020`.
3. Abra `http://<IP_LAN>:5173` no navegador (ou no celular, mesma rede) e faça login
   (§0.7).

Cada `.bat` fecha com `CTRL+C` (responda `S`) ou fechando a janela no X.

**Produção** — o desenho (ver `historico/PROMPT_ETAPA_14_MIGRACAO_REPOSITORIO.md §8`):
serviço NSSM `app_compras` rodando `uvicorn app.main:app --host 127.0.0.1 --port 8020`
(sem `--reload`), e nginx na porta 80 servindo o build estático de `npm run build`
(`app/static/v2/`) em `/`, com proxy de `/api/` para o uvicorn — endereço
`http://192.168.0.50/`. Scripts em `infra/` (`instalar_servico.ps1`,
`instalar_nginx.ps1`, `infra/nginx/compras.conf`, `infra/README.md` com a ordem e como
desfazer). **Enquanto o socket órfão existir (§0.4), o bind e o `proxy_pass` usam o IP
específico `192.168.0.50` em vez de `127.0.0.1`/`0.0.0.0`.**
⚠ Em 14/09/2026 esses scripts **ainda não foram escritos/instalados** neste repositório
— só existe `infra/agendar_atualizacao.ps1`. Ver §0.6 antes de assumir que a produção
está de pé.

### 0.4 O socket órfão

Desde **25/08/2026 08:34** existe um socket órfão escutando em `0.0.0.0:8020`. O processo
dono, **PID 2240, não existe mais** — mas o socket segue segurando a porta, sem responder
a nada.

Três consequências, todas medidas:

1. Subir qualquer coisa com `--host 0.0.0.0:8020` falha com `WinError 10048` (porta em
   uso), mesmo sem nenhum processo vivo nela.
2. Uma requisição a `127.0.0.1:8020` cai no órfão e fica pendurada até o timeout — parece
   o servidor travado, não é.
3. Os três contornos hoje em vigor por causa disso: `teste.bat` faz bind no IP da rede
   (`IP_LAN`) em vez de `0.0.0.0`; o proxy do Vite aponta para o IP da rede, não para
   `127.0.0.1`; e o desenho de produção (§0.3) usa `192.168.0.50` em vez de
   `127.0.0.1`/`0.0.0.0` enquanto o órfão existir.

Isso já mandou gente investigar "o servidor caiu" quando o servidor nunca tinha subido.
**A correção de verdade é reiniciar esta máquina** — o que também derruba outros serviços
de produção nela (`relatorio_compras` na 8010, e mais uvicorns em 8000/8001/8077/8100, de
outras áreas). Não é decisão a tomar sozinho; ver
`historico/PROMPT_ETAPA_14_MIGRACAO_REPOSITORIO.md §9.1` e §13 pergunta 1.

### 0.5 Onde cada coisa mora

| O quê | Caminho |
|---|---|
| Raiz do repositório | `C:\Users\Administrator\Desktop\app_compras_v2` |
| Convenções, fronteira de acesso, banco | `CONTEXTO.md` (este arquivo) |
| Regras de negócio, fiscal, alertas, decisões do Diretor | `REGRAS.md` |
| Fluxo dbt (models, seeds, tests) | `dbt/compras/` |
| Ambiente virtual do dbt (não versionado) | `dbt/env_server/` |
| Botão/agendador/`.bat` de atualização | `dbt/atualizar.py`, `dbt/rodar_dbt.bat` |
| API (FastAPI) — só `/api`, sem HTML | `app/main.py`, `app/api/`, `app/core/`, `app/servicos/` |
| Acesso ao Oracle (único ponto) | `app/core/database.py` |
| Autenticação, sessão, admin inicial | `app/core/auth.py` |
| Front (React + Vite) | `web/src/` — 11 telas em `web/src/telas/` |
| Configuração de produção (NSSM, nginx) | `infra/` — ver §0.3 |
| Gabaritos extraídos da planilha/PDF | `docs/` |
| Planilha e PDF originais | `referencia/` |
| Scripts de validação contra a planilha | `validar/` |
| `.env` (credenciais, fora do git) | raiz do repositório, copiado de `.env.exemplo` |
| Registro do que já foi decidido/medido e não é mais atual | `historico/` (não é fonte de verdade — ver `historico/README.md`) |

### 0.6 O que está no ar hoje

**Verificado em 14/09/2026.** O corte para produção deste repositório (`app_compras_v2`,
§0.3) **ainda não foi feito**: `Get-Service app_compras` não existe, e
`C:\nginx\conf\nginx.conf` só tem os vhosts `gestaosac.cdp.lub` e `dre.cdp.lub` — nenhuma
entrada para compras.

O que responde nas portas 8020/5173 agora é o **modo de desenvolvimento da pasta antiga**:
PID 2508 (`192.168.0.50:8020`) e PID 6912 (`0.0.0.0:5173`), ambos com linha de comando
apontando para `C:\Users\Administrator\Desktop\app_compras` (a pasta pré-migração, ainda
não congelada), não para este repositório. Isto é, **hoje ninguém está rodando o código
de `app_compras_v2`** — o repositório está pronto (dbt com `env_server`, front com
`node_modules`), mas ainda não foi colocado no ar. Antes de confiar que "o sistema já
está de pé", confira com `Get-CimInstance Win32_Process -Filter "ProcessId=<PID>" | select
CommandLine` de qual pasta o processo realmente veio.

### 0.7 O que fazer primeiro

1. **Banco:** a partir de `dbt/`, rode `rodar_dbt.bat` (chama `atualizar.py --origem
   manual`, que faz `dbt seed` + `dbt run` + `dbt test` nessa ordem). Leva **entre 158 e
   577 segundos, mediana ≈ 7 minutos** — não os "~70 s" que documentação antiga
   menciona; esse número envelheceu. Confira ao final: `FAT_PEDIDO` e `DIM_PRODUTO` com
   **8.841** linhas.
2. **`.env`:** se ainda não existir na raiz, copie de `.env.exemplo` e preencha
   `ORA_PASSWORD` (e confira `ORA_CLIENT_DIR`). Sem isso `config.validar()` recusa subir,
   de propósito.
3. **API:** duplo clique em `teste.bat` (raiz). Se `APP_USUARIO` estiver vazia, o
   `startup` cria o usuário `admin` com **senha aleatória**, impressa **uma única vez** no
   log do próprio terminal (`Usuario inicial criado: login=admin senha=...`). Copie essa
   senha dali — ela não aparece em nenhum outro lugar.
4. **Front:** duplo clique em `teste_front.bat` (raiz). Abre em `http://<IP_LAN>:5173`.
5. **Login:** entre com `admin` e a senha do passo 3. A troca de senha é obrigatória no
   primeiro acesso (`senha_provisoria=1`).

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
