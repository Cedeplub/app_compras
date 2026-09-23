"""Frescor da carga e disparo do `dbt build` (Etapa 12 — carimbo + botão).

Lê `APP_ATUALIZACAO` (gravada pelo executor `dbt/atualizar.py`, contrato travado
com o outro agente) e `compras_parametro` (data/mês de referência do modelo).
Este serviço NUNCA escreve em `APP_ATUALIZACAO` — quem é dono da linha do
começo ao fim é o processo filho disparado por `disparar()`; aqui só se
interpreta o estado, nunca se corrige.

Por que `subprocess.Popen` e não uma thread: o uvicorn deste projeto sobe à
mão e é derrubado com frequência. Uma thread dentro do FastAPI morreria junto
com o processo da API e deixaria a linha travada em EM_ANDAMENTO para sempre.
O processo filho, desacoplado (DETACHED_PROCESS), sobrevive ao reinício da API.
"""
from __future__ import annotations

import datetime as dt
import logging
import subprocess
import sys

from app import config
from app.core import database

log = logging.getLogger("app_compras.atualizacao")

# Log do disparo (stdout/stderr do Popen do filho). Sem isto, a única
# mensagem que aponta a causa de um disparo que "não funcionou" (ex.:
# "dbt.exe não encontrado", achado 1 da Etapa 16) ia para DEVNULL e nunca
# aparecia em lugar nenhum - custou uma sessão inteira de medição até alguém
# perceber que a causa estava sendo descartada pelo próprio código. `logs/`
# já está em `.gitignore`.
_LOG_DISPARO = config.BASE_DIR / "logs" / "atualizacao_disparo.log"

# CONCLUIDO_COM_AVISO conta como sucesso em toda decisão de negocio (frescor,
# trava de intervalo entre disparos): dbt run passou, so o dbt test reprovou.
_STATUS_SUCESSO = ("CONCLUIDO", "CONCLUIDO_COM_AVISO")

# Sem este corte, um processo morto por reboot/kill travaria o botao para
# sempre em "em andamento" - ninguem mais conseguiria disparar nada.
#
# Build completo medido: 235s e 276s (build inteiro, dbt run + test). O
# `dbt run` isolado ja variou 76s/253s no mesmo dia, mesmos models - carga do
# Oracle, nao bug. 20min era menor que um build plausivel num dia ruim: aos
# 20min a linha virava FALHOU (so para exibicao) e, sem a separacao abaixo,
# isso também liberava o botao - um clique nesse momento disparava uma SEGUNDA
# carga concorrente sobre a MESMA execucao, ainda rodando. 45min so deve ser
# atingido por um processo de fato morto (reboot/kill).
_LIMITE_EXECUCAO_MORTA_MIN = 45

# "Considerar morta" (acima) e "liberar o botao" sao decisoes diferentes e
# usam numeros diferentes de proposito: a trava de arquivo do atualizar.py
# (codigo 3) e a rede de seguranca contra concorrencia real, mas a API nao
# deve *convidar* ao clique bem no instante em que a duracao apenas ficou
# fora do comum. Este numero e sempre >= _LIMITE_EXECUCAO_MORTA_MIN, com uma
# folga adicional para absorver desalinho de relogio entre o host da API e o
# host do banco (ambos os limites agora sao calculados pelo relogio do banco,
# nao pelo `datetime.now()` da API - ver `_ultima_execucao`).
_LIMITE_LIBERAR_BOTAO_MIN = 60

# Um build leva de 2 a 5 minutos (medido: dbt run de 76s e de 253s no mesmo
# dia). Sem esta trava, clique repetido enfileira builds concorrentes.
_LIMITE_RELIBERACAO_MIN = 10


class AtualizacaoEmAndamento(RuntimeError):
    """Já existe uma execução em andamento (dentro do limite de execução morta)."""


class AtualizacaoRecente(RuntimeError):
    """A última execução bem-sucedida terminou há pouco tempo."""

    def __init__(self, minutos_faltando: int):
        self.minutos_faltando = minutos_faltando
        super().__init__(
            f"Os dados já foram atualizados recentemente. "
            f"Tente novamente em {minutos_faltando} minuto"
            f"{'s' if minutos_faltando != 1 else ''}."
        )


