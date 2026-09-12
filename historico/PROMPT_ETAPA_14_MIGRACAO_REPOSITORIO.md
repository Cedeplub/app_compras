# Etapa 14 — Repositório novo `app_compras_v2`, schema revisto e subida em produção

> **Prompt de execução.** Origem: mensagem do usuário no prompter em 11/09/2026, e as
> respostas dele em 12/09/2026 — que mudaram a premissa e ampliaram o escopo.
>
> Base: o código como ele está **neste disco** em 12/09/2026, não o que está no GitHub (§3.1).
>
> **Esta etapa muda número, e de propósito.** Ela zera as tabelas `APP_*`, mata uma delas,
> religa um model do dbt e troca duas janelas de terminal por um serviço. O que ela **não**
> pode mudar é a regra: as 11 regras de negócio, as decisões do Diretor e as divergências
> deliberadas da planilha atravessam inteiras, e há teste para provar.

---

## 1. O pedido, verbatim

Primeira mensagem, 11/09:

1. *"quero fazer uma migração para uma nova pasta/repositório"*
2. *"A pasta já ficou muito bagunçada com muitos documentos que foram gerados ao longo do
   projeto"*
3. *"Quero que seja feito uma migração para o repositorio/pasta app_compras_v2"*
4. *"Deve ser levado para lá apenas os códigos/scripts/arquivos que são necessários para
   manter o que já existe no ar, ou seja, a versão 2 (v2)"*

Respostas de 12/09, que redefinem a etapa:

5. **GitHub:** *"Migrar local agora, origin depois."*
6. **Escopo:** *"a migração realmente é pra ser feita do zero, até os dados que estão nas
   tabelas (que se mantém no oracle) podem ser apagados e as tabelas podem ser até revistas
   para fazer uma migration para essa nova versão. No momento não me importo com histórico
   de código, desde que o novo repositório tenha o necessário para realizar o que já é feito
   hoje. Além disso, Quero uma documentação de regras de negócios que foram decididas até
   aqui e uma outra documentação que seja um ponto de partida para quando seja iniciado uma
   sessão do zero que vá trabalhar com esse projeto ou para outro desenvolvedor utilizar
   também como base/referencia para continuidade do processo."*
7. **Pasta antiga:** renomear para `_app_compras_congelado_20260912`, guardar 30 dias no
   Desktop.
8. **Produção:** *"outro ponto, já criar no repositório da migração as configurações de NSSM
   e nginx para subir pro ar"*

O item 6 é a etapa inteira. O item 8 puxa a Etapa 11 do `PLANO.md` para dentro dela.

---

## 2. O que a resposta 6 derruba, e o que entra no lugar

| Antes | Agora | Consequência |
|---|---|---|
| Cópia da pasta com o `.git` dentro | **Repositório novo, `git init`, um commit inicial** | O histórico de 23 commits não atravessa. **A pasta congelada passa a ser a única cópia dele que existe** — ver §2.1 |
| Carregar os `.md` citados de dentro do código | **Reescrever** os documentos e ajustar quem os cita | §6 |
| Não tocar no schema | **Migration:** uma tabela morre, o resto é recriado vazio | §5 |
| Dashboard v1 migra intacto | **v1 não vai** — a decisão do §5.3 resolve a pergunta que ficou sem resposta | §5.3, §7.2 |
| Produção fica para a Etapa 11 | **Produção é parte desta etapa**, com NSSM e nginx versionados | §8 |

### 2.1 ⚠ O risco mudou de natureza, não de tamanho

Medido em 12/09/2026:

```
git rev-list --left-right --count main...origin/main   ->  4   0
git log -1 --format="%h %ad" origin/main               ->  bc7018a  2026-09-02 17:15
```

| O que | Quanto |
|---|---|
| Commits locais **nunca enviados** ao GitHub | **4** (`6ce75c2`, `c0495f4`, `0df396e`, `b735f1c`) |
| Arquivos modificados e **não commitados** | **21** — 1.037 inserções, 334 remoções |
| Arquivos **novos, não rastreados** | **6** |

O `origin/main` parou em **02/09/2026**. As Etapas 10, 11 e 12, o carimbo de atualização e a
Etapa 13 em voo existem **só neste disco**.

Como o histórico foi dispensado, o risco não é mais perder `git log` — é **perder conteúdo**.
Duas consequências que precisam estar escritas com todas as letras:

1. **O commit inicial do repositório novo contém o estado de trabalho de hoje, Etapa 13
   inclusa — não o conteúdo do último commit.** Copiar "o que está commitado" descartaria
   1.037 linhas em 21 arquivos e os 6 arquivos não rastreados. Copia-se o **working tree**.
2. **A pasta congelada é a única cópia do histórico que sobra.** Ela deixa de ser um
   backup de conveniência e passa a ser o arquivo morto do projeto. Por isso ela é
   renomeada, nunca apagada, e o `.git` dentro dela fica intacto.

Os 6 não rastreados, nominalmente — confira que os seis chegaram:

```
CADASTRO_DIVERGENCIAS.md
v2/PROMPT_ETAPA_13_NAVEGACAO_E_TABELAS.md
validar/validar_grafico_produto.py
validar/validar_ordenacao_paginada.py
web/src/componentes/CabecalhoOrdenavel.jsx
web/src/contexto/carrinho.jsx
```

---

## 3. O estado de hoje, medido em 11–12/09/2026

### 3.1 O que mantém o sistema no ar são duas janelas de terminal

| Porta | PID | Linha de comando |
|---|---|---|
| `192.168.0.50:8020` | 2508 | `python -m uvicorn app.main:app --host 192.168.0.50 --port 8020 --reload` |
| `0.0.0.0:5173` | 6912 | `node ...\app_compras\web\node_modules\.bin\..\vite\bin\vite.js` |
| `0.0.0.0:8010` | 2384 | `relatorio_compras`, **outro projeto, em produção — não encoste** |
| `0.0.0.0:80` | 11364 | nginx |

**Não existe serviço NSSM nem regra de nginx para este projeto.** `Get-Service` devolve
`Nginx` e `relatorio_compras`. `C:\nginx\conf\nginx.conf` tem dois `server` de nome
(`gestaosac.cdp.lub` → 8001, `dre.cdp.lub` → 8000 e 3000) e nenhuma menção a 8020. É isso
que o §8 substitui.

### 3.2 As contagens do schema `COMPRAS`

**O que o `dbt run` reconstrói** — zerar custa tempo de build, não perda:

| Tabela | Linhas | Tabela | Linhas |
|---|---|---|---|
| `FAT_PEDIDO` | 8.841 | `COMPRAS_MONITORAMENTO` | 337.540 |
| `FAT_ALERTA` | 8.058 | `COMPRAS_VENDA_MENSAL` | 81.397 |
| `DIM_PRODUTO` | 8.841 | `COMPRAS_ENTRADA` | 11.941 |
| `DIM_FORNECEDOR` | 61 | `COMPRAS_PEDIDO` | 8.841 |
| `DIM_TRIBUTACAO` | 15 | `COMPRAS_ALERTA` | 8.058 |

São **8.841 SKUs**, não os 8.772 que os `.md` de agosto repetem. Use 8.841.

**O custo do rebuild, medido nas 14 execuções registradas em `APP_ATUALIZACAO`:** de
**158 s a 577 s**, mediana **≈ 417 s (7 minutos)**. Não são os "~70 s" que a documentação
do projeto repete — esse número envelheceu. Sete minutos é o preço de zerar tudo.

**O que se perde ao zerar as `APP_*`** — listado para ninguém ser surpreendido:

