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
EIXOS = {
    "categoria": [None, "DECISAO", "CADASTRO"],
    "status": [None, "Ativo", "Inativo"],
    "soComAlerta": [None, "true"],
    "departamento": [None, "YPF"],
    "classe": [None, "A"],
    "busca": [None, "OLEO"],
    "ordenacao": ["prioridade", "cobertura", "margem", "codigo"],
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


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://192.168.0.50:8020")
    ap.add_argument("--login", required=True)
    ap.add_argument("--senha", default=os.environ.get("APP_TESTE_SENHA"))
    args = ap.parse_args()
    if not args.senha:
        raise SystemExit("informe --senha ou defina APP_TESTE_SENHA")

    cookie = entrar(args.url, args.login, args.senha)

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
