"""Tela 1 — decisao de compra. Le COMPRAS_PEDIDO/COMPRAS_ALERTA, grava
APP_DECISAO_PEDIDO.

⚠ Uma decisao gravada aqui so entra em COMPRAS_PEDIDO no PROXIMO `dbt run`
(CONTEXTO.md §2 / §6 regra 6). Por isso `gravar_pedido` devolve a linha lida
DE VOLTA de APP_DECISAO_PEDIDO ao vivo, combinada com o resto da linha (que
so muda no proximo build) - senao a tela mostraria o valor velho de PEDIDO
logo apos gravar, como se a gravacao tivesse falhado.
"""
from __future__ import annotations

import datetime as dt

from app.core import auditoria, database

# ─────────────────────────────────────────────────────────────────────────────
# A LISTA LE O PEDIDO DE APP_DECISAO_PEDIDO AO VIVO, NAO DE COMPRAS_PEDIDO.
#
# COMPRAS_PEDIDO.PEDIDO (e tudo que descende dele: PEDIDO_UNIDADES, VALOR_PEDIDO)
# so' e' recalculado no proximo `dbt run` - o dbt LE as APP_* e nunca escreve
# nelas (CONTEXTO.md §2). Ler essas tres colunas da tabela materializada fazia a
# tela mentir de duas formas, as duas encontradas em uso real:
#   1. VALOR_PEDIDO ficava parado no valor do ultimo build (zero, enquanto
#      APP_DECISAO_PEDIDO estava vazia) mesmo depois de gravar - o comprador
#      digitava a quantidade e nao conseguia conferir quanto ia gastar, que e'
#      exatamente para o que a coluna existe.
#   2. Pior: ao RECARREGAR a pagina, o PEDIDO gravado sumia da tela e voltava a
#      zero, porque a listagem relia da tabela velha. A decisao estava salva no
#      banco, mas o comprador via como se o sistema a tivesse perdido.
#
# Por isso o LEFT JOIN abaixo, e por isso as tres colunas sao RECALCULADAS aqui
# com a mesma formula do model int_produto_pedido - que e' a fonte da verdade:
#     pedido_unidades = pedido x fator_exibicao
#     valor_pedido    = pedido_unidades x custo_tot_oficial
# Se a formula mudar la', tem de mudar aqui. As demais colunas (estoque, media,
# meses, sugestao) continuam vindo de COMPRAS_PEDIDO: elas nao dependem da
# decisao humana e so' mudam no build mesmo.
#
# ⚠ O FATOR e' o CONGELADO da decisao quando ela existe, e o corrente so' quando
# nao ha decisao (MELHORIA A5, decisao do Diretor de Compras). O `case ... is not
# null` reproduz int_produto_pedido de proposito: um `nvl(d.fator_exibicao, ...)`
# cairia no fator corrente se o congelado fosse nulo, desfazendo a decisao em
# silencio.
# ─────────────────────────────────────────────────────────────────────────────
_FATOR = ("case when d.id_produto is not null then d.fator_exibicao"
          " else p.fator_exibicao end")

COLUNAS_LISTA = f"""
    p.codigo, p.descricao, p.fornecedor, p.comprador, p.classe, p.alerta,
    p.est_disp, p.media_janela, p.meses_est, p.sug_cobertura, p.embal_compra,
    nvl(d.pedido, 0)                                  as pedido,
    {_FATOR}                                          as fator_exibicao,
    nvl(d.pedido, 0) * {_FATOR}                       as pedido_unidades,
    nvl(d.pedido, 0) * {_FATOR} * p.custo_tot_oficial as valor_pedido
"""

# O join fica num lugar so' para a listagem e a linha unica nao divergirem.
_DE_COMPRAS_PEDIDO = """
      from compras_pedido p
      left join app_decisao_pedido d
        on d.id_produto = p.codigo
"""


def listar_pedidos(filtros: dict, pagina: int, itens_por_pagina: int) -> tuple[list[dict], int]:
    condicoes = []
    binds: dict = {}

    if filtros.get("tipo_alerta"):
        # Nunca `like` na string ALERTA — usa COMPRAS_ALERTA.TIPO_ALERTA
        # (CONTEXTO §6 / instrucao da Etapa 6a).
        condicoes.append(
            "exists (select 1 from compras_alerta a"
            "         where a.codigo = p.codigo and a.tipo_alerta = :tipo_alerta)"
        )
        binds["tipo_alerta"] = filtros["tipo_alerta"]

    if filtros.get("fornecedor"):
        condicoes.append("p.fornecedor = :fornecedor")
        binds["fornecedor"] = filtros["fornecedor"]

    if filtros.get("comprador"):
        condicoes.append("p.comprador = :comprador")
        binds["comprador"] = filtros["comprador"]

    if filtros.get("classe"):
        condicoes.append("p.classe = :classe")
        binds["classe"] = filtros["classe"]

    if filtros.get("busca"):
        condicoes.append(
            "(to_char(p.codigo) like :busca or upper(p.descricao) like upper(:busca))"
        )
        binds["busca"] = f"%{filtros['busca'].strip()}%"

    onde = f"where {' and '.join(condicoes)}" if condicoes else ""

    total_linha = database.consultar_um(
        f"select count(distinct p.codigo) as n from compras_pedido p {onde}", binds
    )
    total = int(total_linha["n"]) if total_linha else 0

    pagina = max(1, pagina)
    offset = (pagina - 1) * itens_por_pagina
    linhas = database.consultar(
        f"""
        select {COLUNAS_LISTA}
          {_DE_COMPRAS_PEDIDO}
          {onde}
         order by p.codigo
        offset :offset rows fetch next :limite rows only
        """,
        {**binds, "offset": offset, "limite": itens_por_pagina},
    )
    _anexar_alertas(linhas)
    return linhas, total


