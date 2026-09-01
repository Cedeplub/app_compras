import {
  AlertTriangle, Boxes, Factory, Layers, Package, PackageSearch, PackageX,
  RefreshCw, Tag, TrendingDown,
} from "lucide-react";

/* Aparência das etiquetas de alerta.
 *
 * Rótulo, peso e severidade vêm da API (`/api/opcoes` → `alertas`), porque o
 * MESMO peso ordena a lista no SQL. Aqui fica só o que é assunto de tela: o
 * ícone e a cor de cada severidade.
 *
 * Quatro cores, não catorze. O protótipo dá uma cor por tipo, o que funciona
 * com 6 tipos e vira confete com 14 — e o comprador precisa distinguir
 * "isto trava minha decisão" de "isto é contexto", não decorar a paleta.
 */

export const COR_SEVERIDADE = {
  critico: "#DE434B",  // vermelho da marca
  atencao: "#B98A2E",  // âmbar
  parado: "#8A8578",   // cinza-oliva
  info: "#375DA8",     // navy
};

const ICONE = {
  RUPTURA: PackageX,
  MARGEM_INSTAVEL: TrendingDown,
  MARGEM_INSTAVEL_VAREJO: TrendingDown,
  CUSTO: AlertTriangle,
  PARADO: Boxes,
  FORA_DE_LINHA: PackageX,
  INATIVO: Package,
  DEVOLUCAO: RefreshCw,
  MVA: Tag,
  TRIB: Tag,
  SUCESSAO: Layers,
  FABRICA: Factory,
  IMPORTADO: Package,
  LITRAGEM: PackageSearch,
};

export const iconeDoAlerta = (tipo) => ICONE[tipo] ?? AlertTriangle;

export const corDoAlerta = (meta) => COR_SEVERIDADE[meta?.severidade] ?? COR_SEVERIDADE.info;

/* O texto do alerta vem pronto do banco ("RUPTURA RECORRENTE - 10 DIAS SEM
 * ESTOQUE"), com o detalhe numérico já dentro. O protótipo remonta esse detalhe
 * em JavaScript (`detalheAlerta`, §3.2) a partir de campos soltos — e o próprio
 * autor marcou ali um ⚠ porque a versão dele usa um campo estático que não
 * reage ao cenário. Aqui não há o que remontar: usa-se o texto da planilha.
 *
 * Só a parte DEPOIS do travessão vira o detalhe da etiqueta; a parte antes já
 * está dita pelo rótulo. "RUPTURA RECORRENTE - 10 DIAS SEM ESTOQUE" mostra
 * "Ruptura · 10 dias sem estoque". */
export function detalheDoTexto(texto) {
  if (!texto) return null;
  const partes = texto.split(/\s+[-–]\s+/);
  if (partes.length < 2) return null;
  const detalhe = partes.slice(1).join(" - ").trim();
  return detalhe ? detalhe.charAt(0) + detalhe.slice(1).toLowerCase() : null;
}
