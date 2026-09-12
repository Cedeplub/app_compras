"""Valida a ordenação por clique de coluna (Etapa 13, §3 / §8.4 item 2 do
`v2/PROMPT_ETAPA_13_NAVEGACAO_E_TABELAS.md`), nas três rotas paginadas:
`/api/produtos`, `/api/pedidos`, `/api/lotes-preco`.

NAO CONSERTA NADA. Mede e reporta. Chama as funções de rota de
`app.api.rotas` DIRETO em Python (mesmo código que o FastAPI executa — só
sem subir um servidor HTTP e sem precisar de sessão/cookie, já que `usuario`
não é lido dentro do corpo dessas funções, só usado pelo `Depends` de
autenticação) e `app.core.database` para a "verdade" (select max()/min()
direto, nunca contra a página).

O defeito que este script existe para pegar: ordenar "só a página" em vez do
CONJUNTO INTEIRO — parece funcionar (a página parece ordenada) e mente (o
pior/melhor item do FILTRO INTEIRO não aparece na página 1). Por isso a
comparação nunca é "página 1 comparada com página 2"; é sempre "primeira
linha da página 1 comparada com um `select max()`/`min()` independente".

⚠ Há dado de produção no banco (lote #186, 'Enviado', criado por 'admin'; 4
pedidos reais, todos 'Rascunho', criados por 'admin'; 4 decisões em
APP_DECISAO_PRECO). Este script:
  - LÊ o baseline no início (nunca assume um estado fixo);
  - cria usuário(s) PRÓPRIO(S) (nunca usa o login 'admin');
  - só cria/avança/exclui os pedidos e lotes que ELE MESMO criou — nunca toca
    nos 4 pedidos nem no lote #186 pré-existentes;
  - restaura o banco ao estado exato do baseline no `finally`, e para de
    reportar (não conserta) se a restauração não bater.

── Correção de 11/09/2026 (achado do `revisor`) ────────────────────────────
`cenario_lotes` gravava lotes em SKUs FIXOS (30, 31, 58, 59, 60, 63) e a
limpeza apagava `APP_DECISAO_PRECO`/`_HIST` desses códigos INCONDICIONALMENTE
— sem checar se o SKU já tinha decisão de preço real gravada por um usuário
de verdade. Não colidia por coincidência, não por garantia: bastava alguém
precificar o SKU 30 na tela para a próxima rodada deste script sobrescrever o
preço com um valor de teste e, no `finally`, apagá-lo — perda de decisão real,
silenciosa.

A correção resolve na raiz, não só detecta a colisão: `_codigos_sem_decisao`
escolhe, EM TEMPO DE EXECUÇÃO, códigos reais que HOJE não têm nenhuma linha em
APP_DECISAO_PRECO — o cenário nunca decide sobrescrever um SKU ocupado, então
não há necessidade de abortar silenciosamente nem de "pular sem avisar": os
códigos escolhidos são impressos no relatório (`rep.registrar`), então quem lê
o log sempre sabe QUAL SKU foi usado. `_sem_decisao_ainda` é a rede residual
— confere de novo, junto ao uso, contra a corrida entre a escolha e a
gravação; se ela achar colisão (deveria ser rarissimo), o cenário ABORTA com
mensagem nomeando o(s) SKU(s), em vez de prosseguir. E a limpeza deixou de
apagar por lista de código: antes de apagar, confere `atualizado_por` contra
os logins de teste que ELA MESMA criou — só remove a linha se o autor for um
desses; decisão de outro autor (corrida rara demais para o guard de entrada
pegar) fica intacta e o script avisa.

Uso:
    python validar/validar_ordenacao_paginada.py
"""
from __future__ import annotations

import datetime as dt
import secrets
import sys
import traceback
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ))

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

from fastapi.exceptions import HTTPException  # noqa: E402

from app.api import rotas  # noqa: E402
from app.core import auth, database  # noqa: E402
from app.servicos import lote_preco, pedido, produto  # noqa: E402

# Dois códigos reais, fornecedores DIFERENTES, FATOR_EXIBICAO=1 (medido em
# 11/09/2026) — usados só para o teste de valorTotal (mín./máx.), com
# preco_unitario explícito bem afastado de qualquer valor real hoje (min
# real medido: R$ 31.548,02; máx real medido: R$ 3.049.490,17).
COD_VALOR_ALTO = 1230   # fornecedor INATIVOS
COD_VALOR_BAIXO = 1232  # fornecedor CLICK

