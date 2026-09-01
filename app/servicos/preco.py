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
                "margem_alvo": margem_alvo,
                "margem_alvo_varejo": margem_alvo_varejo,
                "alt_pv_at_av": alt_pv_at_av,
                "alt_pv_var_av": alt_pv_var_av,
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
                "novo": {
                    "margem_alvo": margem_alvo,
                    "margem_alvo_varejo": margem_alvo_varejo,
                    "alt_pv_at_av": alt_pv_at_av,
                    "alt_pv_var_av": alt_pv_var_av,
                },
                "usuario": usuario_login,
            },
            ip,
        )
