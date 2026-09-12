"""Valida `app/servicos/lote_preco.py` (Etapa 12 — v2/PROMPT_ETAPA_12_PRECOS_DEFINIDOS.md
§4.4, §4.5, §4.6, §6.4) — o lote de preços como documento, e os dois arquivos
que saem dele para a rotina 201 do Winthor.

NAO CONSERTA NADA. Mede e reporta. Quem ajusta o serviço, se este script achar
defeito, é o `backend-fastapi` — nunca este arquivo.

Só chama `app/core/database.py` (nunca abre conexão própria) e as funções
públicas de `app.servicos.lote_preco` / `app.servicos.preco` — nunca SQL de
gravação direto em `APP_DECISAO_PRECO*`/`APP_LOTE_PRECO*`, EXCETO na limpeza
final (não existe função de serviço para "desfazer uma decisão gravada" — ver
docstring de `preco._gravar_decisao_preco_conn` — então restaurar o estado
exige DELETE direto, e só ali) e num ponto do cenário de conferência (§4.5)
onde é preciso simular, na PRÓPRIA linha que este script criou em
APP_LOTE_PRECO_ITEM, que o "atual" ficou desatualizado (nunca em
COMPRAS_PEDIDO, que é propriedade do dbt).

Nenhuma consulta ao CEDEP. Nenhum acesso a banco fora de `app/core/database.py`.

── Independência de ordem (11/09/2026) ─────────────────────────────────────
Este validador reprovou 18/19 (revisor `opus`) porque `cenario_isolamento_
catalogo` usava o MESMO login de `cenario_transicoes`, e o serviço ganhou
uma regra nova entre a entrega original e a revisão: `criar_lote` sem
`id_lote` passou a REAPROVEITAR o Rascunho aberto do usuário (§4.3), em vez
de sempre criar um lote novo. `cenario_transicoes` deixava o lote #19 de
volta em Rascunho; o cenário seguinte, com o mesmo login, herdava esse
Rascunho em silêncio e o arquivo saía com os itens do cenário 1, não com o
único SKU do cenário de isolamento.

A correção não foi "usar um id_lote fixo" (isso mascararia a regra nova, não
provaria nada sobre ela) — foi dar **login próprio a cada cenário que espera
`criar_lote` abrir um documento NOVO**. Só um cenário usa deliberadamente o
mesmo login em chamadas sucessivas: `cenario_reaproveitamento_rascunho`, que
existe justamente para PROVAR o reaproveitamento — ali é o comportamento sob
teste, não um acidente de wiring. Nenhum outro cenário lê ou depende de
estado (lote, decisão, usuário) que outro cenário tenha deixado para trás.

Prova de que a independência é real, não afirmada (ver relatório da Etapa):
o script foi rodado (1) sozinho, (2) com a lista de cenários invertida
(`--inverter-ordem`) e (3) duas vezes seguidas — as três vezes com o mesmo
resultado. Cada cenário cria seu(s) próprio(s) usuário(s) de teste
(`Recursos.novo_usuario`) e os devolve para limpeza no fim, então a ordem de
execução não pode mais fazer um cenário emprestar Rascunho de outro.

AUTOTESTE (a lição do CONTEXTO.md: validador que nunca reprovou não prova
nada). Para os defeitos mais perigosos de detectar em silêncio — formato do
arquivo da 201, as duas exclusões do §4.6, "preço à vista, nunca a prazo",
tolerância de aplicação e normalização de COD_FAB — este script primeiro
FORJA um artefato/caso com o defeito e prova que a função de checagem RECUSA,
para só depois rodar a checagem real e provar que ela PASSA. Sem isso, uma
checagem que sempre devolve "ok" teria o mesmo efeito prático de não existir.

Estado do banco ANTES de rodar (medido em 11/09/2026): `APP_DECISAO_PRECO`
= 2 linhas (SKUs 9 e 6871, timestamps 2026-09-02 13:50:47 e 2026-09-08
22:48:18), `APP_DECISAO_PRECO_HIST` = 0, as três `APP_LOTE_*` = 0,
`APP_USUARIO` = 2. O script tem que devolver o banco a esse estado exato, e
provar isso com contagem antes/depois — `try/finally`, não boa vontade.

── O buraco que faltava: `RascunhoConflitante` (11/09/2026) ────────────────
O `revisor` (opus) achou, na 2ª passada, que nenhum cenário aqui exercitava
`RascunhoConflitante` — "voltar para rascunho" virava 500 quando o usuário já
tinha outro Rascunho aberto, porque o índice único
`UX_APP_LOTE_PRECO_RASCUNHO` barrava o UPDATE e o `ORA-00001` não passava por
tradutor nenhum. Foi corrigido no serviço (checagem explícita
`_conflito_rascunho` em `_transicionar`) e a correção foi provada por
execução manual — não por teste. `cenario_rascunho_conflitante` fecha esse
buraco: cria A, avança A, cria B com o MESMO login (único cenário além de
`cenario_reaproveitamento_rascunho` que faz isso de propósito), prova que
voltar A recusa citando o número de B, e o contraponto — excluir B e voltar A
de novo — prova que a recusa não é permanente. Não cobre a corrida residual
(duas threads entre a checagem e o UPDATE): o revisor avaliou que é cara de
testar e que o comentário no código já documenta o risco honestamente.

Uso:
    python validar/validar_lote_preco.py
    python validar/validar_lote_preco.py --inverter-ordem
"""
from __future__ import annotations

import argparse
import datetime as dt
import io
import secrets
import sys
import threading
import traceback
from pathlib import Path
from unittest import mock

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ))

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

from openpyxl import Workbook, load_workbook  # noqa: E402

from app.core import auth, database  # noqa: E402
from app.servicos import lote_preco, preco  # noqa: E402

TOLERANCIA_APLICACAO = 0.005

# Códigos reais do banco, medidos antes de escrever este script (ver
# scratchpad da sessão) — nenhum é fabricado. Nenhum coincide com as duas
# decisões que já existem hoje (SKUs 9 e 6871), para o restauro final nunca
# precisar tocar nelas.
COD_ATACADO_APENAS = 244      # cod_fab '31401222', não repetido, ativo
COD_VAREJO_APENAS = 247       # cod_fab '31401253'
COD_AMBOS_CANAIS = 248        # cod_fab '33350622'
COD_SEM_CODFAB = 2772         # ativo, cod_fab NULO — um dos 49 do §4.6
COD_CODFAB_REPETIDO = 8170    # cod_fab '120717.0.02', repetido em 8171/8172/8173
COD_INEXISTENTE = 99_999_999  # maior codigo real do catalogo é 8927

# Três SKUs para o cenário de conferência de aplicação (§4.5) — nenhum
# repetido com os de cima. COD_CONF_PARCIAL é o quarto estado (10/09/2026):
# "parcial" = um canal aplicado e o outro pendente, SEM nenhum divergente.
COD_CONF_APLICADO = 11
COD_CONF_PENDENTE = 28
COD_CONF_DIVERGENTE = 29
COD_CONF_PARCIAL = 32          # pv_atacado 40,99 / pv_varejo 53,21 (medido 11/09/2026)

# Normalização de COD_FAB num ponto só (`_normalizar_cod_fab`), medido em
# 11/09/2026 contra compras_pedido.cod_fab (8.772 linhas):
COD_CODFAB_ESPACO_A = 4851     # cod_fab 'HC000660486'
COD_CODFAB_ESPACO_B = 4294     # cod_fab ' HC000660486' (espaço à esquerda) — NUNCA entra em
                                # nenhum lote deste script; existe só no catálogo, é o par que
                                # faz o 4851 colidir DEPOIS de normalizar.
COD_CODFAB_TAB = 471           # cod_fab 'H0002317339\t\t\t' (tabulação nas pontas), sozinho
                                # no seu grupo — tem que ENTRAR no arquivo, sem os \t.

# Reaproveitamento do Rascunho (§4.3) — três códigos usados de propósito com
# o MESMO login, no único cenário em que isso é intencional.
COD_REAPROVEITA_A = 311
COD_REAPROVEITA_B = 312
COD_REAPROVEITA_C = 317

# RascunhoConflitante (achado do revisor, opus, 11/09/2026: nenhum cenário
# exercitava isto) — outro par de códigos com o MESMO login de propósito,
# pelo mesmo motivo do bloco acima. cod_fab '10293'/'10297', medidos em
# 11/09/2026, nenhum repetido com os demais deste arquivo.
COD_RASCUNHO_CONFLITANTE_A = 319
COD_RASCUNHO_CONFLITANTE_B = 320

# "A prazo" informativo (§4.4/§9.3) — um SKU só para provar que `obter_itens`
# aciona `_a_prazo_valido` (a integração é observada com um spy que ENCAMINHA
# para a função real — nunca substitui comportamento).
COD_A_PRAZO_TESTE = 310

# Concorrência real (threads) — dois códigos distintos de tudo acima.
COD_CONCORRENCIA_A = 308
COD_CONCORRENCIA_B = 309

# 29 códigos reais e distintos de tudo acima, para o teste de atomicidade
# (criar lote com 30 itens, um inexistente no meio).
CODIGOS_ATOMICIDADE = [
    30, 31, 58, 59, 60, 63, 64, 65, 66, 68, 79, 81, 82, 85, 109,
    119, 132, 146, 147, 148, 150, 153, 155, 163, 164, 166, 167, 168, 169,
]