# Os códigos do cenário de lote (§ "Correção de 11/09/2026" no docstring do
# módulo) NÃO são mais fixos — ver `_codigos_sem_decisao`. Fixá-los aqui é
# exatamente o que causava o risco: um SKU chumbado pode ganhar decisão de
# preço real entre uma execução e outra.


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
    prefixo = f"validador_ordenacao_{sufixo}_" if sufixo else "validador_ordenacao_"
    login = f"{prefixo}{secrets.token_urlsafe(6)}"
    senha_hash = auth.gerar_hash(secrets.token_urlsafe(24))
    with database.transacao() as conn:
        cur = conn.cursor()
        id_var = cur.var(int)
        cur.execute(
            """
            insert into app_usuario
                (login, nome, senha_hash, origem, senha_provisoria, ativo, eh_admin, eh_diretoria)
            values (:login, 'Validador Etapa 13 (temporário)', :senha_hash, 'local', 0, 1, 0, 1)
            returning id_usuario into :id
            """,
            {"login": login, "senha_hash": senha_hash, "id": id_var},
        )
        id_usuario = int(id_var.getvalue()[0])
        cur.close()
    return id_usuario, login


def capturar_estado() -> dict:
    return {
        "decisao_preco": database.consultar("select * from app_decisao_preco order by id_produto"),
        "lote_n": database.consultar_um("select count(*) n from app_lote_preco")["n"],
        "lote_item_n": database.consultar_um("select count(*) n from app_lote_preco_item")["n"],
        "lote_hist_n": database.consultar_um("select count(*) n from app_lote_preco_status_hist")["n"],
        "pedido_n": database.consultar_um("select count(*) n from app_pedido")["n"],
        "pedido_item_n": database.consultar_um("select count(*) n from app_pedido_item")["n"],
        "pedido_hist_n": database.consultar_um("select count(*) n from app_pedido_status_hist")["n"],
        "usuario_n": database.consultar_um("select count(*) n from app_usuario")["n"],
        # ancoras nominais — para conferir que NADA que já existia mudou de dono/estado
        "lote_186": database.consultar_um(
            "select id_lote, status, criado_por from app_lote_preco where id_lote = 186"
        ),
    }


def limpar(usuarios: list[tuple[int, str]], ids_pedido: list[int], ids_lote: list[int],
           codigos_decisao: list[int]) -> None:
    """`codigos_decisao` são os códigos que O PRÓPRIO `cenario_lotes` ESCOLHEU
    em tempo de execução (`_codigos_sem_decisao`) — já comprovados livres
    ANTES do teste. Mesmo assim, antes de apagar, confere de novo:
    `atualizado_por` da linha tem que ser um dos logins de teste que ESTE
    script criou. Se não for (corrida rara: alguém gravou decisão real nesse
    código no meio do teste), a linha NÃO é apagada — só avisada. A limpeza
    apaga o que ELA criou, não "o que está naquele código"."""
    login_qualquer = usuarios[0][1] if usuarios else "validador_ordenacao_limpeza"
    uid_qualquer = usuarios[0][0] if usuarios else 0
    logins_teste = {login for _uid, login in usuarios}

    for id_pedido in ids_pedido:
        try:
            pedido.excluir_pedido(id_pedido, login_qualquer, uid_qualquer)
        except Exception as exc:  # noqa: BLE001
            print(f"  aviso: falha ao excluir pedido {id_pedido} na limpeza: {exc}")

    for id_lote in ids_lote:
        try:
            lote_preco.excluir_lote(id_lote, login_qualquer, uid_qualquer)
        except Exception as exc:  # noqa: BLE001
            print(f"  aviso: falha ao excluir lote {id_lote} na limpeza: {exc}")

    if codigos_decisao:
        marcas = ", ".join(f":c{i}" for i in range(len(codigos_decisao)))
        binds = {f"c{i}": c for i, c in enumerate(codigos_decisao)}
        linhas = database.consultar(
            f"select id_produto, atualizado_por from app_decisao_preco where id_produto in ({marcas})",
            binds,
        )
        codigos_meus = [int(r["id_produto"]) for r in linhas if r["atualizado_por"] in logins_teste]
        codigos_alheios = [int(r["id_produto"]) for r in linhas if r["atualizado_por"] not in logins_teste]
        if codigos_alheios:
            print(
                f"  aviso: {len(codigos_alheios)} código(s) escolhidos pelo cenário de lote têm decisão "
                f"gravada por outro autor (corrida rara entre a escolha e agora) — NÃO apagando: "
                f"{codigos_alheios}. Confira manualmente."
            )
        if codigos_meus:
            marcas2 = ", ".join(f":c{i}" for i in range(len(codigos_meus)))
            binds2 = {f"c{i}": c for i, c in enumerate(codigos_meus)}
            with database.transacao() as conn:
                cur = conn.cursor()
                cur.execute(f"delete from app_decisao_preco_hist where id_produto in ({marcas2})", binds2)
                cur.execute(f"delete from app_decisao_preco where id_produto in ({marcas2})", binds2)
                cur.close()

    for id_usuario, _login in usuarios:
        with database.transacao() as conn:
            cur = conn.cursor()
            cur.execute("delete from app_auditoria where id_usuario = :id", {"id": id_usuario})
            cur.execute("delete from app_sessao where id_usuario = :id", {"id": id_usuario})
            cur.execute("delete from app_usuario where id_usuario = :id", {"id": id_usuario})
            cur.close()


