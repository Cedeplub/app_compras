"""Tela 2 — precificacao. O UNICO ponto do modelo em que uma pessoa decide um
numero em vez de uma formula calcular (PDF §9.3/§14, CONTEXTO §6 regra 10).

- ALT_PV_AT_AV / ALT_PV_VAR_AV NUNCA sao preenchidos automaticamente com uma
  sugestao calculada: campo vazio (NULL) e "ninguem decidiu ainda", um estado
  valido - nao e dado faltando.
- Todo UPDATE em APP_DECISAO_PRECO grava a linha anterior em
  APP_DECISAO_PRECO_HIST antes de sobrescrever, com ATUALIZADO_EM/POR
  ORIGINAIS copiados (nao os novos - ver comentario da coluna DECIDIDO_EM em
  sql/02_tabelas_app.sql). As duas gravacoes + a auditoria vao na MESMA
  transacao: ou tudo, ou nada.
- Grava preco exige EH_DIRETORIA (a API recusa; a tela so esconde o botao).

⚠ A decisao gravada aqui so entra em COMPRAS_PEDIDO no PROXIMO `dbt run`. Por
isso `obter_cenarios` sempre le os campos DECIDIDOS (margem_alvo,
margem_alvo_varejo, alt_pv_at_av, alt_pv_var_av) AO VIVO de APP_DECISAO_PRECO,
nao da copia calculada em COMPRAS_PEDIDO - senao a tela mostraria o valor
velho logo apos gravar.
"""
from __future__ import annotations

import datetime as dt

from app.core import auditoria, database

CAMPOS_DECISAO = ("margem_alvo", "margem_alvo_varejo", "alt_pv_at_av", "alt_pv_var_av")

# Campos calculados / sugestoes do modelo - somente leitura, vem de
# COMPRAS_PEDIDO (dbt), nunca gravados pela aplicacao.
CAMPOS_CENARIO_ATACADO = (
    "pv_atacado, margem_st_s_valor, margem_oficial, margem_sem_red,"
    " pv_sug_st_s_valor_av, pv_sug_st_s_valor_ap,"
    " pv_sug_oficial_av, pv_sug_oficial_ap,"
    " pv_sug_sem_red_av, pv_sug_sem_red_ap, alt_pv_at_ap"
)
CAMPOS_CENARIO_VAREJO = (
    "pv_varejo, margem_st_s_valor_varejo, margem_sem_red_varejo,"
    " pv_sug_st_s_valor_var_av, pv_sug_st_s_valor_var_ap,"
    " pv_sug_sem_red_var_av, pv_sug_sem_red_var_ap, alt_pv_var_ap"
)


def obter_cenarios(codigo: int) -> dict | None:
    base = database.consultar_um(
        f"select codigo, descricao, fornecedor, {CAMPOS_CENARIO_ATACADO}, {CAMPOS_CENARIO_VAREJO}"
        " from compras_pedido where codigo = :codigo",
        {"codigo": codigo},
    )
    if base is None:
        return None

    decisao = database.consultar_um(
        "select margem_alvo, margem_alvo_varejo, alt_pv_at_av, alt_pv_var_av,"
        " atualizado_em, atualizado_por from app_decisao_preco where id_produto = :codigo",
        {"codigo": codigo},
    )
    for campo in CAMPOS_DECISAO:
        base[campo] = decisao[campo] if decisao else None
    base["decisao_atualizado_em"] = decisao["atualizado_em"] if decisao else None
    base["decisao_atualizado_por"] = decisao["atualizado_por"] if decisao else None
    return base


def buscar(termo: str, limite: int = 30) -> list[dict]:
    termo = (termo or "").strip()
    if not termo:
        return []
    return database.consultar(
        "select codigo, descricao, fornecedor from compras_pedido"
        " where to_char(codigo) like :t or upper(descricao) like upper(:t)"
        " order by codigo fetch first :limite rows only",
        {"t": f"%{termo}%", "limite": limite},
    )