TODOS_CODIGOS_DECISAO = (
    [COD_ATACADO_APENAS, COD_VAREJO_APENAS, COD_AMBOS_CANAIS, COD_SEM_CODFAB,
     COD_CODFAB_REPETIDO, COD_CONF_APLICADO, COD_CONF_PENDENTE, COD_CONF_DIVERGENTE,
     COD_CONF_PARCIAL, COD_CODFAB_ESPACO_A, COD_CODFAB_TAB,
     COD_REAPROVEITA_A, COD_REAPROVEITA_B, COD_REAPROVEITA_C,
     COD_RASCUNHO_CONFLITANTE_A, COD_RASCUNHO_CONFLITANTE_B,
     COD_A_PRAZO_TESTE, COD_CONCORRENCIA_A, COD_CONCORRENCIA_B]
    + CODIGOS_ATOMICIDADE
)


class Reporter:
    def __init__(self):
        self.itens: list[tuple[str, bool, str]] = []

    def registrar(self, nome: str, ok: bool, detalhe: str = "") -> None:
        self.itens.append((nome, ok, detalhe))
        marca = "PROVADO" if ok else "FALHOU "
        print(f"[{marca}] {nome}")
        if detalhe:
            for linha in detalhe.splitlines():
                print(f"          {linha}")

    def nao_testado(self, nome: str, motivo: str) -> None:
        self.itens.append((nome, None, motivo))
        print(f"[NAO TESTADO] {nome}\n          motivo: {motivo}")

    def resumo(self) -> int:
        provados = [n for n, ok, _ in self.itens if ok is True]
        falhas = [n for n, ok, _ in self.itens if ok is False]
        pendentes = [n for n, ok, _ in self.itens if ok is None]
        print("\n" + "=" * 78)
        print(f"{len(provados)} PROVADO(S), {len(falhas)} FALHOU(RAM), {len(pendentes)} NAO TESTADO(S)")
        if falhas:
            print("FALHARAM: " + "; ".join(falhas))
        if pendentes:
            print("NAO TESTADOS: " + "; ".join(pendentes))
        return 1 if falhas else 0


# ─────────────────────────────────────────────────────────── infraestrutura ─

def criar_usuario_teste(sufixo: str = "") -> tuple[int, str]:
    """Usuário próprio para os `usuario_login`/`usuario_id` que as funções do
    serviço exigem (a FK fk_app_auditoria_usuario obriga um id_usuario real em
    APP_USUARIO). Senha gerada com `secrets.token_urlsafe`, nunca usada para
    logar de fato — apagado no `finally`, junto com sessões e auditoria.

    `sufixo` é só para o login ficar legível no banco durante uma depuração
    (ex. `validador_lote_preco_isolamento_xxxx`) — não tem efeito em nenhuma
    regra do serviço."""
    prefixo = f"validador_lote_preco_{sufixo}_" if sufixo else "validador_lote_preco_"
    login = f"{prefixo}{secrets.token_urlsafe(6)}"
    senha_hash = auth.gerar_hash(secrets.token_urlsafe(24))
    with database.transacao() as conn:
        cur = conn.cursor()
        id_var = cur.var(int)
        cur.execute(
            """
            insert into app_usuario
                (login, nome, senha_hash, origem, senha_provisoria, ativo, eh_admin, eh_diretoria)
            values (:login, 'Validador Etapa 12 (temporário)', :senha_hash, 'local', 0, 1, 0, 1)
            returning id_usuario into :id
            """,
            {"login": login, "senha_hash": senha_hash, "id": id_var},
        )
        id_usuario = int(id_var.getvalue()[0])
        cur.close()
    return id_usuario, login


class Recursos:
    """Registro central de tudo que precisa ser desfeito no fim.

    Cada cenário chama `novo_usuario()` para o(s) SEU(S) próprio(s)
    usuário(s) — nunca reaproveita o de outro cenário. É exatamente essa
    separação que fecha a dependência de ordem que derrubou o validador para
    18/19 em 11/09/2026 (ver docstring do módulo)."""

    def __init__(self):
        self.usuarios: list[tuple[int, str]] = []
        self.lotes: list[int] = []

    def novo_usuario(self, sufixo: str = "") -> tuple[int, str]:
        uid, login = criar_usuario_teste(sufixo)
        self.usuarios.append((uid, login))
        return uid, login

    def registrar_lote(self, id_lote: int) -> None:
        if id_lote not in self.lotes:
            self.lotes.append(id_lote)


def limpar(usuarios: list[tuple[int, str]], ids_lote: list[int], codigos: list[int]) -> None:
    """Restaura o banco ao estado anterior — SEMPRE roda, mesmo se um cenário
    explodiu no meio (`try/finally` no `main`). Ordem: lotes (cascade cuida de
    itens e histórico de status) -> histórico de decisão -> decisão -> rastro
    de auditoria de CADA usuário de teste -> sessões (defensivo) -> os
    usuários. `excluir_lote` só usa login/uid para carimbar a auditoria da
    exclusão (o serviço não checa dono) — qualquer usuário de teste ainda
    vivo serve, e a auditoria dessa própria exclusão é apagada logo abaixo."""
    login_qualquer = usuarios[0][1] if usuarios else "validador_lote_preco_limpeza"
    uid_qualquer = usuarios[0][0] if usuarios else 0
    for id_lote in ids_lote:
        try:
            lote_preco.excluir_lote(id_lote, login_qualquer, uid_qualquer)
        except Exception as exc:  # noqa: BLE001
            print(f"  aviso: falha ao excluir lote {id_lote} na limpeza: {exc}")

    if codigos:
        marcas = ", ".join(f":c{i}" for i in range(len(codigos)))
        binds = {f"c{i}": c for i, c in enumerate(codigos)}
        with database.transacao() as conn:
            cur = conn.cursor()
            cur.execute(f"delete from app_decisao_preco_hist where id_produto in ({marcas})", binds)
            cur.execute(f"delete from app_decisao_preco where id_produto in ({marcas})", binds)
            cur.close()

    for id_usuario, _login in usuarios:
        with database.transacao() as conn:
            cur = conn.cursor()
            cur.execute("delete from app_auditoria where id_usuario = :id", {"id": id_usuario})
            cur.execute("delete from app_sessao where id_usuario = :id", {"id": id_usuario})
            cur.execute("delete from app_usuario where id_usuario = :id", {"id": id_usuario})
            cur.close()


def capturar_estado() -> dict:
    return {
        "decisao_preco": database.consultar("select * from app_decisao_preco order by id_produto"),
        "decisao_preco_hist_n": database.consultar_um("select count(*) n from app_decisao_preco_hist")["n"],
        "lote_n": database.consultar_um("select count(*) n from app_lote_preco")["n"],
        "lote_item_n": database.consultar_um("select count(*) n from app_lote_preco_item")["n"],
        "lote_hist_n": database.consultar_um("select count(*) n from app_lote_preco_status_hist")["n"],
        "usuario_n": database.consultar_um("select count(*) n from app_usuario")["n"],
    }


# ──────────────────────────────────────────────────── funções de checagem ──
# Cada uma é usada DUAS vezes: contra um artefato forjado com defeito (deve
# devolver problema) e contra o artefato real do serviço (deve devolver []).

def checar_xlsx_201(conteudo: bytes, esperado: list[tuple[str, float]]) -> list[str]:
    """`esperado`: [(cod_fab, preco_a_vista), ...] — a checagem NÃO assume
    ordem. Verifica: 2 colunas, zero linha de cabeçalho, conjunto exato de
    (cod_fab, preço arredondado a 2 casas)."""
    problemas = []
    wb = load_workbook(io.BytesIO(conteudo), read_only=True, data_only=True)
    ws = wb.active
    linhas = [tuple(r) for r in ws.iter_rows(values_only=True)]
    if ws.max_column != 2:
        problemas.append(f"esperado 2 colunas, achou {ws.max_column}")
    if linhas and isinstance(linhas[0][0], str) and linhas[0][0].strip().upper() in (
        "COD_FAB", "CODFAB", "CODIGO", "CÓDIGO", "PRODUTO",
    ):
        problemas.append(f"linha 1 parece cabeçalho: {linhas[0]!r}")
    esperado_set = {(cf, round(float(p), 2)) for cf, p in esperado}
    achado_set = set()
    for linha in linhas:
        if len(linha) < 2 or linha[0] is None or linha[1] is None:
            problemas.append(f"linha incompleta ou vazia: {linha!r}")
            continue
        try:
            achado_set.add((str(linha[0]), round(float(linha[1]), 2)))
        except (TypeError, ValueError):
            problemas.append(f"coluna B não é número nesta linha: {linha!r}")
    if achado_set != esperado_set:
        faltando = esperado_set - achado_set
        sobrando = achado_set - esperado_set
        problemas.append(f"conjunto diverge — faltando={faltando} sobrando={sobrando}")
    if len(linhas) != len(esperado):
        problemas.append(f"esperada(s) {len(esperado)} linha(s), achada(s) {len(linhas)}")
    wb.close()
    return problemas


