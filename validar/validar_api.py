"""Exercita TODAS as combinações de filtro da API. Nasceu de um defeito real.

Em 02/09/2026 a tela deu 500 ao ligar um botão de tipo de alerta: ORA-01036,
bind declarado e não usado. Eu tinha testado a listagem só no caminho padrão —
sem nenhum tipo ligado — e esse caminho passava. O defeito morava exatamente no
ramo que eu não exercitei.

A lição não é "testar mais": é que um `where` montado por pedaços tem um número
de caminhos que cresce rápido, e conferir um por um à mão não escala. Este
script percorre o produto cartesiano dos filtros e reporta qualquer status que
não seja 200.

Uso:
    python validar/validar_api.py --url http://192.168.0.50:8020 \\
                                  --login <usuario> --senha <senha>

A senha vem da linha de comando ou de APP_TESTE_SENHA, nunca de literal no
arquivo — este repositório não guarda credencial (ver .gitignore).
"""
from __future__ import annotations

import argparse
import itertools
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

# Os eixos que se combinam no `where`. Um `None` significa "filtro ausente", que
# é um caminho tão real quanto os outros — e no caso do ORA-01036 era justamente
# a presença de um e a ausência de outro que quebrava.
#
# ⚠ Etapa 15, ponto 4: o eixo "estoque" foi acrescentado com 3 valores e TRIPLICA o
# produto cartesiano — de 1.728 combinações (576 combinações x 3 TIPOS_ALERTA) para
# 5.184. Se o tempo de execução ficar impraticável, a regra é REPORTAR o tempo medido
# no relatório, nunca remover o eixo em silêncio (armadilha 15 do prompt da etapa).
EIXOS = {
    "categoria": [None, "DECISAO", "CADASTRO"],
    "status": [None, "Ativo", "Inativo"],
    "soComAlerta": [None, "true"],
    "departamento": [None, "YPF"],
    "classe": [None, "A"],
    "busca": [None, "OLEO"],
    "ordenacao": ["prioridade", "cobertura", "margem", "codigo"],
    "estoque": [None, "com", "sem"],
}
# tipoAlerta é lista: vale testar zero, um e vários — o ramo de vários é o que
# gera `:ta0, :ta1, :ta2` e foi onde o defeito apareceu.
TIPOS_ALERTA = [[], ["RUPTURA"], ["RUPTURA", "MARGEM_BAIXA", "MARGEM_BAIXA_VAREJO"]]


def _abrir(url: str, cookie: str | None = None, dados: bytes | None = None):
    req = urllib.request.Request(url, data=dados,
                                 headers={"Content-Type": "application/json"})
    if cookie:
        req.add_header("Cookie", cookie)
    return urllib.request.urlopen(req, timeout=60)


def entrar(base: str, login: str, senha: str) -> str:
    import json
    corpo = json.dumps({"login": login, "senha": senha}).encode()
    resp = _abrir(f"{base}/api/login", dados=corpo)
    cookie = resp.headers.get("Set-Cookie", "").split(";")[0]
    if not cookie:
        raise SystemExit("login não devolveu cookie de sessão")
    return cookie


