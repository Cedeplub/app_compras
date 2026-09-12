"""Prova que `compras.int_cadastro_estoque` e `compras.int_venda_mensal` reproduzem,
linha a linha e coluna a coluna, os dois SQLs de origem de `relatorios_compras`
(`query.py` e `query_mensal.py`).

DESENHO DA VALIDACAO (leia antes de mexer) - ver CONTEXTO.md secao 6.3
------------------------------------------------------------------------------
Este script NAO compara contra um .xlsx salvo em disco. Ele importa `query.py` e
`query_mensal.py` de `relatorios_compras` e chama `montar_consulta()` de cada um -
a mesma funcao que gera o relatorio "de verdade" - para montar o SQL original.
Isso elimina a duplicacao da fonte da verdade: se o SQL original mudar em
`relatorios_compras`, este validador nunca fica comparando contra uma copia velha
sem avisar ninguem.

O METODO MUDOU depois de uma reprovacao falsa (ver CONTEXTO.md 6.3): comparar
tabela materializada contra consulta ao vivo produz um veredito que depende da
HORA em que se roda, porque entre o `dbt run` e a consulta o CEDEP continua
vendendo, reservando e faturando. Isso NAO e' erro de porte, e' defasagem - mas
um criterio de aceite que muda com a hora nao serve. O metodo agora e' dividido
por model, de acordo com o upstream de cada um:

  * ESTOQUE (`int_cadastro_estoque`): upstream e' SO' view de staging. Entao o
    SQL COMPILADO do model (dbt compile, sem materializar) e' executado AO VIVO,
    na sequencia imediata do SQL original, na MESMA conexao. Os dois lados veem
    o EXATO MESMO INSTANTE do banco - a comparacao testa LOGICA, nao sincronia.
    Aceite: zero divergencia nas 41 colunas. Nao ha desculpa de defasagem
    possivel aqui, porque nao ha defasagem.

  * MENSAL (`int_venda_mensal`): upstream inclui TABELAS materializadas
    (`int_faturamento_mensal`, `int_devolucao_mensal`,
    `int_dias_sem_estoque_mensal`), entao reconstruir a cadeia inteira ao vivo a
    cada validacao custaria caro demais para rodar com frequencia. Comparamos o
    SQL original executado agora contra o CONTEUDO JA MATERIALIZADO do model.
    Isso condena a comparacao a ter defasagem SEMPRE no mes corrente (mes em
    andamento muda entre o build e esta consulta), e so' ali - por isso o
    veredito considera SOMENTE OS MESES FECHADOS (mes < 1o dia do mes corrente
    de hoje). O mes corrente e' reportado A PARTE, como informacao, e NUNCA
    reprova sozinho.

Os dois lados rodam na MESMA conexao (usuario COMPRAS, que tem SELECT nas
tabelas do CEDEP usadas por esses relatorios): `ALTER SESSION SET
CURRENT_SCHEMA = CEDEP` antes do SQL original (que usa nomes de tabela sem
prefixo, ex. `pcest`); o SQL compilado do dbt e a leitura do model mensal ja
vem com schema `compras.` totalmente qualificado, entao nao dependem do
schema da sessao.

O periodo do relatorio mensal e' descoberto NO MODEL (`min(mes)`/`max(mes)` de
`compras.int_venda_mensal`) e devolvido como bind :DT_INICIO/:DT_FIM para o SQL
original - se comparassemos janelas diferentes, qualquer conclusao seria
invalida.

Uso:
    python validar_relatorios.py [--tolerancia 0.01] [--somente estoque|mensal|ambos]
                                  [--limite-produtos N] [--codfilial 2] [--uf-destino BA]
                                  [--dbt-target dev]

Aceite:
  - estoque: zero diferenca de linhas e zero divergencia em toda coluna (SQL
    compilado ao vivo x SQL original ao vivo, mesmo instante).
  - mensal: zero diferenca de linhas e zero divergencia em toda coluna, **so'
    nos meses fechados**. O mes corrente e' informativo e nao entra no veredito.

O script NAO afrouxa nada para "passar" - ele mede e imprime; ajustar o model
para o numero fechar e' trabalho de outro agente, e so' depois de alguem decidir
que o gabarito e' que esta certo.
"""
from __future__ import annotations

import argparse
import datetime
import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

import oracledb
import yaml

# ─────────────────────────────────────────────────────────────────────────────
# Caminhos fixos do ambiente (ver CONTEXTO.md §3 e §6.2/6.3)
# ─────────────────────────────────────────────────────────────────────────────
RELATORIOS_DIR = r"C:\Users\Administrator\Desktop\relatorios_compras"
ORACLE_CLIENT_LIB_DIR = r"C:\Oracle\instantclient_21_17"
PROFILES_PATH = os.path.expanduser(r"~\.dbt\profiles.yml")
DBT_DIR = Path(__file__).resolve().parent.parent / "dbt"
DBT_PROJECT_DIR = DBT_DIR / "compras"
DBT_PROJECT_PATH = str(DBT_PROJECT_DIR / "dbt_project.yml")
DBT_EXE = DBT_DIR / "env_server" / "Scripts" / "dbt.exe"
DBT_COMPILED_INTERMEDIATE_DIR = (
    DBT_PROJECT_DIR / "target" / "compiled" / "compras" / "models" / "intermediate"
)

sys.path.insert(0, RELATORIOS_DIR)
import query as query_estoque  # noqa: E402  (import depois do sys.path.insert)
import query_mensal  # noqa: E402


# ─────────────────────────────────────────────────────────────────────────────
# Especificacao das colunas de cada relatorio: nome no SQL original (COLUNAS de
# query.py/query_mensal.py, que E' a fonte da verdade da ordem/rotulo), nome
# esperado na tabela/consulta dbt e tipo de comparacao.
#
# Para int_cadastro_estoque o mapeamento e' identidade coluna a coluna, com UMA
# excecao documentada em dbt/compras/models/intermediate/int_cadastro_estoque.sql:
# a coluna "fornecedor" de query.py (que e' literalmente pcfornec.fornecedor, o
# fornecedor legal da NF) foi renomeada para "fornecedor_legal_nf" no model, de
# proposito, para nao repetir a armadilha da regra 7 do CONTEXTO ("FORNECEDOR" de
# negocio e' o texto do departamento, nao o da NF). E' o MESMO dado, so' o nome
# mudou - por isso comparamos as duas.
# ─────────────────────────────────────────────────────────────────────────────