def _ultima_execucao() -> dict | None:
    """Traz a ultima linha JA com os minutos decorridos calculados pelo banco.

    `minutos_desde_inicio`/`minutos_desde_fim` usam `sysdate` (relogio do
    Oracle) contra `inicio`/`fim` (gravados pelo Oracle) - o mesmo relogio dos
    dois lados. Comparar `datetime.now()` do host da API com um timestamp do
    banco (dois hosts, dois relogios) faria um desalinho de fuso/DST/drift
    bloquear o botao por uma hora ou destravar uma execucao viva na hora
    seguinte.
    """
    return database.consultar_um(
        "select id_atualizacao, origem, solicitado_por, inicio, fim, status,"
        " duracao_seg, fase_falha, mensagem, arquivo_log,"
        " (sysdate - cast(inicio as date)) * 1440 as minutos_desde_inicio,"
        " (sysdate - cast(fim as date)) * 1440 as minutos_desde_fim"
        " from app_atualizacao order by inicio desc fetch first 1 rows only"
    )


def _parametro() -> dict:
    linha = database.consultar_um(
        "select data_referencia, mes_referencia from compras_parametro"
    )
    return linha or {"data_referencia": None, "mes_referencia": None}


def _interpretar(execucao: dict | None) -> dict:
    """Marca como FALHOU (so para exibicao) apos `_LIMITE_EXECUCAO_MORTA_MIN`.

    Nunca altera a linha no banco. Isto e so a interpretacao mostrada na
    tela; quem decide se o botao pode ser clicado e `_bloqueado_em_andamento`,
    com um limite proprio e maior (`_LIMITE_LIBERAR_BOTAO_MIN`) — ver comentario
    das duas constantes.
    """
    if execucao is None:
        return execucao
    minutos = execucao.get("minutos_desde_inicio")
    if execucao["status"] == "EM_ANDAMENTO" and minutos is not None and minutos > _LIMITE_EXECUCAO_MORTA_MIN:
        execucao = {
            **execucao,
            "status": "FALHOU",
            "mensagem": "execução interrompida — provavelmente o processo foi encerrado",
        }
    return execucao


def _bloqueado_em_andamento(execucao_bruta: dict | None) -> bool:
    """Decide se o botao deve ficar bloqueado por execucao em andamento.

    Deliberadamente separado de `_interpretar`: usa o status BRUTO (antes de
    qualquer reinterpretacao) e o limite maior `_LIMITE_LIBERAR_BOTAO_MIN`, para
    que "considerar morta na tela" (45min) e "liberar o botao para um novo
    disparo" (60min) nunca sejam o mesmo instante.
    """
    if not execucao_bruta or execucao_bruta["status"] != "EM_ANDAMENTO":
        return False
    minutos = execucao_bruta.get("minutos_desde_inicio")
    if minutos is None:
        return True
    return minutos <= _LIMITE_LIBERAR_BOTAO_MIN


