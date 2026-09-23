"""Configuracao do dashboard. Tudo vem do .env ao lado da raiz do projeto.

Nenhuma credencial tem valor padrao aqui: se faltar no .env, `validar()` diz o que
falta e `main.py` recusa subir em vez de rodar com senha embutida no codigo (o
oposto do que `relatorios_compras/config.py` faz — ver CONTEXTO.md).
"""
from __future__ import annotations

import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
ENV_PATH = BASE_DIR / ".env"


def _carregar_env() -> None:
    if not ENV_PATH.exists():
        return
    for linha in ENV_PATH.read_text(encoding="utf-8").splitlines():
        linha = linha.strip()
        if not linha or linha.startswith("#") or "=" not in linha:
            continue
        chave, valor = linha.split("=", 1)
        # setdefault: variavel de ambiente real tem prioridade sobre o .env
        os.environ.setdefault(chave.strip(), valor.strip())


_carregar_env()

# ------------------------------------------------------------------ Oracle ---
# Schema COMPRAS. O app nao enxerga o CEDEP por nenhum caminho (CONTEXTO.md §2).
ORA_USER = os.environ.get("ORA_USER", "")
ORA_PASSWORD = os.environ.get("ORA_PASSWORD", "")
ORA_DSN = os.environ.get("ORA_DSN", "")
ORA_SCHEMA = os.environ.get("ORA_SCHEMA", "COMPRAS")

# Modo thick e obrigatorio neste servidor (verificador de senha legado 0x939).
# ORA_PYTHON_DRIVER_TYPE nao vale fora do dbt-oracle (CONTEXTO.md §3).
ORA_CLIENT_DIR = os.environ.get("ORA_CLIENT_DIR", "")

ORA_POOL_MAX = int(os.environ.get("ORA_POOL_MAX", "4"))

# ---------------------------------------------------------------- Guardas ---
# Execucoes simultaneas no banco. Teto propositalmente <= ORA_POOL_MAX para
# nunca esgotar o pool com consulta pendurada.
MAX_EXECUCOES_SIMULTANEAS = int(os.environ.get("APP_MAX_EXEC", "3"))

# Teto por execucao, em segundos. Estourou, devolve erro claro em vez de pendurar.
TIMEOUT_SEGUNDOS = int(os.environ.get("APP_TIMEOUT_SEGUNDOS", "30"))

# ------------------------------------------------------------------- HTTP ---
HTTP_HOST = os.environ.get("APP_HOST", "0.0.0.0")
HTTP_PORT = int(os.environ.get("APP_PORT", "8020"))

# Cookie de sessao (token opaco, nao JWT). secure=True exige HTTPS; a rede
# interna ainda e HTTP.
COOKIE_NOME = "app_compras_sessao"
COOKIE_SECURE = os.environ.get("APP_COOKIE_SECURE", "0") == "1"
SESSAO_HORAS = int(os.environ.get("APP_SESSAO_HORAS", "12"))

# Paginacao da tela de decisao de compra.
ITENS_POR_PAGINA = int(os.environ.get("APP_ITENS_POR_PAGINA", "50"))

# --------------------------------------------------------------------- dbt ---
# Profile/target que `dbt/atualizar.py` usa como default dos seus argumentos
# `--profile`/`--target`. Os defaults abaixo REPRODUZEM o comportamento de hoje
# (produção não muda de comportamento so por esta constante existir): antes
# desta mudanca o script ja rodava com profile fixo "compras" (dbt_project.yml)
# e target default "prod" (argparse). Uma instancia isolada (ex.: dev) define
# DBT_PROFILE=compras_dev e DBT_TARGET=dev no seu proprio .env.
#
# Atencao ao ler: `_carregar_env()` acima usa `os.environ.setdefault`, entao uma
# variavel de ambiente JA DEFINIDA no processo (por exemplo, pela Tarefa
# Agendada) vence o que estiver escrito no .env. Hoje a Tarefa Agendada so
# define DBT_PROFILES_DIR (dbt/atualizar.py), entao isto nao muda nada em
# producao agora - mas quem for depurar um valor de DBT_PROFILE/DBT_TARGET que
# "nao bate com o .env" precisa checar o ambiente do processo antes de suspeitar
# do arquivo.
DBT_PROFILE = os.environ.get("DBT_PROFILE", "compras")
DBT_TARGET = os.environ.get("DBT_TARGET", "prod")


def validar() -> str:
    """Devolve a mensagem do que falta para subir o app, ou string vazia."""
    faltando = [
        nome
        for nome, valor in (
            ("ORA_USER", ORA_USER),
            ("ORA_PASSWORD", ORA_PASSWORD),
            ("ORA_DSN", ORA_DSN),
            ("ORA_CLIENT_DIR", ORA_CLIENT_DIR),
        )
        if not valor
    ]
    if faltando:
        return f"Faltam no .env: {', '.join(faltando)}"
    return ""