@dataclass
class ColSpec:
    orig: str  # nome da coluna no SQL original (lowercase)
    dest: str  # nome esperado no model dbt (lowercase)
    tipo: str  # txt | int | num | dec | kg | data
    rotulo: str  # rotulo humano, so para o relatorio impresso


def _colspecs_estoque() -> list[ColSpec]:
    RENOMEIOS = {"fornecedor": "fornecedor_legal_nf"}
    specs = []
    for nome, rotulo, tipo in query_estoque.COLUNAS:
        specs.append(ColSpec(orig=nome, dest=RENOMEIOS.get(nome, nome), tipo=tipo, rotulo=rotulo))
    return specs


def _colspecs_mensal() -> list[ColSpec]:
    specs = []
    for nome, rotulo, tipo in query_mensal.COLUNAS:
        if tipo == "mes":
            continue  # "mes" e' parte da chave, nao e' comparado como coluna de valor
        specs.append(ColSpec(orig=nome, dest=nome, tipo=tipo, rotulo=rotulo))
    return specs


# ─────────────────────────────────────────────────────────────────────────────
# Conexao
# ─────────────────────────────────────────────────────────────────────────────


def _ler_perfil_compras(profiles_path: str) -> dict:
    with open(profiles_path, encoding="utf-8") as f:
        cfg = yaml.safe_load(f)
    return cfg["compras"]


def _ler_credencial_compras(profiles_path: str) -> tuple[str, str, str]:
    """Le usuario/senha/connection_string do perfil 'compras' em profiles.yml.

    A senha NUNCA e' impressa nem gravada em lugar algum - so' vive nesta
    variavel local e no dicionario de conexao do oracledb.
    """
    perfil = _ler_perfil_compras(profiles_path)
    target = perfil["target"]
    out = perfil["outputs"][target]
    return out["user"], out["password"], out["connection_string"]


def _target_padrao_compras(profiles_path: str) -> str:
    """Target usado por padrao no `dbt compile` - o mesmo 'target' que o
    perfil 'compras' usa para conectar, para nao correr o risco de compilar
    contra um profile diferente do que este script conecta."""
    return _ler_perfil_compras(profiles_path)["target"]


def conectar(lib_dir: str, profiles_path: str) -> oracledb.Connection:
    try:
        oracledb.init_oracle_client(lib_dir=lib_dir)
    except oracledb.ProgrammingError:
        pass  # ja inicializado (chamada dupla no mesmo processo) - inofensivo
    user, password, dsn = _ler_credencial_compras(profiles_path)
    conn = oracledb.connect(user=user, password=password, dsn=dsn)
    del password
    return conn


# ─────────────────────────────────────────────────────────────────────────────
# dbt compile - SQL "ao vivo" do model (sem materializar)
# ─────────────────────────────────────────────────────────────────────────────


def compilar_model(nome_model: str, target: str, profiles_dir: str,
                    dbt_vars: dict | None = None) -> str:
    """Roda `dbt compile --select <nome_model>` (NAO `dbt run` - nao precisa
    materializar) e devolve o texto do SQL compilado, com os `ref()`/`var()`
    ja resolvidos para `compras.<tabela>` e valores literais.

    `dbt_vars` sobrescreve as vars do dbt_project.yml (ex.: compras_filial_estoque,
    compras_uf_destino) para casar exatamente com os binds usados do lado do SQL
    original - senao um usuario rodando com --codfilial diferente do default
    estaria comparando dois filtros diferentes sem perceber.
    """
    if not DBT_EXE.exists():
        raise RuntimeError(f"dbt.exe nao encontrado em {DBT_EXE}")
    cmd = [str(DBT_EXE), "compile", "--select", nome_model, "--target", target,
           "--profiles-dir", profiles_dir]
    if dbt_vars:
        cmd += ["--vars", json.dumps(dbt_vars)]

    compiled_path = DBT_COMPILED_INTERMEDIATE_DIR / f"{nome_model}.sql"
    # Brecha 4: `dbt compile --select <seletor-que-nao-bate-com-nada>` sai com
    # codigo 0 e so' avisa "does not match any nodes" no stdout - o arquivo
    # compilado ANTIGO (de um model renomeado, por exemplo) continua no lugar
    # e passaria despercebido se so' checassemos returncode+exists(). Guardamos
    # o instante ANTES de rodar e exigimos que o arquivo tenha sido regravado
    # DEPOIS: se o mtime nao avancou, o compile nao gerou nada novo de verdade.
    t_inicio_compile = time.time()

    proc = subprocess.run(
        cmd, cwd=str(DBT_PROJECT_DIR), capture_output=True, text=True,
        encoding="utf-8", errors="replace",
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"`dbt compile --select {nome_model}` falhou (codigo {proc.returncode}).\n"
            f"--- stdout ---\n{proc.stdout}\n--- stderr ---\n{proc.stderr}"
        )
    saida = proc.stdout + proc.stderr
    if "does not match any nodes" in saida or "Nothing to do" in saida:
        raise RuntimeError(
            f"`dbt compile --select {nome_model}` terminou com codigo 0, mas o seletor "
            f"nao bateu com nenhum node (model renomeado/removido/seletor errado). "
            f"Saida:\n{saida}"
        )
    if not compiled_path.exists():
        raise RuntimeError(
            f"`dbt compile` terminou com codigo 0 mas o arquivo compilado nao "
            f"apareceu em {compiled_path}. Saida:\n{proc.stdout}"
        )
    mtime_depois = compiled_path.stat().st_mtime
    # 1s de folga pela resolucao de relogio do filesystem/SO - ver Brecha 4.
    if mtime_depois < t_inicio_compile - 1.0:
        raise RuntimeError(
            f"`dbt compile --select {nome_model}` terminou com codigo 0, mas "
            f"{compiled_path} NAO foi regravado agora: mtime = "
            f"{datetime.datetime.fromtimestamp(mtime_depois):%Y-%m-%d %H:%M:%S}, anterior ao "
            f"inicio deste compile ({datetime.datetime.fromtimestamp(t_inicio_compile):%Y-%m-%d %H:%M:%S})."
            f" O arquivo e' um SQL compilado ANTIGO (provavelmente de uma execucao passada, "
            f"com o model ainda existindo sob outro nome) - comparar contra ele daria um "
            f"falso PASSOU sobre um model que nao existe mais (Brecha 4). Saida:\n{saida}"
        )
    return compiled_path.read_text(encoding="utf-8")