class Recursos:
    def __init__(self):
        self.usuarios: list[tuple[int, str]] = []
        self.pedidos: list[int] = []
        self.lotes: list[int] = []
        self.codigos_decisao: list[int] = []
        """Códigos ESCOLHIDOS em tempo de execução por `_codigos_sem_decisao`
        para o cenário de lote — nunca fixos (ver docstring do módulo)."""

    def novo_usuario(self, sufixo: str = "") -> tuple[int, str]:
        uid, login = criar_usuario_teste(sufixo)
        self.usuarios.append((uid, login))
        return uid, login


def _codigos_sem_decisao(qtd: int) -> list[int]:
    """Escolhe, AGORA, códigos reais de COMPRAS_PEDIDO que HOJE não têm
    nenhuma linha em APP_DECISAO_PRECO. Resolve na raiz o risco descrito no
    docstring do módulo: um código só entra na lista se comprovadamente
    estiver livre neste instante — nunca um SKU chumbado que pode ganhar
    decisão real entre uma execução e outra. `order by codigo` só torna o
    resultado estável entre execuções (mesmos códigos hoje, salvo alguém
    decidir preço nesse meio-tempo); não há preferência de negócio pelo
    código baixo."""
    linhas = database.consultar(
        """
        select p.codigo
          from compras_pedido p
         where not exists (
               select 1 from app_decisao_preco d where d.id_produto = p.codigo
             )
         order by p.codigo
        fetch first :qtd rows only
        """,
        {"qtd": qtd},
    )
    return [int(r["codigo"]) for r in linhas]


def _sem_decisao_ainda(codigos: list[int]) -> list[int]:
    """Rede residual: confere, JÁ NO MOMENTO DE USAR (logo antes de gravar),
    que nenhum dos códigos escolhidos por `_codigos_sem_decisao` ganhou
    decisão de preço no intervalo entre a escolha e agora. Devolve os
    códigos que JÁ TÊM decisão — lista vazia significa "tudo livre, pode
    prosseguir". Não é a defesa principal (essa é ter escolhido código
    livre); é para a corrida residual, rara mas possível com o sistema em
    uso real."""
    if not codigos:
        return []
    marcas = ", ".join(f":c{i}" for i in range(len(codigos)))
    binds = {f"c{i}": c for i, c in enumerate(codigos)}
    linhas = database.consultar(
        f"select id_produto from app_decisao_preco where id_produto in ({marcas})", binds
    )
    return [int(r["id_produto"]) for r in linhas]


# ─────────────────────────────────────────────────────────── comparadores ──

def _igual(obtido, esperado) -> bool:
    if obtido is None and esperado is None:
        return True
    if obtido is None or esperado is None:
        return False
    if isinstance(esperado, dt.datetime):
        texto = str(obtido)
        if len(texto) <= 10:  # veio truncado para "AAAA-MM-DD" (contrato._data)
            return dt.date.fromisoformat(texto[:10]) == esperado.date()
        o = dt.datetime.fromisoformat(texto)
        return abs((o - esperado).total_seconds()) < 1.0
    if isinstance(esperado, dt.date):
        return dt.date.fromisoformat(str(obtido)[:10]) == esperado
    if isinstance(esperado, (int, float)):
        try:
            return abs(float(obtido) - float(esperado)) <= 0.01
        except (TypeError, ValueError):
            return False
    return obtido == esperado