| Tabela | Linhas | O que some | Dói? |
|---|---|---|---|
| `APP_USUARIO` | 2 | `admin` e `comprador_teste` | Não. `auth.garantir_admin_inicial()` recria o `admin` no startup, com senha provisória |
| `APP_SESSAO` | 3 | As 3 sessões vivas | **Sim, um pouco:** todo mundo é deslogado. A sessão é token opaco em banco |
| `APP_AUDITORIA` | 139 | A trilha de 24/08 a 11/09, 17 ações distintas | Não. É trilha de teste do `admin` |
| `APP_ATUALIZACAO` | 14 | O histórico de duração do dbt | Não, **desde que as durações do parágrafo acima estejam no documento novo** — e estão |
| `APP_DECISAO_PRECO` | 4 | 4 preços decididos por `admin` | Não. Teste |
| `APP_DECISAO_PRECO_HIST` | **0** | nada | Ver §5.2 |
| `APP_DECISAO_PEDIDO` | 4 | 4 pedidos digitados por `admin` em **25/08** | Não. §5.3 |
| `APP_PEDIDO` / `_ITEM` / `_STATUS_HIST` | 4 / 66 / 4 | 4 pedidos, todos em **Rascunho** (PETROBRAS, TECFIL, YPF, VALVOLINE), criados por `admin` | Não. Teste |
| `APP_LOTE_PRECO` / `_ITEM` / `_STATUS_HIST` | 1 / 2 / 2 | 1 lote em "Enviado", de `admin` | Não. Teste |

**Nenhuma linha de `APP_*` foi escrita por alguém que não seja `admin` ou
`comprador_teste`.** Não há decisão de comprador real no banco. É o que autoriza zerar sem
plano de resgate.

### 3.3 As 9 seeds carregam decisão do Diretor — elas não se perdem

As seeds vão como CSV, exatamente como estão, e são **o artefato mais valioso que não é
código** deste projeto: elas guardam o valor decidido **e o motivo, na própria linha**.

```
MARGEM_ALTA_MIN;0.25;S;... decisao do Diretor de Compras em 02/09/2026,
                          corte subido de 0,20 para 0,25 na 2a rodada
MARGEM_ALTA_MIN_VAREJO;0.5;S;... limiar PROPOSITALMENTE maior que o do atacado ...
                          corte subido de 0,45 para 0,50 na 2a rodada
COBERTURA_ALVO_PADRAO;2;S;... hoje ADIBRAX, ROBUST e TODOS OS DEPARTAMENTOS
OPORTUNIDADE_GIRO_MESES;3;S;... decisao do Diretor de Compras em 02/09/2026 ...
```

`seed_fornecedor.csv` carrega `COMPRADOR` por departamento — WASHINGTON, FELIPE e os
demais, a decisão do item 8 da 1ª rodada (5.932 SKUs para Washington).

⚠ **`dbt run` não roda `dbt seed`.** Na base limpa, o `dbt seed` é obrigatório e vem
**antes** — `rodar_dbt.bat` já faz a sequência certa; rodar `dbt run` direto deixa os
models apontando para tabelas de seed que não existem.

---

## 4. O inventário, sob o critério "do zero"

A medição anterior continua valendo como fato — 7 dos 9 `.md` da raiz são citados de dentro
de SQL de model, de `validar/*.py` ou dos 9 agentes. O que muda é a conclusão: agora é
legítimo **reescrever** o que é citado, em vez de carregar o arquivo velho.

### 4.1 Código: vai inteiro

| Caminho | Observação |
|---|---|
| `app/` **menos o v1** | §7.2 lista o que fica para trás |
| `web/` (sem `node_modules`) | As 11 telas, `vite.config.js`, `tailwind.config.js`, `package-lock.json` |
| `dbt/compras/` (sem `target/` e `logs/`) | Com os dois ajustes do §5.3 |
| `dbt/atualizar.py`, `dbt/rodar_dbt.bat` | Caminho único de atualização — botão, agendador e `.bat` chamam o mesmo Python |
| `validar/` (7 scripts) | `validar_pedido.py` **lê** `docs/gabarito_pedido_formulas.txt` em execução |
| `docs/` menos o `.bak` | Não é documentação solta: o gabarito é **entrada de código** |
| `referencia/` | `validar_pedido.py:192` e `validar_intermediaria.py:79` apontam para os `.xlsx` daqui |
| `teste.bat`, `teste_front.bat` | Continuam sendo o modo de desenvolvimento. Produção é o §8 |
| `requirements.txt`, `.gitignore`, `.env.exemplo` | — |
| `v2/prototipo/` | `PROTOTIPO.md` é citado por toda tarefa de tela |

### 4.2 Não atravessa — refeito no destino, não copiado

| Caminho | Tamanho | Por quê | O que fazer |
|---|---|---|---|
| `dbt/env_server/` | **133 MB** | Venv com caminho absoluto chumbado: `Scripts/activate.bat:11` diz `VIRTUAL_ENV=C:\Users\Administrator\Desktop\app_compras\dbt\env_server`, e cada `Scripts/*.py` tem shebang absoluto (`daff.py:1`) | `python -m venv env_server` + `env_server\Scripts\python -m pip install -r compras\requirements.txt` |
| `web/node_modules/` | **~100 MB** | Shims de `.bin` com caminho absoluto | `npm ci` — **`ci`, não `install`**: `install` sobe versão dentro dos `^` e mudaria o front numa etapa que não é para mudar front (armadilha 13) |
| `dbt/compras/target/` | 7,3 MB | Artefato de compilação | nasce no primeiro `dbt run` |
| `dbt/compras/logs/`, `dbt/logs_execucao/` | **26 MB**, 23 arquivos | Log de execução | nada |
| `dbt/.atualizacao.lock` | — | Trava. Copiada, faz o destino recusar a primeira atualização | nada |
| `**/__pycache__/`, `.impeccable/` | — | Bytecode e cache de ferramenta com caminhos antigos | nada |
| `app/static/v2/` | build de 08/09 | Bundle velho, e hoje **inalcançável** — §8.3 | `npm run build` |
| `.git/` | 3,3 MB | Histórico dispensado pelo usuário. Fica na pasta congelada | `git init` no destino |

### 4.3 Vai, e **não está no git** — cópia à mão, ou o destino sobe quebrado

| Arquivo | Sem ele |
|---|---|
| `.env` (365 bytes) | `config.validar()` lista o que falta e `main.py` **recusa subir**, de propósito |
| `referencia/MODELO_COMPRAS_CEDEP_v11.xlsx` (25 MB) | `validar_pedido.py` não roda: é o gabarito de 122 colunas |
| `referencia/MODELO_COMPRAS_CEDEP_v10.xlsx` (25 MB) | `validar_intermediaria.py` frente 2 não roda |
| `.claude/settings.local.json` | Atrito, não quebra |

### 4.4 Documentos: veredicto por arquivo

