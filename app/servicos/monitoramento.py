"""Monitoramento e Entradas — as duas telas de acompanhamento (Etapa 10).

Lê COMPRAS_MONITORAMENTO (grão dia × produto, 400 dias) e COMPRAS_ENTRADA
(grão item de nota, 180 dias). Nenhuma delas escreve.

── Por que a agregação é feita no BANCO ─────────────────────────────────────
São 338 mil linhas de venda diária. Trazer isso para o Python e somar em
memória seria transferir megabytes por clique para produzir um número. O SQL
soma onde o dado está e devolve dezenas de linhas.

── O comparativo com o ano anterior ─────────────────────────────────────────
O protótipo mostra "+6,4%" fixo, que não reage a filtro, período ou métrica
(PROTOTIPO.md §8) — o próprio Diretor confirmou que é limitação, não intenção.
Aqui ele é calculado, e com um cuidado que muda o número: quando o período está
EM CURSO, a comparação usa a fatia equivalente do ano anterior, não o período
inteiro.

Medido em 02/09/2026: o mês corrente tinha 2 dias corridos, R$ 4,77 mi. Contra
o mesmo trecho de 2025 (R$ 3,22 mi) são +48%. Contra setembro/2025 inteiro
seriam −88%. O primeiro número é a verdade; o segundo é o calendário fingindo
ser queda de venda.
"""
from __future__ import annotations

import datetime as dt

from app.core import database


def _data(iso: str) -> dt.date:
    """Texto ISO da tela vira `date` de verdade antes de virar bind.

    Passar a string crua causava ORA-01861 (`literal does not match format
    string`): o Oracle tentaria interpretá-la com o NLS_DATE_FORMAT da sessão,
    que varia com o ambiente e não é ISO por padrão. Converter aqui torna a
    consulta independente de configuração de sessão — e o erro, se a data vier
    malformada, aparece em Python com a mensagem certa em vez de estourar no
    banco.
    """
    try:
        return dt.date.fromisoformat(iso)
    except (TypeError, ValueError) as e:
        raise ValueError(f"data inválida: {iso!r} (esperado AAAA-MM-DD)") from e

# As quatro métricas da tela, cada uma com a coluna que a sustenta.
# ⚠ PESO e LITROS são aproximação: a quantidade é histórica, mas o peso e a
# litragem unitários vêm do cadastro ATUAL do produto (o dbt documenta isso em
# compras_monitoramento). Um produto que mudou de embalagem carrega o peso novo
# no histórico inteiro. Aceitável para acompanhar tendência, não para conferir
# uma nota fiscal antiga.
METRICAS = {
    "faturamento": "valor_liquido",
    "quantidade": "quantidade_liquida",
    "peso": "peso_liquido_kg",
    "litros": "litros_liquido",
}

# A ordem importa: é a sequência de quebra automática do protótipo (§2.2) —
# Departamento → Seção → Linha → Categoria. Linha e Categoria ainda não existem
# no modelo (dependem de cadastro no Winthor), então a cadeia hoje para na Seção.
DIMENSOES = ["departamento", "secao"]


def _filtros(f: dict, alias: str = "m") -> tuple[str, dict]:
    cond, binds = [], {}
    if f.get("departamento"):
        cond.append(f"{alias}.departamento = :departamento")
        binds["departamento"] = f["departamento"]
    if f.get("secao"):
        cond.append(f"{alias}.secao = :secao")
        binds["secao"] = f["secao"]
    if f.get("status"):
        cond.append(f"{alias}.status = :status")
        binds["status"] = f["status"]
    if f.get("busca"):
        cond.append(f"(to_char({alias}.codigo_produto) like :busca"
                    f" or upper({alias}.produto) like upper(:busca))")
        binds["busca"] = f"%{f['busca'].strip()}%"
    return (" and " + " and ".join(cond)) if cond else "", binds


def proxima_dimensao(filtros: dict) -> str | None:
    """A primeira dimensão ainda NÃO fixada por filtro, E que tenha o que abrir.

    É a regra de quebra automática do protótipo: a tela não tem botão de
    "agrupar por" — ela abre pela primeira dimensão que ainda está em "Todos".
    Fixou departamento, quebra por seção; fixou os dois, mostra só o total.

    ⚠ A segunda condição é nossa, e nasce de um defeito real. Seção só existe de
    verdade em 2 dos 47 departamentos; nos outros 39 ela repete o nome do
    próprio departamento. Sem a checagem, fixar "PETROBRAS" abriria uma quebra
    por seção com uma linha só, chamada "PETROBRAS", repetindo o total que já
    está no cartão acima — uma tabela que não informa nada e parece defeito.

    A checagem é feita no DADO, não numa lista de exceções: quando o cadastro do
    Winthor fechar, a quebra passa a funcionar sozinha para os departamentos que
    ganharem seção, sem mudança de código.
    """
    for d in DIMENSOES:
        if filtros.get(d):
            continue
        if d == "secao" and not _secao_util(filtros):
            continue
        return d
    return None