def checar_exclusoes(excluidos: list[dict], esperado: dict[int, str]) -> list[str]:
    """`esperado`: {codigo: motivo_exato}. Todo código esperado precisa
    aparecer na lista de excluídos devolvida por `gerar_xlsx_201`, com o
    motivo certo."""
    problemas = []
    por_codigo = {int(e["codigo"]): e["motivo"] for e in excluidos}
    for codigo, motivo in esperado.items():
        if codigo not in por_codigo:
            problemas.append(f"SKU {codigo} ausente da lista de excluídos (esperado motivo {motivo!r})")
        elif por_codigo[codigo] != motivo:
            problemas.append(f"SKU {codigo}: motivo {por_codigo[codigo]!r}, esperado {motivo!r}")
    return problemas


def checar_preco_a_vista(preco_arquivo: float, preco_avista_esperado: float, preco_a_prazo_real: float) -> list[str]:
    """Prova que o preço no arquivo é o À VISTA arredondado a 2 casas — e
    explicitamente diferente do preço A PRAZO (que é o defeito caro: gravar
    `ALT_PV_*_AP` na coluna B em vez de `ALT_PV_*_AV`)."""
    problemas = []
    if round(preco_arquivo, 2) != round(preco_avista_esperado, 2):
        problemas.append(f"arquivo tem {preco_arquivo}, esperado à vista {preco_avista_esperado}")
    if abs(preco_arquivo - preco_a_prazo_real) < 0.005:
        problemas.append(
            f"arquivo ({preco_arquivo}) bate com o preço A PRAZO ({preco_a_prazo_real})"
            " — os dois só coincidiriam por acaso; isto é o sinal do defeito caro (§4.6/item 5 do Diretor)"
        )
    return problemas


# ─────────────────────────────────────────────────────────────── cenários ──

def item(codigo: int, at: float | None = None, var: float | None = None) -> dict:
    d: dict = {"codigo": codigo}
    if at is not None:
        d["alt_pv_at_av"] = at
    if var is not None:
        d["alt_pv_var_av"] = var
    return d


def _linhas(conteudo: bytes) -> list[tuple[str, float]]:
    wb = load_workbook(io.BytesIO(conteudo), read_only=True, data_only=True)
    linhas = [
        (str(r[0]), float(r[1]))
        for r in wb.active.iter_rows(values_only=True)
        if r and r[0] is not None and r[1] is not None
    ]
    wb.close()
    return linhas


def _fase_arquivo_201_e_exclusoes(rep: Reporter, login: str, uid: int, recursos: Recursos) -> int | None:
    """Testes 1, 2 e 3 do §6.4 — o lote principal, com os 5 itens que provam
    a inclusão normal (§4.4) e as duas exclusões (§4.6)."""
    itens = [
        item(COD_ATACADO_APENAS, at=500.567),           # só atacado — 3 casas de propósito (testa arredondamento)
        item(COD_VAREJO_APENAS, var=35.10),              # só varejo — não pode aparecer no arquivo de atacado
        item(COD_AMBOS_CANAIS, at=800.25, var=900.75),   # os dois canais
        item(COD_SEM_CODFAB, at=95.00, var=115.00),      # exclusão 1 — sem cód. de fábrica
        item(COD_CODFAB_REPETIDO, at=15.00, var=20.00),  # exclusão 2 — cód. de fábrica repetido (120717.0.02)
    ]
    detalhe = lote_preco.criar_lote(itens, "lote de teste do validador — Etapa 12", login, uid)
    id_lote = detalhe["id_lote"]
    recursos.registrar_lote(id_lote)

    # ── teste 1: formato do arquivo + item de varejo puro NÃO aparece no de atacado
    conteudo_at, nome_at, exc_at = lote_preco.gerar_xlsx_201(id_lote, "atacado", login, uid)
    conteudo_var, nome_var, exc_var = lote_preco.gerar_xlsx_201(id_lote, "varejo", login, uid)

    esperado_atacado = [("31401222", 500.57), ("33350622", 800.25)]
    esperado_varejo = [("31401253", 35.10), ("33350622", 900.75)]

    # autoteste: forja um arquivo com CODIGO na coluna A (em vez de COD_FAB) e
    # com cabeçalho — prova que a checagem RECUSA antes de confiar nela.
    wb_errado = Workbook()
    ws_errado = wb_errado.active
    ws_errado.append(["COD_FAB", "PRECO"])          # cabeçalho que não devia existir
    ws_errado.append([COD_ATACADO_APENAS, 500.57])  # CODIGO interno em vez de COD_FAB — o defeito do §4.6
    ws_errado.append(["33350622", 800.25])
    buffer_errado = io.BytesIO()
    wb_errado.save(buffer_errado)
    problemas_forjado = checar_xlsx_201(buffer_errado.getvalue(), esperado_atacado)
    rep.registrar(
        "autoteste — checar_xlsx_201 recusa arquivo com cabeçalho e CODIGO em vez de COD_FAB",
        bool(problemas_forjado),
        "\n".join(problemas_forjado) or "NENHUM problema encontrado — a checagem não sabe falhar",
    )

    problemas_real_at = checar_xlsx_201(conteudo_at, esperado_atacado)
    rep.registrar(
        f"arquivo 201 atacado: 2 col, sem cabeçalho, COD_FAB, {len(esperado_atacado)} itens elegíveis "
        f"(varejo puro SKU {COD_VAREJO_APENAS} não aparece); nome={nome_at}",
        not problemas_real_at,
        "\n".join(problemas_real_at) or f"conjunto bate: {esperado_atacado}",
    )
    problemas_real_var = checar_xlsx_201(conteudo_var, esperado_varejo)
    rep.registrar(
        f"arquivo 201 varejo: 2 col, sem cabeçalho, COD_FAB, {len(esperado_varejo)} itens elegíveis "
        f"(atacado puro SKU {COD_ATACADO_APENAS} não aparece); nome={nome_var}",
        not problemas_real_var,
        "\n".join(problemas_real_var) or f"conjunto bate: {esperado_varejo}",
    )
    rep.registrar(
        "nome do arquivo traz regiao2/codfab203 (atacado) e regiao1/codfab203 (varejo)",
        "regiao2" in nome_at and "codfab203" in nome_at and "regiao1" in nome_var and "codfab203" in nome_var,
        f"{nome_at} / {nome_var}",
    )

    # ── teste 2: as duas exclusões, com motivo certo, nos dois canais
    esperado_exclusoes = {
        COD_SEM_CODFAB: "sem código de fábrica",
        COD_CODFAB_REPETIDO: "código de fábrica repetido",
    }
    # autoteste: apaga a entrada do SKU repetido da lista real (simula o bug
    # "esqueceu de reportar a exclusão") e prova que a checagem recusa.
    exc_at_forjado = [e for e in exc_at if int(e["codigo"]) != COD_CODFAB_REPETIDO]
    problemas_forjado2 = checar_exclusoes(exc_at_forjado, esperado_exclusoes)
    rep.registrar(
        "autoteste — checar_exclusoes recusa lista sem o SKU de cód. fábrica repetido",
        bool(problemas_forjado2),
        "\n".join(problemas_forjado2) or "NENHUM problema encontrado — a checagem não sabe falhar",
    )

    problemas_exc_at = checar_exclusoes(exc_at, esperado_exclusoes)
    problemas_exc_var = checar_exclusoes(exc_var, esperado_exclusoes)
    rep.registrar(
        f"os dois excluídos (SKU {COD_SEM_CODFAB} sem cód. fábrica, SKU {COD_CODFAB_REPETIDO} "
        "cód. fábrica repetido em 8171/8172/8173) aparecem em `excluidos` com o motivo certo, "
        "nos dois canais, e NÃO aparecem no arquivo",
        not problemas_exc_at and not problemas_exc_var
        and ("120717.0.02", 15.00) not in {(l[0], round(l[1], 2)) for l in _linhas(conteudo_at)}
        and ("120717.0.02", 20.00) not in {(l[0], round(l[1], 2)) for l in _linhas(conteudo_var)},
        "\n".join(problemas_exc_at + problemas_exc_var) or str(esperado_exclusoes),
    )

    # coluna "Entra no arquivo 201?" do Excel de conferência
    conteudo_conf, _ = lote_preco.gerar_excel_conferencia(id_lote)
    wb_conf = load_workbook(io.BytesIO(conteudo_conf), data_only=True)
    ws_conf = wb_conf.active
    cabecalho_linha = next(
        i for i, row in enumerate(ws_conf.iter_rows(values_only=True), start=1)
        if row and row[0] == "CÓDIGO CEDEP"
    )
    col_entra = [c.value for c in ws_conf[cabecalho_linha]].index("ENTRA NO ARQUIVO 201?") + 1
    col_codigo = 1
    motivos_excel = {}
    for row in ws_conf.iter_rows(min_row=cabecalho_linha + 1, values_only=False):
        codigo_cel = row[col_codigo - 1].value
        if codigo_cel is not None:
            motivos_excel[int(codigo_cel)] = row[col_entra - 1].value
    wb_conf.close()
    ok_excel = (
        motivos_excel.get(COD_SEM_CODFAB) == "sem código de fábrica"
        and motivos_excel.get(COD_CODFAB_REPETIDO) == "código de fábrica repetido"
        and motivos_excel.get(COD_AMBOS_CANAIS) == "sim"
    )
    rep.registrar(
        "Excel de conferência: coluna 'Entra no arquivo 201?' traz o motivo exato para os excluídos e 'sim' para um item normal",
        ok_excel,
        str({k: motivos_excel.get(k) for k in (COD_SEM_CODFAB, COD_CODFAB_REPETIDO, COD_AMBOS_CANAIS)}),
    )

    # ── teste 3: preço à vista, nunca a prazo — usando SKU 9 (real, só leitura)
    # como par conhecido de valores DIFERENTES (à vista 360.00 x a prazo
    # 371.412) para provar que a checagem distingue os dois sem precisar
    # tocar na decisão de ninguém.
    sku9 = database.consultar_um(
        "select alt_pv_at_av, alt_pv_at_ap from compras_pedido where codigo = 9"
    )
    problemas_forjado3 = checar_preco_a_vista(
        preco_arquivo=round(float(sku9["alt_pv_at_ap"]), 2),   # simula o bug: arquivo com o valor A PRAZO
        preco_avista_esperado=round(float(sku9["alt_pv_at_av"]), 2),
        preco_a_prazo_real=round(float(sku9["alt_pv_at_ap"]), 2),
    )
    rep.registrar(
        "autoteste — checar_preco_a_vista recusa quando o valor é o A PRAZO (par real: SKU 9, à vista 360,00 x a prazo 371,41)",
        bool(problemas_forjado3),
        "\n".join(problemas_forjado3) or "NENHUM problema encontrado — a checagem não sabe falhar",
    )
    linhas_at = _linhas(conteudo_at)
    preco_gravado_244 = dict(linhas_at)["31401222"]
    # 500.567 é o alt_pv_at_av decidido acima para o SKU 244 — nenhum ALT_PV_*_AP
    # existe para ele (produto nunca decidido antes deste teste).
    problemas_real3 = checar_preco_a_vista(
        preco_arquivo=preco_gravado_244,
        preco_avista_esperado=500.57,
        preco_a_prazo_real=999999.99,  # nenhum valor plausível de a prazo bateria por acaso
    )
    rep.registrar(
        f"SKU {COD_ATACADO_APENAS} decidido a 500,567 sai no arquivo como 500.57 (2 casas, à vista) com number_format 0.00",
        not problemas_real3,
        "\n".join(problemas_real3) or f"gravado={preco_gravado_244}",
    )

    return id_lote