| Arquivo | Destino | Motivo |
|---|---|---|
| `CONTEXTO.md` | **reescrito** — vira o documento 2 do §6 | Citado por ~80 arquivos **pelo nome e pelo número da seção** (`validar_pedido.py:6` cita `§6.2` e `§6.3`) |
| `REGRAS.md` | **reescrito** — vira o documento 1 do §6 | Citado pelos 9 agentes e por `compras_entrada_exclui_devolucao_transferencia.sql` |
| `MELHORIAS.md` | **absorvido** pelo novo `REGRAS.md`; deixa de existir | Citado por 7 models, 1 macro, 1 test e `validar_pedido.py` — todos passam a citar `REGRAS.md §<seção>` |
| `PENDENCIAS_DIRETORIA.md` | **absorvido**; deixa de existir | Citado por 8 models e 2 tests — mesma troca |
| `CADASTRO_DIVERGENCIAS.md` | **absorvido**; deixa de existir | Citado só pelo prompt da Etapa 13 |
| `v2/DECISOES_DIRETOR.md` | **absorvido**; deixa de existir | As duas rodadas entram no `REGRAS.md` **com o valor que ficou valendo**, não com a discussão |
| `README.md` | **capa nova, ~20 linhas**, apontando para os dois | Porta de entrada do repositório |
| `STATUS.md` | `historico/STATUS_20260826.md` | Data 26/08, descreve "pausado" e uma fila já executada |
| `VISAO_GERAL.md` | `historico/VISAO_GERAL_20260828.md` | Citado por **ninguém**. Tem o caminho antigo na linha 11 |
| `v2/PLANO.md` | `historico/PLANO_v2_20260901.md` | Descreve etapas já feitas; o §6 do PLANO (socket órfão) migra para o `CONTEXTO.md` novo |
| `v2/PROMPT_ETAPA_12`, `v2/PROMPT_ETAPA_13`, este arquivo | `historico/` | Prompt executado é registro, não referência |
| `v2/prototipo/*` | `v2/prototipo/` | Continua sendo referência viva de tela |
| `docs/gabarito_pedido_formulas_v10.txt.bak` | `historico/` | `.bak` da v10, substituída pela v11 |
| `test_porta.bat` | **não vai** | Script descartável da Etapa 6, citado por ninguém |

`historico/` nasce com um `README.md` de três linhas: *nada aqui é fonte de verdade; está
aqui porque explica por que alguma coisa é como é. O que vale está em `CONTEXTO.md`,
`REGRAS.md` e no código.* Fica **dentro** do repositório novo: documento que sai do
repositório é documento que ninguém abre outra vez.

### 4.5 Os 9 agentes vão, e vão **editados**

`.claude/agents/` tem 10 arquivos. Todos os 9 ativos citam `CONTEXTO.md` **e** `REGRAS.md`;
`frontend-react.md` cita também `PLANO.md` e `PROTOTIPO.md`; `backend-fastapi.md` cita
`MELHORIAS.md`.

| Arquivo | Ação |
|---|---|
| `backend-fastapi.md` | trocar `MELHORIAS.md` por `REGRAS.md §<divergências>` |
| `frontend-react.md` | trocar `v2/PLANO.md` por `CONTEXTO.md §0`; `PROTOTIPO.md` continua |
| `infra-windows.md` | linha 41 descreve o NSSM como plano; passa a descrever o serviço **que existe** (§8) |
| `dbt-regras`, `dbt-relatorios`, `dbt-staging`, `oracle-dba`, `validador`, `revisor` | só conferir que `CONTEXTO.md` e `REGRAS.md` continuam batendo com o conteúdo novo |
| `frontend-htmx.md.desativado` | **não vai.** O v1 não vai; o agente dele não tem mais o que fazer |

---

## 5. A migration do schema

O usuário autorizou apagar os dados e rever as tabelas. O produto é **DDL versionado em
`sql/`, na ordem de execução, que sobe o schema do zero numa base limpa.**

### 5.1 O princípio, e o motivo dele

**Nenhuma tabela em uso muda de forma. Uma tabela morre. O resto é recriado vazio.**

Motivo: rever a forma de uma tabela que está em uso no meio de uma migração dobra o risco
sem ganho — cada coluna renomeada é um `app/servicos/*.py` e um `stg_*.sql` para acertar, e
o modo de falha é silencioso. A única mudança de forma que se paga é a que elimina uma
tabela inteira, e essa tem justificativa medida (§5.3).

### 5.2 Veredicto por tabela

| Tabela | Hoje | No schema novo | Motivo |
|---|---|---|---|
| `APP_USUARIO` | 2 | **igual**, vazia | `auth.garantir_admin_inicial()` recria o `admin` no startup |
| `APP_SESSAO` | 3 | **igual**, vazia | — |
| `APP_AUDITORIA` | 139 | **igual**, vazia | 17 ações distintas, todas ainda em uso |
| `APP_ATUALIZACAO` | 14 | **igual**, vazia | — |
| `APP_DECISAO_PRECO` | 4 | **igual**, vazia | **Viva.** A tela de Precificação da v2 escreve nela — `GRAVAR_DECISAO_PRECO`, 34 eventos, o último em **11/09 09:41**. É fonte de `stg_decisao_preco` → `int_produto_preco_sugerido` |
| `APP_DECISAO_PRECO_HIST` | **0** | **igual, mas medir antes** | 34 gravações em 4 produtos e **zero linhas de histórico**. `preco.py:109` só insere quando já existia valor anterior. Ou o arquivamento nunca disparou, ou a tabela foi limpa à mão. **Meça antes de recriar** — recriar uma tabela que ninguém alimenta é carregar peso morto; se o arquivamento estiver quebrado, o conserto é outra etapa, não esta |
| `APP_PEDIDO`, `APP_PEDIDO_ITEM`, `APP_PEDIDO_STATUS_HIST` | 4 / 66 / 4 | **iguais**, vazias | São o pedido da v2 |
| `APP_LOTE_PRECO`, `_ITEM`, `_STATUS_HIST` | 1 / 2 / 2 | **iguais**, vazias | Etapa 12, em uso — 15 `CRIAR_LOTE_PRECO`, o último em 11/09 |
| **`APP_DECISAO_PEDIDO`** | 4 | **DEIXA DE EXISTIR** | §5.3 |

### 5.3 `APP_DECISAO_PEDIDO` morre, e `stg_decisao_pedido` muda de fonte

**O achado que decide isto, e que também responde à pergunta do v1 que ficou em aberto:**

- A única escritora de `APP_DECISAO_PEDIDO` é a tela v1 (`app/servicos/compra.py:186`).
- O último evento `GRAVAR_DECISAO_PEDIDO` da auditoria é de **25/08/2026**. São 18 dias
  parada, enquanto `GRAVAR_DECISAO_PRECO` e `CRIAR_LOTE_PRECO` registram atividade em 11/09.
- A v2 **não escreve nela**: grava em `APP_PEDIDO` + `APP_PEDIDO_ITEM`.
- E — esta é a consequência que ninguém tinha notado — **a decisão de pedido da v2 nunca
  chega ao `FAT_PEDIDO`.** `int_produto_pedido.sql:117` lê `stg_decisao_pedido`, que lê
  `APP_DECISAO_PEDIDO`. `APP_PEDIDO` só aparece em `models/app/compras_produto_contexto.sql`.
  Hoje, `FAT_PEDIDO` tem exatamente **4 linhas com `PEDIDO <> 0`, de 8.841** — e as quatro
  são do `admin`, de 25/08. A coluna `PEDIDO` do gabarito de 122 colunas está sendo
  alimentada por uma tabela morta.

**Decisão: `stg_decisao_pedido` passa a ler `APP_PEDIDO_ITEM`.** Isso mata a tabela velha e
fecha a lacuna no mesmo movimento.

Três detalhes de desenho, cada um com o motivo:

1. **O fator congelado sobrevive.** `APP_PEDIDO_ITEM` já tem `FATOR_EXIBICAO NUMBER NOT
   NULL` — o snapshot que a regra 6 exige está lá. O teste
   `compras_pedido_unidades_usa_fator_congelado.sql` continua valendo **sem alteração de
   regra**, só trocando a referência. Sem essa coluna a mudança seria impossível; com ela é
   uma troca de `from`.
2. **A agregação soma em unidade REAL, não em unidade de exibição.** O grão muda: a tabela
   velha tinha PK em `ID_PRODUTO` (uma linha por produto), a nova tem grão
   `PEDIDO × PRODUTO` — o mesmo SKU pode estar em dois pedidos, com fatores diferentes
   (`1` e `12`, como nas 4 linhas de hoje). Somar `QUANTIDADE` entre itens de fatores
   diferentes soma caixa com unidade e produz um número que não é nada. `stg_decisao_pedido`
   passa a devolver, por produto: `sum(QUANTIDADE * FATOR_EXIBICAO) as unidades` e o
   `FATOR_EXIBICAO` do item **mais recente**, usado só para reexibir. `int_produto_pedido`
   consome `unidades` direto, em vez de multiplicar.
