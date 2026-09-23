# Etapa 16 — O ambiente de desenvolvimento não atualiza, e o botão que o atualizaria apontaria para produção

**Origem.** Usuário (suporte.ia1@cedeplub.com), 23/09/2026, pelo prompter, com print da tela
de Precificação servida pela instância de desenvolvimento.

**Base de código.** `ce180d0` (16/09/2026 13:35 — "Estoque na precificação, o preço aplicado
se apaga e o carrinho na aba", a Etapa 15). Produção e desenvolvimento estão **no mesmo
commit**; a única diferença versionável entre as duas árvores é um patch não commitado em
`dbt/compras/models/staging/sources.yml`, no branch local `fix-source-app-schema-por-target`
da pasta de dev.

**Isto muda número?** **Não.** Nenhuma fórmula, nenhum cálculo fiscal, nenhuma coluna de
`COMPRAS_PEDIDO` é tocada. O que muda é **quando** e **onde** o número é recalculado: a
instância de desenvolvimento passa a conseguir reconstruir o próprio schema, e passa a ser
impedida de reconstruir o de produção. As margens negativas do print são idênticas nos dois
schemas e **não são defeito** — ver §5.

---

## 1. O pedido, verbatim

> 1. *"faça uma revisão e verifique se o sistema em dev está replicando corretamente o em
>    produção. Após testar verifiquei que a base de dados dev não está atualizando."*

Do print, sem interpretação:

> 2. Faixa vermelha no topo: *"Não foi possível confirmar o início da atualização. Tente
>    novamente em instantes."*
> 3. Carimbo do cabeçalho, em âmbar: *"Sem atualização registrada"*.
> 4. Tela Precificação, `Status=Ativo`, `Estoque=Todos`, cenário `ST s/Valor`, ordenação
>    `Margem — pior primeiro`. Rodapé: **4.593 produto(s)**.
> 5. Margens do topo: −239,2% · −193,3% · −187,6% · −187,5% · −187,5% · −187,5% · −187,2% ·
>    −108,6% · −62,0% · −51,4% · −50,8% · −48,6% · −47,5%.
> 6. Os campos "NOVO PREÇO AT" e "NOVO PREÇO VAR" aparecem com o mesmo valor da coluna
>    "SUGERIDO" (410,58 / 31,43 / 52,40 …).

---

## 2. Os dois ambientes existem, e são dois schemas no mesmo banco

Medido em 23/09/2026 08:24 (relógio do banco).

| | Produção | Desenvolvimento |
|---|---|---|
| Pasta | `C:\Users\Administrator\Desktop\app_compras_v2` | `C:\Users\Administrator\Desktop\app_compras_v2_dev` |
| Commit | `ce180d0`, árvore limpa | `ce180d0`, branch `fix-source-app-schema-por-target`, 1 arquivo modificado |
| Usuário/schema Oracle | `compras` / `COMPRAS` | `compras_dev` / `COMPRAS_DEV` |
| Instância Oracle | `192.168.0.98:1521/WINT` | a mesma |
| API | serviço NSSM `app_compras`, `127.0.0.1:8020`, `Running` | `python -m uvicorn … 127.0.0.1:8021`, à mão |
| Front | build estático `app/static/v2`, servido pelo nginx (`compras.conf`) | Vite, `127.0.0.1:5174` |
| Como sobe | `infra\instalar_servico.ps1` + `infra\instalar_nginx.ps1` | `teste_dev.bat` |
| Tarefa Agendada do dbt | `CEDEP - app_compras - atualizar dados`, 06:00 e 13:00 | **nenhuma** |
| `dbt/env_server/` | existe (venv, Python 3.13.2, dbt 1.9.11) | **não existe** |

São de fato dois ambientes, e o isolamento é real: conectado como `compras_dev`, um
`select count(*) from COMPRAS.COMPRAS_PEDIDO` devolve **ORA-00942** — não há grant
cruzado. `~/.dbt/profiles.yml` tem três profiles: `compras` (alvos `dev` e `prod`, os dois
apontando para o schema `compras`) e `compras_dev` (alvo único `dev`, schema `compras_dev`).

Dois fatos que o executor precisa saber antes de encostar em qualquer arquivo:

- **`teste_dev.bat` não é versionado.** Está em `.git/info/exclude` da pasta de dev. Existe
  só nesta máquina, e some com ela.
- **O comentário de `~/.dbt/profiles.yml` mente.** Ele ainda afirma que *"não existe ainda
  um schema de desenvolvimento separado no servidor"*. O bloco `compras_dev:` logo abaixo
  desmente o comentário. `profiles.yml` **não é versionado** (está no `.gitignore`) e não é
  arquivo desta etapa — o registro de que o ambiente existe vai para o `infra/README.md`
  (§9.3) e, se a pergunta A for respondida com sim, para o `CONTEXTO.md §0`.

---

## 3. Defeito 1 — `dbt/env_server/` não existe em dev, e a falha é silenciosa

**É este o defeito que produziu os itens 2 e 3 do print.** Ele é a causa, não um sintoma.

O encadeamento, com arquivo e linha:

| Onde | O que acontece |
|---|---|
| `dbt/atualizar.py:67` | `DBT_EXE = <raiz>/dbt/env_server/Scripts/dbt.exe` |
| `dbt/atualizar.py:522-524` | `if not DBT_EXE.exists(): log.error(...); sys.exit(1)` — **antes** de inserir em `APP_ATUALIZACAO` |
| `app/servicos/atualizacao.py`, em `disparar()` | `subprocess.Popen([...], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)` |
| `app/api/rotas.py:120` | a rota devolve **202** assim que o `Popen` retorna — e o `Popen` retorna com sucesso, porque quem não existe é o `dbt.exe`, não o `python.exe` |
| `web/src/contexto/atualizacao.jsx`, `atualizar()` | 202 → estado otimista, `setTimeout(..., LIMITE_CONFIRMACAO_MS)` |
| `web/src/contexto/atualizacao.jsx:179` | 90s depois, sem confirmação: *"Não foi possível confirmar o início da atualização. Tente novamente em instantes."* |

O `log.error("dbt.exe não encontrado")` do processo filho é escrito no `stderr` do filho, e o
`stderr` do filho é `DEVNULL`. **A única mensagem que explicava o defeito foi jogada fora pelo
próprio código.** É por isso que o usuário viu um aviso genérico em vez da causa.

O item 3 do print é o mesmo defeito, visto pelo outro lado: **`COMPRAS_DEV.APP_ATUALIZACAO`
tem 0 linhas** (medido). Como o filho morre em `sys.exit(1)` antes do `insert`, nunca houve
linha nenhuma para o carimbo ler, e `web/src/componentes/Cabecalho.jsx:249` imprime
`"Sem atualização registrada"`. **O carimbo está certo e está dizendo a verdade.** Não é para
consertar o carimbo.

Para comparação, em `COMPRAS` a mesma tabela tem **23 linhas**, e a última é
`(564, 'AGENDADO', início 23/09/2026 06:00:00, fim 23/09/2026 06:06:06, 'CONCLUIDO')`.

---

## 4. Defeito 2 — o botão de dev, se achasse o `dbt.exe`, reconstruiria **produção**

Mais grave que o Defeito 1, e a razão pela qual **não se resolve o Defeito 1 apenas copiando
o `env_server` para a pasta de dev**.

Três fatos, cada um inofensivo sozinho:

1. `dbt/atualizar.py`, no `argparse`: `--target` tem `default="prod"`.
2. `dbt/atualizar.py`, em `rodar_dbt_fase()`: o comando montado é
   `[DBT_EXE, fase, "--target", target, "--no-use-colors"]` — **`--profile` nunca é passado**.
3. `dbt/compras/dbt_project.yml:5`: `profile: 'compras'`.

Somados: o botão "Atualizar agora" da instância de **dev** roda
`dbt seed/run/test --target prod` sob o profile `compras`, que resolve para o usuário
`compras` e o schema `compras` — **o schema de produção**.

E o registro mentiria com cara de acerto: `atualizar.py` grava em `APP_ATUALIZACAO` através de
`app/core/database.py`, que lê o `.env` **da pasta onde está rodando**. O `.env` de dev diz
`ORA_SCHEMA=COMPRAS_DEV`. Resultado do clique: **produção reconstruída, `CONCLUIDO` gravado em
`COMPRAS_DEV.APP_ATUALIZACAO`, e o carimbo de dev finalmente verde — mostrando números que
continuariam velhos.** A instância mediria a saúde de um build que aconteceu em outro schema.

A assimetria é exatamente esta: **o Oracle da aplicação vem do `.env`; o Oracle do dbt vem do
`dbt_project.yml` + `profiles.yml`.** Nada hoje obriga os dois a concordarem.

### A decisão de desenho

Duas mudanças, e a segunda é a que importa.

**(a) O profile e o target passam a vir do `.env`, como todo o resto da instância.**
`app/config.py` ganha `DBT_PROFILE = os.environ.get("DBT_PROFILE", "compras")` e
`DBT_TARGET = os.environ.get("DBT_TARGET", "prod")`; `atualizar.py` usa os dois como *default*
dos argumentos `--profile` (novo) e `--target` (existente), e passa `--profile` ao `dbt`. Os
defaults reproduzem o comportamento de hoje, então **o `.env` de produção não precisa mudar
uma linha** — mas ele vai mudar mesmo assim, por explicitude, e `.env.exemplo` documenta os
dois.

⚠ `app/config.py:25` usa `os.environ.setdefault` ao carregar o `.env`: variável de ambiente já
definida **vence** o `.env`. A Tarefa Agendada define `DBT_PROFILES_DIR` e nada mais, então
isto não muda nada hoje — mas quem for depurar precisa saber.

**(b) Uma trava que recusa o build quando os dois lados discordam.** É a parte que impede o
acidente, e ela não depende de ninguém preencher o `.env` direito. Antes da primeira fase do
dbt, `atualizar.py`:

- lê `profiles.yml` (`DBT_PROFILES_DIR`, que ele já resolve na linha 87) com `yaml.safe_load`;
- pega `outputs[<target>]['schema']` do profile escolhido;
- compara, em maiúsculas, com `config.ORA_SCHEMA`;
- se forem diferentes, **aborta com `sys.exit(1)` antes de qualquer `insert` ou fase de dbt**,
  com uma mensagem que nomeia os dois schemas — algo como
  `"Recusado: a aplicação escreve em COMPRAS_DEV e o dbt (profile=compras, target=prod) construiria COMPRAS. Ajuste DBT_PROFILE/DBT_TARGET no .env desta pasta."`

Por que a comparação com `ORA_SCHEMA` e não uma lista de pastas permitidas: o invariante
verdadeiro é *"o build tem de cair no mesmo schema em que esta instância registra que
buildou"*. Uma lista de pastas envelhece na terceira pasta; o invariante não envelhece.

`yaml` já está disponível — o dbt-core o traz. Se o import falhar, **aborte também**, com a
mesma gravidade: uma trava que se desliga sozinha quando não consegue verificar não é trava.

**(c) O `stderr` do filho para de ir para o lixo.** Em `app/servicos/atualizacao.py`,
`disparar()` passa a abrir `<raiz>/logs/atualizacao_disparo.log` em modo *append* e a usá-lo
como `stdout`/`stderr` do `Popen` (criando `logs/` se não existir — a pasta de dev não tem).
`DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP` e `close_fds=True` **ficam como estão**: o
desacoplamento do filho é a decisão da Etapa 12 e continua certa. O que muda é só o destino
dos dois descritores. `logs/*.log` já está no `.gitignore`.

Motivo, escrito no ponto: este diagnóstico custou uma sessão de medição porque a única
mensagem que apontava a causa foi descartada em `DEVNULL`. Um arquivo de log de disparo é a
diferença entre "o aviso apareceu de novo" e "o aviso apareceu e o log diz por quê".

---

## 5. Sobre o print — o que **não** é defeito

Cada item abaixo foi medido nos **dois** schemas. Nenhum deles abre trabalho.

### 5.1 As margens negativas (item 5 do print)

As 12 piores margens de atacado são **byte-idênticas** em `COMPRAS` e em `COMPRAS_DEV`:

| SKU | 8817 | 7973 | 1547 | 1455 | 1843 | 1689 | 1969 | 1999 | 2671 | 4943 | 699 | 5967 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Margem AT | −239,2 | −193,3 | −187,6 | −187,5 | −187,5 | −187,5 | −187,5 | −187,5 | −187,2 | −140,7 | −133,4 | −108,6 |

Contagens, iguais nos dois schemas:

| | `COMPRAS` | `COMPRAS_DEV` |
|---|---|---|
| `MKP_ATACADO < 1` | 1.358 | 1.358 |
| `MARGEM_ST_S_VALOR < 0` | 621 | 621 |
| idem, com `STATUS='Ativo'` | 335 e 246 | 335 e 246 |

Preço abaixo do custo em 335 SKUs ativos é um achado **de negócio**, não de ambiente, e já
estava em produção antes deste pedido. Vai para a pergunta B da §11. **Não é tarefa desta
etapa e ninguém deve "corrigir" cálculo por causa disto.**

### 5.2 Os quatro SKUs com a mesma margem

Medido, idêntico nos dois schemas:

| SKU | `CUSTO_ULT_ENT` | `CUSTO_TOT_S_VALOR` | razão | `PV_ATACADO` | `MKP_ATACADO` | Margem AT |
|---|---|---|---|---|---|---|
| 1547 | 25,87 | 34,98009463 | 1,35215 | 12,75 | 0,3644930 | −187,60% |
| 1689 | 44,14 | 59,68385686 | 1,35215 | 21,76 | 0,3645877 | −187,53% |
| 1843 | 39,82 | 53,84257318 | 1,35215 | 19,63 | 0,3645814 | −187,54% |
| 2671 | 6,99 | 9,45152151 | 1,35215 | 3,45 | 0,3650206 | −187,21% |

A razão `CUSTO_TOT_S_VALOR / CUSTO_ULT_ENT` é **1,35215 nos quatro** — é o multiplicador do
cenário ST s/Valor para a linha `RE ST BA MVA 71.78% C/PIS`, que os quatro compartilham. E
`CUSTO_ULT_ENT / PV_ATACADO` cai entre 2,026 e 2,029 nos quatro. Margem depende só da razão
preço/custo; razões iguais dão margens iguais. **Aritmética, não defeito.**

A hipótese de "o preço estar sendo derivado do custo" **está descartada por medição**: entre
os dois schemas, `CUSTO_ULT_ENT` e `CUSTO_TOT_S_VALOR` divergem em **0** SKUs enquanto
`PV_ATACADO` diverge em **6** (§6). Se o preço fosse função do custo, os dois teriam divergido
juntos.

### 5.3 "NOVO PREÇO AT/VAR preenchidos" (item 6 do print)

Não estão preenchidos. É o **`placeholder`**, e é deliberado:
`web/src/telas/Precificacao.jsx:796` —
`placeholder={!pendente && sim.sugerido != null ? numero(sim.sugerido, 2) : undefined}`.

O campo só **nasce com valor** quando há decisão em `APP_DECISAO_PRECO` ainda não aplicada no
WinThor (`Precificacao.jsx:634-638`). Em `COMPRAS_DEV`, `APP_DECISAO_PRECO` tem **0 linhas**
(medido) — nesta instância nenhum campo pode nascer preenchido. **Comportamento correto.
Não mexer.** Nascer com `PV_SUG_*` continua proibido (`CONTEXTO.md`, regra 10), e não é o que
está acontecendo.

### 5.4 Etapa 15 (item 4 do print)

A coluna Estoque e o filtro "Com estoque / Sem estoque" estão em dev porque dev está em
`ce180d0`, o mesmo commit de produção. Confirmado: `git log --oneline -1` devolve `ce180d0`
nas duas pastas. O rodapé de 4.593 também confere — `COMPRAS_PEDIDO.STATUS` tem
`'Ativo' = 4.593` e `'Inativo' = 4.282`, **nos dois schemas**.

---

## 6. Dev replica produção? Sim, com 40 horas de atraso — e isso é defasagem, não bug

`COMPRAS_DEV` foi construída **uma única vez**, à mão, em 22/09/2026. A sequência está no
`dbt.log` e no `run_results.json` da pasta de dev:

| Hora | Comando | Desfecho |
|---|---|---|
| 16:07:40 | `dbt seed --profile compras_dev --target dev` | ok |
| 16:08:02 | `dbt run --profile compras_dev --target dev` | **ORA-00942** em `stg_decisao_pedido` e `stg_decisao_preco` |
| ~16:13 | edição manual de `sources.yml` | o patch do branch `fix-source-app-schema-por-target` |
| 16:14:48 | `dbt run --profile compras_dev --target dev` | ok — as 8 tabelas `COMPRAS_*` nascem 22/09 16:16 |
| 16:17:41 | `dbt test --profile compras_dev --target dev` | `PASS=298 WARN=2 ERROR=0 SKIP=0 TOTAL=300` |

Repare no `--profile` na linha de comando: **é exatamente o argumento que `atualizar.py` não
passa** (§4). O ambiente só existe porque alguém o digitou à mão.

Desde então, nada. `user_objects.last_ddl_time` das 8 tabelas `COMPRAS_*`: **22/09 16:16** em
dev, **23/09 06:05** em produção. Defasagem no momento da medição (23/09 08:24): **~40 horas**.

Comparação linha a linha de `COMPRAS_PEDIDO` — 8.875 SKUs de cada lado, **0 só em um lado**:

| Coluna | SKUs que divergem | Exemplo |
|---|---|---|
| `CUSTO_ULT_ENT` | **0** | — |
| `CUSTO_TOT_S_VALOR` | **0** | — |
| `PV_ATACADO` | 6 | SKU 164: 721,40 (prod) × 745,90 (dev) |
| `PV_VAREJO` | 6 | SKU 164: 799,90 × 839,00 |
| `MKP_ATACADO` | 6 | SKU 164: 1,32136 × 1,36623 |
| `MARGEM_ST_S_VALOR` | 6 | SKU 164: 0,091615 × 0,117099 |
| `EST_DISP` | 400 | SKU 68: 11 × 12 |

Tudo o que diverge é coisa que se mexe no WinThor entre um build e outro: preço e estoque.
**Zero divergência em custo e em qualquer coluna de fórmula.** A lição do `REGRAS.md` se
aplica na íntegra: divergência que cresce com o relógio é defasagem, não bug.

### A parte de "replicar produção" que nunca vai fechar sozinha

| Coluna derivada de decisão | `COMPRAS` | `COMPRAS_DEV` |
|---|---|---|
| `PEDIDO` preenchido | 175 | **0** |
| `PEDIDO_UNIDADES` preenchido | 175 | **0** |
| `ALT_PV_AT_AV` não nulo | 134 | **0** |

Porque as `APP_*` de dev nasceram vazias na criação do schema: `APP_PEDIDO_ITEM` = 0,
`APP_DECISAO_PRECO` = 0, `APP_LOTE_PRECO` = 0 (produção: 194, 134, 3). Isto é **correto e
esperado** — decisão de compra e de preço é dado de gente, não do ERP, e não se copia de
produção para um ambiente de teste. Quem for comparar os dois ambientes precisa **excluir
essas colunas da comparação**, ou vai reportar 175 divergências que não são divergências.

---

## 7. Defeito 3 — nenhum script de `infra/` pode ser rodado da pasta de dev

Todos os scripts de `infra/` derivam `$ProjetoRaiz` de `$PSCommandPath` — ou seja, uma cópia
rodada a partir da pasta de dev **aponta para a pasta de dev**. Mas o nome do serviço, o nome
da tarefa e a porta são **constantes**, de produção:

| Arquivo | Constante | O que a cópia de dev faria |
|---|---|---|
| `infra/agendar_atualizacao.ps1:57` | `$TarefaNome = "CEDEP - app_compras - atualizar dados"` | `Unregister-ScheduledTask` na tarefa de **produção** e recria apontando para dev |
| `infra/publicar.ps1` | `$ServicoNome = "app_compras"` | build em dev, seguido de `Restart-Service` no serviço de **produção** |
| `infra/instalar_servico.ps1:46,49,124` | `$BIND="127.0.0.1"`, `$ServicoNome="app_compras"`, porta 8020 | `nssm remove` + reinstala o serviço de **produção** com `AppDirectory` de dev |
| `infra/instalar_nginx.ps1` / `desinstalar_nginx.ps1` | `compras.conf`, com `root` absoluto para `app_compras_v2` | mexe no `nginx.conf` compartilhado com `gestaosac.cdp.lub` e `dre.cdp.lub` |
| `infra/desinstalar_servico.ps1` | `app_compras` | derruba **produção** |

**Decisão: trava de raiz, sem escape.** Cada um dos seis scripts ganha, logo depois de
calcular `$ProjetoRaiz`, um bloco de quatro linhas com a constante
`$RaizProducao = "C:\Users\Administrator\Desktop\app_compras_v2"` e um `Exit 1` quando
`$ProjetoRaiz` não for essa pasta, explicando que estes scripts operam **só** a produção e
que dev sobe por `teste_dev.bat`.

O bloco é **repetido nos seis arquivos, não fatorado num `.ps1` comum**: o `infra/README.md`
diz que cada script se vale sozinho, e dot-source acrescenta uma dependência de ordem
justamente nos arquivos que precisam funcionar no pior dia. Quatro linhas repetidas seis
vezes custam menos que um arquivo comum que alguém esquece de copiar.

Comparar com `-eq` sobre os dois caminhos **normalizados** (`[IO.Path]::GetFullPath` e
`TrimEnd('\')`), não comparação crua de string — a barra final e a capitalização variam
conforme quem invocou o script.

---

## 8. Resumo — o que explica o quê

Ordenado por gravidade, com o efeito visível ao lado.

| # | Defeito | Gravidade | O que o usuário viu |
|---|---|---|---|
| 2 (§4) | `atualizar.py` roda `--target prod` sob o profile `compras`, independentemente da pasta | **crítica, latente** | nada ainda — e só porque o Defeito 1 o impediu |
| 1 (§3) | `dbt/env_server/` ausente em dev; `sys.exit(1)` com `stderr` em `DEVNULL` | alta | a faixa vermelha **e** o "Sem atualização registrada" |
| 3 (§7) | scripts de `infra/` com nome de serviço/tarefa chumbado | alta, latente | nada ainda |
| — (§6) | dev com 40h de defasagem | é **consequência** do Defeito 1, não defeito próprio | nada no print |
| — (§5) | margens negativas, 4 SKUs com margem igual, campos "preenchidos" | **não são defeito** | os itens 5 e 6 do print |

O Defeito 1 é o que o usuário viu. O Defeito 2 é o que ele teria visto se o Defeito 1 não
existisse, e é pior. **Resolver o 1 sem resolver o 2 é trocar um botão inoperante por um botão
que reconstrói produção a partir de dev.**

---

## 9. O trabalho, por agente

Nesta ordem. Cada agente lê **só** o que está listado.

### 9.1 `dbt-staging` — `model: haiku`

Commitar o patch que já está no disco.

- **Arquivo:** `dbt/compras/models/staging/sources.yml` (source `compras_app`, hoje
  `schema: "{{ target.schema }}"` no branch `fix-source-app-schema-por-target` da pasta de dev).
- **Trabalho:** aplicar a mesma mudança na pasta de produção e commitar. O comentário que já
  acompanha o patch está bom e fica.
- **Acrescentar ao comentário** uma linha só: o motivo medido — em 22/09/2026 16:08 o
  `dbt run` de dev falhou com `ORA-00942` em `stg_decisao_pedido` e `stg_decisao_preco`
  porque o `schema: compras` chumbado mandava um usuário sem grant ler as `APP_*` de outro
  schema.
- **Não faz diferença em produção, de propósito:** no profile `compras`, tanto o alvo `dev`
  quanto o `prod` têm `schema: compras`, então `{{ target.schema }}` resolve exatamente para
  o que estava escrito. Prove isso (critério de aceite 1), não afirme.
- **Não tocar** na source `cedep`: ela continua chumbada porque o ERP é o mesmo nos dois
  ambientes e é só leitura.
- **Ler:** este prompt §2 e §6; `dbt/compras/models/staging/sources.yml`.
- **Não ler:** `REGRAS.md` — nenhuma regra de negócio é tocada.

### 9.2 `backend-fastapi` — `model: sonnet`

O Defeito 2 e a parte (c) do Defeito 1. É o item mais importante da etapa.

- **`app/config.py`:** acrescentar `DBT_PROFILE` (default `"compras"`) e `DBT_TARGET`
  (default `"prod"`), no mesmo estilo das constantes vizinhas. Comentar que
  `_carregar_env()` usa `setdefault`, logo variável de ambiente já definida vence o `.env`.
- **`.env.exemplo`:** documentar as duas chaves novas, com os valores de produção como
  exemplo e uma linha dizendo qual par um ambiente isolado usaria.
- **`dbt/atualizar.py`:**
  - novo argumento `--profile`, com default `config.DBT_PROFILE`; `--target` passa a ter
    default `config.DBT_TARGET`;
  - `rodar_dbt_fase()` passa `--profile <profile>` além de `--target <target>`;
  - **a trava da §4(b)**, executada logo após a checagem de `DBT_EXE.exists()` e **antes** de
    `trava_exclusao`, de `inserir_inicio` e de qualquer fase: compara
    `profiles.yml → <profile>.outputs[<target>].schema` (upper) com `config.ORA_SCHEMA`
    (upper) e aborta com `sys.exit(1)` se diferirem, nomeando os dois schemas na mensagem;
  - falha ao ler ou parsear o `profiles.yml` também aborta — trava que se desliga sozinha não
    é trava;
  - atualizar a docstring do topo, que hoje diz *"Roda sequência seed → run → test com
    `--target PROD`"*.
- **`app/servicos/atualizacao.py`, `disparar()`:** `stdout` e `stderr` do `Popen` passam a
  apontar para `<config.BASE_DIR>/logs/atualizacao_disparo.log`, aberto em *append*, com
  `logs/` criado se não existir. **Manter** `DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP` e
  `close_fds=True`. **Manter** o 202 sem espera e o contrato de que quem grava em
  `APP_ATUALIZACAO` é o filho, do começo ao fim.
- **Não mexer:** em `_LIMITE_EXECUCAO_MORTA_MIN`, `_LIMITE_LIBERAR_BOTAO_MIN`,
  `_LIMITE_RELIBERACAO_MIN`, nem em `LIMITE_CONFIRMACAO_MS` no front. Os 90s do aviso são o
  desenho certo; eles apareceram porque a atualização de fato não começou.
- **Não mexer** em `app/api/rotas.py`: a rota está correta.
- **Ler:** este prompt §3 e §4; `dbt/atualizar.py`; `app/servicos/atualizacao.py`;
  `app/config.py`; `CONTEXTO.md §0.2`.
- **Não ler:** `REGRAS.md`; `web/` inteiro — esta etapa não muda uma linha de front.

### 9.3 `infra-windows` — `model: sonnet` (e não o haiku de nascença)

Sonnet porque o trabalho é escrever a trava que impede um script de derrubar produção; o
risco não está na sintaxe do PowerShell, está em acertar qual caminho é qual.

1. **`infra/instalar_dbt.ps1`** (novo). Cria o venv do dbt da **própria árvore**:
   `python -m venv <ProjetoRaiz>\dbt\env_server` seguido de
   `<...>\env_server\Scripts\pip install -r <ProjetoRaiz>\dbt\compras\requirements.txt`.
   Deriva tudo de `$PSCommandPath`; **não recebe caminho por parâmetro** e **não leva a trava
   de raiz da §7** — este é o único script de `infra/` que deve rodar em qualquer árvore, e é
   assim porque ele não toca em serviço, tarefa nem nginx. Diz isso num comentário no topo.
   Recusa-se a rodar se `env_server` já existir, mandando apagar à mão primeiro.
   Referência: produção usa Python 3.13.2 e dbt 1.9.11 (`dbt/env_server/pyvenv.cfg`).
2. **A trava de raiz da §7** nos seis: `instalar_servico.ps1`, `desinstalar_servico.ps1`,
   `instalar_nginx.ps1`, `desinstalar_nginx.ps1`, `agendar_atualizacao.ps1`, `publicar.ps1`.
3. **`infra/README.md`:** uma seção curta com (a) a tabela de §2 reduzida a produção × dev,
   (b) o passo `instalar_dbt.ps1` num ambiente novo, (c) a frase de que os demais scripts
   recusam rodar fora de `app_compras_v2`, (d) que `teste_dev.bat` não é versionado.
4. **Criar o `env_server` da pasta de dev** rodando `infra\instalar_dbt.ps1` a partir de
   `app_compras_v2_dev`.

- **Não criar** Tarefa Agendada para dev. Dev atualiza quando alguém pede; agendamento
  automático em dev só acrescenta carga no mesmo Oracle da produção sem ninguém olhando o
  resultado. Se isso for desejado, é outra etapa e o nome da tarefa tem de mudar.
- **Não tocar** em `C:\nginx\conf\nginx.conf` nem em `infra/nginx/compras.conf`. Dev não passa
  pelo nginx e o `nginx.conf` desta máquina serve `gestaosac.cdp.lub` e `dre.cdp.lub`.
- **Não rodar** `publicar.ps1`: esta etapa não muda `web/`, e rodá-lo da pasta errada é
  exatamente o acidente que a trava previne.
- **Ler:** este prompt §2, §3 e §7; `infra/README.md`; os seis `.ps1`;
  `dbt/compras/requirements.txt`; `dbt/env_server/pyvenv.cfg`.
- **Não ler:** `REGRAS.md`; `dbt/compras/models/`.

### 9.4 `validador` — `model: sonnet`

Um comparador dos dois ambientes, que sirva agora e no próximo susto.

- **Arquivo novo:** `validar/comparar_ambientes.py`, no estilo de `validar/validar_pedido.py`
  (inclusive `_ler_credencial_compras`, que já lê o `profiles.yml`).
- **Faz:** conecta nos dois schemas com os profiles `compras` e `compras_dev`, compara
  `COMPRAS_PEDIDO` SKU a SKU e reporta, por coluna, quantos divergem e um exemplo.
- **Separa o relatório em três blocos, e é isto que dá valor ao script:**
  1. **colunas de fórmula/custo** — divergência aqui é **defeito**, e o esperado é zero;
  2. **colunas que vêm vivas do WinThor** (`PV_ATACADO`, `PV_VAREJO`, `EST_DISP` e derivadas
     `MKP_*`/`MARGEM_*`) — divergência aqui é **defasagem**, e o relatório imprime junto a
     diferença de `last_ddl_time` entre os dois schemas, em horas, para o leitor atribuir;
  3. **colunas derivadas de `APP_*`** (`PEDIDO`, `PEDIDO_UNIDADES`, `PEDIDO_NA_MEDIDA`,
     `ALT_PV_*`) — **excluídas da comparação**, com a contagem dos dois lados impressa e a
     nota de que dev nasce sem decisões (§6).
- **Só `SELECT`.** Nada de escrita em nenhum dos dois schemas.
- **O script é exercitado com defeito injetado antes de valer** (armadilha 15): rode-o uma vez
  colocando `EST_DISP` no bloco 1 e confirme que ele acusa as ~400 divergências como defeito;
  devolva a coluna ao bloco 2 e confirme que elas voltam a ser reportadas como defasagem. Um
  comparador que nunca acusou nada não prova que os ambientes batem.
- **Números de referência desta medição (23/09/2026 08:24), para conferir a primeira
  rodada — e para recontar, não repetir**: 8.875 SKUs de cada lado, 0 exclusivos;
  `CUSTO_ULT_ENT` e `CUSTO_TOT_S_VALOR` com 0 divergências; `PV_ATACADO`, `PV_VAREJO`,
  `MKP_ATACADO` e `MARGEM_ST_S_VALOR` com 6; `EST_DISP` com 400.
- **Ler:** este prompt §5 e §6; `validar/validar_pedido.py`; `CONTEXTO.md §0.2` e a regra 6.
- **Ler de `REGRAS.md`: nada.** Nenhum cálculo é revisto aqui. Se o comparador acusar
  divergência no bloco 1, isso vira outra etapa, com `dbt-regras`.

### 9.5 `revisor` — `model: opus`, sempre o último

Opus, apesar de a etapa não ter cálculo fiscal: o raio de alcance de um erro aqui é o schema
de produção inteiro.

Revisar, sem alterar:

1. que a trava de §4(b) **realmente** roda antes de `inserir_inicio` e antes da primeira fase
   — uma trava que dispara depois do `insert` deixa lixo em `APP_ATUALIZACAO`;
2. que `--profile` é passado nas **três** fases (`seed`, `run`, `test`), não só no `run`;
3. que nenhum default novo mudou o comportamento de produção;
4. que os seis `.ps1` têm a trava e que `instalar_dbt.ps1`, deliberadamente, não tem — e que o
   comentário explica o porquê;
5. que `disparar()` continua desacoplado (`DETACHED_PROCESS`), ou seja, que o arquivo de log
   não reacoplou o filho à vida do uvicorn;
6. que nada em `web/` foi tocado, e que `sources.yml` é a única mudança em `dbt/compras/`.

- **Ler:** este prompt inteiro; o diff da etapa.

---

## 10. Quem não entra

| Agente | Por quê |
|---|---|
| `oracle-dba` | `COMPRAS_DEV` já existe, com as `APP_*` de `sql/01`–`06` criadas em 22/09 13:51, com os grants de leitura no CEDEP (o build de 22/09 16:14 passou) e **sem** grant cruzado para `COMPRAS` (ORA-00942 medido). Não falta DDL nenhum. |
| `dbt-regras` | Nenhuma fórmula muda. As margens de §5 são **idênticas** nos dois schemas e vêm de antes deste pedido. Convocá-lo aqui é convidar a "consertar" o que está certo. |
| `dbt-relatorios` | Nenhum dos dois relatórios é tocado. |
| `frontend-react` | **Nenhuma linha de `web/`.** A faixa de erro e o carimbo âmbar estão **certos** — os dois estavam relatando com precisão uma atualização que nunca começou. O `placeholder` de §5.3 também está certo. Como `web/` não muda, a armadilha 16 (build/`publicar.ps1`) não se aplica a esta etapa, e `publicar.ps1` **não deve ser rodado**. |

---

## 11. Perguntas — só as que o executor não pode responder

**A.** O ambiente de desenvolvimento deve ser **versionado** — `.env.exemplo` com um bloco de
dev, `teste_dev.bat` commitado, uma seção em `CONTEXTO.md §0` — ou continua sendo um arranjo
desta máquina? Hoje `teste_dev.bat` está em `.git/info/exclude` e some com a máquina. Isto
muda o escopo da §9.3 (item 3) e é decisão de processo, não técnica.

**B.** 335 SKUs **ativos** estão com preço de atacado abaixo do custo (`MKP_ATACADO < 1`), e
246 com margem negativa — em **produção**, medido hoje, e de antes deste pedido. Isso é
conhecido e aceito pelo Diretor de Compras, ou é achado novo que merece uma etapa própria? Os
quatro SKUs de §5.2 estão com o preço de atacado em ~metade do último custo de entrada, todos
na mesma linha de tributação.

**C.** Dev deve ganhar um agendamento próprio depois desta etapa? A §9.3 decidiu que **não**
(dev atualiza sob demanda), porque dois agendamentos disparam dois builds contra o mesmo
Oracle sem ninguém conferindo o de dev. Se a resposta for sim, o nome da tarefa precisa deixar
de ser `CEDEP - app_compras - atualizar dados`.

---

## 12. Aceite

1. **O patch de `sources.yml` não muda produção.** `dbt compile --profile compras --target prod
   --select stg_decisao_pedido stg_decisao_preco` antes e depois do commit, com o SQL compilado
   dos dois models idêntico byte a byte nas duas vezes. Cole o `diff` vazio.
2. **A trava de §4(b) recusa o caso do Defeito 2.** Com a pasta de dev e um `.env` apontando
   para `DBT_PROFILE=compras` / `DBT_TARGET=prod`, `python dbt\atualizar.py --origem manual
   --por teste` sai com código 1, imprime uma mensagem que nomeia `COMPRAS_DEV` e `COMPRAS`,
   e **`COMPRAS_DEV.APP_ATUALIZACAO` continua com o mesmo número de linhas de antes da
   tentativa** (o `insert` não aconteceu). Cole a mensagem e as duas contagens.
3. **A trava deixa passar o caso legítimo.** Com o `.env` de dev correto
   (`DBT_PROFILE=compras_dev`, `DBT_TARGET=dev`), o mesmo comando roda as três fases e grava
   uma linha em `COMPRAS_DEV.APP_ATUALIZACAO` com `status` em (`CONCLUIDO`,
   `CONCLUIDO_COM_AVISO`). Cole a linha, com `inicio`, `fim` e `status`.
4. **Produção segue intocada pelo item 3.** `select max(last_ddl_time) from all_objects where
   owner='COMPRAS' and object_name like 'COMPRAS!_%' escape '!'` — o mesmo carimbo antes e
   depois do aceite 3. Cole os dois valores.
5. **O carimbo de dev deixa de dizer "Sem atualização registrada".** Depois do aceite 3,
   `GET /api/atualizacao` na instância de dev devolve `emAndamento: false` e um `fim`
   preenchido. Cole o JSON.
6. **O botão volta a funcionar de ponta a ponta em dev.** Clique em "Atualizar agora" na
   instância de dev; a faixa vermelha de 90s **não** aparece e o carimbo passa por
   "Atualizando…" antes de mostrar a data. Descreva a sequência observada e cole as linhas
   correspondentes de `logs/atualizacao_disparo.log`.
7. **O log de disparo captura a falha, que era o ponto.** Renomeie temporariamente
   `dbt\env_server\Scripts\dbt.exe` na pasta de dev, clique no botão, e mostre que
   `logs/atualizacao_disparo.log` contém `dbt.exe não encontrado` com o caminho. Restaure o
   nome. Este é o defeito injetado que prova o item (c) da §4.
8. **As seis travas de raiz disparam.** Rodar cada um dos seis `.ps1` a partir de
   `app_compras_v2_dev` termina em `Exit 1` **sem** ter tocado em serviço, tarefa ou nginx.
   Prove com o estado depois: `Get-Service app_compras` em `Running`,
   `(Get-ScheduledTask 'CEDEP - app_compras - atualizar dados').Actions.WorkingDirectory`
   ainda em `C:\Users\Administrator\Desktop\app_compras_v2`, e `nginx -t` passando.
9. **`instalar_dbt.ps1` funciona na árvore de dev.**
   `app_compras_v2_dev\dbt\env_server\Scripts\dbt.exe --version` responde `1.9.x`.
10. **O comparador acusa antes de absolver.** Cole as duas rodadas do aceite da §9.4: a com
    `EST_DISP` no bloco de fórmula (acusa ~400 como defeito) e a com ele no bloco de
    defasagem (reporta como defasagem, com as horas de diferença de `last_ddl_time`).
11. **Depois de dev e produção rodarem no mesmo dia, o bloco de fórmula fecha em zero.**
    `comparar_ambientes.py` com 0 divergências no bloco 1. Divergência residual em preço,
    estoque e `MKP`/`MARGEM` é **aceitável e esperada** (os builds não são simultâneos) —
    o critério é sobre o bloco 1, não sobre zero absoluto.
12. **Nada em `web/` mudou.** `git diff --stat` da etapa sem nenhum arquivo sob `web/`, e
    `publicar.ps1` não foi executado.