def _anexar_alertas(linhas: list[dict]) -> None:
    """Anexa a cada linha a LISTA de alertas ativos, vinda de COMPRAS_ALERTA.

    Por que existe: a coluna ALERTA de COMPRAS_PEDIDO e' uma string concatenada
    com "; " - util para quem le a planilha, pessima para a tela. Renderizada
    inteira numa celula de tabela, ela vira um paragrafo de 10 linhas e estica a
    altura da linha inteira (foi o que aconteceu na 1a versao da tela).

    A saida errada seria dar split("; ") no template: o separador e' detalhe da
    montagem da string e um alerta que contenha ";" no texto quebraria a divisao
    em silencio. COMPRAS_ALERTA ja' tem o dado DESPIVOTADO, uma linha por tipo,
    que e' exatamente o que a tela precisa - e e' o caminho que o proprio
    fat_alerta foi criado para servir.

    Uma consulta so' para a pagina inteira (nao uma por linha), com a ordem de
    exibicao da planilha preservada por ORDEM_EXIBICAO.
    """
    if not linhas:
        return
    codigos = [int(l["codigo"]) for l in linhas]
    # bind nomeado por posicao: :c0, :c1... - lista em IN nao aceita bind unico
    marcas = ", ".join(f":c{i}" for i in range(len(codigos)))
    binds = {f"c{i}": c for i, c in enumerate(codigos)}
    achados = database.consultar(
        f"""
        select codigo, tipo_alerta, texto_alerta
          from compras_alerta
         where codigo in ({marcas})
         order by codigo, ordem_exibicao
        """,
        binds,
    )
    por_codigo: dict[int, list[dict]] = {}
    for a in achados:
        por_codigo.setdefault(int(a["codigo"]), []).append(
            {"tipo": a["tipo_alerta"], "texto": a["texto_alerta"]}
        )
    for l in linhas:
        l["alertas"] = por_codigo.get(int(l["codigo"]), [])


def obter_linha(codigo: int) -> dict | None:
    return database.consultar_um(
        f"select {COLUNAS_LISTA} {_DE_COMPRAS_PEDIDO} where p.codigo = :codigo",
        {"codigo": codigo},
    )


def gravar_pedido(codigo: int, pedido: float, usuario_login: str, usuario_id: int,
                  ip: str | None = None) -> dict:
    """Grava APP_DECISAO_PEDIDO com o FATOR_EXIBICAO vigente NESTE instante,
    congelado junto (MELHORIA A5 / regra 3 da Etapa 6a): a quantidade real da
    decisao (PEDIDO x FATOR_EXIBICAO) sempre se le desta mesma linha, nunca
    recalculada com o fator atual do cadastro.
    """
    base = database.consultar_um(
        "select fator_exibicao from compras_pedido where codigo = :codigo", {"codigo": codigo}
    )
    if base is None:
        raise ValueError(f"produto {codigo} não encontrado em COMPRAS_PEDIDO")
    fator_exibicao = base["fator_exibicao"]

    agora = dt.datetime.now()
    with database.transacao() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            merge into app_decisao_pedido t
            using (select :codigo as id_produto from dual) s
               on (t.id_produto = s.id_produto)
             when matched then update set
                  pedido = :pedido, fator_exibicao = :fator_exibicao,
                  atualizado_em = :agora, atualizado_por = :usuario
             when not matched then insert
                  (id_produto, pedido, fator_exibicao, atualizado_em, atualizado_por)
                  values (:codigo, :pedido, :fator_exibicao, :agora, :usuario)
            """,
            {
                "codigo": codigo,
                "pedido": pedido,
                "fator_exibicao": fator_exibicao,
                "agora": agora,
                "usuario": usuario_login,
            },
        )
        cur.close()
        # ID_USUARIO preenchido, nao None - ver o mesmo comentario em preco.py.
        auditoria.registrar(
            conn, usuario_id, "GRAVAR_DECISAO_PEDIDO", "APP_DECISAO_PEDIDO", str(codigo),
            {"pedido": pedido, "fator_exibicao": fator_exibicao, "usuario": usuario_login},
            ip,
        )

    # Le a linha de volta. `obter_linha` ja junta APP_DECISAO_PEDIDO ao vivo e
    # recalcula pedido/pedido_unidades/valor_pedido (ver o bloco no topo deste
    # arquivo), entao a linha devolvida aqui e' EXATAMENTE a mesma que a
    # listagem mostraria num F5 - nao ha' um segundo caminho de calculo so' para
    # o fragmento pos-gravacao, que poderia divergir da lista sem ninguem notar.
    linha = obter_linha(codigo)
    if linha:
        _anexar_alertas([linha])   # o fragmento pos-gravar precisa das mesmas etiquetas
    return linha


def opcoes_filtro() -> dict:
    """Listas distintas para preencher os filtros da tela - vem de
    COMPRAS_PEDIDO/COMPRAS_ALERTA, nunca de CEDEP."""
    return {
        "fornecedores": [r["fornecedor"] for r in database.consultar(
            "select distinct fornecedor from compras_pedido where fornecedor is not null order by 1"
        )],
        "compradores": [r["comprador"] for r in database.consultar(
            "select distinct comprador from compras_pedido where comprador is not null order by 1"
        )],
        "classes": [r["classe"] for r in database.consultar(
            "select distinct classe from compras_pedido where classe is not null order by 1"
        )],
        "tipos_alerta": [r["tipo_alerta"] for r in database.consultar(
            "select distinct tipo_alerta from compras_alerta where tipo_alerta is not null order by 1"
        )],
    }