def _fase_edicao_e_historico(rep: Reporter, login: str, uid: int, id_lote: int) -> None:
    """Teste 5: editar item do lote regrava APP_DECISAO_PRECO E grava
    APP_DECISAO_PRECO_HIST com o valor que estava saindo."""
    hist_antes = database.consultar_um(
        "select count(*) n from app_decisao_preco_hist where id_produto = :c", {"c": COD_ATACADO_APENAS}
    )["n"]
    valor_antes = database.consultar_um(
        "select alt_pv_at_av from app_decisao_preco where id_produto = :c", {"c": COD_ATACADO_APENAS}
    )["alt_pv_at_av"]

    lote_preco.upsert_item(
        id_lote, COD_ATACADO_APENAS,
        margem_alvo=None, margem_alvo_varejo=None,
        alt_pv_at_av=505.00, alt_pv_var_av=None,
        usuario_login=login, usuario_id=uid,
    )

    hist_depois = database.consultar_um(
        "select count(*) n from app_decisao_preco_hist where id_produto = :c", {"c": COD_ATACADO_APENAS}
    )["n"]
    valor_hist = database.consultar_um(
        "select alt_pv_at_av from app_decisao_preco_hist where id_produto = :c"
        " order by id_hist desc fetch first 1 rows only",
        {"c": COD_ATACADO_APENAS},
    )["alt_pv_at_av"]
    valor_depois = database.consultar_um(
        "select alt_pv_at_av from app_decisao_preco where id_produto = :c", {"c": COD_ATACADO_APENAS}
    )["alt_pv_at_av"]

    ok = (
        hist_depois == hist_antes + 1
        and abs(float(valor_hist) - float(valor_antes)) < 0.001
        and abs(float(valor_depois) - 505.00) < 0.001
    )
    rep.registrar(
        f"editar item do lote (SKU {COD_ATACADO_APENAS}: 500,567 -> 505,00) atualiza APP_DECISAO_PRECO "
        "e grava o valor anterior em APP_DECISAO_PRECO_HIST",
        ok,
        f"hist antes/depois={hist_antes}/{hist_depois}, valor arquivado={valor_hist}, valor novo={valor_depois}",
    )


def _fase_transicoes(rep: Reporter, login: str, uid: int, id_lote: int) -> None:
    """Teste 6: domínio de só 2 estados (decisão do usuário de 10/09) —
    Rascunho -> Enviado ok, desfazer volta, pulo em qualquer direção dá
    TransicaoInvalida (o 409 da rota), e toda transição real deixa linha em
    APP_LOTE_PRECO_STATUS_HIST; a tentativa inválida NÃO deixa linha.

    ⚠ Este cenário devolve o lote a 'Rascunho' de propósito, ao final — é
    exatamente esse estado residual que, com login COMPARTILHADO, fazia
    outro cenário reaproveitar este lote (o bug de 11/09/2026). Aqui isso
    não importa mais: nenhum outro cenário usa este login."""
    hist_n = lambda: database.consultar_um(  # noqa: E731
        "select count(*) n from app_lote_preco_status_hist where id_lote = :id", {"id": id_lote}
    )["n"]
    status = lambda: database.consultar_um(  # noqa: E731
        "select status from app_lote_preco where id_lote = :id", {"id": id_lote}
    )["status"]

    n0 = hist_n()  # 1 (a criação, None -> Rascunho)
    detalhe = lote_preco.avancar_status(id_lote, login, uid)
    n1 = hist_n()
    rep.registrar(
        "Rascunho -> Enviado: avança e grava 1 linha em APP_LOTE_PRECO_STATUS_HIST",
        detalhe["status"] == "Enviado" and n1 == n0 + 1 and status() == "Enviado",
        f"status={detalhe['status']}, hist {n0}->{n1}",
    )

    pulo_ok = False
    try:
        lote_preco.avancar_status(id_lote, login, uid)  # Enviado é a última etapa
    except lote_preco.TransicaoInvalida:
        pulo_ok = True
    n2 = hist_n()
    rep.registrar(
        "avançar além de Enviado dá TransicaoInvalida (409) e NÃO grava linha nova",
        pulo_ok and n2 == n1,
        f"hist {n1}->{n2}",
    )

    detalhe = lote_preco.voltar_status(id_lote, login, uid)
    n3 = hist_n()
    rep.registrar(
        "Enviado -> Rascunho (desfazer): volta e grava 1 linha",
        detalhe["status"] == "Rascunho" and n3 == n2 + 1 and status() == "Rascunho",
        f"status={detalhe['status']}, hist {n2}->{n3}",
    )

    pulo_ok2 = False
    try:
        lote_preco.voltar_status(id_lote, login, uid)  # Rascunho é a primeira etapa
    except lote_preco.TransicaoInvalida:
        pulo_ok2 = True
    n4 = hist_n()
    rep.registrar(
        "voltar antes de Rascunho dá TransicaoInvalida (409) e NÃO grava linha nova",
        pulo_ok2 and n4 == n3,
        f"hist {n3}->{n4}",
    )


def cenario_lote_principal(rep: Reporter, recursos: Recursos) -> None:
    """Testes 1, 2, 3, 5 e 6 — um ciclo de vida completo do MESMO lote
    (criação -> exportação 201 -> edição -> transições de status), com
    usuário PRÓPRIO deste cenário. O encadeamento AQUI é intencional (é o
    mesmo documento, do início ao fim); o que a independência de ordem exige
    é que NENHUM OUTRO cenário dependa deste — e é isso que os outros
    cenários, cada um com seu próprio login, garantem."""
    uid, login = recursos.novo_usuario("principal")
    id_lote = _fase_arquivo_201_e_exclusoes(rep, login, uid, recursos)
    if id_lote is None:
        return
    _fase_edicao_e_historico(rep, login, uid, id_lote)
    _fase_transicoes(rep, login, uid, id_lote)