def validar_particao_estoque(base: str, cookie: str) -> bool:
    """Etapa 15, ponto 4 (prompt §6.2, §8.5 item 3) — o invariante de PARTIÇÃO.

    Para cada `status` em (ausente, "Ativo", "Inativo"), confere:

        total(estoque=com) + total(estoque=sem) == total(sem o filtro de estoque)

    lendo o campo `total` da resposta de `GET /api/produtos`. Nove requisições ao todo
    (3 status x 3 variações de `estoque`). Os dois ramos do filtro (`app/servicos/produto.py
    _condicoes`, Etapa 15 §6.2) são:

        -- com: nvl(p.est_disp, 0) > 0
        -- sem: nvl(p.est_disp, 0) <= 0

    que por construção cobrem toda a reta real (nulo e negativo caem em "sem") — então a
    soma tem de bater sempre, sem SKU sumindo dos dois lados.

    Contagem de referência medida em 16/09/2026 (recontar no dia — EST_DISP muda a cada
    `dbt run`): com `status=Ativo`, com=3.305 / sem=1.253 / total=4.558; sem filtro de
    status, com=3.386 / sem=5.455 / total=8.841.

    ⚠ COMO RODAR A VARIANTE COM DEFEITO INJETADO (nunca em produção — só para provar que
    este validador de fato enxerga a quebra da partição):

    1. Em `app/servicos/produto.py:_condicoes`, trocar temporariamente

           elif filtros.get("estoque") == "sem":
               condicoes.append("nvl(p.est_disp, 0) <= 0")

       por

           elif filtros.get("estoque") == "sem":
               condicoes.append("nvl(p.est_disp, 0) < 0")

    2. Subir o servidor de teste com essa alteração e chamar esta função de novo
       (`python validar/validar_api.py --url ... --login ... --validar-particao-estoque`).
    3. Ela tem de REPROVAR nos três status: os SKUs com `EST_DISP == 0` (5.455 no universo
       total, medido em 16/09) deixam de contar como "sem", e `com + sem` fica exatamente
       5.455 menor que `total` (na visão sem filtro de status; a fração correspondente nos
       recortes por status). A diferença relatada por esta função tem de bater com esse
       número.
    4. DESFAZER a alteração no arquivo antes de seguir — nunca deixar o defeito em
       `produto.py`.
    """
    import json

    falhas: list[tuple[str, int, int, int]] = []
    print("validando particao com/sem estoque (9 requisicoes: 3 status x [ausente, com, sem])…")
    for status in (None, "Ativo", "Inativo"):
        totais: dict[str | None, int] = {}
        for estoque in (None, "com", "sem"):
            params = [(n, v) for n, v in (("status", status), ("estoque", estoque)) if v is not None]
            params.append(("porPagina", "1"))
            url = f"{base}/api/produtos?{urllib.parse.urlencode(params)}"
            with _abrir(url, cookie) as r:
                corpo = json.loads(r.read())
            totais[estoque] = corpo["total"]

        soma = totais["com"] + totais["sem"]
        rotulo = status or "(ausente)"
        ok = soma == totais[None]
        print(f"  status={rotulo}: com={totais['com']} + sem={totais['sem']} = {soma}  "
              f"total(sem filtro de estoque)={totais[None]}  -> {'OK' if ok else 'FALHOU'}")
        if not ok:
            falhas.append((rotulo, totais["com"], totais["sem"], totais[None]))

    if falhas:
        print(f"\n{len(falhas)} de 3 status com particao QUEBRADA:")
        for rotulo, com, sem, total in falhas:
            print(f"  status={rotulo}: com={com} + sem={sem} = {com + sem} != total={total} "
                  f"(diferenca={total - (com + sem)})")
        return False

    print("\npartição com/sem estoque OK nos 3 status.")
    return True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://192.168.0.50:8020")
    ap.add_argument("--login", required=True)
    ap.add_argument("--senha", default=os.environ.get("APP_TESTE_SENHA"))
    ap.add_argument("--pular-cartesiano", action="store_true",
                     help="pula o produto cartesiano (5.184 chamadas) e roda só a partição com/sem estoque")
    ap.add_argument("--pular-particao-estoque", action="store_true",
                     help="pula o invariante com+sem=total (9 chamadas) — só o produto cartesiano")
    args = ap.parse_args()
    if not args.senha:
        raise SystemExit("informe --senha ou defina APP_TESTE_SENHA")

    cookie = entrar(args.url, args.login, args.senha)

    if not args.pular_particao_estoque:
        if not validar_particao_estoque(args.url, cookie):
            return 1
        print()

    if args.pular_cartesiano:
        return 0

    nomes = list(EIXOS)
    combinacoes = list(itertools.product(*(EIXOS[n] for n in nomes)))
    total = len(combinacoes) * len(TIPOS_ALERTA)
    falhas: list[tuple[str, str]] = []
    print(f"exercitando {total} combinações de filtro…")

    for valores in combinacoes:
        for tipos in TIPOS_ALERTA:
            params = [(n, v) for n, v in zip(nomes, valores) if v is not None]
            params += [("tipoAlerta", t) for t in tipos]
            params += [("porPagina", "5")]
            url = f"{args.url}/api/produtos?{urllib.parse.urlencode(params)}"
            try:
                with _abrir(url, cookie) as r:
                    if r.status != 200:
                        falhas.append((url, f"HTTP {r.status}"))
            except urllib.error.HTTPError as e:
                falhas.append((url, f"HTTP {e.code}: {e.read()[:180].decode(errors='replace')}"))
            except Exception as e:                      # rede, timeout
                falhas.append((url, f"{type(e).__name__}: {e}"))

    if falhas:
        print(f"\n{len(falhas)} de {total} FALHARAM:\n")
        for url, erro in falhas[:20]:
            print(f"  {erro}\n    {url}\n")
        if len(falhas) > 20:
            print(f"  … e mais {len(falhas) - 20}")
        return 1

    print(f"\ntodas as {total} combinações responderam 200.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
