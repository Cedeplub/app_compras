#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Ponto de entrada único para atualização do dbt.

Chamado por três lugares:
  1. Tarefa Agendada (06:00 e 13:00): python atualizar.py --origem agendado
  2. Botão na tela (POST /api/atualizacao): Popen sem wait
  3. rodar_dbt.bat (uso manual): python atualizar.py --origem manual --por USERNAME

Roda sequência seed → run → test com --target PROD.
Travado por arquivo para impedir duas execuções simultâneas.
Grava desfecho em APP_ATUALIZACAO e retorna:
  0 = CONCLUIDO
  1 = FALHOU
  2 = CONCLUIDO_COM_AVISO
  3 = já rodando (trava)

Importa app.core.database para falar com Oracle, e invoca dbt/env_server/Scripts/dbt.exe
como subprocesso (não dentro do venv).
"""
from __future__ import annotations

import argparse
import contextlib
import datetime
import logging
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
from typing import Literal

import oracledb

# Insira raiz do projeto no sys.path para importar app.core.database
_RAIZ = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_RAIZ))

from app.core import database

# Forçar UTF-8 na saída, independente do codepage do console que invocou este
# script (Tarefa Agendada/SYSTEM, botão via Popen com stdout=DEVNULL, .bat sem
# chcp, etc. - o `chcp 65001` do .bat não cobre esses outros chamadores).
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

# ============================================================================
# Configuração
# ============================================================================

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
log = logging.getLogger("atualizar")

LOCK_FILE = pathlib.Path(__file__).parent / ".atualizacao.lock"
DBT_PROJECT = pathlib.Path(__file__).parent / "compras"
DBT_EXE = pathlib.Path(__file__).parent / "env_server" / "Scripts" / "dbt.exe"
DBT_LOG = DBT_PROJECT / "logs" / "dbt.log"
LOGS_DIR = pathlib.Path(__file__).parent / "logs_execucao"

# Limpar logs com mais de 30 dias
DAYS_KEEP_LOGS = 30

# Timeout para dbt (30 minutos por fase). Pior caso seed+run+test = 90 min.
# O -ExecutionTimeLimit da Tarefa Agendada (infra/agendar_atualizacao.ps1) tem
# que ficar ACIMA dessa soma (hoje: 120 min) - nunca abaixo, senão o Agendador
# mata o processo no meio, nenhum finally roda, e a linha em APP_ATUALIZACAO
# fica EM_ANDAMENTO para sempre. Medido em produção: build completo em 235s e
# 276s - 30min/fase é folga de sobra, não o tempo normal de execução.
TIMEOUT_DBT = 30 * 60

# Diretório real do profiles.yml do dbt. A Tarefa Agendada roda como SYSTEM
# (ou outra conta de serviço) e SYSTEM não tem ~/.dbt próprio - por isso
# infra/agendar_atualizacao.ps1 define DBT_PROFILES_DIR explicitamente no
# ambiente do processo agendado. Aqui só existe o fallback para uso manual
# (rodar_dbt.bat, terminal), onde ~/.dbt é o do usuário logado de verdade.
DBT_PROFILES_DIR = os.environ.get("DBT_PROFILES_DIR") or str(pathlib.Path.home() / ".dbt")

# Status no banco
STATUS_EM_ANDAMENTO = "EM_ANDAMENTO"
STATUS_CONCLUIDO = "CONCLUIDO"
STATUS_CONCLUIDO_COM_AVISO = "CONCLUIDO_COM_AVISO"
STATUS_FALHOU = "FALHOU"

FASES = Literal["seed", "run", "test"]

# ============================================================================
# Trava de exclusão
# ============================================================================


def _escrever_trava_nova() -> None:
    """Cria o arquivo de trava com O_EXCL e grava PID:horário_criação no MESMO
    descritor, atomicamente (mesma chamada que garantiu a exclusão mútua) -
    nunca existe uma janela em que o arquivo existe vazio."""
    fd = os.open(str(LOCK_FILE), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    try:
        conteudo = f"{os.getpid()}:{time.time():.3f}".encode("utf-8")
        os.write(fd, conteudo)
    finally:
        os.close(fd)


@contextlib.contextmanager
def trava_exclusao(origem: str, por: str | None):
    """Adquire trava de arquivo (PID:horário_criação).

    - Arquivo vazio → outro processo ganhou o O_EXCL e ainda não terminou de
      gravar (janela ínfima, não existe mais graças a _escrever_trava_nova,
      mas se ainda assim acontecer tratamos como trava viva, nunca como
      corrompida): recusa com código 3.
    - PID gravado e processo vivo com o mesmo horário de criação → recusa (3).
    - PID gravado mas processo morto, ou vivo porém reaproveitado por OUTRO
      processo (horário de criação não bate) → trava órfã: apaga e adquire.
    """
    trava_adquirida = False

    for tentativa in range(1, 7):
        try:
            _escrever_trava_nova()
            log.info("Trava adquirida (PID %d)", os.getpid())
            trava_adquirida = True
            break
        except FileExistsError:
            pass

        # Trava já existe (de alguém). Ler e decidir.
        try:
            conteudo = LOCK_FILE.read_text().strip()
        except FileNotFoundError:
            # Liberada entre o O_EXCL falhar e a leitura: tentar de novo.
            continue
        except OSError as e:
            log.error("Não foi possível ler o arquivo de trava: %s", e)
            registrar_recusa(origem, por, None, f"erro ao ler trava: {e}")
            sys.exit(3)

        if not conteudo:
            # Vazio: trava recém-criada por outro processo, nunca "corrompida".
            log.error("já existe uma atualização em andamento (trava sendo criada por outro processo)")
            registrar_recusa(origem, por, None, "trava vazia (outro processo criando agora)")
            sys.exit(3)

        pid_antigo = None
        criacao_antiga = None
        try:
            partes = conteudo.split(":", 1)
            pid_antigo = int(partes[0])
            if len(partes) > 1:
                criacao_antiga = float(partes[1])
        except ValueError:
            log.warning("Trava com conteúdo inesperado (%r), tratando como órfã", conteudo)

        if pid_antigo is not None:
            criacao_atual = _processo_criacao(pid_antigo)
            if criacao_atual is not None:
                # Processo com esse PID existe. Só é "o mesmo" que segurou a
                # trava se o horário de criação bater (tolerância de 3s) -
                # senão é reaproveitamento de PID e a trava é órfã.
                mesmo_processo = (
                    criacao_antiga is None or abs(criacao_atual - criacao_antiga) < 3
                )
                if mesmo_processo:
                    log.error("já existe uma atualização em andamento (PID %d)", pid_antigo)
                    registrar_recusa(origem, por, pid_antigo, "trava ativa")
                    sys.exit(3)
                else:
                    log.warning(
                        "PID %d existe mas foi reaproveitado por outro processo (trava órfã)",
                        pid_antigo
                    )
            else:
                log.warning("Trava órfã (PID %d morto), apagando", pid_antigo)

        try:
            LOCK_FILE.unlink()
        except FileNotFoundError:
            pass
        except OSError as e:
            log.error("Não foi possível apagar trava órfã: %s", e)
            registrar_recusa(origem, por, pid_antigo, f"trava órfã, falha ao apagar: {e}")
            sys.exit(3)
        # loop tenta de novo

    if not trava_adquirida:
        log.error("Não foi possível adquirir a trava após %d tentativas", tentativa)
        registrar_recusa(origem, por, None, "trava disputada demais, desistindo")
        sys.exit(3)

    try:
        yield
    finally:
        if trava_adquirida:
            try:
                LOCK_FILE.unlink()
                log.info("Trava liberada")
            except OSError:
                log.warning("Falha ao liberar trava")


def _processo_criacao(pid: int) -> float | None:
    """Retorna o epoch de criação do PID (via wmic CreationDate), ou None se
    o processo não existe. Usado para distinguir 'mesmo processo que criou a
    trava' de 'PID reaproveitado por processo diferente' (defeito 2)."""
    try:
        result = subprocess.run(
            ["wmic", "process", "where", f"ProcessId={pid}", "get", "CreationDate"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5
        )
        for linha in result.stdout.splitlines():
            linha = linha.strip()
            if linha[:14].isdigit():
                dt = datetime.datetime.strptime(linha[:14], "%Y%m%d%H%M%S")
                return dt.timestamp()
        return None
    except Exception as e:
        log.warning("Erro ao verificar PID %d com wmic: %s", pid, e)
        # wmic indisponível: cair para uma checagem simples de existência
        # (tasklist) sem horário de criação - mesmo_processo assume True
        # (comportamento conservador: melhor recusar do que colidir).
        try:
            result = subprocess.run(
                ["tasklist", "/FI", f"PID eq {pid}"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=5
            )
            return time.time() if str(pid) in result.stdout else None
        except Exception as e2:
            log.warning("Fallback tasklist também falhou: %s", e2)
            return None


def registrar_recusa(origem: str, por: str | None, pid_antigo: int | None, motivo: str) -> None:
    """Grava a recusa (trava ocupada) em arquivo - não em APP_ATUALIZACAO, que
    é tabela de execuções; uma recusa não é execução e poluiria o carimbo do
    cabeçalho (que lê a última linha). Sem isto, o botão que dispara com
    stdout/stderr=DEVNULL não deixava rastro nenhum de uma recusa (achado 3)."""
    try:
        LOGS_DIR.mkdir(parents=True, exist_ok=True)
        linha = (
            f"{datetime.datetime.now():%Y-%m-%d %H:%M:%S} RECUSADA "
            f"origem={origem} por={por or '-'} pid_segurando={pid_antigo or '?'} "
            f"motivo={motivo}\n"
        )
        with open(LOGS_DIR / "recusas.log", "a", encoding="utf-8") as f:
            f.write(linha)
    except OSError as e:
        log.error("Não foi possível gravar log de recusa (%s): %s", motivo, e)


# ============================================================================
# Banco de dados
# ============================================================================


def inserir_inicio(origem: str, por: str | None) -> int:
    """Insert em APP_ATUALIZACAO com status EM_ANDAMENTO. Retorna id_atualizacao.

    Usa `returning id_atualizacao into` no próprio insert - nunca
    `select max(id_atualizacao)`, que sob concorrência (achados 2/3 tornam
    isso possível) pega o ID de OUTRA execução e fecha a linha errada,
    deixando a sua própria EM_ANDAMENTO para sempre (o defeito 1 de novo).
    """
    sql_insert = """
    insert into APP_ATUALIZACAO (origem, solicitado_por, inicio, status)
    values (:origem, :por, systimestamp, :status)
    returning id_atualizacao into :id_out
    """

    binds = {"origem": origem, "por": por, "status": STATUS_EM_ANDAMENTO}

    with database.conexao() as conn:
        cur = conn.cursor()
        id_var = cur.var(oracledb.DB_TYPE_NUMBER)
        cur.execute(sql_insert, {**binds, "id_out": id_var})
        conn.commit()
        valores = id_var.getvalue()
        id_atualizacao = int(valores[0]) if valores else None
        cur.close()

    if id_atualizacao is None:
        raise RuntimeError("Falha ao inserir em APP_ATUALIZACAO: ID não obtido")

    log.info("Registrado em APP_ATUALIZACAO: id=%d, origem=%s", id_atualizacao, origem)
    return id_atualizacao


def atualizar_desfecho(
    id_atualizacao: int,
    status: str,
    fase_falha: str | None,
    mensagem: str,
    duracao_seg: int,
    arquivo_log: str | None
) -> None:
    """UPDATE da linha com desfecho."""
    sql = f"""
    update APP_ATUALIZACAO
    set
        fim = systimestamp,
        status = :status,
        fase_falha = :fase,
        mensagem = :msg,
        duracao_seg = :duracao,
        arquivo_log = :arquivo
    where id_atualizacao = :id
    """
    binds = {
        "id": id_atualizacao,
        "status": status,
        "fase": fase_falha,
        "msg": truncar_bytes(mensagem, 500) if mensagem else None,
        "duracao": duracao_seg,
        "arquivo": arquivo_log
    }

    with database.conexao() as conn:
        cur = conn.cursor()
        cur.execute(sql, binds)
        conn.commit()
        cur.close()

    log.info(
        "Atualizado APP_ATUALIZACAO: id=%d, status=%s, fase_falha=%s, duracao=%ds",
        id_atualizacao, status, fase_falha, duracao_seg
    )


# ============================================================================
# dbt - execução
# ============================================================================


def rodar_dbt_fase(fase: FASES, target: str) -> tuple[int, str]:
    """Roda uma fase do dbt (seed, run, test).

    Retorna (código_saída, stdout+stderr_capturado).
    """
    cmd = [str(DBT_EXE), fase, "--target", target, "--no-use-colors"]
    log.info("Iniciando: %s", " ".join(cmd))

    # DBT_PROFILES_DIR explícito no ambiente do subprocesso: a Tarefa Agendada
    # roda como SYSTEM, que não tem ~/.dbt - sem isto, `dbt seed` morre com
    # "could not find profile" e a tarefa nunca consegue rodar (achado 1).
    env = dict(os.environ)
    env["DBT_PROFILES_DIR"] = DBT_PROFILES_DIR
    env.setdefault("PYTHONUTF8", "1")

    try:
        result = subprocess.run(
            cmd,
            cwd=str(DBT_PROJECT),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=TIMEOUT_DBT,
            env=env
        )
        return result.returncode, result.stdout
    except subprocess.TimeoutExpired:
        log.error("Timeout após %d segundos", TIMEOUT_DBT)
        return 1, f"TIMEOUT: dbt {fase} ultrapassou {TIMEOUT_DBT}s"
    except Exception as e:
        log.error("Erro ao executar dbt: %s", e)
        return 1, f"ERRO: {e}"


def truncar_bytes(texto: str, limite_bytes: int) -> str:
    """Trunca por BYTES (utf-8), não por caracteres.

    A coluna é varchar2(500) - em AL32UTF8 isso é 500 BYTES, não 500
    caracteres. Um acento (nome/comentário em pt-BR ecoado pelo dbt) some
    bem antes de 500 caracteres e o UPDATE falha com ORA-12899 -
    exatamente ao tentar fechar a linha de uma execução que já falhou.
    """
    if not texto:
        return texto
    bruto = texto.encode("utf-8")[:limite_bytes]
    return bruto.decode("utf-8", errors="ignore")


def extrair_mensagem_erro(saida: str, max_chars: int = 500) -> str:
    """Extrai as linhas úteis de erro (Error, Failure, Completed with).

    Percorre a saída procurando por marcadores, remove ANSI escapes e timestamps
    dbt (HH:MM:SS), retorna as últimas linhas relevantes. Trunca em max_chars.
    """
    # Remover escape sequences ANSI (\x1b[...m)
    saida = re.sub(r"\x1b\[[0-9;]*m", "", saida)

    # Remover timestamps do dbt (HH:MM:SS no INÍCIO da linha, ex: "11:52:28
    # Encountered an error:"). Ancorado com ^/re.M: sem âncora isso apagava
    # QUALQUER hora que aparecesse no meio do texto, não só o carimbo do dbt.
    saida = re.sub(r"^\d{2}:\d{2}:\d{2}\s+", "", saida, flags=re.MULTILINE)

    linhas = saida.split("\n")
    mensagens = []

    for linha in linhas:
        linha = linha.strip()
        linha_lower = linha.lower()
        # "0 errors" (ex.: "Completed successfully - 0 errors, 0 warnings")
        # é linha de SUCESSO, não deve entrar como mensagem de erro. Só pula
        # se não houver também uma contagem de erro != 0 na mesma linha.
        if re.search(r"\b0\s+errors?\b", linha_lower) and not re.search(r"\b[1-9]\d*\s+errors?\b", linha_lower):
            continue
        if any(x in linha for x in ["Error", "error", "Failure", "failure", "Completed with"]):
            mensagens.append(linha)

    resultado = "\n".join(mensagens[-5:]) if mensagens else "Sem detalhes de erro na saída"
    return resultado[:max_chars]


# ============================================================================
# Logs
# ============================================================================


def apagar_log_anterior() -> None:
    """Apaga dbt/compras/logs/dbt.log antes de começar."""
    if DBT_LOG.exists():
        try:
            DBT_LOG.unlink()
            log.info("Log anterior deletado: %s", DBT_LOG)
        except Exception as e:
            log.warning("Não foi possível deletar log anterior: %s", e)


def copiar_log(id_atualizacao: int) -> str | None:
    """Copia dbt/compras/logs/dbt.log para dbt/logs_execucao/dbt_<yyyyMMdd_HHmmss>.log.

    Retorna o caminho relativo para APP_ATUALIZACAO.arquivo_log.
    """
    if not DBT_LOG.exists():
        log.warning("Log do dbt não encontrado: %s", DBT_LOG)
        return None

    LOGS_DIR.mkdir(parents=True, exist_ok=True)

    agora = datetime.datetime.now()
    timestamp = agora.strftime("%Y%m%d_%H%M%S")
    arquivo_dest = LOGS_DIR / f"dbt_{timestamp}.log"

    try:
        shutil.copy(str(DBT_LOG), str(arquivo_dest))
        log.info("Log copiado para: %s", arquivo_dest)
        return f"dbt/logs_execucao/dbt_{timestamp}.log"
    except Exception as e:
        log.error("Erro ao copiar log: %s", e)
        return None


def limpar_logs_antigos() -> None:
    """Deleta logs em dbt/logs_execucao/ com mais de DAYS_KEEP_LOGS dias."""
    if not LOGS_DIR.exists():
        return

    agora = time.time()
    limpar_antes = agora - (DAYS_KEEP_LOGS * 86400)

    for arquivo in LOGS_DIR.glob("dbt_*.log"):
        if arquivo.stat().st_mtime < limpar_antes:
            try:
                arquivo.unlink()
                log.info("Log antigo deletado: %s", arquivo.name)
            except Exception as e:
                log.warning("Erro ao deletar log antigo %s: %s", arquivo.name, e)


# ============================================================================
# Orquestração
# ============================================================================


def main():
    parser = argparse.ArgumentParser(
        description="Atualizar dbt (seed, run, test)"
    )
    parser.add_argument(
        "--origem",
        required=True,
        choices=["manual", "agendado"],
        help="Origem da execução"
    )
    parser.add_argument(
        "--por",
        default=None,
        help="Usuário que solicitou (só com --origem manual)"
    )
    parser.add_argument(
        "--target",
        default="prod",
        help="Target do dbt (padrão: prod)"
    )

    args = parser.parse_args()

    origem = args.origem.upper()
    por = args.por
    target = args.target

    log.info("=" * 70)
    log.info("Iniciando atualização (origem=%s, por=%s, target=%s)", origem, por, target)
    log.info("=" * 70)

    # Verificar se arquivo dbt.exe existe
    if not DBT_EXE.exists():
        log.error("dbt.exe não encontrado: %s", DBT_EXE)
        sys.exit(1)

    tempo_inicio = time.time()
    id_atualizacao = None
    status_final = STATUS_FALHOU
    fase_falha = None
    mensagem = ""
    arquivo_log = None

    try:
        with trava_exclusao(origem, por):
            # 1. Trava adquirida, prosseguir
            apagar_log_anterior()

            # 2. Inserir em APP_ATUALIZACAO
            database.iniciar_pool()
            id_atualizacao = inserir_inicio(origem, por)

            # 3. Rodar fases
            saida_acumulada = {}

            for fase in ["seed", "run", "test"]:
                log.info("Iniciando fase: %s", fase)
                codigo, saida = rodar_dbt_fase(fase, target)
                saida_acumulada[fase] = saida

                if codigo != 0:
                    if fase == "test":
                        # Test falhou, mas dados foram carregados: CONCLUIDO_COM_AVISO
                        log.warning("Phase %s retornou %d (aviso)", fase, codigo)
                        status_final = STATUS_CONCLUIDO_COM_AVISO
                        fase_falha = fase
                        mensagem = extrair_mensagem_erro(saida)
                        break  # Não continua, mas é aviso
                    else:
                        # Seed ou run falhou: FALHOU
                        log.error("Phase %s retornou %d (erro)", fase, codigo)
                        status_final = STATUS_FALHOU
                        fase_falha = fase
                        mensagem = extrair_mensagem_erro(saida)
                        break
            else:
                # Todas as fases OK
                status_final = STATUS_CONCLUIDO
                log.info("Todas as fases completadas com sucesso")

            # 4. Copiar log
            arquivo_log = copiar_log(id_atualizacao)

    except Exception as e:
        log.error("EXCEÇÃO NÃO TRATADA (antes de atualizar desfecho): %s", e, exc_info=True)
        status_final = STATUS_FALHOU

    finally:
        # 5. SEMPRE atualizar desfecho, mesmo em exceção
        # Este bloco **sempre** roda e **sempre** fecha a linha
        duracao = int(time.time() - tempo_inicio)
        if id_atualizacao and status_final:
            try:
                atualizar_desfecho(
                    id_atualizacao,
                    status_final,
                    fase_falha,
                    mensagem,
                    duracao,
                    arquivo_log
                )
            except Exception as e2:
                log.error("ERRO ao atualizar desfecho (crítico): %s", e2, exc_info=True)
                # Última tentativa: gravar só status para liberar o botão
                try:
                    with database.transacao() as conn:
                        cur = conn.cursor()
                        cur.execute(
                            "update APP_ATUALIZACAO set fim=systimestamp, status=:status where id_atualizacao=:id",
                            {"id": id_atualizacao, "status": status_final}
                        )
                        cur.close()
                except Exception as e3:
                    log.error("FALHA CRÍTICA ao gravar status: %s", e3, exc_info=True)

        # 6. Limpar logs antigos
        try:
            limpar_logs_antigos()
        except Exception as e:
            log.warning("Erro ao limpar logs: %s", e)

        database.fechar_pool()

    # 7. Resumo na saída
    log.info("=" * 70)
    log.info("RESUMO DA EXECUÇÃO")
    log.info("-" * 70)
    log.info("Duração: %d segundos", int(time.time() - tempo_inicio))
    log.info("Status: %s", status_final)
    if fase_falha:
        log.info("Fase de falha: %s", fase_falha)
    if mensagem:
        log.info("Mensagem: %s", mensagem)
    if arquivo_log:
        log.info("Log: %s", arquivo_log)
    log.info("=" * 70)

    # 8. Código de saída
    if status_final == STATUS_CONCLUIDO:
        sys.exit(0)
    elif status_final == STATUS_CONCLUIDO_COM_AVISO:
        sys.exit(2)
    elif status_final == STATUS_FALHOU:
        sys.exit(1)
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