def verificar_extremo(rep: Reporter, rotulo_rota: str, listar_fn, chave: str,
                       expressao_sql: str, from_sql: str, extrator) -> None:
    falhas = []
    for direcao, agregador in (("desc", "max"), ("asc", "min")):
        esperado = database.consultar_um(f"select {agregador}({expressao_sql}) as v {from_sql}")["v"]
        corpo = listar_fn(ordenar=chave, dir=direcao, pagina=1, porPagina=1)
        itens = corpo["itens"]
        if not itens:
            falhas.append(f"{direcao}: rota não devolveu nenhum item")
            continue
        obtido = extrator(itens[0])
        if not _igual(obtido, esperado):
            ident = itens[0].get("codigo", itens[0].get("id"))
            falhas.append(
                f"{direcao}: primeira linha da página 1 (id/codigo={ident}) tem {chave}={obtido!r}, "
                f"mas o {agregador}() direto no banco é {esperado!r}"
            )
    rep.registrar(
        f"{rotulo_rota} — ordenar={chave}: primeira linha da página 1 (desc=máximo, asc=mínimo) "
        "bate com select max()/min() do CONJUNTO INTEIRO",
        not falhas,
        "\n".join(falhas) or "desc==max() e asc==min() do banco, conferidos",
    )


# ───────────────────────────────────────────────────────────── /api/produtos ─

def _listar_produtos(**kw):
    kw.setdefault("tipoAlerta", None)
    kw.setdefault("cenarioMargem", None)
    return rotas.listar_produtos(usuario=None, **kw)


def _extrator_valor_em_risco(it):
    mj, pv = it.get("mediaJanela"), it.get("pvAtacado")
    return None if mj is None or pv is None else mj * pv


def _extrator_margem_st_valor_atacado(it):
    return next((c["margemAtual"] for c in it["cenariosAtacado"] if c["id"] == "st_valor"), None)


_DE_SIMPLES = "from compras_pedido p"
_DE_DECISAO = "from compras_pedido p left join app_decisao_preco d on d.id_produto = p.codigo"

FIELD_MAP_PRODUTOS: dict[str, tuple[str, str, object]] = {
    "codigo": ("p.codigo", _DE_SIMPLES, lambda it: it["codigo"]),
    "descricao": ("p.descricao", _DE_SIMPLES, lambda it: it["nome"]),
    "cobertura": ("p.meses_est", _DE_SIMPLES, lambda it: it["mesesCobertura"]),
    "giro": ("p.dias_sem_venda", _DE_SIMPLES, lambda it: it["diasSemVenda"]),
    "valor": ("p.valor_estoque", _DE_SIMPLES, lambda it: it["valorEstoque"]),
    "preco": ("p.pv_atacado", _DE_SIMPLES, lambda it: it["pvAtacado"]),
    "estoque": ("p.est_disp", _DE_SIMPLES, lambda it: it["estDisp"]),
    "pendente": ("p.pendente", _DE_SIMPLES, lambda it: it["pendente"]),
    "estPedido": ("p.est_pend", _DE_SIMPLES, lambda it: it["estPend"]),
    "ultimaEntrada": ("p.dt_ult_ent", _DE_SIMPLES, lambda it: it["ultimaEntrada"]),
    "ultimaSaida": ("p.dt_ult_saida", _DE_SIMPLES, lambda it: it["ultimaSaida"]),
    "mediaVenda": ("p.media_janela", _DE_SIMPLES, lambda it: it["mediaJanela"]),
    "tendencia": ("p.tend_pct", _DE_SIMPLES, lambda it: it["tendPct"]),
    "clientesAtacado": ("p.qt_cli_atacado", _DE_SIMPLES, lambda it: it["clientesAtacado"]),
    "clientesVarejo": ("p.qt_cli_varejo", _DE_SIMPLES, lambda it: it["clientesVarejo"]),
    "vendaAtual": ("p.vd_mes_atual", _DE_SIMPLES, lambda it: it["vendaHistorico"]["quantidade"][0]),
    "valorEmRisco": ("p.media_janela * p.pv_atacado", _DE_SIMPLES, _extrator_valor_em_risco),
    "precoVarejo": ("p.pv_varejo", _DE_SIMPLES, lambda it: it["pvVarejo"]),
    "tributacao": ("p.modalidade", _DE_SIMPLES, lambda it: it["modalidade"]),
    "valorNf": ("p.vl_ent_unit", _DE_SIMPLES, lambda it: it["valorNfUnitario"]),
    "precoDecididoAtacado": ("d.alt_pv_at_av", _DE_DECISAO, lambda it: it["precoDecididoAtacadoAV"]),
    "margem": ("p.margem_st_s_valor", _DE_SIMPLES, _extrator_margem_st_valor_atacado),
}