# ─────────────────────────────────────────────────────────────────────────────
# Execucao de SQL -> lista de dicts {coluna_lower: valor}
# ─────────────────────────────────────────────────────────────────────────────


def executar(conn: oracledb.Connection, sql: str, binds: dict | None = None,
             arraysize: int = 5000) -> list[dict]:
    linhas, _ = executar_com_colunas(conn, sql, binds, arraysize)
    return linhas


def executar_com_colunas(conn: oracledb.Connection, sql: str, binds: dict | None = None,
                          arraysize: int = 5000) -> tuple[list[dict], set[str]]:
    cur = conn.cursor()
    cur.arraysize = arraysize
    cur.prefetchrows = arraysize
    cur.execute(sql, binds or {})
    colunas = [d[0].lower() for d in cur.description]
    linhas = []
    while True:
        bloco = cur.fetchmany(arraysize)
        if not bloco:
            break
        linhas.extend(dict(zip(colunas, row)) for row in bloco)
    cur.close()
    return linhas, set(colunas)


def colunas_da_tabela(conn: oracledb.Connection, sql_from: str) -> set[str]:
    """Nomes de coluna (lowercase) de uma tabela/consulta, sem depender de haver
    linha nenhuma (evita o falso-positivo "coluna nao encontrada" quando o
    resultado vem vazio)."""
    cur = conn.cursor()
    cur.execute(f"select * from {sql_from} where rownum = 0")
    colunas = {d[0].lower() for d in cur.description}
    cur.close()
    return colunas


def tabela_existe(conn: oracledb.Connection, schema: str, tabela: str) -> bool:
    cur = conn.cursor()
    cur.execute(
        "select count(*) from all_objects where owner = :o and object_name = :n"
        " and object_type in ('TABLE', 'VIEW')",
        {"o": schema.upper(), "n": tabela.upper()},
    )
    (n,) = cur.fetchone()
    cur.close()
    return n > 0


def data_construcao(conn: oracledb.Connection, schema: str, tabela: str) -> datetime.datetime | None:
    cur = conn.cursor()
    cur.execute(
        "select last_ddl_time from all_objects where owner = :o and object_name = :n"
        " and object_type = 'TABLE'",
        {"o": schema.upper(), "n": tabela.upper()},
    )
    row = cur.fetchone()
    cur.close()
    return row[0] if row else None


# ─────────────────────────────────────────────────────────────────────────────
# Periodo do relatorio mensal
# ─────────────────────────────────────────────────────────────────────────────


def _primeiro_dia_mes(d: datetime.date) -> datetime.date:
    return d.replace(day=1)


def _add_months(d: datetime.date, n: int) -> datetime.date:
    m = d.month - 1 + n
    y = d.year + m // 12
    m = m % 12 + 1
    return d.replace(year=y, month=m, day=1)


def periodo_do_model(conn: oracledb.Connection) -> tuple[datetime.datetime, datetime.datetime]:
    """min(mes)/max(mes) de compras.int_venda_mensal, convertidos em
    (DT_INICIO, DT_FIM exclusivo) - os mesmos binds que o SQL original espera."""
    cur = conn.cursor()
    cur.execute("select min(mes), max(mes) from compras.int_venda_mensal")
    minimo, maximo = cur.fetchone()
    cur.close()
    dt_inicio = minimo
    dt_fim = _add_months(maximo.date() if hasattr(maximo, "date") else maximo, 1)
    return (
        datetime.datetime(dt_inicio.year, dt_inicio.month, dt_inicio.day),
        datetime.datetime(dt_fim.year, dt_fim.month, dt_fim.day),
    )


def periodo_fallback(dbt_project_path: str,
                      hoje: datetime.date | None = None) -> tuple[datetime.datetime, datetime.datetime, int]:
    """Usado SO' quando compras.int_venda_mensal ainda nao existe: reconstroi a
    janela que o model VAI usar (var compras_meses_historico, lido do proprio
    dbt_project.yml para nao duplicar o numero) so' para provar que o SQL
    original executa e devolve linhas. NAO serve para comparacao - fica
    marcado como tal no relatorio."""
    hoje = hoje or datetime.date.today()
    meses_historico = 24
    try:
        with open(dbt_project_path, encoding="utf-8") as f:
            cfg = yaml.safe_load(f)
        meses_historico = int(cfg.get("vars", {}).get("compras_meses_historico", 24))
    except Exception:
        pass
    primeiro_mes_atual = _primeiro_dia_mes(hoje)
    dt_fim = _add_months(primeiro_mes_atual, 1)
    dt_inicio = _add_months(primeiro_mes_atual, -(meses_historico - 1))
    return (
        datetime.datetime(dt_inicio.year, dt_inicio.month, dt_inicio.day),
        datetime.datetime(dt_fim.year, dt_fim.month, dt_fim.day),
        meses_historico,
    )


# ─────────────────────────────────────────────────────────────────────────────
# Normalizacao / comparacao de valores
# ─────────────────────────────────────────────────────────────────────────────


def _norm_texto(v):
    if v is None:
        return None
    if isinstance(v, str) and v == "":
        return None
    return v


def _norm_num(v):
    if v is None:
        return None
    return float(v)


def _norm_data(v):
    if v is None:
        return None
    if isinstance(v, datetime.datetime):
        return v.date()
    if isinstance(v, datetime.date):
        return v
    return v


def comparar_valor(tipo: str, orig, dest, tolerancia: float):
    """Devolve (igual: bool, diff_ordenacao: float) - diff_ordenacao so' serve
    para escolher os "3 piores exemplos" e o maior-diferenca-absoluta; nunca e'
    usada para decidir igualdade sozinha em coluna de texto/data."""
    if tipo == "txt":
        a, b = _norm_texto(orig), _norm_texto(dest)
        igual = a == b
        diff = 0.0 if igual else 1.0
        return igual, diff
    if tipo == "data":
        a, b = _norm_data(orig), _norm_data(dest)
        igual = a == b
        if igual:
            return True, 0.0
        if a is None or b is None:
            return False, float("inf")
        return False, abs((a - b).days)
    # int | num | dec | kg -> numerico com tolerancia
    a, b = _norm_num(orig), _norm_num(dest)
    if a is None and b is None:
        return True, 0.0
    if a is None or b is None:
        return False, float("inf")
    diff = abs(a - b)
    return diff <= tolerancia, diff