def _secao_util(filtros: dict) -> bool:
    """Há mais de uma seção no recorte atual? Se não, quebrar por ela é ruído."""
    onde, binds = _filtros(filtros)
    linha = database.consultar_um(
        f"select count(distinct m.secao) as n from compras_monitoramento m"
        f" where m.secao is not null {onde}",
        binds,
    )
    return int(linha["n"] or 0) > 1


def resumo(filtros: dict, de: str, ate: str, de_ant: str, ate_ant: str,
           metrica: str) -> dict:
    """Total do período e do mesmo trecho do ano anterior, com a variação."""
    coluna = METRICAS.get(metrica, METRICAS["faturamento"])
    onde, binds = _filtros(filtros)

    linha = database.consultar_um(
        f"""
        select
            nvl(sum(case when m.dia between :de and :ate
                         then m.{coluna} end), 0)         as atual,
            nvl(sum(case when m.dia between :de_ant and :ate_ant
                         then m.{coluna} end), 0)         as anterior,
            count(distinct case when m.dia between :de and :ate
                                then m.codigo_produto end) as produtos
          from compras_monitoramento m
         where (m.dia between :de and :ate
                or m.dia between :de_ant and :ate_ant)
               {onde}
        """,
        {**binds, "de": _data(de), "ate": _data(ate),
         "de_ant": _data(de_ant), "ate_ant": _data(ate_ant)},
    )
    atual = float(linha["atual"] or 0)
    anterior = float(linha["anterior"] or 0)
    return {
        "atual": atual,
        "anterior": anterior,
        # Sem base no ano anterior não existe variação. Devolver 0% ou 100%
        # inventaria um número; `null` a tela sabe mostrar como "—".
        "variacao": (atual - anterior) / anterior if anterior else None,
        "produtos": int(linha["produtos"] or 0),
    }


def por_dimensao(filtros: dict, de: str, ate: str, de_ant: str, ate_ant: str,
                 metrica: str, dimensao: str) -> list[dict]:
    """A quebra do período pela dimensão, com o comparativo linha a linha."""
    if dimensao not in DIMENSOES:
        raise ValueError(f"dimensão inválida: {dimensao}")
    coluna = METRICAS.get(metrica, METRICAS["faturamento"])
    onde, binds = _filtros(filtros)

    linhas = database.consultar(
        f"""
        select m.{dimensao}                                as grupo,
               nvl(sum(case when m.dia between :de and :ate
                            then m.{coluna} end), 0)       as atual,
               nvl(sum(case when m.dia between :de_ant and :ate_ant
                            then m.{coluna} end), 0)       as anterior
          from compras_monitoramento m
         where (m.dia between :de and :ate
                or m.dia between :de_ant and :ate_ant)
               {onde}
         group by m.{dimensao}
        having nvl(sum(case when m.dia between :de and :ate
                            then m.{coluna} end), 0) <> 0
            or nvl(sum(case when m.dia between :de_ant and :ate_ant
                            then m.{coluna} end), 0) <> 0
         order by 2 desc
        """,
        {**binds, "de": _data(de), "ate": _data(ate),
         "de_ant": _data(de_ant), "ate_ant": _data(ate_ant)},
    )
    return [
        {
            "grupo": l["grupo"],
            "atual": float(l["atual"] or 0),
            "anterior": float(l["anterior"] or 0),
            "variacao": ((float(l["atual"] or 0) - float(l["anterior"] or 0))
                         / float(l["anterior"])) if l["anterior"] else None,
        }
        for l in linhas
    ]


def por_produto(filtros: dict, de: str, ate: str, de_ant: str, ate_ant: str,
                metrica: str, limite: int = 50) -> list[dict]:
    """Os produtos do período, do maior para o menor na métrica escolhida."""
    coluna = METRICAS.get(metrica, METRICAS["faturamento"])
    onde, binds = _filtros(filtros)

    linhas = database.consultar(
        f"""
        select * from (
            select m.codigo_produto, m.produto, m.departamento, m.secao, m.status,
                   nvl(sum(case when m.dia between :de and :ate
                                then m.{coluna} end), 0)   as atual,
                   nvl(sum(case when m.dia between :de_ant and :ate_ant
                                then m.{coluna} end), 0)   as anterior
              from compras_monitoramento m
             where (m.dia between :de and :ate
                    or m.dia between :de_ant and :ate_ant)
                   {onde}
             group by m.codigo_produto, m.produto, m.departamento, m.secao, m.status
            having nvl(sum(case when m.dia between :de and :ate
                                then m.{coluna} end), 0) <> 0
             order by 6 desc
        ) where rownum <= :limite
        """,
        {**binds, "de": _data(de), "ate": _data(ate),
         "de_ant": _data(de_ant), "ate_ant": _data(ate_ant), "limite": limite},
    )
    return [
        {
            "codigo": int(l["codigo_produto"]),
            "nome": l["produto"],
            "departamento": l["departamento"],
            "secao": l["secao"],
            "status": l["status"],
            "atual": float(l["atual"] or 0),
            "anterior": float(l["anterior"] or 0),
            "variacao": ((float(l["atual"] or 0) - float(l["anterior"] or 0))
                         / float(l["anterior"])) if l["anterior"] else None,
        }
        for l in linhas
    ]