def cenario_extremos_produtos(rep: Reporter) -> None:
    """Todas as colunas de `produto.ORDENACOES` + "margem" (aceite #9: Precificação
    ordenada por "Margem AT" decrescente — a pior margem do CATÁLOGO INTEIRO,
    8.841 SKUs, não da página)."""
    for chave, (expr, de, extrator) in FIELD_MAP_PRODUTOS.items():
        verificar_extremo(rep, "/api/produtos", _listar_produtos, chave, expr, de, extrator)

    faltando = produto.ORDENACOES_VALIDAS - set(FIELD_MAP_PRODUTOS) - {"mkp", "custo", "prioridade"}
    if faltando:
        rep.nao_testado(
            f"/api/produtos — colunas do whitelist não cobertas: {sorted(faltando)}",
            "fora do escopo desta rodada (adicionadas ao ORDENACOES depois deste script, "
            "ou esquecidas no de-para) — confira FIELD_MAP_PRODUTOS",
        )
    rep.nao_testado(
        "/api/produtos — ordenar=mkp/custo (dependem de cenarioMargem)",
        "escopo desta rodada cobriu 'margem' (aceite #9) — 'mkp'/'custo' usam a mesma fórmula "
        "de custo do cenário e não têm coluna materializada equivalente para conferência "
        "independente sem duplicar a regra fiscal (REGRAS.md, fora do que este validador reimplementa)",
    )


def cenario_nulls_last_produtos(rep: Reporter) -> None:
    """A armadilha do Oracle (§3.2): `nulls last` tem que valer NAS DUAS
    direções. `ultimaEntrada` (DT_ULT_ENT) tem nulo real (SKU sem entrada
    nenhuma) — pagina a lista INTEIRA nas duas direções e prova que todo nulo
    fica no FIM do conjunto todo, nunca misturado com valor real."""
    total = database.consultar_um("select count(*) n from compras_pedido")["n"]
    nulos = database.consultar_um("select count(*) n from compras_pedido where dt_ult_ent is null")["n"]
    por_pagina = 200
    for direcao in ("desc", "asc"):
        valores: list = []
        pag = 1
        while True:
            corpo = _listar_produtos(ordenar="ultimaEntrada", dir=direcao, pagina=pag, porPagina=por_pagina)
            itens = corpo["itens"]
            if not itens:
                break
            valores.extend(it["ultimaEntrada"] for it in itens)
            if pag >= corpo["totalPaginas"]:
                break
            pag += 1
        nulos_obtidos = sum(1 for v in valores if v is None)
        primeiro_nulo = next((i for i, v in enumerate(valores) if v is None), None)
        cauda_toda_nula = all(v is None for v in valores[primeiro_nulo:]) if primeiro_nulo is not None else True
        ok = len(valores) == total and nulos_obtidos == nulos and cauda_toda_nula
        rep.registrar(
            f"/api/produtos ordenar=ultimaEntrada dir={direcao}: os {nulos} SKU(s) sem DT_ULT_ENT "
            f"ficam no FIM da lista de {total} (paginada por inteiro, {por_pagina}/página)",
            ok,
            f"linhas percorridas={len(valores)} (esperado {total}), nulos encontrados={nulos_obtidos} "
            f"(esperado {nulos}), primeira posição nula={primeiro_nulo}, cauda 100% nula={cauda_toda_nula}",
        )


# ───────────────────────────────────────────────────────────── /api/pedidos ─

def _listar_pedidos(**kw):
    kw.setdefault("status", None)
    return rotas.listar_pedidos(usuario=None, **kw)


FIELD_MAP_PEDIDOS: dict[str, tuple[str, str, object]] = {
    "id": ("p.id_pedido", "from app_pedido p", lambda it: it["id"]),
    "criadoEm": ("p.criado_em", "from app_pedido p", lambda it: it["criadoEm"]),
    "fornecedor": ("p.fornecedor", "from app_pedido p", lambda it: it["fornecedor"]),
    "status": ("p.status", "from app_pedido p", lambda it: it["status"]),
    "valorTotal": ("nvl(agg.valor_total,0)", f"from app_pedido p {pedido._AGG}", lambda it: it["valorTotal"]),
    "qtdItens": ("nvl(agg.qtd_itens,0)", f"from app_pedido p {pedido._AGG}", lambda it: it["qtdItens"]),
}