def _fmt(v) -> str:
    if v is None:
        return "NULL"
    if isinstance(v, float):
        return f"{v:.4f}".rstrip("0").rstrip(".")
    s = str(v)
    return s if len(s) <= 40 else s[:37] + "..."


def _as_date(v) -> datetime.date | None:
    if v is None:
        return None
    if isinstance(v, datetime.datetime):
        return v.date()
    return v


# ─────────────────────────────────────────────────────────────────────────────
# Motor de comparacao (generico para os dois relatorios)
# ─────────────────────────────────────────────────────────────────────────────


@dataclass
class ResultadoColuna:
    coluna_orig: str
    coluna_dest: str
    rotulo: str
    total_comparavel: int
    divergentes: int
    maior_diferenca: float
    exemplos: list[tuple]  # (chave_legivel, valor_orig, valor_dest, diff)

    @property
    def pct(self) -> float:
        return 100.0 * self.divergentes / self.total_comparavel if self.total_comparavel else 0.0


@dataclass
class ResultadoRelatorio:
    nome: str
    tempo_orig_s: float
    tempo_dest_s: float
    n_orig: int
    n_dest: int
    n_chaves_duplicadas_orig: int
    n_chaves_duplicadas_dest: int
    so_orig: list
    so_dest: list
    colunas_nao_encontradas: list[str]
    resultados_coluna: list[ResultadoColuna] = field(default_factory=list)
    informativo: bool = False  # True = mes corrente: so' SO_DEST reprova ali (ver `reprova`)
    motivo_informativo: str = ""
    # Brecha 3 (fora da janela): linhas com chave "mes > mes corrente" nao deveriam
    # existir em NENHUM dos dois lados. Preenchido pelo chamador (validar_mensal),
    # nao pelo motor generico `comparar_relatorio`, porque so' o chamador sabe qual
    # e' a janela esperada.
    linhas_fora_janela_orig: int = 0
    linhas_fora_janela_dest: int = 0
    exemplos_fora_janela_orig: list = field(default_factory=list)
    exemplos_fora_janela_dest: list = field(default_factory=list)

    @property
    def ok(self) -> bool:
        """Veredito COMPLETO (usado como esta' para relatorio nao-informativo).

        Brecha 1 (fan-out): chave duplicada em qualquer lado, ou contagem de
        linha divergente, REPROVA aqui - nao e' mais so' um aviso impresso.
        Um `left join` que multiplica linha por chave nao muda o conjunto de
        chaves nem, em geral, os valores da ULTIMA linha (que e' a que
        `_indexar` guarda) - so' aparece como duplicata/contagem, entao sem
        este check o defeito passava batido.

        Brecha 3 (janela): linha com `mes > mes corrente` em qualquer lado
        tambem reprova aqui - nunca deveria existir.
        """
        return (
            not self.so_orig
            and not self.so_dest
            and not self.colunas_nao_encontradas
            and self.n_chaves_duplicadas_orig == 0
            and self.n_chaves_duplicadas_dest == 0
            and self.n_orig == self.n_dest
            and self.linhas_fora_janela_orig == 0
            and self.linhas_fora_janela_dest == 0
            and all(r.divergentes == 0 for r in self.resultados_coluna)
        )

    @property
    def reprova(self) -> bool:
        """O que de fato decide o exit code do script - ver `main()`.

        Brecha 2: em relatorio informativo (mes corrente), a UNICA coisa que
        continua informativa e' "so' no SQL original" (`so_orig`) - explicavel
        por venda ocorrida depois do build (CONTEXTO 6.3). "So' no lado dbt"
        (`so_dest` - o model tem uma chave que o original nao tem) NAO tem essa
        desculpa: se o model inventou uma linha, isso reprova mesmo no mes
        corrente (CONTEXTO regra 9). Fan-out e linha fora da janela tambem nunca
        sao desculpaveis por defasagem, entao entram aqui.

        Em relatorio nao-informativo, `reprova` e' simplesmente `not ok`.
        """
        if self.informativo:
            return (
                bool(self.so_dest)
                or self.n_chaves_duplicadas_dest > 0
                or self.linhas_fora_janela_orig > 0
                or self.linhas_fora_janela_dest > 0
            )
        return not self.ok


def _indexar(linhas: list[dict], chave_fn) -> tuple[dict, int]:
    idx: dict = {}
    duplicadas = 0
    for row in linhas:
        k = chave_fn(row)
        if k in idx:
            duplicadas += 1
        idx[k] = row  # ultima linha vence; duplicadas fica registrado
    return idx, duplicadas


