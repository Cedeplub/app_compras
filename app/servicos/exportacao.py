"""Utilidades de estilo Excel reaproveitadas por `pedido.py` (Tela 4).

HISTÓRICO: este arquivo já teve `fornecedores_com_pedido`/`itens_do_fornecedor`,
que liam um `APP_DECISAO_PEDIDO` agregado por fornecedor e janela de datas —
modelo anterior ao conceito de pedido com cabeçalho (`APP_PEDIDO`) e itens
(`APP_PEDIDO_ITEM`, ver `sql/04_tabelas_pedido.sql`). Essa tabela foi dropada
nesta migração e as duas funções ficaram órfãs (confirmado por grep: nenhum
chamador em `app/`, `web/src/`, `validar/`). A exportação real hoje mora em
`pedido.py` (`gerar_excel_pedido`, `exportar_winthor`), operando sobre um
`id_pedido` já existente — não sobre uma janela de datas. Removidas junto:
`_janela`, `gerar_xlsx`, `nome_arquivo`, `_br`, `_COLUNAS`, `_AVISO`, que só
serviam a essas duas funções.

O que sobrevive é só o que `pedido.py` importa deste módulo: `_HEADER_FILL`,
`_HEADER_FONT` (estilo do cabeçalho da tabela) e `_slug` (nome de arquivo sem
acento/espaço).
"""
from __future__ import annotations

import re
import unicodedata

from openpyxl.styles import Font, PatternFill

_HEADER_FILL = PatternFill("solid", fgColor="1F3864")
_HEADER_FONT = Font(color="FFFFFF", bold=True, size=10)


def _slug(texto: str) -> str:
    """Nome de fornecedor sem acento/espaco, para nome de arquivo."""
    sem_acento = unicodedata.normalize("NFKD", texto or "").encode("ascii", "ignore").decode("ascii")
    return re.sub(r"[^A-Za-z0-9]+", "_", sem_acento).strip("_").upper() or "FORNECEDOR"
