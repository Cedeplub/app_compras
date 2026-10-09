import { ChevronLeft, ChevronRight } from "lucide-react";
import { GRANULARIDADES, rotuloPeriodo } from "../periodo.js";

/* Seletor de período — porte de `SeletorPeriodo` (.jsx linha 380).
 *
 * Diferença de fundo: no protótipo ele é decorativo. Navega no tempo e o número
 * não muda, porque os arrays são estáticos (§8). Aqui cada troca recalcula o
 * intervalo e refaz a consulta.
 *
 * O botão "avançar" fica desabilitado no período corrente: não há dado no
 * futuro, e deixar clicar levaria a uma tela vazia que parece defeito.
 */

const NAVY = "#375DA8";

/** Mês/ano de uma data ISO, por extenso curto: "nov/2018". Em UTC, pelo mesmo
 *  motivo de `periodo.js` — `new Date("2018-11-01")` lido no fuso local vira
 *  outubro a oeste de Greenwich, e o rótulo mentiria por um mês. */
function desdeQuando(iso) {
  if (!iso) return null;
  const [ano, mes] = String(iso).slice(0, 10).split("-");
  const nomes = ["jan", "fev", "mar", "abr", "mai", "jun",
                 "jul", "ago", "set", "out", "nov", "dez"];
  const i = Number(mes) - 1;
  return nomes[i] ? `${nomes[i]}/${ano}` : null;
}

export default function SeletorPeriodo({ granularidade, setGranularidade,
                                         offset, setOffset, referencia,
                                         dataInicio = null }) {
  const inicio = desdeQuando(dataInicio);
  return (
    <div className="flex flex-wrap items-center gap-3">
      <div className="flex gap-1 rounded-lg bg-gray-100 p-0.5">
        {GRANULARIDADES.map((g) => (
          <button key={g} type="button" aria-pressed={granularidade === g}
                  onClick={() => { setGranularidade(g); setOffset(0); }}
                  style={granularidade === g ? { background: NAVY, color: "white" } : {}}
                  className="rounded-md px-3 py-1.5 text-xs font-medium text-gray-500">
            {g}
          </button>
        ))}
      </div>

      <div className="flex items-center gap-1">
        <button type="button" onClick={() => setOffset(offset - 1)}
                aria-label="Período anterior"
                className="rounded-md border border-gray-300 p-1.5 text-gray-600">
          <ChevronLeft size={14} aria-hidden="true" />
        </button>
        <span className="min-w-[130px] text-center text-sm font-semibold text-gray-800">
          {referencia ? rotuloPeriodo(granularidade, offset, referencia) : "—"}
        </span>
        <button type="button" onClick={() => setOffset(offset + 1)} disabled={offset >= 0}
                aria-label="Próximo período"
                className="rounded-md border border-gray-300 p-1.5 text-gray-600 disabled:opacity-30">
          <ChevronRight size={14} aria-hidden="true" />
        </button>
      </div>

      {/* Até onde dá para voltar. Pedido do Diretor em 09/10/2026 junto com a
          ampliação da janela ("informar desde quando a base vai agora"): sem
          isto, quem navega para trás descobre o limite achando tela vazia, que
          parece defeito. Sai de COMPRAS_PARAMETRO.DATA_INICIO, que é
          `min(dia)` do dado REAL — não da var do dbt, que diria o que foi
          pedido e não o que existe. */}
      {inicio && (
        <span className="text-2xs text-gray-400">
          base desde {inicio}
        </span>
      )}
    </div>
  );
}