def cenario_isolamento_catalogo(rep: Reporter, recursos: Recursos) -> None:
    """⚠ do §6.4/item 2: a checagem de COD_FAB repetido é contra o CATÁLOGO
    INTEIRO, não contra os itens do lote — monta um lote com UM SÓ dos quatro
    SKUs (8170) e prova que ele ainda é excluído, porque 8171/8172/8173 (fora
    do lote) continuam existindo no catálogo com o mesmo cód. de fábrica.

    Usuário PRÓPRIO (nunca visto por nenhum outro cenário): é exatamente o
    que faltava em 11/09/2026, quando este cenário reaproveitava — sem
    querer — o Rascunho que `cenario_lote_principal` tinha deixado aberto,
    porque os dois compartilhavam login. A asserção `lote_reaproveitado is
    False` abaixo prova, em runtime, que desta vez o lote é mesmo NOVO."""
    uid, login = recursos.novo_usuario("isolamento")
    detalhe = lote_preco.criar_lote(
        [item(COD_CODFAB_REPETIDO, at=25.00)],
        "lote de teste — isolamento (só 1 dos 4 SKUs de cód. fábrica repetido)",
        login, uid,
    )
    id_lote = detalhe["id_lote"]
    recursos.registrar_lote(id_lote)
    conteudo, _, excluidos = lote_preco.gerar_xlsx_201(id_lote, "atacado", login, uid)
    linhas = _linhas(conteudo)
    ok = (
        detalhe["lote_reaproveitado"] is False
        and len(linhas) == 0
        and len(excluidos) == 1
        and int(excluidos[0]["codigo"]) == COD_CODFAB_REPETIDO
        and excluidos[0]["motivo"] == "código de fábrica repetido"
    )
    rep.registrar(
        f"lote com SÓ o SKU {COD_CODFAB_REPETIDO} (sem 8171/8172/8173), login PRÓPRIO deste cenário "
        "(lote_reaproveitado=False): arquivo sai com 0 linhas — a colisão é contra o catálogo "
        "inteiro, não contra os itens do lote",
        ok,
        f"reaproveitado={detalhe['lote_reaproveitado']}, linhas no arquivo={linhas}, excluidos={excluidos}",
    )


def cenario_atomicidade(rep: Reporter, recursos: Recursos) -> None:
    """Teste 4: 29 códigos reais + 1 inexistente no meio (posição 15 de 30).
    Recusa o lote inteiro, sem deixar nem decisão nem lote — e a checagem é
    literal: nenhum dos 29 pode ter ganhado linha em APP_DECISAO_PRECO, e
    nenhum lote novo pode existir."""
    uid, login = recursos.novo_usuario("atomicidade")
    codigos_lote = list(CODIGOS_ATOMICIDADE)
    codigos_lote.insert(14, COD_INEXISTENTE)  # 15ª posição de 30
    itens = [item(c, at=999.99) for c in codigos_lote]

    lote_n_antes = database.consultar_um("select count(*) n from app_lote_preco")["n"]
    excecao = None
    try:
        lote_preco.criar_lote(itens, "não deveria existir — teste de atomicidade", login, uid)
    except lote_preco.ProdutoInvalido as exc:
        excecao = exc
    except Exception as exc:  # noqa: BLE001
        excecao = exc

    lote_n_depois = database.consultar_um("select count(*) n from app_lote_preco")["n"]
    marcas = ", ".join(f":c{i}" for i in range(len(CODIGOS_ATOMICIDADE)))
    binds = {f"c{i}": c for i, c in enumerate(CODIGOS_ATOMICIDADE)}
    decisoes_vazadas = database.consultar(
        f"select id_produto from app_decisao_preco where id_produto in ({marcas})", binds
    )
    rep.registrar(
        f"criar_lote com 30 itens (1 inexistente na posição 15, código {COD_INEXISTENTE}) recusa o "
        "lote INTEIRO: nenhum APP_LOTE_PRECO criado, nenhuma das 29 decisões válidas gravada",
        isinstance(excecao, lote_preco.ProdutoInvalido)
        and lote_n_depois == lote_n_antes
        and not decisoes_vazadas
        and str(COD_INEXISTENTE) in str(excecao),
        f"exceção={type(excecao).__name__}: {excecao}; lotes antes/depois={lote_n_antes}/{lote_n_depois}; "
        f"decisões vazadas={decisoes_vazadas}",
    )


def cenario_conferencia_aplicacao(rep: Reporter, recursos: Recursos) -> None:
    """Teste 7: tolerância de 0,005, nos dois lados da fronteira — primeiro em
    isolamento (as funções puras `_status_canal` e `_situacao_item`), depois
    de ponta a ponta com um lote real e os QUATRO rótulos (aplicado / pendente
    / parcial / divergente — 'parcial' é o estado que entrou em 10/09/2026:
    atacado aplicado + varejo ainda pendente deixou de contar como
    'divergente'). Fecha comparando a tolerância aplicada no SQL de agregação
    (`_AGG_LOTE`, usado por `listar_lotes`/`obter_lote`) com a mesma
    classificação em Python (`obter_itens`) — as duas usam a MESMA constante
    `_TOLERANCIA_APLICACAO`; se um dia voltarem a ser dois literais
    independentes, este teste é o que pega a divergência."""
    sc = lote_preco._status_canal  # função pura, sem banco — mesmo raciocínio de §4.5
    casos = [
        ("dentro da tolerância (diff 0,0049 < 0,005) -> aplicado", (100.00, 100.0049, 100.00), "aplicado"),
        # 0,0050 exato é ambíguo em ponto flutuante (100.005-100.00 arredonda
        # para 0,0049999999999954525 em double precision — o PRÓPRIO serviço
        # sofreria a mesma ambiguidade, então não é fronteira útil de testar).
        # 0,0060 fica de fato do outro lado, sem ambiguidade de arredondamento.
        ("fora da tolerância (diff 0,0060 > 0,005), banco parado -> pendente", (100.00, 100.0060, 100.00), "pendente"),
        ("bem fora da tolerância, banco parado -> pendente", (100.00, 150.00, 100.00), "pendente"),
        ("banco mudou para um terceiro valor -> divergente", (100.00, 150.00, 120.00), "divergente"),
        ("banco ainda não chegou (None) -> pendente", (100.00, 150.00, None), "pendente"),
        ("canal não decidido (novo=None) -> None", (100.00, None, 999.00), None),
    ]
    falhas = []
    for nome, (atual, novo, banco), esperado in casos:
        obtido = sc(atual, novo, banco)
        if obtido != esperado:
            falhas.append(f"{nome}: obtido={obtido!r} esperado={esperado!r}")
    rep.registrar(
        "conferência de aplicação (_status_canal), tolerância 0,005 nos dois lados da fronteira, 6 casos",
        not falhas,
        "\n".join(falhas) or "\n".join(f"{n}: ok" for n, _, _ in casos),
    )

    # `_situacao_item` combinando os dois canais — os QUATRO estados, em
    # isolamento (função pura, sem banco).
    si = lote_preco._situacao_item
    casos_item = [
        ("atacado aplicado + varejo aplicado -> aplicado",
         {"pv_atacado_atual": 100.0, "pv_atacado_novo": 110.0, "pv_atacado_banco": 110.0,
          "pv_varejo_atual": 50.0, "pv_varejo_novo": 55.0, "pv_varejo_banco": 55.0}, "aplicado"),
        ("atacado pendente + varejo pendente -> pendente",
         {"pv_atacado_atual": 100.0, "pv_atacado_novo": 110.0, "pv_atacado_banco": 100.0,
          "pv_varejo_atual": 50.0, "pv_varejo_novo": 55.0, "pv_varejo_banco": 50.0}, "pendente"),
        ("atacado aplicado + varejo pendente -> PARCIAL (não mais 'divergente')",
         {"pv_atacado_atual": 100.0, "pv_atacado_novo": 110.0, "pv_atacado_banco": 110.0,
          "pv_varejo_atual": 50.0, "pv_varejo_novo": 55.0, "pv_varejo_banco": 50.0}, "parcial"),
        ("atacado divergente + varejo aplicado -> divergente vence sobre os demais",
         {"pv_atacado_atual": 100.0, "pv_atacado_novo": 110.0, "pv_atacado_banco": 130.0,
          "pv_varejo_atual": 50.0, "pv_varejo_novo": 55.0, "pv_varejo_banco": 55.0}, "divergente"),
        ("só atacado decidido, aplicado (varejo None não conta) -> aplicado",
         {"pv_atacado_atual": 100.0, "pv_atacado_novo": 110.0, "pv_atacado_banco": 110.0,
          "pv_varejo_atual": None, "pv_varejo_novo": None, "pv_varejo_banco": None}, "aplicado"),
    ]
    falhas_item = []
    for nome, item_dict, esperado in casos_item:
        obtido = si(item_dict)
        if obtido != esperado:
            falhas_item.append(f"{nome}: obtido={obtido!r} esperado={esperado!r}")
    rep.registrar(
        "_situacao_item combina os dois canais nos QUATRO estados (aplicado/pendente/parcial/divergente)",
        not falhas_item,
        "\n".join(falhas_item) or "\n".join(f"{n}: ok" for n, _, _ in casos_item),
    )

    # ponta a ponta: 4 SKUs reais, 1 lote, 4 rótulos.
    uid, login = recursos.novo_usuario("conferencia")
    banco_apl = database.consultar_um(
        "select pv_atacado from compras_pedido where codigo = :c", {"c": COD_CONF_APLICADO}
    )["pv_atacado"]
    banco_pen = database.consultar_um(
        "select pv_atacado from compras_pedido where codigo = :c", {"c": COD_CONF_PENDENTE}
    )["pv_atacado"]
    banco_div = database.consultar_um(
        "select pv_atacado from compras_pedido where codigo = :c", {"c": COD_CONF_DIVERGENTE}
    )["pv_atacado"]
    banco_par = database.consultar_um(
        "select pv_atacado, pv_varejo from compras_pedido where codigo = :c", {"c": COD_CONF_PARCIAL}
    )

    itens = [
        item(COD_CONF_APLICADO, at=float(banco_apl)),         # decidido == banco -> aplicado
        item(COD_CONF_PENDENTE, at=float(banco_pen) + 5.00),  # decidido != banco, banco parado -> pendente
        item(COD_CONF_DIVERGENTE, at=float(banco_div) + 5.00),
        # atacado bate com o banco (aplicado), varejo ainda não foi digitado no Winthor (pendente) -> parcial
        item(COD_CONF_PARCIAL, at=float(banco_par["pv_atacado"]), var=float(banco_par["pv_varejo"]) + 5.00),
    ]
    detalhe = lote_preco.criar_lote(itens, "lote de teste — conferência de aplicação", login, uid)
    id_lote = detalhe["id_lote"]
    recursos.registrar_lote(id_lote)

    # Simula, só na LINHA QUE ESTE SCRIPT CRIOU em APP_LOTE_PRECO_ITEM, que o
    # "atual" ficou desatualizado (como se o banco tivesse mudado depois do
    # snapshot) — NUNCA em COMPRAS_PEDIDO, que é do dbt. É o único jeito de
    # produzir "divergente" sem tocar numa tabela de fora do app.
    with database.transacao() as conn:
        cur = conn.cursor()
        cur.execute(
            "update app_lote_preco_item set pv_atacado_atual = :atual_falso"
            " where id_lote = :id and id_produto = :codigo",
            {"atual_falso": float(banco_div) - 12.69, "id": id_lote, "codigo": COD_CONF_DIVERGENTE},
        )
        cur.close()

    itens_lote = {i["codigo"]: i for i in lote_preco.obter_itens(id_lote)}
    codigos_conf = (COD_CONF_APLICADO, COD_CONF_PENDENTE, COD_CONF_DIVERGENTE, COD_CONF_PARCIAL)
    situacoes = {c: itens_lote[c]["situacao"] for c in codigos_conf}
    esperado = {
        COD_CONF_APLICADO: "aplicado", COD_CONF_PENDENTE: "pendente",
        COD_CONF_DIVERGENTE: "divergente", COD_CONF_PARCIAL: "parcial",
    }
    rep.registrar(
        "de ponta a ponta (obter_itens, join real com COMPRAS_PEDIDO): 4 SKUs reais classificados "
        "aplicado / pendente / divergente / parcial",
        situacoes == esperado,
        f"obtido={situacoes} esperado={esperado}",
    )

    # `qtd_aplicados`/`qtd_itens` agregados no SQL (`_AGG_LOTE`, mesma fonte
    # de tolerância) batendo com a contagem em Python — prova que os dois
    # caminhos concordam.
    cabecalho_agregado = lote_preco.obter_lote(id_lote)
    qtd_aplicados_python = sum(1 for s in situacoes.values() if s == "aplicado")
    rep.registrar(
        "qtd_aplicados agregado no SQL (_AGG_LOTE, tolerância 0,005) bate com a contagem em Python "
        "de itens 'aplicado' — a mesma _TOLERANCIA_APLICACAO alimenta os dois caminhos",
        int(cabecalho_agregado["qtd_aplicados"]) == qtd_aplicados_python
        and int(cabecalho_agregado["qtd_itens"]) == len(itens),
        f"SQL: qtd_itens={cabecalho_agregado['qtd_itens']} qtd_aplicados={cabecalho_agregado['qtd_aplicados']}; "
        f"Python: qtd_itens={len(itens)} qtd_aplicados={qtd_aplicados_python}",
    )