3. **Todos os status contam.** `APP_PEDIDO.STATUS` percorre Rascunho → Orçamento Enviado →
   Fechado → Exportado. A coluna `PEDIDO` do gabarito significa *"quanto o comprador decidiu
   comprar"*, não *"quanto foi aprovado"* — e a tabela velha também não tinha status nenhum.
   Contar todos preserva o significado; restringir a "Enviado para cima" seria **regra nova**,
   e vai como pergunta 3 do §10.

Arquivos que mudam, nominalmente:

```
sql/                                       DDL sem app_decisao_pedido
dbt/compras/models/staging/sources.yml:85  remove a source app_decisao_pedido
dbt/compras/models/staging/stg_decisao_pedido.sql   passa a ler app_pedido_item, agregado
dbt/compras/models/intermediate/int_produto_pedido.sql:117  consome `unidades`
dbt/compras/models/intermediate/int_produto_alerta.sql:90   comentário cita a tabela velha
dbt/compras/tests/compras_pedido_unidades_usa_fator_congelado.sql   troca a referência
dbt/compras/tests/compras_fat_alerta_espelha_checks.sql             idem
```

### 5.4 O DDL novo

`sql/` renumerado, na ordem de execução, cada arquivo idempotente como os de hoje:

```
sql/00_LEIAME.md              a ordem, e o que cada script faz
sql/01_usuario_compras.sql    usuario COMPRAS + GRANTs de SELECT no CEDEP
sql/02_tabelas_auth.sql       APP_USUARIO, APP_SESSAO, APP_AUDITORIA
sql/03_tabelas_decisao.sql    APP_DECISAO_PRECO (+ _HIST, se o §5.2 confirmar)
sql/04_tabelas_pedido.sql     APP_PEDIDO, APP_PEDIDO_ITEM, APP_PEDIDO_STATUS_HIST
sql/05_tabelas_lote_preco.sql APP_LOTE_PRECO, _ITEM, _STATUS_HIST
sql/06_tabela_atualizacao.sql APP_ATUALIZACAO
sql/98_limpar_dados.sql       DELETE em todas as APP_*, na ordem das FKs. NAO dropa
sql/99_revogar.sql            desfaz os GRANTs
```

`98_limpar_dados.sql` é `delete`, não `truncate`, e não dropa nada: quem roda uma limpeza
precisa poder errar e dar `rollback`. E os `comment on table` / `comment on column` de hoje
atravessam — são a única documentação do schema que vive junto do schema.

**O que a migration NÃO faz:** não toca no CEDEP, não recria nenhuma `COMPRAS_*`, `DIM_*`,
`INT_*`, `STG_*` ou `FAT_*`. Essas são do dbt e nascem do `dbt seed` + `dbt run` — 7 minutos.

---

## 6. Os dois documentos novos — são entregável, não apêndice

O usuário pediu dois. Os de hoje cobrem parte, mas estão escritos para agente, misturados
com convenção de código, espalhados por seis arquivos e envelhecidos em pontos (a ordenação
de alerta mudou duas vezes; o `STATUS.md` é de 26/08; o `PLANO.md` ainda descreve como
futuro etapas já feitas).

**Os nomes `CONTEXTO.md` e `REGRAS.md` são mantidos, e o conteúdo é reescrito.** Motivo:
~80 arquivos os citam pelo nome, e `validar_pedido.py:6` cita `CONTEXTO.md §6.2` e `§6.3`
pelo **número da seção**. Trocar os nomes obrigaria a reescrever ~80 ponteiros junto; manter
os nomes e a numeração das seções existentes reduz a mudança a dois arquivos. O conteúdo de
onboarding entra como **`§0`**, antes do `§1`, justamente para não renumerar nada.

### 6.1 Documento 1 — `REGRAS.md`: as regras de negócio decididas até aqui

Consolidado, atual, **sem uma linha de convenção de código**. Quem escreve: `dbt-regras`,
`model: opus` — é o único agente que conhece o fiscal, a margem e o alerta, e escrever a
regra errada aqui é caro de um jeito que não aparece em teste.

Lê, para escrever: `REGRAS.md` (468 linhas), `MELHORIAS.md` (286), `PENDENCIAS_DIRETORIA.md`
(154), `CADASTRO_DIVERGENCIAS.md` (275), `v2/DECISOES_DIRETOR.md` (273), `CONTEXTO.md §6`, os
9 CSVs de `dbt/compras/seeds/` e os comentários de cabeçalho dos models `int_produto_*`.

O que tem de conter:

1. **As 11 regras** do índice do `CONTEXTO.md §6`, cada uma com a armadilha medida.
2. **As decisões do Diretor, das duas rodadas, com o valor que ficou valendo** — não a
   discussão. `MARGEM_ALTA_MIN` **0,25** (subido de 0,20), `MARGEM_ALTA_MIN_VAREJO` **0,50**
   (subido de 0,45), `OPORTUNIDADE_GIRO_MESES` **3**, a taxonomia de 10 tipos com `PARADO`
   dividido em `SEM_GIRO` (315) e `BAIXO_GIRO` (123), a separação DECISAO/CADASTRO que tirou
   **1.871 SKUs** da tela de Alertas, os pesos de `app/api/alertas.py`, os dois indicadores
   (capital parado **R$ 71,4 mi**, venda em risco **R$ 2,3 mi**), Washington com **5.932 SKUs**,
   e ROBUST/ADIBRAX caindo no `COBERTURA_ALVO_PADRAO`.
3. **As divergências deliberadas da planilha**, com o efeito medido — incluindo a A5 (fator
   congelado) e as 5 divergências PDF × planilha já decididas.
4. **O que segue em aberto**, em lista curta: Seção/Linha/Categoria em cadastro no WinThor
   (o único bloqueio externo), e o que o §10 deixar sem resposta.

⚠ **Cada número entra recalculado, não copiado do `.md` de agosto.** Onde o recálculo
divergir do escrito, vale o recálculo, e a divergência fica registrada em uma linha.

### 6.2 Documento 2 — `CONTEXTO.md §0`: o ponto de partida

Escrito **para quem não leu nada** — sessão nova ou desenvolvedor novo. Quem escreve:
`backend-fastapi`, `model: sonnet`. Motivo: é o agente que conhece as três pontas (banco,
API, subida) sem ser o dono de nenhuma, e o documento não decide número nenhum.

Lê: `README.md`, `STATUS.md`, `VISAO_GERAL.md`, `v2/PLANO.md` (em especial o §6, do socket
órfão), `CONTEXTO.md §1–§5`, `teste.bat`, `teste_front.bat`, `dbt/rodar_dbt.bat`, e o §8
deste prompt.

O que tem de conter:

1. **O que o projeto é** em dez linhas: a planilha de 8.841 SKUs e 122 colunas, os dois
   entregáveis, quem usa.
2. **A fronteira de acesso**, com o desenho — e a frase que nunca pode faltar: *decisão
   gravada no dashboard só chega ao `fat_pedido` no próximo `dbt run`*.
3. **Como subir**, os dois modos: desenvolvimento (`teste.bat` na 8020, `teste_front.bat` na
   5173, e por que o `--host` é o IP e não `0.0.0.0`) e produção (§8, com o nome do serviço
   e a URL).
4. **O socket órfão**, com data, PID e as três consequências. É a primeira coisa que confunde
   quem chega.