def comparar_relatorio(
    nome: str,
    colspecs: list[ColSpec],
    chave_cols_orig: list[str],
    fmt_chave,
    linhas_orig: list[dict],
    linhas_dest: list[dict],
    colunas_dest_disponiveis: set[str],
    tempo_orig_s: float,
    tempo_dest_s: float,
    tolerancia: float,
    informativo: bool = False,
    motivo_informativo: str = "",
) -> ResultadoRelatorio:
    idx_orig, dup_orig = _indexar(linhas_orig, lambda r: tuple(r[c] for c in chave_cols_orig))
    idx_dest, dup_dest = _indexar(linhas_dest, lambda r: tuple(r[c] for c in chave_cols_orig))

    chaves_orig = set(idx_orig)
    chaves_dest = set(idx_dest)
    so_orig = sorted(chaves_orig - chaves_dest)
    so_dest = sorted(chaves_dest - chaves_orig)
    comuns = chaves_orig & chaves_dest

    colunas_nao_encontradas = [
        f"{c.orig} -> {c.dest}" for c in colspecs if c.dest not in colunas_dest_disponiveis
    ]

    resultados: list[ResultadoColuna] = []
    for c in colspecs:
        if c.dest not in colunas_dest_disponiveis:
            continue
        total = 0
        divergentes = 0
        maior_diff = 0.0
        exemplos: list[tuple] = []
        for k in comuns:
            ov = idx_orig[k].get(c.orig)
            dv = idx_dest[k].get(c.dest)
            total += 1
            igual, diff = comparar_valor(c.tipo, ov, dv, tolerancia)
            if not igual:
                divergentes += 1
                diff_ordenacao = diff if diff != float("inf") else 1e18
                maior_diff = max(maior_diff, diff_ordenacao if diff_ordenacao < 1e18 else maior_diff)
                exemplos.append((fmt_chave(k), ov, dv, diff_ordenacao))
        exemplos.sort(key=lambda t: t[3], reverse=True)
        resultados.append(
            ResultadoColuna(
                coluna_orig=c.orig,
                coluna_dest=c.dest,
                rotulo=c.rotulo,
                total_comparavel=total,
                divergentes=divergentes,
                maior_diferenca=maior_diff,
                exemplos=exemplos[:3],
            )
        )

    resultados.sort(key=lambda r: r.divergentes, reverse=True)

    return ResultadoRelatorio(
        nome=nome,
        tempo_orig_s=tempo_orig_s,
        tempo_dest_s=tempo_dest_s,
        n_orig=len(linhas_orig),
        n_dest=len(linhas_dest),
        n_chaves_duplicadas_orig=dup_orig,
        n_chaves_duplicadas_dest=dup_dest,
        so_orig=so_orig,
        so_dest=so_dest,
        colunas_nao_encontradas=colunas_nao_encontradas,
        resultados_coluna=resultados,
        informativo=informativo,
        motivo_informativo=motivo_informativo,
    )


# ─────────────────────────────────────────────────────────────────────────────
# Impressao
# ─────────────────────────────────────────────────────────────────────────────


def _veredito_str(r: ResultadoRelatorio) -> str:
    if r.informativo:
        if r.reprova:
            return ("REPROVADO (mesmo informativo - so_dest/duplicata/fora-da-janela nao e' "
                     "desculpavel por defasagem; ver CONTEXTO regra 9 e Brecha 1/3)")
        return "INFORMATIVO (nao entra no veredito)"
    return "PASSOU" if r.ok else "REPROVADO"


def imprimir_resultado(r: ResultadoRelatorio):
    print()
    print("=" * 88)
    print(f"RELATORIO: {r.nome}")
    if r.informativo:
        print(f"(INFORMATIVO por padrao - NAO entra no veredito, EXCETO so_dest/duplicata-dest/"
              f"fora-da-janela, que reprovam mesmo aqui. {r.motivo_informativo})")
    print("=" * 88)
    print(f"SQL original : {r.n_orig:>8} linhas em {r.tempo_orig_s:8.2f}s")
    print(f"Lado dbt     : {r.n_dest:>8} linhas em {r.tempo_dest_s:8.2f}s")
    if r.n_chaves_duplicadas_orig:
        print(f"FALHA: {r.n_chaves_duplicadas_orig} chave(s) duplicada(s) no SQL original "
              f"(a query deveria devolver 1 linha por chave) - reprova o aceite, nao e' so' aviso")
    if r.n_chaves_duplicadas_dest:
        print(f"FALHA: {r.n_chaves_duplicadas_dest} chave(s) duplicada(s) no lado dbt (fan-out - "
              f"ex.: um `left join` que multiplica linha por chave) - reprova o aceite, mesmo se os "
              f"valores da ultima linha batem, e mesmo em relatorio informativo")
    if r.n_orig != r.n_dest:
        print(f"FALHA: contagem de linhas diverge (orig={r.n_orig}, dest={r.n_dest})")
    if r.linhas_fora_janela_orig or r.linhas_fora_janela_dest:
        print(f"FALHA: linha(s) com mes > mes corrente (fora da janela esperada) - nunca deveriam "
              f"existir; reprova o aceite, mesmo em relatorio informativo")
        print(f"    no SQL original: {r.linhas_fora_janela_orig}  exemplos: {r.exemplos_fora_janela_orig}")
        print(f"    no lado dbt    : {r.linhas_fora_janela_dest}  exemplos: {r.exemplos_fora_janela_dest}")

    print()
    print(f"-- Diferencas de CONJUNTO --")
    print(f"So' no SQL original : {len(r.so_orig)}" +
          ("  (informativo aqui - explicavel por venda ocorrida depois do build)" if r.informativo and r.so_orig else ""))
    for k in r.so_orig[:3]:
        print(f"    exemplo: {k}")
    print(f"So' no lado dbt      : {len(r.so_dest)}" +
          ("  <<< NUNCA e' informativo, mesmo no mes corrente - reprova (CONTEXTO regra 9)" if r.so_dest else ""))
    for k in r.so_dest[:3]:
        print(f"    exemplo: {k}")

    if r.colunas_nao_encontradas:
        print()
        print("-- Colunas do SQL original SEM correspondente encontrado no lado dbt --")
        print("   (nao entraram na comparacao por coluna abaixo)")
        for c in r.colunas_nao_encontradas:
            print(f"    {c}")

    divergentes_cols = [c for c in r.resultados_coluna if c.divergentes > 0]
    ok_cols = [c for c in r.resultados_coluna if c.divergentes == 0]
    print()
    print(f"-- Por coluna, ordenado por gravidade ({len(divergentes_cols)} com divergencia, "
          f"{len(ok_cols)} identicas de {len(r.resultados_coluna)} comparadas) --")
    if not divergentes_cols:
        print("    (nenhuma)")
    for c in divergentes_cols:
        print()
        print(f"  [{c.coluna_orig}] -> [{c.coluna_dest}]  ({c.rotulo})")
        print(f"      {c.divergentes}/{c.total_comparavel} linhas divergem ({c.pct:.2f}%), "
              f"maior diferenca absoluta = {c.maior_diferenca:.4f}")
        for chave, ov, dv, diff in c.exemplos:
            print(f"      exemplo {chave}: original={_fmt(ov)}  dbt={_fmt(dv)}  diff={diff:.4f}"
                  if diff < 1e18 else
                  f"      exemplo {chave}: original={_fmt(ov)}  dbt={_fmt(dv)}  (nulo de um lado)")

    print()
    print(f"VEREDITO {r.nome}: {_veredito_str(r)}")