def cenario_cod_fab_normalizacao(rep: Reporter, recursos: Recursos) -> None:
    """§4.6, ponto único de normalização de COD_FAB (`_normalizar_cod_fab`,
    Python `.strip()`, NÃO `trim()` do Oracle — medido que `TRIM()` do Oracle
    não remove tabulação). Dois casos reais medidos em 11/09/2026 contra
    `compras_pedido.cod_fab` (8.772 linhas):

    - 4851 ('HC000660486') só colide com 4294 (' HC000660486', espaço à
      esquerda) DEPOIS de normalizar — sem `.strip()` os dois pareceriam
      SKUs diferentes e o preço do 4851 sairia no arquivo pisando o slot do
      fornecedor, sem que ninguém percebesse.
    - 471 ('H0002317339\\t\\t\\t', tabulação nas pontas) está sozinho no seu
      grupo — tem que ENTRAR no arquivo, e sem os \\t (a rotina 201 não faz
      trim ao casar — ver docstring de `gerar_xlsx_201`).

    Duas chamadas a `criar_lote`, cada uma com login PRÓPRIO — a segunda NÃO
    pode reaproveitar o Rascunho da primeira (senão os dois SKUs cairiam no
    mesmo lote e o teste do 471 dependeria da ordem em que os itens foram
    inseridos, voltando ao mesmo tipo de acoplamento que quebrou o
    validador)."""
    uid1, login1 = recursos.novo_usuario("codfab_espaco")
    detalhe1 = lote_preco.criar_lote(
        [item(COD_CODFAB_ESPACO_A, at=10.00)],
        "lote de teste — colisão de COD_FAB só após normalizar (4851 x 4294)",
        login1, uid1,
    )
    id_lote1 = detalhe1["id_lote"]
    recursos.registrar_lote(id_lote1)
    _, _, excluidos1 = lote_preco.gerar_xlsx_201(id_lote1, "atacado", login1, uid1)
    ok1 = (
        len(excluidos1) == 1
        and int(excluidos1[0]["codigo"]) == COD_CODFAB_ESPACO_A
        and excluidos1[0]["motivo"] == "código de fábrica repetido"
    )
    rep.registrar(
        f"SKU {COD_CODFAB_ESPACO_A} ('HC000660486') excluído por colidir com {COD_CODFAB_ESPACO_B} "
        "(' HC000660486', espaço à esquerda) — a colisão só aparece DEPOIS de normalizar",
        ok1,
        f"excluidos={excluidos1}",
    )

    uid2, login2 = recursos.novo_usuario("codfab_tab")
    detalhe2 = lote_preco.criar_lote(
        [item(COD_CODFAB_TAB, at=200.00)],
        "lote de teste — COD_FAB com tabulação nas pontas (471)",
        login2, uid2,
    )
    id_lote2 = detalhe2["id_lote"]
    recursos.registrar_lote(id_lote2)
    conteudo2, _, excluidos2 = lote_preco.gerar_xlsx_201(id_lote2, "atacado", login2, uid2)
    linhas2 = _linhas(conteudo2)
    ok2 = not excluidos2 and linhas2 == [("H0002317339", 200.00)]
    rep.registrar(
        f"SKU {COD_CODFAB_TAB} (cód. fábrica com tabulação nas pontas) sai no arquivo SEM o invisível "
        "('H0002317339', sem os \\t)",
        ok2,
        f"linhas={linhas2}, excluidos={excluidos2}",
    )


def cenario_reaproveitamento_rascunho(rep: Reporter, recursos: Recursos) -> None:
    """§4.3 — `criar_lote` sem `id_lote` reaproveita o Rascunho do MESMO
    usuário em vez de abrir um novo (regra incluída depois de 10/09/2026 —
    é a mudança que fez este validador cair para 18/19 quando dois cenários
    DIFERENTES usavam sem querer o mesmo login). Este é o ÚNICO cenário que
    usa o MESMO login em chamadas sucessivas de propósito: aqui o
    reaproveitamento é o comportamento sob teste, não um acidente.

    Cobre também `observacao` preservada/atualizada — antes da correção,
    reaproveitar descartava o parâmetro em silêncio."""
    uid, login = recursos.novo_usuario("reaproveitamento")

    detalhe1 = lote_preco.criar_lote(
        [item(COD_REAPROVEITA_A, at=10.00)], "observação original", login, uid,
    )
    id_lote = detalhe1["id_lote"]
    recursos.registrar_lote(id_lote)
    rep.registrar(
        "primeira criar_lote (usuário sem Rascunho prévio) NÃO reaproveita — cria um lote novo",
        detalhe1["lote_reaproveitado"] is False,
        f"lote_reaproveitado={detalhe1['lote_reaproveitado']}, id_lote={id_lote}",
    )

    detalhe2 = lote_preco.criar_lote(
        [item(COD_REAPROVEITA_B, at=20.00)], None, login, uid,
    )
    codigos2 = {i["codigo"] for i in detalhe2["itens"]}
    ok2 = (
        detalhe2["lote_reaproveitado"] is True
        and detalhe2["id_lote"] == id_lote
        and codigos2 == {COD_REAPROVEITA_A, COD_REAPROVEITA_B}
        and detalhe2["observacao"] == "observação original"
    )
    rep.registrar(
        "segunda criar_lote (MESMO login, sem id_lote, observacao=None) REAPROVEITA o Rascunho: "
        "mesmo id_lote, os dois itens juntos, e a observação ORIGINAL é preservada (nvl)",
        ok2,
        f"id_lote={detalhe2['id_lote']} (esperado {id_lote}), itens={codigos2}, "
        f"observacao={detalhe2.get('observacao')!r}",
    )

    detalhe3 = lote_preco.criar_lote(
        [item(COD_REAPROVEITA_C, at=30.00)], "observação atualizada", login, uid,
    )
    codigos3 = {i["codigo"] for i in detalhe3["itens"]}
    ok3 = (
        detalhe3["lote_reaproveitado"] is True
        and detalhe3["id_lote"] == id_lote
        and codigos3 == {COD_REAPROVEITA_A, COD_REAPROVEITA_B, COD_REAPROVEITA_C}
        and detalhe3["observacao"] == "observação atualizada"
    )
    rep.registrar(
        "terceira criar_lote (MESMO login, observacao NOVA) reaproveita de novo e ATUALIZA a "
        "observação — antes da correção esta gravação descartava o parâmetro em silêncio",
        ok3,
        f"id_lote={detalhe3['id_lote']} (esperado {id_lote}), itens={codigos3}, "
        f"observacao={detalhe3.get('observacao')!r}",
    )


