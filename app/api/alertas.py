"""Registro único dos tipos de alerta: rótulo, peso e severidade.

Por que existe um registro em vez de espalhar isso pelo código: o peso é usado
em DOIS lugares que precisam concordar — o SQL que ordena a lista por prioridade
(e portanto decide o que cai na primeira página) e a tela, que precisa explicar
ao comprador por que um produto está no topo. Se os dois divergirem, a lista fica
ordenada por um critério e legendada por outro, e ninguém percebe.

Os pesos e rótulos abaixo são os que o **Diretor de Compras decidiu** em
02/09/2026 (`v2/DECISOES_DIRETOR.md`, respostas aos itens 1 e 4) — não são mais
proposta minha.

⚠ `TIPOS` cobre só a categoria DECISAO. Os alertas de CADASTRO (IMPORTADO,
LITRAGEM, TRIB, MVA, SUCESSAO, FABRICA) saíram da tela de Alertas por decisão do
item 2 e vão para a tela de Pendência de Cadastro. Quem separa os dois é a
coluna `CATEGORIA` de COMPRAS_ALERTA, não esta tabela.
"""
from __future__ import annotations

# ─────────────────────────────────────────────────────────────────────────────
# severidade → é o que a tela usa para escolher a cor. Cinco níveis, não uma cor
# por tipo: catorze cores viram confete, e o comprador precisa distinguir "isto
# trava minha decisão" de "isto é contexto", não decorar a paleta.
#
#   critico      vermelho  — decisão de compra ou de preço parada por isto
#   parado       oliva     — produto sem giro; é limpeza, não compra
#   atencao      âmbar     — pendência que atrapalha, resolve-se no cadastro
#   oportunidade verde     — não é problema: é dinheiro na mesa a recolher
#   info         navy      — muda a leitura do número, não exige ação
# ─────────────────────────────────────────────────────────────────────────────

TIPOS: dict[str, dict] = {
    # tipo                     rótulo na tela      peso  severidade
    "RUPTURA":               {"rotulo": "Ruptura",        "peso": 5, "severidade": "critico"},
    "SEM_GIRO":              {"rotulo": "Sem giro",       "peso": 4, "severidade": "parado"},
    "MARGEM_BAIXA":          {"rotulo": "Margem baixa",   "peso": 4, "severidade": "critico"},
    "MARGEM_BAIXA_VAREJO":   {"rotulo": "Margem varejo",  "peso": 4, "severidade": "critico"},
    # "custo acima da nota": é erro de dado, mas contamina toda a precificação
    # do produto — por isso entra como crítico, e não como pendência.
    "CUSTO":                 {"rotulo": "Custo",          "peso": 4, "severidade": "critico"},
    "BAIXO_GIRO":            {"rotulo": "Baixo giro",     "peso": 3, "severidade": "parado"},
    "OPORTUNIDADE_DE_GIRO":  {"rotulo": "Oportunidade",   "peso": 3, "severidade": "oportunidade"},
    "DEVOLUCAO":             {"rotulo": "Devolução",      "peso": 2, "severidade": "atencao"},
    "MARGEM_ALTA":           {"rotulo": "Margem alta",    "peso": 1, "severidade": "info"},
    # Badge visual, não alerta pontuado (decisão do item 1): o comprador precisa
    # ver que o produto está fora de linha, mas isso não deve competir na
    # priorização. `PONTUA='N'` em COMPRAS_ALERTA é quem manda; o peso 0 aqui
    # só evita que alguém precise ler duas fontes para descobrir o mesmo.
    "FORA_DE_LINHA":         {"rotulo": "Fora de linha",  "peso": 0, "severidade": "parado"},
}

# Curva ABC entra no desempate. Pesos idênticos aos do protótipo (§5).
PESO_CLASSE = {"A": 3, "B/C": 2, "S/VEND": 1}


def _ramos_peso(alias: str = "a") -> str:
    return " ".join(f"when '{t}' then {c['peso']}" for t, c in TIPOS.items())


def sql_ordem_prioridade(alias_produto: str = "p") -> str:
    """`order by` da tela de Alertas.

    ⚠ NÃO é a soma pura do protótipo. O Diretor mudou a regra no item 3, e o
    motivo foi medido: com a soma, dos 6 produtos classe A em ruptura, 5 caíam
    da página 2 à 7 — porque acumular cinco alertas fracos batia um RUPTURA
    sozinho. Quem olhasse a primeira página perdia quase todos.

    Agora: **severidade máxima primeiro**, soma como desempate, curva como
    terceiro critério. Um RUPTURA (5) vence qualquer acúmulo de peso ≤ 4,
    independentemente de quantos sejam.

    Só entram os alertas que PONTUAM e são de DECISAO: FORA_DE_LINHA é etiqueta,
    e as pendências de cadastro não são decisão de compra.
    """
    ramos = _ramos_peso()
    ramos_classe = " ".join(f"when '{c}' then {p}" for c, p in PESO_CLASSE.items())
    pontuaveis = (
        f"from compras_alerta a"
        f" where a.codigo = {alias_produto}.codigo"
        f"   and a.categoria = 'DECISAO' and a.pontua = 'S'"
    )
    return (
        f"nvl((select max(case a.tipo_alerta {ramos} else 0 end) {pontuaveis}), 0) desc,"
        f" nvl((select sum(case a.tipo_alerta {ramos} else 0 end) {pontuaveis}), 0) desc,"
        f" case {alias_produto}.classe {ramos_classe} else 0 end desc,"
        f" {alias_produto}.codigo"
    )


def metadados() -> list[dict]:
    """O que a tela precisa para desenhar cada etiqueta, em ordem de peso."""
    return [
        {"tipo": tipo, "rotulo": cfg["rotulo"],
         "peso": cfg["peso"], "severidade": cfg["severidade"]}
        for tipo, cfg in sorted(
            TIPOS.items(), key=lambda kv: (-kv[1]["peso"], kv[0])
        )
    ]