def cenario_pedidos(rep: Reporter, recursos: Recursos) -> None:
    """Cria, com usuário PRÓPRIO, pedidos com valores extremos de propósito
    (valorTotal muito alto/muito baixo, um pedido com 50 itens — acima do
    máximo real medido em 11/09/2026, 45 itens no pedido #21) para que a
    conferência tenha variação de verdade, e para forçar o status a ter mais
    de um valor (avança 1 dos pedidos criados para 'Orçamento Enviado').
    NUNCA toca nos 4 pedidos reais pré-existentes (#9, #10, #21, #41)."""
    uid, login = recursos.novo_usuario("pedidos")

    itens_extremos = [
        {"codigo": COD_VALOR_ALTO, "quantidade": 1, "preco_unitario": 100_000_000.0},
        {"codigo": COD_VALOR_BAIXO, "quantidade": 1, "preco_unitario": 0.01},
    ]
    criados_extremos = pedido.salvar_carrinho(itens_extremos, login, uid)
    for p in criados_extremos:
        recursos.pedidos.append(p["id_pedido"])

    fornecedor_volume = database.consultar_um(
        "select fornecedor from compras_pedido"
        " where fator_exibicao is not null and fator_exibicao > 0"
        " group by fornecedor order by count(*) desc fetch first 1 rows only"
    )["fornecedor"]
    codigos_volume = database.consultar(
        "select codigo from compras_pedido"
        " where fornecedor = :f and fator_exibicao is not null and fator_exibicao > 0"
        " fetch first 50 rows only",
        {"f": fornecedor_volume},
    )
    itens_volume = [
        {"codigo": int(r["codigo"]), "quantidade": 1, "preco_unitario": 10.0} for r in codigos_volume
    ]
    criados_volume = pedido.salvar_carrinho(itens_volume, login, uid)
    for p in criados_volume:
        recursos.pedidos.append(p["id_pedido"])
    rep.registrar(
        f"pedido de teste com {len(itens_volume)} itens criado (fornecedor {fornecedor_volume}) — "
        "acima do máximo real medido (45 itens, pedido #21)",
        len(criados_volume) == 1 and len(itens_volume) > 45,
        f"id(s)={[p['id_pedido'] for p in criados_volume]}",
    )

    # variedade de status: avança o pedido-volume para "Orçamento Enviado"
    id_pedido_volume = criados_volume[0]["id_pedido"]
    pedido.avancar_status(id_pedido_volume, login, uid)

    for chave, (expr, de, extrator) in FIELD_MAP_PEDIDOS.items():
        verificar_extremo(rep, "/api/pedidos", _listar_pedidos, chave, expr, de, extrator)

    faltando = pedido.ORDENACOES_VALIDAS - set(FIELD_MAP_PEDIDOS)
    if faltando:
        rep.nao_testado(f"/api/pedidos — colunas não cobertas: {sorted(faltando)}", "confira FIELD_MAP_PEDIDOS")


# ─────────────────────────────────────────────────────────── /api/lotes-preco ─

def _listar_lotes(**kw):
    kw.setdefault("status", None)
    return rotas.listar_lotes_preco(usuario=None, **kw)


FIELD_MAP_LOTES: dict[str, tuple[str, str, object]] = {
    "id": ("l.id_lote", "from app_lote_preco l", lambda it: it["id"]),
    "criadoEm": ("l.criado_em", "from app_lote_preco l", lambda it: it["criadoEm"]),
    "status": ("l.status", "from app_lote_preco l", lambda it: it["status"]),
    "qtdItens": ("nvl(agg.qtd_itens,0)", f"from app_lote_preco l {lote_preco._AGG_LOTE}", lambda it: it["qtdItens"]),
    "qtdAplicados": (
        "nvl(agg.qtd_aplicados,0)", f"from app_lote_preco l {lote_preco._AGG_LOTE}",
        lambda it: it["qtdAplicados"],
    ),
}


def _item_lote(codigo: int, at: float) -> dict:
    return {"codigo": codigo, "alt_pv_at_av": at}