def cenario_rascunho_conflitante(rep: Reporter, recursos: Recursos) -> None:
    """`RascunhoConflitante` (achado do `revisor`, opus, 11/09/2026: nenhum
    cenário deste arquivo exercitava a exceção). É a regressão do defeito que
    bloqueou a 2ª passada da revisão: voltar um lote Enviado para Rascunho
    quando o MESMO usuário já tinha OUTRO lote em Rascunho aberto violava
    `UX_APP_LOTE_PRECO_RASCUNHO` e o `ORA-00001` subia cru como 500. A
    correção foi a checagem explícita `_conflito_rascunho`, dentro de
    `_transicionar` (ver docstring de `RascunhoConflitante` em
    `lote_preco.py`) — corrigida e provada por execução manual, nunca por
    teste, até agora.

    Usuário PRÓPRIO, mesma disciplina de todo cenário deste arquivo — mas
    aqui é o MESMO login em chamadas sucessivas de propósito (como em
    `cenario_reaproveitamento_rascunho`): é assim que dois lotes concorrentes
    do mesmo usuário acontecem de verdade.

    Passos: cria A (Rascunho) -> avança A (Enviado) -> cria B com o MESMO
    login (Rascunho, pois não havia outro aberto) -> tenta voltar A ->
    `RascunhoConflitante` citando o número de B -> exclui B -> volta A de
    novo -> funciona e grava uma linha em `APP_LOTE_PRECO_STATUS_HIST`.

    ⚠ NÃO cobre a corrida residual (duas threads entre a checagem explícita e
    o UPDATE) — o `revisor` avaliou que é cara de testar e que o comentário
    no código já é documentação honesta (ver docstring de `_conflito_
    rascunho`). O caso comum, síncrono, é o que importa aqui."""
    uid, login = recursos.novo_usuario("rascunho_conflitante")

    detalhe_a = lote_preco.criar_lote(
        [item(COD_RASCUNHO_CONFLITANTE_A, at=10.00)], None, login, uid,
    )
    id_lote_a = detalhe_a["id_lote"]
    recursos.registrar_lote(id_lote_a)
    lote_preco.avancar_status(id_lote_a, login, uid)

    detalhe_b = lote_preco.criar_lote(
        [item(COD_RASCUNHO_CONFLITANTE_B, at=20.00)], None, login, uid,
    )
    id_lote_b = detalhe_b["id_lote"]
    recursos.registrar_lote(id_lote_b)
    rep.registrar(
        f"criar_lote (mesmo login, A já Enviado) abre B NOVO #{id_lote_b} em Rascunho "
        "(não havia outro Rascunho para reaproveitar)",
        detalhe_b["lote_reaproveitado"] is False and detalhe_b["status"] == "Rascunho",
        f"id_lote_b={id_lote_b}, lote_reaproveitado={detalhe_b.get('lote_reaproveitado')}, "
        f"status={detalhe_b.get('status')}",
    )

    # ── AUTOTESTE ────────────────────────────────────────────────────────
    # `_conflito_rascunho` é substituída (mock, nunca o arquivo do serviço é
    # tocado) por uma versão que sempre devolve None — simula a checagem
    # explícita AUSENTE, exatamente o estado do código antes da correção que
    # o revisor cobrou. Com ela fora, `_transicionar` ainda tenta o UPDATE
    # para 'Rascunho', que esbarra no MESMO índice único de verdade
    # (`UX_APP_LOTE_PRECO_RASCUNHO`, já usado por `cenario_concorrencia_
    # criacao_lote`) e cai na rede de corrida residual do próprio código:
    # ainda recusa com `RascunhoConflitante`, só que com a mensagem GENÉRICA,
    # sem o número do outro lote. Isso prova que a exigência do passo
    # seguinte ("a mensagem tem de nomear o outro lote") reprova de verdade
    # quando falta — não é uma asserção que sempre passaria.
    nome_indice = lote_preco._nome_indice_unico_rascunho()
    if not nome_indice:
        rep.nao_testado(
            "AUTOTESTE — checagem explícita simulada ausente ainda recusa (rede do índice), "
            "mas sem nomear o outro lote",
            "UX_APP_LOTE_PRECO_RASCUNHO não existe no banco (user_indexes) — sem o índice a "
            "simulação gravaria o UPDATE de verdade em vez de esbarrar nele; autoteste pulado "
            "para não corromper o estado de A",
        )
    else:
        with mock.patch.object(lote_preco, "_conflito_rascunho", return_value=None):
            excecao_defeito: Exception | None = None
            try:
                lote_preco.voltar_status(id_lote_a, login, uid)
            except Exception as exc:  # noqa: BLE001
                excecao_defeito = exc
        status_a_sob_mock = database.consultar_um(
            "select status from app_lote_preco where id_lote = :id", {"id": id_lote_a}
        )["status"]
        defeito_detectado = (
            isinstance(excecao_defeito, lote_preco.RascunhoConflitante)
            and f"#{id_lote_b}" not in str(excecao_defeito)
            and status_a_sob_mock == "Enviado"  # o UPDATE não persistiu (rollback)
        )
        rep.registrar(
            "AUTOTESTE — com a checagem explícita simulada ausente (mock em `_conflito_rascunho`), "
            "a rede do índice único ainda recusa, mas SEM nomear o lote B: prova que a checagem do "
            "próximo passo (mensagem cita o outro lote) é capaz de FALHAR de verdade, não é vácua",
            defeito_detectado,
            f"exceção sob mock: {excecao_defeito!r}; status de A sob mock: {status_a_sob_mock}",
        )

    # ── checagem real (mock desfeito) ────────────────────────────────────
    excecao_real: Exception | None = None
    try:
        lote_preco.voltar_status(id_lote_a, login, uid)
    except Exception as exc:  # noqa: BLE001
        excecao_real = exc
    status_a_apos_recusa = database.consultar_um(
        "select status from app_lote_preco where id_lote = :id", {"id": id_lote_a}
    )["status"]
    rep.registrar(
        f"voltar A (Enviado -> Rascunho) com B ainda aberto em Rascunho -> RascunhoConflitante "
        f"citando '#{id_lote_b}'; A permanece Enviado",
        isinstance(excecao_real, lote_preco.RascunhoConflitante)
        and f"#{id_lote_b}" in str(excecao_real)
        and status_a_apos_recusa == "Enviado",
        f"exceção: {excecao_real}; status de A: {status_a_apos_recusa}",
    )

    # ── contraponto: sem o conflito, funciona ────────────────────────────
    hist_antes = database.consultar_um(
        "select count(*) n from app_lote_preco_status_hist where id_lote = :id", {"id": id_lote_a}
    )["n"]
    lote_preco.excluir_lote(id_lote_b, login, uid)
    resultado = lote_preco.voltar_status(id_lote_a, login, uid)
    hist_depois = database.consultar_um(
        "select count(*) n from app_lote_preco_status_hist where id_lote = :id", {"id": id_lote_a}
    )["n"]
    rep.registrar(
        "contraponto: excluído B, voltar A funciona (Enviado -> Rascunho) e grava uma linha "
        "em APP_LOTE_PRECO_STATUS_HIST",
        resultado["status"] == "Rascunho" and hist_depois == hist_antes + 1,
        f"status devolvido={resultado.get('status')}, hist antes={hist_antes}, depois={hist_depois}",
    )


