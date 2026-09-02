import {
  AlertTriangle, Boxes, PackageSearch, PackageX, RefreshCw, Sparkles,
  TrendingDown, TrendingUp,
} from "lucide-react";

/* Aparência das etiquetas de alerta.
 *
 * Rótulo, peso e severidade vêm da API (`/api/opcoes` → `alertas`), porque o
 * MESMO peso ordena a lista no SQL. Aqui fica só o que é assunto de tela: o
 * ícone e a cor de cada severidade.
 *
 * Cinco cores por SEVERIDADE, não uma por tipo. O protótipo dá uma cor a cada
 * tipo, o que funciona com os 6 dele e viraria confete com os 10 de decisão —
 * e o comprador precisa distinguir "isto trava minha decisão" de "isto é
 * contexto", não decorar a paleta.
 */

export const COR_SEVERIDADE = {
  critico: "#DE434B",       // vermelho da marca
  atencao: "#B98A2E",       // âmbar
  parado: "#8A8578",        // cinza-oliva
  oportunidade: "#15803D",  // verde: não é problema, é dinheiro a recolher
  info: "#375DA8",          // navy
};

/* Só os tipos da categoria DECISAO: os de cadastro (IMPORTADO, LITRAGEM, TRIB,
 * MVA, SUCESSAO, FABRICA) saíram da tela de Alertas por decisão do Diretor
 * (item 2) e ganharão os seus próprios ícones na tela de Pendência de Cadastro. */
const ICONE = {
  RUPTURA: PackageX,
  SEM_GIRO: Boxes,
  BAIXO_GIRO: PackageSearch,
  MARGEM_BAIXA: TrendingDown,
  MARGEM_BAIXA_VAREJO: TrendingDown,
  MARGEM_ALTA: TrendingUp,
  CUSTO: AlertTriangle,
  OPORTUNIDADE_DE_GIRO: Sparkles,
  DEVOLUCAO: RefreshCw,
  FORA_DE_LINHA: PackageX,
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