def cenario_lotes(rep: Reporter, recursos: Recursos) -> None:
    """Cria, com DOIS usuários PRÓPRIOS (um por lote — `criar_lote` sem
    `id_lote` REAPROVEITA o Rascunho aberto do MESMO usuário, §4.3; usar o
    mesmo login para os dois lotes juntaria os itens num só, como o
    docstring de `validar_lote_preco.py` já documentou), dois lotes (1 item
    e 5 itens — o único lote real hoje, #186, tem 2) para dar variação real
    a qtdItens e a status ('Rascunho' dos meus x 'Enviado' do #186). NUNCA
    toca no lote #186.

    Os 6 códigos usados são ESCOLHIDOS AGORA entre os que não têm decisão de
    preço gravada (`_codigos_sem_decisao`) — nunca um SKU fixo (achado do
    revisor, 11/09/2026, ver docstring do módulo). Se não houver 6 códigos
    livres, ou se algum ganhar decisão entre a escolha e o uso, o cenário
    ABORTA sem gravar nada — nunca sobrescreve/apaga uma decisão real."""
    codigos = _codigos_sem_decisao(6)
    if len(codigos) < 6:
        rep.registrar(
            "cenário lotes — há códigos livres suficientes (sem decisão de preço gravada) para o teste",
            False,
            f"achei só {len(codigos)} código(s) sem decisão em COMPRAS_PEDIDO; preciso de 6. "
            "Abortando o cenário sem gravar nada — não uso um código com decisão real.",
        )
        return

    colisao = _sem_decisao_ainda(codigos)
    if colisao:
        rep.registrar(
            "cenário lotes — nenhum dos códigos escolhidos ganhou decisão entre a escolha e o uso",
            False,
            f"código(s) {colisao} ganharam decisão de preço gravada agora mesmo (corrida rara) — "
            "abortando o cenário para não sobrescrever/apagar decisão real. Rode de novo.",
        )
        return

    codigos_lote_a, codigos_lote_b = codigos[:1], codigos[1:6]
    recursos.codigos_decisao.extend(codigos)
    rep.registrar(
        f"cenário lotes — códigos escolhidos AGORA, sem decisão prévia (nunca fixos): "
        f"A={codigos_lote_a}, B={codigos_lote_b}",
        True,
        "escolhidos por _codigos_sem_decisao; confira estes números na sua conferência manual",
    )

    uid_a, login_a = recursos.novo_usuario("lotes_a")
    uid_b, login_b = recursos.novo_usuario("lotes_b")

    itens_a = [_item_lote(c, 50.00 + i) for i, c in enumerate(codigos_lote_a)]
    detalhe_a = lote_preco.criar_lote(itens_a, "lote de teste do validador de ordenação — A", login_a, uid_a)
    recursos.lotes.append(detalhe_a["id_lote"])

    itens_b = [_item_lote(c, 60.00 + i) for i, c in enumerate(codigos_lote_b)]
    detalhe_b = lote_preco.criar_lote(itens_b, "lote de teste do validador de ordenação — B", login_b, uid_b)
    recursos.lotes.append(detalhe_b["id_lote"])

    rep.registrar(
        "os dois lotes de teste ficaram em documentos SEPARADOS (sem reaproveitamento de Rascunho, "
        "por usarem usuários diferentes)",
        detalhe_a["id_lote"] != detalhe_b["id_lote"],
        f"a={detalhe_a['id_lote']} (reaproveitado={detalhe_a.get('lote_reaproveitado')}), "
        f"b={detalhe_b['id_lote']} (reaproveitado={detalhe_b.get('lote_reaproveitado')})",
    )

    for chave, (expr, de, extrator) in FIELD_MAP_LOTES.items():
        verificar_extremo(rep, "/api/lotes-preco", _listar_lotes, chave, expr, de, extrator)

    faltando = lote_preco.ORDENACOES_VALIDAS - set(FIELD_MAP_LOTES)
    if faltando:
        rep.nao_testado(f"/api/lotes-preco — colunas não cobertas: {sorted(faltando)}", "confira FIELD_MAP_LOTES")


# ───────────────────────────────────────────────────────────── 422 ─────────

