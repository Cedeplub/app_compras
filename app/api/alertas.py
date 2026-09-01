"""Registro único dos tipos de alerta: rótulo, peso e severidade.

Por que existe um registro em vez de espalhar isso pelo código: o peso é usado
em DOIS lugares que precisam concordar — o SQL que ordena a lista por prioridade
(e portanto decide o que cai na primeira página) e a tela, que precisa explicar
ao comprador por que um produto está no topo. Se os dois divergirem, a lista fica
ordenada por um critério e legendada por outro, e ninguém percebe.

⚠ PENDENTE DE DECISÃO DO DIRETOR DE COMPRAS.
Os PESOS e os RÓTULOS abaixo são uma proposta minha, não um dado do modelo. O
protótipo tem 6 tipos inventados (`ruptura`, `sem_giro`, `baixo_giro`,
`estoque_alto`, `margem_baixa`, `margem_alta`) com pesos 5/4/3/2/2/1; o modelo
real tem 14 tipos, e só RUPTURA existe nos dois. Traduzi por proximidade de
sentido e marquei cada escolha. Enquanto ele não confirmar, a ordenação da tela
de Alertas é um palpite defensável — não uma regra acordada.
"""
from __future__ import annotations

# ─────────────────────────────────────────────────────────────────────────────
# severidade → é o que a tela usa para escolher a cor. Quatro níveis, não uma
# cor por tipo: 14 cores distintas viram enfeite, e o comprador precisa saber
# "isto exige ação hoje" x "isto é contexto", não decorar catorze tons.
#
#   critico  vermelho  — decisão de compra ou de preço parada por causa disto
#   atencao  âmbar     — pendência que trava o cálculo, resolve-se no cadastro
#   parado   oliva     — produto sem giro; é limpeza, não compra
#   info     navy      — muda a leitura do número, não exige ação
# ─────────────────────────────────────────────────────────────────────────────

TIPOS: dict[str, dict] = {
    # tipo                     rótulo na tela         peso  severidade
    "RUPTURA":                {"rotulo": "Ruptura",            "peso": 5, "severidade": "critico"},
    "MARGEM_INSTAVEL":        {"rotulo": "Margem",             "peso": 4, "severidade": "critico"},
    "MARGEM_INSTAVEL_VAREJO": {"rotulo": "Margem varejo",      "peso": 4, "severidade": "critico"},
    # CUSTO = "custo acima da nota". É erro de dado, mas distorce preço de venda
    # — por isso entra como crítico, e não como pendência de cadastro.
    "CUSTO":                  {"rotulo": "Custo",              "peso": 4, "severidade": "critico"},
    "PARADO":                 {"rotulo": "Parado",             "peso": 3, "severidade": "parado"},
    "FORA_DE_LINHA":          {"rotulo": "Fora de linha",      "peso": 3, "severidade": "parado"},
    "INATIVO":                {"rotulo": "Inativo",            "peso": 3, "severidade": "parado"},
    "DEVOLUCAO":              {"rotulo": "Devolução",          "peso": 2, "severidade": "atencao"},
    # MVA e TRIB impedem calcular preço sugerido: sem eles a coluna sai vazia.
    "MVA":                    {"rotulo": "MVA",                "peso": 2, "severidade": "atencao"},
    "TRIB":                   {"rotulo": "Tributação",         "peso": 2, "severidade": "atencao"},
    "SUCESSAO":               {"rotulo": "Sucessão",           "peso": 2, "severidade": "atencao"},
    "FABRICA":                {"rotulo": "Estoque fábrica",    "peso": 1, "severidade": "info"},
    "IMPORTADO":              {"rotulo": "Importado",          "peso": 1, "severidade": "info"},
    "LITRAGEM":               {"rotulo": "Litragem",           "peso": 1, "severidade": "info"},
}

# Curva ABC entra no mesmo score: entre dois produtos com os mesmos alertas,
# o classe A decide primeiro. Pesos idênticos aos do protótipo (§5).
PESO_CLASSE = {"A": 3, "B/C": 2, "S/VEND": 1}


def sql_score_prioridade(alias_produto: str = "p") -> str:
    """Expressão SQL do score de prioridade, para o `order by`.

    Gerada a partir do MESMO dicionário que a tela usa — é isso que garante que
    a ordem e a legenda não possam divergir. Fica no banco, e não em Python
    depois de buscar, porque o score decide QUAL página cada produto ocupa:
    ordenar os 50 já trazidos deixaria o produto mais urgente na página 4.
    """
    ramos = " ".join(
        f"when '{tipo}' then {cfg['peso']}" for tipo, cfg in TIPOS.items()
    )
    ramos_classe = " ".join(
        f"when '{classe}' then {peso}" for classe, peso in PESO_CLASSE.items()
    )
    return f"""(
        nvl((select sum(case a.tipo_alerta {ramos} else 0 end)
               from compras_alerta a
              where a.codigo = {alias_produto}.codigo), 0)
        + (case {alias_produto}.classe {ramos_classe} else 0 end)
    )"""


def metadados() -> list[dict]:
    """O que a tela precisa para desenhar cada etiqueta, em ordem de peso."""
    return [
        {"tipo": tipo, "rotulo": cfg["rotulo"],
         "peso": cfg["peso"], "severidade": cfg["severidade"]}
        for tipo, cfg in sorted(
            TIPOS.items(), key=lambda kv: (-kv[1]["peso"], kv[0])
        )
    ]