# ─────────────────────────────────────────────────────────────────────────────
# Validacao: estoque (int_cadastro_estoque) - SQL COMPILADO ao vivo x ORIGINAL ao vivo
# ─────────────────────────────────────────────────────────────────────────────


def validar_estoque(conn, codfilial: str, uf_destino: str, limite_produtos: int | None,
                     tolerancia: float, dbt_target: str, profiles_path: str) -> ResultadoRelatorio | None:
    print()
    print("[estoque] METODO: upstream de int_cadastro_estoque e' SO' view de staging "
          "(stg_estoque, stg_produto, ...). O SQL COMPILADO do model (dbt compile, "
          "sem materializar) e' executado AO VIVO na sequencia imediata do SQL "
          "original, na MESMA conexao - os dois lados veem o MESMO INSTANTE do banco. "
          "Aceite: zero divergencia. Nao ha desculpa de defasagem possivel aqui.")

    try:
        sql_compilado = compilar_model(
            "int_cadastro_estoque", dbt_target, os.path.dirname(profiles_path),
            dbt_vars={"compras_filial_estoque": codfilial, "compras_uf_destino": uf_destino},
        )
    except RuntimeError as e:
        print(f"[estoque] `dbt compile` falhou - comparacao pendente.\n{e}")
        return None
    print(f"[estoque] SQL compilado (int_cadastro_estoque, filial={codfilial}, "
          f"uf_destino={uf_destino}) obtido via `dbt compile`.")

    cur = conn.cursor()
    cur.execute("alter session set current_schema = CEDEP")
    cur.close()

    codprod_filtro = None
    if limite_produtos:
        codprod_filtro = _amostra_codprod(conn, codfilial, limite_produtos)

    sql_orig, binds = query_estoque.montar_consulta(
        codprod=codprod_filtro, estoque=None, limite=None
    )
    binds["CODFILIAL"] = codfilial
    binds["UF_DESTINO"] = uf_destino

    t0 = time.perf_counter()
    linhas_orig = executar(conn, sql_orig, binds)
    tempo_orig = time.perf_counter() - t0
    print(f"[estoque] SQL original executado: {len(linhas_orig)} linhas em {tempo_orig:.2f}s")

    sql_compilado_exec = sql_compilado
    if codprod_filtro:
        sql_compilado_exec = (
            f"select * from (\n{sql_compilado}\n) t_compilado "
            f"where codprod in ({','.join(str(c) for c in codprod_filtro)})"
        )

    t0 = time.perf_counter()
    linhas_dest, colunas_dest_disponiveis = executar_com_colunas(conn, sql_compilado_exec)
    tempo_dest = time.perf_counter() - t0
    print(f"[estoque] SQL compilado executado (ao vivo): {len(linhas_dest)} linhas em {tempo_dest:.2f}s "
          f"(intervalo entre os dois SELECTs: {tempo_orig + tempo_dest:.2f}s no total desta secao)")

    colspecs = _colspecs_estoque()
    resultado = comparar_relatorio(
        nome="int_cadastro_estoque (SQL compilado, ao vivo) x query.py (compras_estoque, ao vivo)",
        colspecs=colspecs,
        chave_cols_orig=["codprod"],
        fmt_chave=lambda k: f"CODIGO={k[0]}",
        linhas_orig=linhas_orig,
        linhas_dest=linhas_dest,
        colunas_dest_disponiveis=colunas_dest_disponiveis,
        tempo_orig_s=tempo_orig,
        tempo_dest_s=tempo_dest,
        tolerancia=tolerancia,
    )
    return resultado


def _amostra_codprod(conn, codfilial: str, n: int) -> list[int]:
    """Amostra DETERMINISTICA dos N menores codprod (mesmo resultado toda vez
    que rodar, com o mesmo `n`).

    Brecha 5: `where rownum <= :n order by codprod` aplica o `rownum` ANTES do
    `order by` - o Oracle numera as linhas na ordem em que o optimizer decide
    varrer a tabela (nao garantida, pode mudar entre execucoes), e SO' DEPOIS
    ordena essas N linhas ja escolhidas. Isso contradiz o que o help de
    `--limite-produtos` promete ("amostra deterministica"). A correcao e' por
    o `order by` DENTRO de uma subquery e aplicar o `rownum` DE FORA, sobre o
    resultado ja ordenado.
    """
    cur = conn.cursor()
    cur.execute("alter session set current_schema = CEDEP")
    cur.execute(
        "select codprod from ("
        "  select codprod from pcest where codfilial = :cf order by codprod"
        ") where rownum <= :n",
        {"cf": codfilial, "n": n},
    )
    codigos = [row[0] for row in cur.fetchall()]
    cur.close()
    return codigos


# ─────────────────────────────────────────────────────────────────────────────
# Validacao: mensal (int_venda_mensal) - materializado x original, veredito
# restrito aos meses FECHADOS
# ─────────────────────────────────────────────────────────────────────────────


