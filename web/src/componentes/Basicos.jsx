import { AlertTriangle, Loader2, Inbox } from "lucide-react";

/* Componentes compartilhados, no desenho de PROTOTIPO.md §6.
 *
 * Três deles — Carregando, Erro e Vazio — NÃO existem no protótipo: lá não há
 * rede, então não há espera nem falha (§8). No MVP há rede em toda tela, e uma
 * tela que não sabe dizer "estou buscando" some por dois segundos e parece
 * quebrada. Por isso nascem aqui, junto com os outros, e não como remendo. */

export function Segmented({ opcoes, valor, aoTrocar, rotulo }) {
  return (
    <div role="group" aria-label={rotulo} className="inline-flex rounded-lg bg-gray-100 p-0.5">
      {opcoes.map((o) => {
        const ativo = o.id === valor;
        return (
          <button
            key={o.id}
            type="button"
            aria-pressed={ativo}
            onClick={() => aoTrocar(o.id)}
            className={`rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
              ativo ? "bg-navy text-white shadow-sm" : "text-cinza-neutro hover:text-gray-900"
            }`}
          >
            {o.rotulo}
          </button>
        );
      })}
    </div>
  );
}

/* §6: A → navy, B/C → cinza, S/VEND → vermelho. */
const CORES_CLASSE = {
  A: "bg-navy/10 text-navy",
  "B/C": "bg-gray-200 text-cinza-neutro",
  "S/VEND": "bg-vermelho/10 text-vermelho",
};

export function ClasseChip({ classe }) {
  if (!classe) return null;
  return (
    <span className={`rounded px-1.5 py-0.5 text-2xs font-bold tracking-wide ${
      CORES_CLASSE[classe] ?? "bg-gray-200 text-cinza-neutro"}`}>
      {classe}
    </span>
  );
}

/* Cores por tipo de alerta.
 *
 * ⚠ Os tipos aqui são os REAIS de COMPRAS_ALERTA, medidos no banco, e não os 6
 * de PROTOTIPO.md §4.5. Só RUPTURA existe nos dois. O protótipo inventou uma
 * taxonomia própria (sem_giro, baixo_giro, estoque_alto, margem_baixa,
 * margem_alta) que não é a do modelo — é uma diferença para conversar com o
 * Diretor, não para "consertar" de um lado só.
 *
 * O `texto` vira `title`: o tipo cabe na etiqueta, a explicação inteira não —
 * concatenar as duas foi exatamente o que esticou a linha da tabela na v1.
 */
const CORES_ALERTA = {
  // decisão urgente
  RUPTURA: "bg-vermelho/10 text-vermelho",
  MARGEM_INSTAVEL: "bg-vermelho/10 text-vermelho",
  MARGEM_INSTAVEL_VAREJO: "bg-vermelho/10 text-vermelho",
  CUSTO: "bg-vermelho/10 text-vermelho",
  // giro parado
  PARADO: "bg-cinza-oliva/15 text-cinza-oliva",
  FORA_DE_LINHA: "bg-cinza-oliva/15 text-cinza-oliva",
  // pendência a resolver
  DEVOLUCAO: "bg-ambar/10 text-ambar",
  MVA: "bg-ambar/10 text-ambar",
  TRIB: "bg-ambar/10 text-ambar",
  // informativo: muda a leitura, não exige ação
  IMPORTADO: "bg-navy/10 text-navy",
  LITRAGEM: "bg-navy/10 text-navy",
  SUCESSAO: "bg-navy/10 text-navy",
};

export function BadgeAlerta({ tipo, texto }) {
  return (
    <span
      title={texto || tipo}
      className={`inline-block whitespace-nowrap rounded px-1.5 py-0.5 text-2xs font-semibold ${
        CORES_ALERTA[tipo] ?? "bg-gray-200 text-cinza-neutro"}`}
    >
      {tipo?.replace(/_/g, " ")}
    </span>
  );
}

const CORES_MODALIDADE = {
  ST_SUBSTITUTO: "bg-navy/10 text-navy",
  ST_RECOLHIDO: "bg-roxo/10 text-roxo",
};

export function BadgeTributacao({ modalidade, creditoPisCofins }) {
  const rotulo = { ST_SUBSTITUTO: "ST Substituto", ST_RECOLHIDO: "ST Recolhido" }[modalidade]
    ?? "Normal";
  return (
    <span className="inline-flex flex-wrap gap-1">
      <span className={`rounded px-1.5 py-0.5 text-2xs font-semibold ${
        CORES_MODALIDADE[modalidade] ?? "bg-gray-200 text-cinza-neutro"}`}>
        {rotulo}
      </span>
      {/* §5: "Monofásico" é atributo independente da modalidade, não uma quarta
          modalidade — por isso é uma segunda etiqueta, e não outra cor nesta. */}
      {creditoPisCofins === 0 && (
        <span className="rounded bg-gray-200 px-1.5 py-0.5 text-2xs font-semibold text-cinza-neutro">
          Monofásico
        </span>
      )}
    </span>
  );
}

export function Carregando({ children = "Buscando…" }) {
  return (
    <div role="status" className="flex items-center justify-center gap-2 p-8 text-sm text-cinza-neutro">
      <Loader2 size={16} className="animate-spin" aria-hidden="true" />
      {children}
    </div>
  );
}

export function Erro({ mensagem, aoTentarDeNovo }) {
  return (
    <div role="alert" className="m-4 rounded-lg border border-vermelho/30 bg-vermelho/5 p-4">
      <div className="flex items-start gap-2">
        <AlertTriangle size={16} className="mt-0.5 shrink-0 text-vermelho" aria-hidden="true" />
        <div className="flex-1">
          <p className="text-sm text-gray-900">{mensagem}</p>
          {aoTentarDeNovo && (
            <button
              type="button"
              onClick={aoTentarDeNovo}
              className="mt-2 rounded-md border border-vermelho px-3 py-1 text-sm font-medium text-vermelho"
            >
              Tentar de novo
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

export function Vazio({ titulo, detalhe }) {
  return (
    <div className="flex flex-col items-center gap-2 p-10 text-center">
      <Inbox size={22} className="text-gray-300" aria-hidden="true" />
      <p className="text-md font-medium text-gray-700">{titulo}</p>
      {detalhe && <p className="max-w-xs text-sm text-cinza-neutro">{detalhe}</p>}
    </div>
  );
}