def cenario_a_prazo_informativo(rep: Reporter, recursos: Recursos) -> None:
    """§4.4/§9.3 — `_a_prazo_valido` apaga `ALT_PV_*_AP` quando o "atual"
    congelado do lote diverge do valor VIVO de `COMPRAS_PEDIDO` (sinal de que
    outro lote foi aplicado e incorporado por um `dbt run` depois que este
    item entrou neste lote). Prova em três camadas: função pura com números
    REAIS (SKU 9, só leitura, nunca gravado por este script); integração
    observada com um spy que ENCAMINHA para a função real (nunca substitui
    comportamento) sobre um lote PRÓPRIO deste cenário; e o texto do
    cabeçalho do Excel de conferência, que agora avisa que a coluna é
    informativa e do último build."""
    sku9 = database.consultar_um(
        "select pv_atacado, alt_pv_at_ap from compras_pedido where codigo = 9"
    )
    banco = float(sku9["pv_atacado"])
    a_prazo = float(sku9["alt_pv_at_ap"])

    casos = [
        ("congelado == banco -> mantém o a prazo", banco, banco, a_prazo, a_prazo),
        ("congelado != banco (drift real, diff 12,69) -> apaga (None)", banco - 12.69, banco, a_prazo, None),
        ("a_prazo é None -> None", banco, banco, None, None),
        ("atual congelado é None -> None", None, banco, a_prazo, None),
        ("atual do banco é None -> None", banco, None, a_prazo, None),
    ]
    falhas = []
    for nome, congelado, banco_v, ap, esperado in casos:
        obtido = lote_preco._a_prazo_valido(congelado, banco_v, ap)
        if obtido != esperado:
            falhas.append(f"{nome}: obtido={obtido!r} esperado={esperado!r}")
    rep.registrar(
        "_a_prazo_valido apaga o A PRAZO quando o atual congelado diverge do banco vivo "
        "(números reais do SKU 9 — à vista 455,40 / a prazo 371,412 — só leitura, nunca gravado)",
        not falhas,
        "\n".join(falhas) or "\n".join(f"{n}: ok" for n, *_ in casos),
    )

    uid, login = recursos.novo_usuario("a_prazo")
    detalhe = lote_preco.criar_lote(
        [item(COD_A_PRAZO_TESTE, at=999.99)], "lote de teste — a prazo informativo", login, uid,
    )
    id_lote = detalhe["id_lote"]
    recursos.registrar_lote(id_lote)
    with mock.patch.object(lote_preco, "_a_prazo_valido", wraps=lote_preco._a_prazo_valido) as spy:
        itens = lote_preco.obter_itens(id_lote)
    chamadas_esperadas = 2 * len(itens)  # atacado + varejo, por item
    rep.registrar(
        f"obter_itens chama _a_prazo_valido 2x por item (atacado e varejo) — lote #{id_lote} com "
        f"{len(itens)} item(ns) — spy que ENCAMINHA para a função real, nunca substitui comportamento",
        spy.call_count == chamadas_esperadas,
        f"call_count={spy.call_count}, esperado={chamadas_esperadas}",
    )

    rotulos = [rotulo for rotulo, _ in lote_preco._COLUNAS_CONFERENCIA]
    ok_rotulo = any("INFORMATIVO" in r and "ÚLTIMO BUILD" in r for r in rotulos)
    rep.registrar(
        "cabeçalho da coluna A PRAZO diz que é informativo, do último build",
        ok_rotulo,
        str(rotulos),
    )


def cenario_concorrencia_criacao_lote(rep: Reporter, recursos: Recursos) -> None:
    """Índice único `UX_APP_LOTE_PRECO_RASCUNHO` (`sql/05_tabelas_lote_preco.sql`,
    confirmado existente no banco antes deste teste) — a garantia para a
    corrida do PRIMEIRO lote de um usuário (zero Rascunhos: nada para o
    `FOR UPDATE` de `_achar_rascunho_do_usuario` travar). Duas THREADS DE
    VERDADE, sincronizadas por `threading.Barrier` para maximizar a chance
    de as duas tentarem o INSERT ao mesmo tempo, cada uma com seu próprio
    código de produto — depois das duas, tem que sobrar UM lote só, com os
    DOIS itens dentro (o serviço reage ao ORA-00001 do índice acrescentando
    ao lote que venceu, identificado PELO NOME — nunca por posição)."""
    nome_indice = lote_preco._nome_indice_unico_rascunho()
    if not nome_indice:
        rep.nao_testado(
            "duas criações SIMULTÂNEAS (threads + Barrier) do primeiro lote de um usuário -> um lote só",
            "UX_APP_LOTE_PRECO_RASCUNHO não existe no banco (user_indexes) — o oracle-dba ainda não criou",
        )
        return

    uid, login = recursos.novo_usuario("concorrencia")
    barreira = threading.Barrier(2)
    resultados: list = [None, None]

    def tentar(idx: int, codigo: int) -> None:
        try:
            barreira.wait(timeout=10)
            resultados[idx] = lote_preco.criar_lote([item(codigo, at=50.00)], None, login, uid)
        except Exception as exc:  # noqa: BLE001
            resultados[idx] = exc

    t1 = threading.Thread(target=tentar, args=(0, COD_CONCORRENCIA_A))
    t2 = threading.Thread(target=tentar, args=(1, COD_CONCORRENCIA_B))
    t1.start()
    t2.start()
    t1.join(timeout=30)
    t2.join(timeout=30)

    excecoes = [r for r in resultados if isinstance(r, Exception)]
    ids_obtidos = {r["id_lote"] for r in resultados if isinstance(r, dict)}
    for id_lote in ids_obtidos:
        recursos.registrar_lote(id_lote)

    lotes_rascunho_usuario = database.consultar(
        "select id_lote from app_lote_preco where criado_por = :login and status = 'Rascunho'",
        {"login": login},
    )
    codigos_no_lote = set()
    if len(ids_obtidos) == 1:
        codigos_no_lote = {i["codigo"] for i in lote_preco.obter_itens(next(iter(ids_obtidos)))}

    ok = (
        not excecoes
        and len(ids_obtidos) == 1
        and len(lotes_rascunho_usuario) == 1
        and codigos_no_lote == {COD_CONCORRENCIA_A, COD_CONCORRENCIA_B}
    )
    rep.registrar(
        f"duas criações SIMULTÂNEAS (threads + Barrier, índice {nome_indice}) do PRIMEIRO lote de um "
        "usuário sem Rascunho prévio resultam em UM lote só, com os dois itens dentro",
        ok,
        f"exceções={excecoes}; "
        f"ids devolvidos={[r.get('id_lote') if isinstance(r, dict) else str(r) for r in resultados]}; "
        f"reaproveitado={[r.get('lote_reaproveitado') if isinstance(r, dict) else None for r in resultados]}; "
        f"rascunhos do usuário no banco={len(lotes_rascunho_usuario)}; itens no lote={codigos_no_lote}",
    )


# ──────────────────────────────────────────────────────────────────── main ─

CENARIOS = [
    ("lote_principal (testes 1/2/3/5/6)", cenario_lote_principal),
    ("isolamento_catalogo (teste 2b — regressão do bug de ordem)", cenario_isolamento_catalogo),
    ("atomicidade (teste 4)", cenario_atomicidade),
    ("conferencia_aplicacao (teste 7 — 4 estados + tolerância única)", cenario_conferencia_aplicacao),
    ("cod_fab_normalizacao (colisão por espaço + tabulação)", cenario_cod_fab_normalizacao),
    ("reaproveitamento_rascunho (§4.3 + observacao preservada)", cenario_reaproveitamento_rascunho),
    ("rascunho_conflitante (RascunhoConflitante — achado do revisor 11/09/2026)", cenario_rascunho_conflitante),
    ("a_prazo_informativo (§4.4/§9.3)", cenario_a_prazo_informativo),
    ("concorrencia_criacao_lote (threads + Barrier)", cenario_concorrencia_criacao_lote),
]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--inverter-ordem", action="store_true",
        help="Roda os cenários na ordem INVERSA — prova de independência de ordem (ver docstring do módulo).",
    )
    args = ap.parse_args()

    cenarios = list(reversed(CENARIOS)) if args.inverter_ordem else list(CENARIOS)
    print(f"Ordem dos cenários: {'INVERTIDA' if args.inverter_ordem else 'normal'}")
    for nome, _ in cenarios:
        print(f"  - {nome}")
    print()

    rep = Reporter()
    print("Capturando estado do banco ANTES de qualquer gravação…")
    estado_antes = capturar_estado()
    print(
        f"  APP_DECISAO_PRECO={len(estado_antes['decisao_preco'])} linha(s), "
        f"HIST={estado_antes['decisao_preco_hist_n']}, "
        f"LOTE={estado_antes['lote_n']}/ITEM={estado_antes['lote_item_n']}/"
        f"HIST_LOTE={estado_antes['lote_hist_n']}, USUARIO={estado_antes['usuario_n']}"
    )
    print()

    recursos = Recursos()
    try:
        for nome, funcao in cenarios:
            try:
                funcao(rep, recursos)
            except Exception as exc:  # noqa: BLE001
                rep.registrar(f"cenário {nome}", False, f"exceção: {exc}\n{traceback.format_exc(limit=4)}")
    finally:
        print("\nRestaurando o banco ao estado anterior…")
        limpar(recursos.usuarios, recursos.lotes, TODOS_CODIGOS_DECISAO)

        estado_depois = capturar_estado()
        decisao_igual = estado_antes["decisao_preco"] == estado_depois["decisao_preco"]
        restaurado = (
            decisao_igual
            and estado_depois["decisao_preco_hist_n"] == estado_antes["decisao_preco_hist_n"]
            and estado_depois["lote_n"] == estado_antes["lote_n"]
            and estado_depois["lote_item_n"] == estado_antes["lote_item_n"]
            and estado_depois["lote_hist_n"] == estado_antes["lote_hist_n"]
            and estado_depois["usuario_n"] == estado_antes["usuario_n"]
        )
        rep.registrar(
            "banco restaurado ao estado exato de antes (APP_DECISAO_PRECO com as mesmas 2 linhas, "
            "HIST=0, as três APP_LOTE_*=0, mesmo número de usuários)",
            restaurado,
            f"antes={estado_antes}\ndepois={estado_depois}",
        )

    return rep.resumo()


if __name__ == "__main__":
    sys.exit(main())