5. **Onde cada coisa mora**, em tabela, com caminho real.
6. **O que está no ar hoje**, com data de verificação.
7. **O que fazer primeiro**: rodar `dbt seed` + `dbt run` (7 minutos), subir a API, subir o
   front, entrar com o `admin` de senha provisória.

As seções `§1–§7` de hoje continuam, com os números que têm. `§5` (convenções dbt) fica —
é documento de desenvolvedor, e a separação que o usuário pediu é que a **regra de negócio**
não tenha convenção de código, não o contrário.

---

## 7. O que fica para trás

### 7.1 A pasta congelada

`C:\Users\Administrator\Desktop\_app_compras_congelado_20260912`, guardada 30 dias, **não
apagada**, `.git` intacto. É o arquivo morto do histórico (§2.1) e guarda os 49 MB de
`.xlsx` e os 26 MB de log que não atravessam.

O prefixo `_` é deliberado: as duas pastas têm os mesmos `teste.bat` e `teste_front.bat`,
apontando para as mesmas portas. Enquanto as duas existirem com o nome de sempre, alguém dá
clique duplo na errada — e o sintoma vai ser porta ocupada, que nesta máquina já tem um
culpado falso pronto (§9.1).

### 7.2 O dashboard v1 não vai

Com `APP_DECISAO_PEDIDO` morta (§5.3), o v1 perde a razão de existir: ele era a única tela
que a escrevia. Não vão para o repositório novo:

```
app/templates/            11 arquivos Jinja2
app/static/app.css
app/static/js/app.js
app/static/js/htmx.min.js
app/servicos/compra.py    a tela de decisao de compra do v1
app/servicos/indicador.py a tela de indicadores do v1
.claude/agents/frontend-htmx.md.desativado
```

E `app/main.py` é reescrito enxuto: sem `Jinja2Templates`, sem as 8 rotas HTML, sem o
`from app.servicos import compra, ..., indicador` da linha 20. Ficam o `include_router` da
API, os dois `on_event`, os dois `exception_handler` e o `raiz()`.

⚠ **`exportacao.py` e `preco.py` NÃO são do v1** — a v2 os importa (`rotas.py:26`,
`lote_preco.py:61`, `pedido.py:56`). Apagar qualquer um dos dois derruba a exportação do
pedido e o lote de preço.

**O que isso muda de número, medido:** hoje o `FAT_PEDIDO` tem 4 linhas com `PEDIDO <> 0`,
das 8.841. Com as `APP_*` zeradas, o número de partida é **0 dos dois lados** — cortar o v1
não muda nada, porque não há o que mudar. O que muda é para frente: a decisão de pedido da
v2 passa a chegar ao `FAT_PEDIDO`, coisa que hoje não acontece.

⚠ **Uma dívida que se fecha de graça aqui:** a fórmula do valor do pedido viva em dois
lugares — `int_produto_pedido.sql` e `app/servicos/compra.py` — sem teste comparando os dois.
Com `compra.py` fora, sobra **uma** fórmula. Registre isso no `REGRAS.md` novo como dívida
fechada, com a data.

---

## 8. Produção: NSSM e nginx, versionados no repositório

Hoje o sistema está no ar por duas janelas de terminal que morrem quando alguém fecha a
sessão RDP (§3.1). O repositório novo nasce com a configuração de produção **dentro dele**.

### 8.1 Os arquivos, nomeados

No molde do `infra/` que já existe:

```
infra/README.md                 a ordem de instalacao, e como desfazer
infra/instalar_servico.ps1      cria o servico NSSM app_compras
infra/desinstalar_servico.ps1   para e remove o servico
infra/nginx/compras.conf        o vhost, versionado
infra/instalar_nginx.ps1        copia o vhost, acrescenta o include, testa e recarrega
infra/desinstalar_nginx.ps1     remove o include e o arquivo, testa e recarrega
infra/agendar_atualizacao.ps1   ja existe; so roda de novo a partir do caminho novo
infra/publicar.ps1              npm ci + npm run build + restart do servico
```

**Tudo é script versionado, nada é comando digitado.** Motivo: comando digitado numa janela
não sobrevive à pessoa que digitou, e este projeto já perdeu oito dias servindo um Tailwind
congelado porque um passo de subida era manual.

### 8.2 O serviço NSSM

`nssm.exe` já existe nesta máquina em **`C:\tools\nssm\nssm.exe`**, e o `relatorio_compras`
roda como `LocalSystem`, `StartMode Auto`. O serviço novo segue o mesmo padrão:

| Parâmetro | Valor | Motivo |
|---|---|---|
| Nome | `app_compras` | Mesmo padrão de `relatorio_compras` |
| Application | o `python.exe` do sistema | A API não usa venv; `teste.bat` chama `python` direto |
| AppParameters | `-m uvicorn app.main:app --host <BIND> --port 8020` | **Sem `--reload`.** Em produção o reload reinicia o processo a cada toque em arquivo e mascara falha de startup |
| AppDirectory | a raiz do repositório novo | É de onde `config.BASE_DIR` acha o `.env` |
| AppStdout / AppStderr | `logs\servico.out.log` / `.err.log`, com rotação | Serviço sem log é serviço que falha em silêncio |
| Start | `SERVICE_AUTO_START` | Sobe sozinho depois de reiniciar a máquina |
| AppEnvironmentExtra | `DBT_PROFILES_DIR=C:\Users\Administrator\.dbt` | ⚠ §8.5 |

**`<BIND>` é uma constante única no topo do `instalar_servico.ps1`, comentada.** Enquanto o
socket órfão existir, vale `192.168.0.50`; depois do reinício da máquina, `127.0.0.1`.
Ver §9.1.

### 8.3 O nginx, e o defeito que faria a tela subir em branco

Em produção o Vite dev server **deixa de existir**. O que vai para o ar é o build estático
de `app/static/v2/` — e ele hoje **não é servido por nada**: o `index.html` gerado pede
`/assets/index-*.js` na **raiz**, e `grep -rn "static/v2" app/` devolve zero. Subir assim dá
tela branca com dois 404 no console.

**Decisão: o nginx serve os estáticos direto, e proxia só `/api/` para o uvicorn.**

