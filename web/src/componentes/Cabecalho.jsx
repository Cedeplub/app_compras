import { useEffect, useRef, useState } from "react";
import { NavLink } from "react-router-dom";
import { AlertTriangle, FileText, LogOut, Menu, PackagePlus, Tag } from "lucide-react";
import logoCedep from "../logo-cedep.png";

/* Cabeçalho e menu de áreas — porte de `Header` e `MenuArea`
 * (v2/prototipo/painel_cedep_prototipo_2.jsx, linhas 414 e 456).
 *
 * A navegação tem DOIS níveis, e o cabeçalho é onde o de cima mora:
 *   área  →  Painel · Pedidos · Pedidos Salvos · Precificação   (menu ☰ daqui)
 *   aba   →  Alertas · Monitoramento · Entradas                 (só dentro do
 *            Painel, na BarraAbas)
 *
 * A primeira versão desta tela achatou os dois níveis numa fileira de seis
 * abas, o que fazia "Alertas" e "Pedidos" parecerem irmãos quando um é aba do
 * Painel do Dia e o outro é uma área inteira.
 */

export const AREAS = [
  { id: "painel", para: "/painel/alertas", rotulo: "Painel",
    sub: "Alertas · Monitoramento · Entradas", icone: AlertTriangle },
  { id: "pedidos", para: "/pedidos", rotulo: "Pedidos",
    sub: "Decisão de compra — visão ampla", icone: PackagePlus },
  { id: "pedidos_salvos", para: "/pedidos-salvos", rotulo: "Pedidos Salvos",
    sub: "Status, orçamento e envio pro Winthor", icone: FileText },
  { id: "precificacao", para: "/precificacao", rotulo: "Precificação",
    sub: "Decisão de preço — visão ampla", icone: Tag },
];

const NAVY = "#375DA8";
const VERMELHO = "#DE434B";

export default function Cabecalho({ titulo, subtitulo, areaAtual, usuario, aoSair }) {
  return (
    <div>
      <div className="relative flex items-center justify-between py-3 pl-6 pr-4"
           style={{ background: NAVY }}>
        {/* O corte diagonal branco que entra na faixa navy é a assinatura visual
            da marca no protótipo — o logo repousa sobre ele. As proporções
            (132px de largura, vértice a 76%) são as do original. */}
        <div className="absolute bottom-0 left-0 top-0 bg-white"
             style={{ width: 132, clipPath: "polygon(0 0, 100% 0, 76% 100%, 0 100%)" }}
             aria-hidden="true" />
        <img src={logoCedep} alt="CEDEP" className="relative z-[1] h-8 w-auto" />

        <div className="relative z-[1] flex items-center gap-2">
          <DataDeHoje />
          {/* Os botões Smartphone/Monitor do protótipo NÃO foram portados: eles
              existem porque lá a troca mobile↔mesa é um booleano manual e o
              arquivo simula os dois tamanhos numa janela só. Aqui a
              responsividade é de CSS — quem decide o formato é a largura real
              da tela, então o alternador não teria função. */}
          <MenuArea areaAtual={areaAtual} />
          <BotaoSair usuario={usuario} aoSair={aoSair} />
        </div>
      </div>

      {/* Faixa de marca: 3px, metade navy, metade vermelha. */}
      <div className="flex h-[3px]" aria-hidden="true">
        <div className="flex-1" style={{ background: NAVY }} />
        <div className="flex-1" style={{ background: VERMELHO }} />
      </div>

      <div className="px-4 pb-1 pt-3 md:px-6">
        <h1 className="text-[17px] font-semibold leading-tight text-gray-900">{titulo}</h1>
        {subtitulo && <p className="mt-0.5 text-sm text-gray-500">{subtitulo}</p>}
      </div>
    </div>
  );
}

/* No protótipo a data é a string fixa "28 ago 2026", porque `HOJE` é
 * `new Date(2026, 7, 28)` chumbado no arquivo (PROTOTIPO.md §8). Aqui é a data
 * real do dispositivo — era um dos "de mentira" que o próprio documento lista. */
function DataDeHoje() {
  const hoje = new Date().toLocaleDateString("pt-BR",
    { day: "numeric", month: "short", year: "numeric" }).replace(".", "");
  return <span className="num hidden text-xs text-white/70 sm:block">{hoje}</span>;
}

function MenuArea({ areaAtual }) {
  const [aberto, setAberto] = useState(false);
  const caixa = useRef(null);

  // Fechar com Esc e ao clicar fora. O protótipo cobre o clique fora com um
  // `fixed inset-0` invisível, mas não trata Esc — quem navega por teclado fica
  // preso no menu.
  useEffect(() => {
    if (!aberto) return;
    const aoTeclar = (e) => { if (e.key === "Escape") setAberto(false); };
    const aoClicar = (e) => { if (caixa.current && !caixa.current.contains(e.target)) setAberto(false); };
    document.addEventListener("keydown", aoTeclar);
    document.addEventListener("mousedown", aoClicar);
    return () => {
      document.removeEventListener("keydown", aoTeclar);
      document.removeEventListener("mousedown", aoClicar);
    };
  }, [aberto]);

  return (
    <div className="relative" ref={caixa}>
      <button type="button" onClick={() => setAberto((v) => !v)}
              aria-expanded={aberto} aria-haspopup="menu" aria-label="Menu de áreas"
              className="rounded-full bg-white/15 p-2">
        <Menu size={16} className="text-white" aria-hidden="true" />
      </button>

      {aberto && (
        <div role="menu"
             className="absolute right-0 top-11 z-20 w-64 rounded-xl border border-gray-200 bg-white py-1.5 shadow-lg">
          {AREAS.map((a) => {
            const Icone = a.icone;
            const ativo = areaAtual === a.id;
            return (
              <NavLink key={a.id} to={a.para} role="menuitem"
                       onClick={() => setAberto(false)}
                       className="flex w-full items-center gap-2.5 px-3 py-2.5 text-left"
                       style={ativo ? { background: `${NAVY}0D` } : undefined}>
                <Icone size={16} color={ativo ? NAVY : "#9CA3AF"} aria-hidden="true" />
                <span>
                  <span className="block text-[12.5px] font-medium"
                        style={{ color: ativo ? NAVY : "#374151" }}>{a.rotulo}</span>
                  <span className="block text-2xs text-gray-400">{a.sub}</span>
                </span>
              </NavLink>
            );
          })}
        </div>
      )}
    </div>
  );
}

/* Não existe no protótipo, porque lá não há login. Aqui há sessão, perfil e
 * auditoria — e uma tela que não oferece saída obriga a fechar o navegador. */
function BotaoSair({ usuario, aoSair }) {
  return (
    <button type="button" onClick={aoSair}
            title={`Sair — ${usuario?.nome ?? ""}`}
            className="flex items-center gap-1.5 rounded-full bg-white/15 px-2.5 py-2 text-xs font-medium text-white">
      <LogOut size={14} aria-hidden="true" />
      <span className="hidden sm:inline">Sair</span>
    </button>
  );
}