def validar_mensal(conn, codfilial: str, limite_produtos: int | None,
                    tolerancia: float) -> tuple[list[ResultadoRelatorio], str | None]:
    print()
    print("[mensal] METODO: upstream de int_venda_mensal inclui TABELAS materializadas "
          "(int_faturamento_mensal, int_devolucao_mensal, int_dias_sem_estoque_mensal), "
          "entao reconstruir a cadeia ao vivo a cada validacao custa caro demais para "
          "rodar com frequencia (SQL original leva ~2min). Comparamos o SQL original "
          "executado agora contra o CONTEUDO JA MATERIALIZADO do model - o que condena "
          "o mes EM ANDAMENTO a divergir sempre (o CEDEP vende/fatura entre o build e "
          "esta consulta). Por isso o VEREDITO considera SOMENTE OS MESES FECHADOS "
          "(mes < 1o dia do mes corrente de hoje); o mes corrente e' reportado A PARTE, "
          "como informacao, e nunca reprova sozinho - exatamente como a planilha, que "
          "so' usa meses fechados em Q00..Q11 e V00..V05.")

    cur = conn.cursor()
    cur.execute("alter session set current_schema = CEDEP")
    cur.close()

    tabela_ok = tabela_existe(conn, "COMPRAS", "int_venda_mensal")

    if not tabela_ok:
        dt_inicio, dt_fim, meses = periodo_fallback(DBT_PROJECT_PATH)
        print(f"[mensal] compras.int_venda_mensal ainda NAO existe - periodo RECALCULADO "
              f"localmente (compras_meses_historico={meses}, so' para provar execucao): "
              f"{dt_inicio:%Y-%m-%d} a {dt_fim:%Y-%m-%d} (exclusivo)")
        codprod_filtro = None
        if limite_produtos:
            codprod_filtro = _amostra_codprod(conn, codfilial, limite_produtos)
        sql, binds = query_mensal.montar_consulta(dt_inicio, dt_fim, codprod=codprod_filtro)
        binds["FILIAL_ESTOQUE"] = codfilial
        t0 = time.perf_counter()
        linhas_orig = executar(conn, sql, binds)
        tempo_orig = time.perf_counter() - t0
        print(f"[mensal] SQL original executado: {len(linhas_orig)} linhas em {tempo_orig:.2f}s")
        print(f"[mensal] Prova de execucao do SQL original: OK ({len(linhas_orig)} linhas). "
              f"Comparacao pendente ate compras.int_venda_mensal existir.")
        if linhas_orig:
            print(f"[mensal] Primeira linha (amostra): { {k: _fmt(v) for k, v in list(linhas_orig[0].items())[:6]} }")
        return [], "int_venda_mensal (model ainda nao existe)"

    build_ts = data_construcao(conn, "COMPRAS", "int_venda_mensal")
    if build_ts:
        idade = datetime.datetime.now() - build_ts
        print(f"[mensal] compras.int_venda_mensal construido em {build_ts:%Y-%m-%d %H:%M:%S} "
              f"({idade.total_seconds()/3600:.1f}h atras). Se muito antigo, rode "
              f"`dbt run --select int_venda_mensal+` antes de confiar no veredito.")

    dt_inicio, dt_fim = periodo_do_model(conn)
    print(f"[mensal] periodo efetivo do model (min/max(mes)): "
          f"{dt_inicio:%m/%Y} a {_add_months(dt_fim.date(), -1):%m/%Y} "
          f"(DT_INICIO={dt_inicio:%Y-%m-%d}, DT_FIM exclusivo={dt_fim:%Y-%m-%d})")

    mes_corrente = _primeiro_dia_mes(datetime.date.today())
    print(f"[mensal] mes corrente (hoje={datetime.date.today():%Y-%m-%d}): {mes_corrente:%m/%Y} "
          f"- meses < {mes_corrente:%Y-%m-%d} entram no veredito; {mes_corrente:%m/%Y} e' informativo.")

    codprod_filtro = None
    if limite_produtos:
        codprod_filtro = _amostra_codprod(conn, codfilial, limite_produtos)

    sql, binds = query_mensal.montar_consulta(dt_inicio, dt_fim, codprod=codprod_filtro)
    binds["FILIAL_ESTOQUE"] = codfilial

    t0 = time.perf_counter()
    linhas_orig = executar(conn, sql, binds)
    tempo_orig = time.perf_counter() - t0
    print(f"[mensal] SQL original executado: {len(linhas_orig)} linhas em {tempo_orig:.2f}s")

    filtro_sql = ""
    if codprod_filtro:
        filtro_sql = f" where codigo_produto in ({','.join(str(c) for c in codprod_filtro)})"
    colunas_dest_disponiveis = colunas_da_tabela(conn, "compras.int_venda_mensal")
    t0 = time.perf_counter()
    linhas_dest = executar(conn, f"select * from compras.int_venda_mensal{filtro_sql}")
    tempo_dest = time.perf_counter() - t0
    print(f"[mensal] model dbt lido: {len(linhas_dest)} linhas em {tempo_dest:.2f}s")

    def _mes(row):
        return _as_date(row["mes"])

    linhas_orig_fechados = [r for r in linhas_orig if _mes(r) is not None and _mes(r) < mes_corrente]
    linhas_orig_corrente = [r for r in linhas_orig if _mes(r) == mes_corrente]
    linhas_orig_futuro = [r for r in linhas_orig if _mes(r) is not None and _mes(r) > mes_corrente]

    linhas_dest_fechados = [r for r in linhas_dest if _mes(r) is not None and _mes(r) < mes_corrente]
    linhas_dest_corrente = [r for r in linhas_dest if _mes(r) == mes_corrente]
    linhas_dest_futuro = [r for r in linhas_dest if _mes(r) is not None and _mes(r) > mes_corrente]

    if linhas_orig_futuro or linhas_dest_futuro:
        print(f"[mensal] FALHA: {len(linhas_orig_futuro)} linha(s) no SQL original e "
              f"{len(linhas_dest_futuro)} no model com mes > mes corrente ({mes_corrente:%m/%Y}) "
              f"- isto NUNCA deveria acontecer (a janela e' [DT_INICIO, DT_FIM exclusivo], "
              f"DT_FIM = 1o dia do mes seguinte ao corrente). Excluidas dos grupos de "
              f"comparacao por coluna abaixo (senao a chave nem apareceria em `comuns`), mas "
              f"anexadas a 'MESES FECHADOS' como falha estrutural - reprova o aceite (Brecha 3).")

    print(f"[mensal] split: fechados orig={len(linhas_orig_fechados)}/dest={len(linhas_dest_fechados)}  "
          f"|  corrente({mes_corrente:%m/%Y}) orig={len(linhas_orig_corrente)}/dest={len(linhas_dest_corrente)}")

    colspecs = _colspecs_mensal()

    resultado_fechados = comparar_relatorio(
        nome="int_venda_mensal x query_mensal.py (MESES FECHADOS - determina o veredito)",
        colspecs=colspecs,
        chave_cols_orig=["mes", "codigo_produto"],
        fmt_chave=lambda k: f"CODIGO={k[1]} MES={k[0]:%m/%Y}" if k[0] else f"CODIGO={k[1]} MES=None",
        linhas_orig=linhas_orig_fechados,
        linhas_dest=linhas_dest_fechados,
        colunas_dest_disponiveis=colunas_dest_disponiveis,
        tempo_orig_s=tempo_orig,
        tempo_dest_s=tempo_dest,
        tolerancia=tolerancia,
        informativo=False,
    )
    # Brecha 3: linha "fora da janela" (mes > mes corrente) nao entra na
    # comparacao coluna-a-coluna (a chave nem apareceria em `comuns`), mas nao
    # pode so' virar aviso e sumir - anexada aqui para reprovar o aceite via
    # `ResultadoRelatorio.ok`/`reprova`.
    resultado_fechados.linhas_fora_janela_orig = len(linhas_orig_futuro)
    resultado_fechados.linhas_fora_janela_dest = len(linhas_dest_futuro)
    resultado_fechados.exemplos_fora_janela_orig = [
        f"CODIGO={r['codigo_produto']} MES={_mes(r):%m/%Y}" for r in linhas_orig_futuro[:3]
    ]
    resultado_fechados.exemplos_fora_janela_dest = [
        f"CODIGO={r['codigo_produto']} MES={_mes(r):%m/%Y}" for r in linhas_dest_futuro[:3]
    ]

    resultado_corrente = comparar_relatorio(
        nome=f"int_venda_mensal x query_mensal.py (MES CORRENTE {mes_corrente:%m/%Y})",
        colspecs=colspecs,
        chave_cols_orig=["mes", "codigo_produto"],
        fmt_chave=lambda k: f"CODIGO={k[1]} MES={k[0]:%m/%Y}" if k[0] else f"CODIGO={k[1]} MES=None",
        linhas_orig=linhas_orig_corrente,
        linhas_dest=linhas_dest_corrente,
        colunas_dest_disponiveis=colunas_dest_disponiveis,
        tempo_orig_s=tempo_orig,
        tempo_dest_s=tempo_dest,
        tolerancia=tolerancia,
        informativo=True,
        motivo_informativo=(
            "Mes em andamento: o CEDEP vende/fatura/reserva entre o build do model e "
            "esta consulta ao SQL original, entao divergencia aqui e' esperada por "
            "construcao (mesma causa medida em CONTEXTO.md 6.3 - qtreserv/qtdisp/"
            "dt_ult_saida do estoque). Nao e' erro de porte."
        ),
    )

    return [resultado_fechados, resultado_corrente], None