def _gravar_decisao_preco_conn(
    conn,
    codigo: int,
    margem_alvo: float | None,
    margem_alvo_varejo: float | None,
    alt_pv_at_av: float | None,
    alt_pv_var_av: float | None,
    usuario_login: str,
    usuario_id: int,
    ip: str | None,
    agora: dt.datetime,
) -> None:
    """O que `gravar_decisao_preco` faz, mas sobre uma conexão JÁ aberta, sem
    commit próprio — para que a gravação em lote (`gravar_decisao_preco_lote`)
    rode N vezes na MESMA transação, e o unitário continue funcionando
    exatamente como hoje (chama isto dentro do seu próprio `transacao()`).
    """
    cur = conn.cursor()
    cur.execute(
        "select margem_alvo, margem_alvo_varejo, alt_pv_at_av, alt_pv_var_av,"
        " atualizado_em, atualizado_por from app_decisao_preco"
        " where id_produto = :codigo for update",
        {"codigo": codigo},
    )
    anterior = cur.fetchone()
    colunas = [d[0].lower() for d in cur.description] if anterior else None

    if anterior is not None:
        antiga = dict(zip(colunas, anterior))
        # Regra 2: arquiva o valor que esta SAINDO, com ATUALIZADO_EM/POR
        # ORIGINAIS (nao os novos desta gravacao).
        cur.execute(
            """
            insert into app_decisao_preco_hist
                (id_produto, margem_alvo, margem_alvo_varejo, alt_pv_at_av, alt_pv_var_av,
                 atualizado_em, atualizado_por)
            values
                (:codigo, :margem_alvo, :margem_alvo_varejo, :alt_pv_at_av, :alt_pv_var_av,
                 :atualizado_em, :atualizado_por)
            """,
            {
                "codigo": codigo,
                "margem_alvo": antiga["margem_alvo"],
                "margem_alvo_varejo": antiga["margem_alvo_varejo"],
                "alt_pv_at_av": antiga["alt_pv_at_av"],
                "alt_pv_var_av": antiga["alt_pv_var_av"],
                "atualizado_em": antiga["atualizado_em"],
                "atualizado_por": antiga["atualizado_por"],
            },
        )
    else:
        antiga = None

    # A tela (unitário e lote) só manda o que foi de fato editado; os demais
    # campos chegam aqui como None significando "não mexi nisto", não "apague
    # isto" — hoje não existe funcionalidade de LIMPAR uma decisão já gravada,
    # então None == "mantenha o valor atual" é a leitura segura. Por isso o
    # merge é sobre estes valores RESOLVIDOS (novo se enviado, senão o que já
    # estava em APP_DECISAO_PRECO), nunca sobre os parâmetros crus — do
    # contrário gravar só o atacado zeraria margem/varejo de quem já tinha
    # decisão tomada.
    # ⚠ Se um dia existir "limpar decisão gravada" (voltar um campo para
    # NULL/"ninguém decidiu"), ela precisa de um sinal explícito no payload
    # (ex. um enum ou um campo "_limpar": [...]), NÃO de reinterpretar campo
    # ausente como apagar — isso quebraria esta gravação parcial de novo.
    novo_margem_alvo = margem_alvo if margem_alvo is not None else (antiga["margem_alvo"] if antiga else None)
    novo_margem_alvo_varejo = (
        margem_alvo_varejo if margem_alvo_varejo is not None
        else (antiga["margem_alvo_varejo"] if antiga else None)
    )
    novo_alt_pv_at_av = (
        alt_pv_at_av if alt_pv_at_av is not None
        else (antiga["alt_pv_at_av"] if antiga else None)
    )
    novo_alt_pv_var_av = (
        alt_pv_var_av if alt_pv_var_av is not None
        else (antiga["alt_pv_var_av"] if antiga else None)
    )

    cur.execute(
        """
        merge into app_decisao_preco t
        using (select :codigo as id_produto from dual) s
           on (t.id_produto = s.id_produto)
         when matched then update set
              margem_alvo = :margem_alvo, margem_alvo_varejo = :margem_alvo_varejo,
              alt_pv_at_av = :alt_pv_at_av, alt_pv_var_av = :alt_pv_var_av,
              atualizado_em = :agora, atualizado_por = :usuario
         when not matched then insert
              (id_produto, margem_alvo, margem_alvo_varejo, alt_pv_at_av, alt_pv_var_av,
               atualizado_em, atualizado_por)
              values (:codigo, :margem_alvo, :margem_alvo_varejo, :alt_pv_at_av, :alt_pv_var_av,
                      :agora, :usuario)
        """,
        {
            "codigo": codigo,
            "margem_alvo": novo_margem_alvo,
            "margem_alvo_varejo": novo_margem_alvo_varejo,
            "alt_pv_at_av": novo_alt_pv_at_av,
            "alt_pv_var_av": novo_alt_pv_var_av,
            "agora": agora,
            "usuario": usuario_login,
        },
    )
    cur.close()

    # ID_USUARIO preenchido, nao None: o indice IX_APP_AUDITORIA_USUARIO e
    # (ID_USUARIO, CRIADO_EM), e e ele que responde "o que fulano mudou no
    # mes passado". Com NULL aqui, a gravacao de preco - justamente a acao
    # que mais precisa de rastro - ficaria invisivel para essa consulta, e
    # o autor so existiria dentro do CLOB de detalhe.
    auditoria.registrar(
        conn, usuario_id, "GRAVAR_DECISAO_PRECO", "APP_DECISAO_PRECO", str(codigo),
        {
            "anterior": antiga,
            # Estado RESULTANTE (após aplicar "ausente = mantém"), não o
            # payload cru — senão a auditoria mostraria alt_pv_var_av como
            # None mesmo quando o valor antigo foi preservado no banco.
            "novo": {
                "margem_alvo": novo_margem_alvo,
                "margem_alvo_varejo": novo_margem_alvo_varejo,
                "alt_pv_at_av": novo_alt_pv_at_av,
                "alt_pv_var_av": novo_alt_pv_var_av,
            },
            "usuario": usuario_login,
        },
        ip,
    )