```
# infra/nginx/compras.conf
server {
    listen 80;
    # Por IP TAMBEM, de proposito: funciona no dia 1, antes de existir
    # o registro DNS de compras.cdp.lub. O nome passa a valer sozinho
    # quando o registro entrar, sem tocar neste arquivo.
    server_name compras.cdp.lub 192.168.0.50;

    # /api/ ANTES de /, ou toda chamada cai no fallback do SPA e volta
    # HTML onde a tela espera JSON. Mesmo cuidado do vhost dre.cdp.lub.
    location /api/ {
        proxy_pass http://<BIND>:8020;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        # A exportacao do pedido e do lote monta xlsx em memoria e passa
        # dos 60s padrao. Mesmo motivo do vhost dre.cdp.lub.
        proxy_read_timeout 300s;
    }

    root  <RAIZ>/app/static/v2;
    index index.html;

    # O react-router usa history: /pedidos/41 nao e arquivo. Sem este
    # fallback, o SEGUNDO carregamento de qualquer tela devolve 404 —
    # o primeiro funciona porque veio por navegacao interna.
    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

**Como entra sem derrubar os dois vhosts que já servem:** arquivo próprio, mais **uma linha**
`include compras.conf;` dentro do `http { }` de `C:\nginx\conf\nginx.conf` — o `include
mime.types` já existente prova que caminho relativo ao `conf/` funciona. O
`instalar_nginx.ps1` faz, nesta ordem: copia `nginx.conf` para
`nginx.conf.bkp-<AAAAMMDD>` (o padrão desta máquina — já existe um `.bkp-20260728`),
acrescenta o `include` se ele não estiver lá, roda **`nginx -t`** e só então `nginx -s reload`.

⚠ **`nginx -t` antes do reload não é opcional.** Um `reload` com configuração inválida
derruba `gestaosac.cdp.lub` e `dre.cdp.lub`, que são produção de outras áreas. Se o `-t`
falhar, o script restaura o backup e **não recarrega**.

### 8.4 HTTPS: não, e por quê

**Decisão: HTTP na porta 80, e `APP_COOKIE_SECURE` continua `0`.**

Três motivos: os dois vhosts já em produção nesta máquina são HTTP na 80; `.cdp.lub` é nome
interno, para o qual nenhuma CA pública emite certificado; e um certificado autoassinado
faria o celular do Diretor abrir com aviso de site não confiável — o oposto do objetivo, num
projeto cujo dispositivo alvo é justamente esse celular.

O `compras.conf` leva um comentário de duas linhas dizendo o que se troca no dia em que
houver certificado: o `listen 443 ssl` + os dois `ssl_certificate`, e `APP_COOKIE_SECURE=1`
no `.env`, **que tem de mudar junto** — cookie `Secure` em origem HTTP não é enviado, e o
sintoma é 401 em toda tela, que parece defeito de autenticação. Pergunta 2 do §10.

### 8.5 ⚠ A armadilha do serviço: `LocalSystem` não tem o `profiles.yml`

O botão "Atualizar dados" da tela dispara `subprocess.Popen` de `dbt/atualizar.py`
(`app/servicos/atualizacao.py:215`), que **herda o ambiente do serviço**.
`atualizar.py:87` resolve o diretório do profiles assim:

```python
DBT_PROFILES_DIR = os.environ.get("DBT_PROFILES_DIR") or str(pathlib.Path.home() / ".dbt")
```

Rodando como `Administrator`, `Path.home()` acerta. Rodando como **`LocalSystem`**, aponta
para o perfil do sistema, onde não há `profiles.yml` — e o botão passa a falhar em produção
num caminho que funcionava em teste. Por isso o `AppEnvironmentExtra` do §8.2. A Tarefa
Agendada já resolve o mesmo problema do mesmo jeito, e é de lá que a solução vem.

### 8.6 A Tarefa Agendada, refeita

A tarefa `CEDEP - app_compras - atualizar dados` (estado `Ready`) tem **dois caminhos
absolutos** apontando para a pasta antiga: em `Arguments` e em `WorkingDirectory`.
`Unregister-ScheduledTask` na antiga, e roda-se `infra\agendar_atualizacao.ps1` **a partir
do destino** — ele deriva `$ProjetoRaiz` de `$PSCommandPath` (`:16-17`) e recria apontando
certo.

### 8.7 Como se desfaz tudo

`infra/README.md` termina com a ordem inversa, porque o momento de precisar dela é o pior
momento para deduzi-la: `desinstalar_nginx.ps1` (restaura o backup, `nginx -t`, reload) →
`desinstalar_servico.ps1` (`nssm stop` + `nssm remove app_compras confirm`) →
`Unregister-ScheduledTask` → subir de novo pelas duas janelas de `teste.bat` e
`teste_front.bat`. **O caminho de volta é sempre o modo de desenvolvimento**, que não depende
de nada instalado.

---

## 9. O que quebra fora do repositório

| # | O quê | Quebra? | Evidência |
|---|---|---|---|
| 1 | **Tarefa Agendada** | **SIM** | Dois caminhos absolutos. §8.6 |
| 2 | `dbt/env_server/` | **SIM** | §4.2. E o serviço depende dele: o botão de atualizar chama `DBT_EXE` |
| 3 | `web/node_modules/` | **SIM** | §4.2 |
| 4 | As duas janelas de terminal | **substituídas** | §8 |
| 5 | `~/.dbt/profiles.yml` | **NÃO** | O profile é achado pelo **nome** `compras` (`dbt_project.yml:5`); o arquivo mora em `~/.dbt`, fora do projeto, e não contém nenhum caminho do projeto. Mas ver §8.5 |
| 6 | `nginx.conf` | **uma linha acrescentada** | §8.3 |
| 7 | Caminhos internos em `.py`, `.bat`, `.sql`, `.yml` | **NÃO** | `app/config.py:12` deriva `BASE_DIR` de `__file__`; `dbt/atualizar.py:66-68` idem; os `.bat` abrem com `cd /d "%~dp0"`; `validar/*.py` derivam de `__file__`; `agendar_atualizacao.ps1:16-17` de `$PSCommandPath`. Um `grep` por `Desktop\app_compras` no versionado devolve **três** ocorrências, nenhuma em código de execução: `VISAO_GERAL.md:11`, `:193` e o venv do item 2 |
| 8 | `.env` e os dois `.xlsx` | **SIM, por ausência** | §4.3 |

O item 7 é a boa notícia: o projeto foi escrito relocável.

### 9.1 ⚠ O socket órfão, e o que o serviço faz enquanto ele existir

Desde **25/08/2026** há um socket órfão escutando em `0.0.0.0:8020` cujo dono (PID 2240) não
existe mais. Ele não responde a nada e mesmo assim segura a porta: `--host 0.0.0.0` falha com
`WinError 10048`, e requisição a `127.0.0.1:8020` cai nele e fica pendurada até o timeout.

**Enquanto ele existir:** o serviço NSSM sobe com `--host 192.168.0.50` e o `proxy_pass` do
nginx aponta para `http://192.168.0.50:8020`. É o mesmo contorno já em vigor em três lugares
no código, agora num quarto.

**Depois de reiniciar a máquina:** o órfão some, `<BIND>` vira `127.0.0.1` nos dois arquivos,
e o uvicorn deixa de estar exposto direto na rede — que é o certo, com o nginx na frente.

⚠ **O reinício derruba os outros uvicorns em produção desta máquina** — `relatorio_compras`
na 8010, e mais nas portas 8000, 8001, 8077 e 8100, de outras áreas. **É decisão do usuário,
não do executor.** Pergunta 1 do §10. O `instalar_servico.ps1` e o `compras.conf` ficam
prontos para as duas situações, com a constante `<BIND>` num lugar só e comentada.

**E o modo de falha mais provável da migração:** subir do caminho novo sem derrubar o PID
2508, receber `WinError 10048`, e culpar o órfão. **O culpado será a cópia antiga ainda de
pé.** Derrube 2508 e 6912 explicitamente. **Não toque no 2384** (porta 8010).

---

## 10. A ordem de execução

**Fase A — preservar.**

1. `git add -A && git commit` na pasta antiga, com o estado em voo. Não é hora de `git
   stash`. Isso não é para o repositório novo — é para a pasta congelada virar um arquivo
   morto consistente.
2. `git push origin main` — os 4 commits + o novo, para o repositório antigo deixar de ser
   uma versão pública e desatualizada de si mesmo. Se o push falhar por credencial, **siga**:
   o usuário disse "origin depois".
3. Anotar as contagens do §3.2 do banco **como estão agora**. É a linha de base do aceite.

**Fase B — a pasta nova.**

4. `robocopy` da raiz antiga para `C:\Users\Administrator\Desktop\app_compras_v2` (hoje
   vazia, 0 arquivos — conferido), copiando o **working tree**, sem `.git`:

```
robocopy "C:\Users\Administrator\Desktop\app_compras" "C:\Users\Administrator\Desktop\app_compras_v2" /E /COPY:DAT /R:1 /W:1 /XD .git node_modules env_server target logs logs_execucao __pycache__ .impeccable /XF .atualizacao.lock *.log
```

   ⚠ **`robocopy` devolve 1 quando copiou com sucesso.** A checagem é `if errorlevel 8` —
   tratar `1` como erro aborta uma cópia que deu certo.
5. Conferir nominalmente: os 6 arquivos do §2.1, o `.env`, os dois `.xlsx`,
   `.claude/settings.local.json`.
6. Aplicar as remoções do §7.2 (v1) e do §4.4 (`test_porta.bat`), e criar `historico/` com
   os arquivos e o `README.md` de três linhas.
7. `git init`, `git add -A`, **um** commit inicial. Sem `git remote`.

**Fase C — reconstruir o que não atravessa.**

8. `dbt\env_server`: `python -m venv env_server` + `env_server\Scripts\python -m pip install
   -r compras\requirements.txt`.
9. `web`: `npm ci`, depois `npm run build`.

**Fase D — o schema.**

10. Derrubar PID 2508 e 6912. Não tocar no 2384.
11. Reescrever `sql/` conforme §5.4 e aplicar na base: `98_limpar_dados.sql` e o `drop` de
    `APP_DECISAO_PEDIDO`.
12. Aplicar as mudanças de dbt do §5.3.
13. `dbt\rodar_dbt.bat` — **seed + run + test**, ~7 minutos. Conferir contra §3.2.

**Fase E — produção.**

14. Escrever os arquivos do §8.1.
15. `infra\instalar_servico.ps1`, `infra\instalar_nginx.ps1`, `infra\agendar_atualizacao.ps1`.
16. `Unregister-ScheduledTask` da tarefa antiga.
17. Rodar o aceite do §12.

**Fase F — documentos.**

18. `REGRAS.md` novo (§6.1) e `CONTEXTO.md §0` (§6.2).
19. Trocar os ponteiros: `MELHORIAS.md` e `PENDENCIAS_DIRETORIA.md` são citados de **15
    models, 1 macro, 3 tests e `validar_pedido.py`**. Cada citação vira `REGRAS.md §<seção>`.
    Nenhum SQL muda de lógica — só o texto do comentário.
20. `README.md` novo, `.claude/agents/` conforme §4.5.
21. `git commit` da documentação.

**Fase G — congelar.**

22. Só depois do aceite fechado: renomear a pasta antiga para
    `_app_compras_congelado_20260912`.

---

## 11. O trabalho, por agente

| Agente | `model:` | O quê | Lê | **Não** lê |
|---|---|---|---|---|
| `infra-windows` | **sonnet** (nasce haiku) | Fases A, B, C, E, G. Os 8 arquivos do §8.1 | Este prompt, `v2/PLANO.md §6`, `.gitignore`, `agendar_atualizacao.ps1`, os 3 `.bat`, `nginx.conf`, `.env.exemplo` | `REGRAS.md`, `PROTOTIPO.md` |
| `oracle-dba` | **sonnet** | Fase D, passo 11: o `sql/` do §5.4, o `drop`, os `comment on` | Este prompt §5, `sql/` atual, `CONTEXTO.md §3` | `REGRAS.md`, `PROTOTIPO.md` |
| `dbt-regras` | **opus** | Fase D, passo 12 (§5.3 — mexe em quantidade e no fator congelado) **e** o `REGRAS.md` novo (§6.1) | §5.3 e §6.1 deste prompt, os 5 `.md` que ele consolida, `int_produto_pedido.sql`, `stg_decisao_pedido.sql`, os 2 tests, as 9 seeds | — |
| `backend-fastapi` | **sonnet** | Fase B passo 6 (enxugar `main.py`, §7.2) e o `CONTEXTO.md §0` (§6.2) | §6.2 e §7.2, `main.py`, `rotas.py`, `README.md`, `STATUS.md`, `VISAO_GERAL.md`, `v2/PLANO.md` | `REGRAS.md` — ele não decide regra aqui |
| `validador` | **sonnet** | O aceite do §12, com os números ao lado dos esperados, incluindo os dois testes com defeito injetado | Este prompt §3.2 e §12, `validar/` | `REGRAS.md` |
| `revisor` | **opus** | **Último, e antes da Fase G.** Confere o inventário do §4 contra o destino real, os 6 arquivos do §2.1, e se algum veredicto deste prompt está errado | Tudo. Somente leitura | — |

**Quem não entra:** `dbt-staging` (nenhum `stg_*` novo, nenhuma seed alterada — as 9 CSVs vão
intactas), `dbt-relatorios` (nenhum relatório muda), `frontend-react` (nenhuma tela muda;
`npm ci` e `npm run build` são operação, não desenvolvimento).

Sobre os `model:` — o critério do projeto é *muda número → opus; muda onde o número aparece →
sonnet*. `dbt-regras` é opus porque o §5.3 mexe em quantidade e no fator congelado, e porque
escrever a regra errada no `REGRAS.md` novo contamina tudo o que vier depois. `revisor` é
opus porque é o último portão antes de um passo irreversível: arquivo que não atravessou e
não foi notado só aparece depois que a pasta antiga sumiu.

---

## 12. O que **não** fazer

1. **Não copiar "o último commit".** Copia-se o working tree, com a Etapa 13 dentro. §2.1.
2. **Não apagar a pasta antiga.** Ela é o único lugar onde o histórico do git existe. §7.1.
3. **Não apagar `exportacao.py` nem `preco.py`** junto com o v1. A v2 depende dos dois. §7.2.
4. **Não mudar a forma de nenhuma tabela que fica.** Só `APP_DECISAO_PEDIDO` sai. §5.1.
5. **Não recriar `COMPRAS_*`, `DIM_*`, `INT_*`, `FAT_*` à mão.** São do dbt. §5.4.
6. **Não rodar `dbt run` sem `dbt seed` antes**, na base limpa. §3.3.
7. **Não copiar `env_server` nem `node_modules`.** §4.2.
8. **Não trocar os nomes `CONTEXTO.md` e `REGRAS.md`.** ~80 ponteiros, e um deles cita
   número de seção. §6.
9. **Não recarregar o nginx sem `nginx -t` passar.** Dois vhosts de outras áreas estão
   naquele arquivo. §8.3.
10. **Não subir o serviço com `--reload`.** §8.2.
11. **Não reiniciar a máquina por conta própria.** §9.1.
12. **Não acrescentar nem atualizar dependência** em `web/package.json` ou
    `requirements.txt`. `npm ci`, não `npm install`. A migração move; não moderniza.
13. **Não ligar `APP_COOKIE_SECURE=1`** enquanto for HTTP. §8.4.
14. **Não corrigir o caminho antigo dentro de `historico/`.** Corrigir um retrato é o que faz
    retrato virar mentira.
15. **Não renomear a pasta antiga antes do aceite fechar.** Fase G.

---

## 13. Perguntas

1. **Podemos reiniciar esta máquina, e quando?** É o que libera o socket órfão de
   `0.0.0.0:8020`, permite o serviço voltar para `127.0.0.1` e, de quebra, prova sozinho que
   o serviço sobe automático. **Mas derruba os outros uvicorns em produção aqui** —
   `relatorio_compras` (8010) e os das portas 8000, 8001, 8077 e 8100, de outras áreas. Sem o
   reinício, tudo funciona com o contorno do IP específico; o aceite 12.9 só não pode ser
   provado da forma forte.

2. **Existe CA interna na CEDEP que emita certificado para `*.cdp.lub`?** Decidi HTTP (§8.4)
   porque os dois vhosts vizinhos são HTTP e um autoassinado faria o celular do Diretor abrir
   com aviso. Se houver CA interna com o certificado já distribuído nos aparelhos, HTTPS passa
   a valer a pena e o `compras.conf` muda em quatro linhas.

3. **A coluna `PEDIDO` do `FAT_PEDIDO` deve contar pedido em qualquer status?** Decidi que
   sim (§5.3, item 3), porque é o significado que a coluna do gabarito sempre teve e a tabela
   velha não tinha status nenhum. Se você quiser que só "Orçamento Enviado" para cima entre
   no cálculo, isso é **regra nova** e muda número — vira etapa própria, não entra aqui.

4. **`compras.cdp.lub` — você cria o registro DNS?** O vhost já responde por
   `192.168.0.50` sem ele (§8.3), então nada trava. Mas o endereço que se manda para o
   celular do Diretor fica melhor com nome.

---

## 14. Aceite

Cada item é número conferido, não impressão. Tudo roda **no destino**.

**Conteúdo**

1. **Os 6 arquivos do §2.1 existem no destino**, conferidos um a um pelo nome.
2. **`git log --oneline` no destino mostra 1 commit**, e `git status --short` vem vazio.
3. **`git remote -v` no destino vem vazio.** "Origin depois" tem de ser visível, não
   implícito — um remoto herdado apontaria para o repositório antigo.
4. **Nenhum arquivo do v1 sobrou:** `app/templates/`, `app/static/js/htmx.min.js`,
   `servicos/compra.py`, `servicos/indicador.py` e `frontend-htmx.md.desativado` não existem;
   e `grep -n "compra\|indicador" app/main.py` não devolve `import`.
5. **`exportacao.py` e `preco.py` existem**, e a exportação de um pedido e de um lote de
   preço funciona ponta a ponta.
6. **`grep -rn "Desktop.app_compras\\"` no destino**, ignorando `node_modules`, `env_server`
   e `historico/`, devolve **zero linhas**.

**Banco e dbt**

7. **`dbt seed` + `dbt run` + `dbt test` terminam do caminho novo**, em tempo entre
   **158 s e 577 s** (a faixa das 14 execuções registradas). Contagens contra a linha de base
   da Fase A: `FAT_PEDIDO` **8.841**, `FAT_ALERTA` **8.058**, `DIM_PRODUTO` **8.841**,
   `DIM_TRIBUTACAO` **15**, `DIM_FORNECEDOR` **61** — estas **exatas**.
   `COMPRAS_MONITORAMENTO` (337.540), `COMPRAS_ENTRADA` (11.941) e `COMPRAS_VENDA_MENSAL`
   (81.397) **variam de verdade** se o WinThor movimentou no intervalo: o que se exige delas é
   **variação explicável**, não igualdade.
8. **`FAT_PEDIDO` continua com 122 colunas** — o test `compras_fat_pedido_122_colunas` passa.
9. **`APP_DECISAO_PEDIDO` não existe** em `all_tables` do schema `COMPRAS`, e nenhum model do
   dbt a referencia.
10. **As 9 seeds carregaram com os valores do §3.3**, conferidos em banco:
    `MARGEM_ALTA_MIN` = **0,25**, `MARGEM_ALTA_MIN_VAREJO` = **0,50**,
    `OPORTUNIDADE_GIRO_MESES` = **3**, `COBERTURA_ALVO_PADRAO` = **2**, e
    `SEED_FORNECEDOR` com **61** linhas.
11. **Todas as `APP_*` estão vazias**, exceto `APP_USUARIO`, que tem **1** linha — o `admin`
    recriado pelo startup, com senha provisória.

**Produção**

12. **A tela carrega do build estático, com a 5173 derrubada.** Abrir `http://192.168.0.50/`
    de **outra máquina da rede**, navegar as 11 telas, e confirmar em `Get-NetTCPConnection`
    que **não há nada escutando na 5173**. É o item que prova que o §8.3 resolveu o caminho
    dos `/assets/`.
13. **Recarregar uma tela profunda funciona:** abrir `http://192.168.0.50/pedidos`, apertar
    F5, e receber a tela — não 404. É o `try_files` do §8.3.
14. **Os dois vhosts vizinhos continuam de pé:** `gestaosac.cdp.lub` e `dre.cdp.lub`
    respondem depois do reload, e `nginx -t` devolve `syntax is ok` / `test is successful`.
15. **`Get-Service app_compras` devolve `Running` / `Automatic`**, e o `CommandLine` do PID
    dono cita `app_compras_v2` e **não contém `--reload`**.
16. **Serviço sobe sozinho:** depois do reinício autorizado (pergunta 1), `app_compras` está
    `Running` sem ninguém ter feito nada. **Se o reinício não for autorizado**, a prova fraca é
    `sc qc app_compras` mostrando `START_TYPE : 2 AUTO_START` mais um `Restart-Service`
    bem-sucedido — e fica registrado que o item não foi provado da forma forte.
17. **O botão "Atualizar dados" funciona com o app rodando como serviço** e grava linha em
    `APP_ATUALIZACAO` com `origem = 'manual'`. É o que prova o `DBT_PROFILES_DIR` do §8.5 —
    e é exatamente o teste que falharia se ele tivesse sido esquecido.
18. **A Tarefa Agendada aponta para o destino** (`Get-ScheduledTask | Select Actions`), e um
    disparo manual grava **mais uma** linha em `APP_ATUALIZACAO` com `origem = 'agendado'`.
19. **Um único listener vivo na 8020**, e o `CommandLine` do dono cita `app_compras_v2`. O
    órfão de `0.0.0.0:8020` pode continuar listado enquanto a pergunta 1 não for respondida.
20. **A desinstalação foi exercitada:** rodar `desinstalar_nginx.ps1` e
    `desinstalar_servico.ps1`, confirmar que os dois vhosts vizinhos seguem respondendo e que
    `teste.bat` sobe o sistema de novo — e então reinstalar. Caminho de volta que nunca foi
    percorrido não é caminho de volta.

**Documentos**

21. **`REGRAS.md` e `CONTEXTO.md` existem, reescritos**, e nenhum `.md` da raiz cita
    `MELHORIAS.md`, `PENDENCIAS_DIRETORIA.md`, `CADASTRO_DIVERGENCIAS.md` ou
    `DECISOES_DIRETOR.md` — nem os models, nem os tests, nem `validar_pedido.py`. Um `grep`
    pelos quatro nomes, fora de `historico/`, devolve **zero**.
22. **`CONTEXTO.md §6.2` e `§6.3` ainda existem e ainda tratam do mesmo assunto** —
    `validar_pedido.py:6` aponta para elas pelo número.
23. **Um leitor que não conhece o projeto sobe tudo seguindo só o `CONTEXTO.md §0`**, sem
    abrir mais nada: `dbt seed` + `dbt run`, a API, o front, o login. Se ele precisar
    perguntar qualquer coisa, o documento falhou e volta para a Fase F.
24. **`historico/` tem os 6 arquivos do §4.4 mais o `README.md`**, e a raiz do repositório
    novo tem **3** `.md` — `README.md`, `CONTEXTO.md`, `REGRAS.md` — em vez de 9.

**Os dois testes com defeito injetado** — armadilha 15: teste que nunca falhou não prova nada.

25. **`.env`:** renomear o `.env` do destino e subir o app. Ele **tem de recusar subir**, com
    a mensagem de `config.validar()` nomeando `ORA_PASSWORD`. Restaurar e subir de novo. Sem
    isto, "o app subiu" prova só que havia variável de ambiente na janela.
26. **Fator congelado:** gravar um pedido pela tela com um SKU de `FATOR_EXIBICAO = 12`
    (o produto **6641** é um deles), rodar `dbt run`, e conferir que
    `FAT_PEDIDO.PEDIDO_UNIDADES` = quantidade × 12. Depois, temporariamente, trocar o
    `stg_decisao_pedido` novo para somar `QUANTIDADE` em vez de `QUANTIDADE * FATOR_EXIBICAO`
    e confirmar que o test `compras_pedido_unidades_usa_fator_congelado` **falha**. Reverter.
    É o único jeito de provar que o §5.3 não reintroduziu o erro de multiplicar por 12.
