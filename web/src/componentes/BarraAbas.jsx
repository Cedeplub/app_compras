import { NavLink } from "react-router-dom";
import { AlertTriangle, BarChart3, PackagePlus } from "lucide-react";
import { compacto } from "../formato.js";

/* As três abas do Painel do Dia — porte de `TabBar` (.jsx linha 500).
 *
 * A ÚNICA divergência de forma em relação ao protótipo, e ela é deliberada:
 * lá a barra é fixa no rodapé nos dois tamanhos, porque o arquivo tem uma
 * marcação só e o desenho nasceu para celular. O próprio PROTOTIPO.md §2
 * registra que no desktop "não existe barra equivalente fixa, a troca de aba é
 * a mesma barra reaproveitada" — ou seja, a barra de celular foi empurrada para
 * a tela grande sem redesenho.
 *
 * Aqui: rodapé no celular (onde o polegar alcança) e abas no topo na mesa
 * (onde barra fixa embaixo é estranha e o topo é o lugar convencional). Mesma
 * marcação, mesmos itens, mesmo contador — só a posição muda, por media query.
 */

const ABAS = [
  { para: "/painel/alertas", rotulo: "Alertas", icone: AlertTriangle, temContador: true },
  { para: "/painel/monitoramento", rotulo: "Monitoramento", icone: BarChart3 },
  { para: "/painel/entradas", rotulo: "Entradas", icone: PackagePlus },
];

const NAVY = "#375DA8";
const VERMELHO = "#DE434B";
const CINZA = "#9CA3AF";

export default function BarraAbas({ contadorAlertas }) {
  return (
    <nav aria-label="Painel do dia"
         className="sticky bottom-0 z-20 order-last flex border-t border-gray-200 bg-white
                    md:bottom-auto md:top-0 md:order-none md:border-b md:border-t-0">
      {ABAS.map((a) => {
        const Icone = a.icone;
        const contador = a.temContador ? contadorAlertas : null;
        return (
          <NavLink key={a.para} to={a.para}
                   className="relative flex flex-1 flex-col items-center gap-0.5 py-2.5
                              md:flex-none md:flex-row md:gap-2 md:px-5 md:py-3">
            {({ isActive }) => (
              <>
                <span className="relative">
                  <Icone size={19} color={isActive ? NAVY : CINZA} aria-hidden="true"
                         className="md:hidden" />
                  <Icone size={15} color={isActive ? NAVY : CINZA} aria-hidden="true"
                         className="hidden md:block" />
                  {contador ? (
                    <span style={{ background: VERMELHO }}
                          className="absolute -right-2 -top-1.5 flex h-[15px] min-w-[15px] items-center
                                     justify-center rounded-full px-1 text-[9px] font-bold text-white">
                      {/* O protótipo mostra o número cru, e com 8 produtos de
                          exemplo ele cabe. No real são milhares: "2589" não
                          entra num círculo de 15px e "999+" esconde a ordem de
                          grandeza. `compacto` dá "2,6k", que cabe e informa. */}
                      {contador >= 1000 ? compacto(contador) : contador}
                    </span>
                  ) : null}
                </span>
                <span className="text-2xs font-medium md:text-sm"
                      style={{ color: isActive ? NAVY : CINZA }}>
                  {a.rotulo}
                </span>
                {/* Na mesa, a aba ativa ganha o sublinhado navy que a barra de
                    rodapé não precisa ter (lá o ícone colorido já basta). */}
                {isActive && (
                  <span aria-hidden="true"
                        className="absolute inset-x-0 bottom-0 hidden h-[2px] md:block"
                        style={{ background: NAVY }} />
                )}
              </>
            )}
          </NavLink>
        );
      })}
    </nav>
  );
}