def opcoes_monitoramento() -> dict:
    """Departamentos e seções que TÊM movimento — não o catálogo inteiro.

    Oferecer no filtro um departamento sem uma venda sequer no período leva a
    pessoa a um resultado vazio que parece defeito.
    """
    # ⚠ SEÇÃO só é oferecida onde ela EXISTE de verdade.
    #
    # Medido em 02/09/2026: dos 47 departamentos, apenas 2 (TECFIL e OUTROS)
    # têm mais de uma seção. Nos outros 39 a "seção" é o próprio nome do
    # departamento repetido — 53% das 338 mil linhas têm
    # `departamento = secao`. É o cadastro que ainda está em andamento no
    # Winthor, e não uma dimensão pronta.
    #
    # Oferecer um filtro de Seção populado com os mesmos nomes do filtro de
    # Departamento é pior que não oferecer: parecem duas dimensões e são uma
    # só, e quem cruzar os dois não vê nada mudar. A consulta abaixo devolve
    # seções só dos departamentos que têm mais de uma — e devolve lista vazia
    # quando não há nenhuma, que é o sinal para a tela desabilitar o campo.
    #
    # Quando o cadastro do Winthor fechar, esta mesma consulta passa a devolver
    # as seções reais sozinha, sem mudança de código.
    return {
        "departamentos": [r["departamento"] for r in database.consultar(
            "select distinct departamento from compras_monitoramento"
            " where departamento is not null order by 1")],
        "secoes": [r["secao"] for r in database.consultar(
            """
            select distinct m.secao
              from compras_monitoramento m
             where m.secao is not null
               and m.departamento in (
                     select departamento from compras_monitoramento
                      group by departamento having count(distinct secao) > 1)
             order by 1
            """)],
    }


# ─────────────────────────────────────────────────────────────────────────── #
#  Entradas                                                                    #
# ─────────────────────────────────────────────────────────────────────────── #

def entradas(filtros: dict, de: str, ate: str, limite: int = 200) -> dict:
    """As entradas do período, com o total.

    O agrupamento por Hoje / Ontem / Essa semana / Esse mês é feito na TELA, a
    partir da data crua — o dbt entrega `DATA_ENTRADA` sem bucket de propósito,
    porque "hoje" depende de quando se consulta, não de quando o build rodou.
    """
    cond, binds = [], {"de": _data(de), "ate": _data(ate)}
    if filtros.get("departamento"):
        cond.append("e.departamento = :departamento")
        binds["departamento"] = filtros["departamento"]
    if filtros.get("secao"):
        cond.append("e.secao = :secao")
        binds["secao"] = filtros["secao"]
    if filtros.get("status"):
        cond.append("e.status = :status")
        binds["status"] = filtros["status"]
    if filtros.get("busca"):
        cond.append("(to_char(e.codigo) like :busca or upper(e.produto) like upper(:busca))")
        binds["busca"] = f"%{filtros['busca'].strip()}%"
    onde = (" and " + " and ".join(cond)) if cond else ""

    total = database.consultar_um(
        f"""select nvl(sum(e.valor), 0) as valor, count(*) as linhas,
                   count(distinct e.codigo) as produtos
              from compras_entrada e
             where e.data_entrada between :de and :ate {onde}""",
        binds,
    )
    linhas = database.consultar(
        f"""
        select * from (
            select e.codigo, e.produto, e.departamento, e.secao, e.status,
                   e.tipo_entrada, e.data_entrada, e.quantidade,
                   e.preco_unitario, e.valor
              from compras_entrada e
             where e.data_entrada between :de and :ate {onde}
             order by e.data_entrada desc, e.valor desc
        ) where rownum <= :limite
        """,
        {**binds, "limite": limite},
    )
    return {
        "valorTotal": float(total["valor"] or 0),
        "linhas": int(total["linhas"] or 0),
        "produtos": int(total["produtos"] or 0),
        "itens": [
            {
                "codigo": int(l["codigo"]),
                "nome": l["produto"],
                "departamento": l["departamento"],
                "secao": l["secao"],
                "status": l["status"],
                "tipo": l["tipo_entrada"],
                "data": l["data_entrada"].strftime("%Y-%m-%d") if l["data_entrada"] else None,
                "quantidade": float(l["quantidade"] or 0),
                "precoUnitario": float(l["preco_unitario"] or 0),
                "valor": float(l["valor"] or 0),
            }
            for l in linhas
        ],
    }