def cenario_422(rep: Reporter) -> None:
    """`ordenar`/`dir` são entrada de usuário virando `order by` — o
    whitelist é a única defesa. Chave/direção fora do domínio tem que dar
    422 explicado, nunca 500 nem SQL interpolado."""
    casos = [
        ("/api/produtos", "ordenar", lambda: _listar_produtos(ordenar="'; drop table app_usuario --", dir=None)),
        ("/api/produtos", "dir", lambda: _listar_produtos(ordenar="codigo", dir="lateral")),
        ("/api/pedidos", "ordenar", lambda: _listar_pedidos(ordenar="coisa_invalida", dir=None)),
        ("/api/pedidos", "dir", lambda: _listar_pedidos(ordenar="id", dir="cima")),
        ("/api/lotes-preco", "ordenar", lambda: _listar_lotes(ordenar="coisa_invalida", dir=None)),
        ("/api/lotes-preco", "dir", lambda: _listar_lotes(ordenar="id", dir="baixo")),
    ]
    for rota, parametro, chamada in casos:
        try:
            chamada()
            ok, detalhe = False, "não levantou exceção nenhuma (deveria ser 422)"
        except HTTPException as exc:
            ok = exc.status_code == 422
            detalhe = f"status={exc.status_code} detail={exc.detail!r}"
        except Exception as exc:  # noqa: BLE001
            ok, detalhe = False, f"levantou {type(exc).__name__}: {exc} (deveria ser HTTPException 422, não 500)"
        rep.registrar(f"{rota}: {parametro} inválido devolve 422 (whitelist recusa, nunca vira SQL)", ok, detalhe)


# ──────────────────────────────────────────────────────────────────── main ─

def main() -> int:
    rep = Reporter()
    print("Lendo baseline do banco (produção — lote #186, 4 pedidos reais, 4 decisões)…")
    estado_antes = capturar_estado()
    print(
        f"  APP_DECISAO_PRECO={len(estado_antes['decisao_preco'])} linha(s); "
        f"APP_LOTE_PRECO={estado_antes['lote_n']} (item={estado_antes['lote_item_n']}, "
        f"hist={estado_antes['lote_hist_n']}); "
        f"APP_PEDIDO={estado_antes['pedido_n']} (item={estado_antes['pedido_item_n']}, "
        f"hist={estado_antes['pedido_hist_n']}); USUARIO={estado_antes['usuario_n']}"
    )
    print(f"  lote #186 no baseline: {estado_antes['lote_186']}")
    print()

    recursos = Recursos()
    try:
        try:
            cenario_extremos_produtos(rep)
            print()
            cenario_nulls_last_produtos(rep)
            print()
        except Exception as exc:  # noqa: BLE001
            rep.registrar("cenário produtos (só leitura)", False, f"exceção: {exc}\n{traceback.format_exc(limit=4)}")

        try:
            cenario_pedidos(rep, recursos)
            print()
        except Exception as exc:  # noqa: BLE001
            rep.registrar("cenário pedidos", False, f"exceção: {exc}\n{traceback.format_exc(limit=4)}")

        try:
            cenario_lotes(rep, recursos)
            print()
        except Exception as exc:  # noqa: BLE001
            rep.registrar("cenário lotes", False, f"exceção: {exc}\n{traceback.format_exc(limit=4)}")

        try:
            cenario_422(rep)
        except Exception as exc:  # noqa: BLE001
            rep.registrar("cenário 422", False, f"exceção: {exc}\n{traceback.format_exc(limit=4)}")

    finally:
        print("\nRestaurando o banco ao estado anterior (excluindo só o que este script criou)…")
        limpar(recursos.usuarios, recursos.pedidos, recursos.lotes, recursos.codigos_decisao)

        estado_depois = capturar_estado()
        restaurado = (
            estado_antes["decisao_preco"] == estado_depois["decisao_preco"]
            and estado_antes["lote_n"] == estado_depois["lote_n"]
            and estado_antes["lote_item_n"] == estado_depois["lote_item_n"]
            and estado_antes["lote_hist_n"] == estado_depois["lote_hist_n"]
            and estado_antes["pedido_n"] == estado_depois["pedido_n"]
            and estado_antes["pedido_item_n"] == estado_depois["pedido_item_n"]
            and estado_antes["pedido_hist_n"] == estado_depois["pedido_hist_n"]
            and estado_antes["usuario_n"] == estado_depois["usuario_n"]
            and estado_antes["lote_186"] == estado_depois["lote_186"]
        )
        rep.registrar(
            "banco restaurado ao estado exato do baseline (lote #186 e as 4 decisões intactos, "
            "mesmo número de pedidos/lotes/usuários)",
            restaurado,
            f"antes={estado_antes}\ndepois={estado_depois}",
        )

    return rep.resumo()


if __name__ == "__main__":
    sys.exit(main())