# ─────────────────────────────────────────────────────────────────────────────
# main
# ─────────────────────────────────────────────────────────────────────────────


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tolerancia", type=float, default=0.01,
                     help="tolerancia absoluta para colunas numericas (default 0.01)")
    ap.add_argument("--somente", choices=["estoque", "mensal", "ambos"], default="ambos",
                     help="qual relatorio validar (default ambos)")
    ap.add_argument("--limite-produtos", type=int, default=None,
                     help="restringe a comparacao a N codprod (amostra determinística, "
                          "mesmo filtro aplicado dos dois lados) - so' para desenvolvimento; "
                          "o aceite final e' SEM este parametro")
    ap.add_argument("--codfilial", default="2", help="bind :CODFILIAL / :FILIAL_ESTOQUE (default '2')")
    ap.add_argument("--uf-destino", default="BA", help="bind :UF_DESTINO (default 'BA')")
    ap.add_argument("--lib-dir", default=ORACLE_CLIENT_LIB_DIR, help="Oracle Instant Client (modo thick)")
    ap.add_argument("--profiles-path", default=PROFILES_PATH, help="caminho do profiles.yml")
    ap.add_argument("--dbt-target", default=None,
                     help="target usado no `dbt compile` do lado estoque (default: o mesmo "
                          "'target' de profiles.yml compras)")
    args = ap.parse_args()

    if args.limite_produtos:
        print(f"AVISO: --limite-produtos={args.limite_produtos} ativo - isto e' um modo de "
              f"desenvolvimento. O aceite final exige rodar SEM este parametro.")

    dbt_target = args.dbt_target or _target_padrao_compras(args.profiles_path)

    t_inicio = time.perf_counter()
    conn = conectar(args.lib_dir, args.profiles_path)
    print(f"Conectado como COMPRAS em {datetime.datetime.now():%Y-%m-%d %H:%M:%S}.")
    print()
    print("#" * 88)
    print("METODO (ver CONTEXTO.md 6.3): tabela materializada NAO e' comparada contra SQL")
    print("original 'ao vivo' quando os dois lados podem ver instantes diferentes do banco -")
    print("isso produz veredito que muda com a hora, o que ja causou reprovacao falsa aqui.")
    print("  estoque: SQL compilado do model (dbt compile, sem materializar) executado AO VIVO")
    print("           contra o SQL original AO VIVO, mesma conexao - mesmo instante, sem tolerancia")
    print("           de sincronia.")
    print("  mensal : SQL original AO VIVO contra o CONTEUDO MATERIALIZADO do model; veredito so'")
    print("           sobre meses FECHADOS. Mes corrente sai a parte, informativo, nao reprova.")
    print("#" * 88)

    resultados: list[ResultadoRelatorio] = []
    pendencias: list[str] = []

    if args.somente in ("estoque", "ambos"):
        r = validar_estoque(conn, args.codfilial, args.uf_destino, args.limite_produtos,
                             args.tolerancia, dbt_target, args.profiles_path)
        if r is None:
            pendencias.append("int_cadastro_estoque (dbt compile falhou ou model ainda nao existe)")
        else:
            resultados.append(r)

    if args.somente in ("mensal", "ambos"):
        rs, pendencia = validar_mensal(conn, args.codfilial, args.limite_produtos, args.tolerancia)
        resultados.extend(rs)
        if pendencia:
            pendencias.append(pendencia)

    conn.close()

    for r in resultados:
        imprimir_resultado(r)

    tempo_total = time.perf_counter() - t_inicio

    resultados_veredito = [r for r in resultados if not r.informativo]
    resultados_informativos = [r for r in resultados if r.informativo]

    print()
    print("#" * 88)
    if pendencias:
        print("PENDENTE (model dbt ainda nao construido, comparacao nao pode rodar):")
        for p in pendencias:
            print(f"  - {p}")
    for r in resultados_veredito:
        print(f"{r.nome}: {_veredito_str(r)}")
    for r in resultados_informativos:
        print(f"{r.nome}: {_veredito_str(r)}")
    print(f"Tempo total: {tempo_total:.2f}s")
    print("#" * 88)

    if pendencias and not resultados_veredito:
        sys.exit(2)
    if any(r.reprova for r in resultados):
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