def estado() -> dict:
    """Estado atual da carga: última execução + data/mês de referência vigentes.

    Nunca estoura por `compras_parametro` vazia — esta é a rota que alimenta o
    carimbo do cabeçalho e precisa responder mesmo com o banco a meio caminho
    de um build (tabela em troca de nome, ainda sem linha).
    """
    execucao_bruta = _ultima_execucao()
    execucao = _interpretar(execucao_bruta)
    parametro = _parametro()

    em_andamento = bool(execucao and execucao["status"] == "EM_ANDAMENTO")
    bloqueado = _bloqueado_em_andamento(execucao_bruta)
    pode_atualizar = True
    proxima_liberacao_em = None
    if bloqueado:
        pode_atualizar = False
    elif execucao_bruta and execucao_bruta["status"] in _STATUS_SUCESSO and execucao_bruta["fim"]:
        minutos_desde_fim = execucao_bruta.get("minutos_desde_fim") or 0
        faltam_min = _LIMITE_RELIBERACAO_MIN - minutos_desde_fim
        if faltam_min > 0:
            pode_atualizar = False
            proxima_liberacao_em = int(faltam_min) + 1

    def _iso(v):
        """Timestamp ISO completo — usado em `inicio`/`fim`, onde a HORA é
        informação de verdade (o momento em que a carga rodou)."""
        if v is None:
            return None
        if isinstance(v, (dt.datetime, dt.date)):
            return v.isoformat()
        return v

    def _data(v):
        """Data pura (`%Y-%m-%d`), sem hora — mesma representação que
        `GET /api/parametros` já usa para a MESMA coluna (rotas.py:83).

        Não pode virar timestamp: `new Date("...T00:00:00")` é lido como hora
        LOCAL pelo navegador e `new Date("...")` (data pura) como UTC — a
        mesma data viraria "há 6 dias" ou "há 7 dias" dependendo do fuso do
        cliente (ver `web/src/periodo.js`)."""
        if v is None:
            return None
        if isinstance(v, (dt.datetime, dt.date)):
            return v.strftime("%Y-%m-%d")
        return v

    return {
        "status": execucao["status"] if execucao else None,
        "origem": execucao["origem"] if execucao else None,
        "solicitadoPor": execucao["solicitado_por"] if execucao else None,
        "inicio": _iso(execucao["inicio"]) if execucao else None,
        "fim": _iso(execucao["fim"]) if execucao else None,
        "duracaoSeg": execucao["duracao_seg"] if execucao else None,
        "mensagem": execucao["mensagem"] if execucao else None,
        "dataReferencia": _data(parametro.get("data_referencia")),
        "mesReferencia": _data(parametro.get("mes_referencia")),
        "emAndamento": em_andamento,
        "podeAtualizar": pode_atualizar,
        "proximaLiberacaoEm": proxima_liberacao_em,
    }


def disparar(login: str) -> dict:
    """Dispara `dbt/atualizar.py` em background e devolve o estado atual.

    Recusa (sem disparar nada) quando já há execução em andamento ou quando a
    última bem-sucedida terminou há pouco. Quem grava EM_ANDAMENTO é o próprio
    processo filho (contrato travado) — esta função só o inicia e sai; a API
    não acompanha nem espera.
    """
    execucao_bruta = _ultima_execucao()

    if _bloqueado_em_andamento(execucao_bruta):
        raise AtualizacaoEmAndamento("Já existe uma atualização em andamento.")

    if execucao_bruta and execucao_bruta["status"] in _STATUS_SUCESSO and execucao_bruta["fim"]:
        minutos_desde_fim = execucao_bruta.get("minutos_desde_fim") or 0
        faltam_min = _LIMITE_RELIBERACAO_MIN - minutos_desde_fim
        if faltam_min > 0:
            raise AtualizacaoRecente(int(faltam_min) + 1)

    script = config.BASE_DIR / "dbt" / "atualizar.py"
    # Append, não truncate: cada disparo se soma ao histórico do arquivo -
    # é um log de diagnóstico, não o registro de execução (esse é o
    # APP_ATUALIZACAO, gravado pelo próprio filho).
    # ⚠ Abrir o log NÃO pode derrubar o disparo. Se `logs/` não for gravável
    # (permissão, disco cheio), o botão tem de continuar funcionando SEM o
    # diagnóstico - um log de diagnóstico que impede a função que ele
    # diagnostica troca um defeito silencioso por um barulhento, mas ainda
    # assim quebra o que funcionava. Sem o arquivo, cai no DEVNULL de antes.
    try:
        _LOG_DISPARO.parent.mkdir(parents=True, exist_ok=True)
        log_disparo = open(_LOG_DISPARO, "a", encoding="utf-8")
    except OSError:
        log.warning("Não consegui abrir %s; disparando sem log de diagnóstico.", _LOG_DISPARO)
        log_disparo = None

    saida = log_disparo if log_disparo is not None else subprocess.DEVNULL
    try:
        subprocess.Popen(
            [sys.executable, str(script), "--origem", "manual", "--por", login],
            cwd=str(config.BASE_DIR),
            # Desacoplamento do filho (Etapa 12): sobrevive ao reinício do
            # uvicorn. Isto NÃO muda aqui - só o destino de stdout/stderr muda.
            creationflags=subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS,
            close_fds=True,
            stdout=saida,
            stderr=saida,
        )
    finally:
        # O Popen duplica o descritor para o processo filho; o handle do pai
        # pode (e deve) ser fechado logo em seguida.
        if log_disparo is not None:
            log_disparo.close()
    return estado()