def gravar_decisao_preco(
    codigo: int,
    margem_alvo: float | None,
    margem_alvo_varejo: float | None,
    alt_pv_at_av: float | None,
    alt_pv_var_av: float | None,
    usuario_login: str,
    usuario_id: int,
    ip: str | None = None,
) -> None:
    agora = dt.datetime.now()
    with database.transacao() as conn:
        _gravar_decisao_preco_conn(
            conn, codigo, margem_alvo, margem_alvo_varejo, alt_pv_at_av,
            alt_pv_var_av, usuario_login, usuario_id, ip, agora,
        )


# Teto do lote (item 3 do pedido do Diretor de 08/09/2026). A tela lista 4.558
# produtos, mas uma transação com milhares de UPDATE + INSERT em
# APP_DECISAO_PRECO_HIST + APP_AUDITORIA prende a conexão por tempo longo
# demais para o pool de 4 (config.ORA_POOL_MAX). 200 é o mesmo teto de página
# de listagem (MAX_POR_PAGINA em app/api/rotas.py) — o front manda só os
# campos alterados, então uma "gravação total" real de 4.558 linhas nunca
# deveria acontecer de uma vez; se acontecer, é para o usuário dividir em
# lotes menores, não para o servidor travar tentando.
LIMITE_LOTE_PRECO = 200


def gravar_decisao_preco_lote(
    itens: list[dict],
    usuario_login: str,
    usuario_id: int,
    ip: str | None = None,
) -> list[int]:
    """`itens`: [{"codigo", "margem_alvo"?, "margem_alvo_varejo"?,
    "alt_pv_at_av"?, "alt_pv_var_av"?}], já validados um a um pelo mesmo
    `DecisaoPreco` do endpoint unitário (rotas.py) antes de chegar aqui.

    Dedupe por código (última ocorrência vence, mesmo raciocínio de
    `pedido.salvar_carrinho`) e grava tudo numa ÚNICA transação: uma falha no
    meio do lote não pode deixar metade dos preços gravados sem que o Diretor
    saiba quais. Devolve os códigos efetivamente gravados, na ordem.
    """
    normalizados: dict[int, dict] = {}
    for it in itens:
        normalizados[int(it["codigo"])] = it  # última ocorrência vence

    codigos = list(normalizados.keys())
    if not codigos:
        return []
    if len(codigos) > LIMITE_LOTE_PRECO:
        raise ValueError(
            f"Lote com {len(codigos)} itens excede o limite de {LIMITE_LOTE_PRECO}."
            " Grave em lotes menores."
        )

    # Existência checada ANTES de abrir a transação: um código que não existe
    # em COMPRAS_PEDIDO tem de recusar o LOTE inteiro, nomeando o SKU — não
    # gravar os outros 29 e falhar em silêncio no 30º.
    marcas = ", ".join(f":c{i}" for i in range(len(codigos)))
    existentes = {
        int(r["codigo"]) for r in database.consultar(
            f"select codigo from compras_pedido where codigo in ({marcas})",
            {f"c{i}": c for i, c in enumerate(codigos)},
        )
    }
    faltando = [c for c in codigos if c not in existentes]
    if faltando:
        raise ValueError(
            "Produto(s) não encontrado(s) em COMPRAS_PEDIDO: "
            + ", ".join(str(c) for c in faltando)
        )

    agora = dt.datetime.now()
    with database.transacao() as conn:
        for codigo in codigos:
            it = normalizados[codigo]
            _gravar_decisao_preco_conn(
                conn, codigo,
                it.get("margem_alvo"), it.get("margem_alvo_varejo"),
                it.get("alt_pv_at_av"), it.get("alt_pv_var_av"),
                usuario_login, usuario_id, ip, agora,
            )
    return codigos
