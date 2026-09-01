import { useCallback, useEffect, useState } from "react";
import { NavLink, Navigate, Route, Routes, useNavigate } from "react-router-dom";
import { LogOut } from "lucide-react";
import { api, SESSAO_EXPIROU } from "./api/cliente.js";
import { Carregando, Erro } from "./componentes/Basicos.jsx";
import Login from "./telas/Login.jsx";
import Alertas from "./telas/Alertas.jsx";
import EmConstrucao from "./telas/EmConstrucao.jsx";

/* Navegação por URL de verdade.
 *
 * O protótipo troca de tela mudando `useState` no componente raiz: nenhuma URL
 * muda, o botão voltar do navegador sai do app e F5 volta tudo ao estado
 * inicial (PROTOTIPO.md §7). Aqui cada tela tem endereço — o comprador pode
 * mandar o link de um produto para o Diretor, e recarregar não perde o lugar. */
const ABAS = [
  { para: "/alertas", rotulo: "Alertas" },
  { para: "/monitoramento", rotulo: "Monitoramento" },
  { para: "/entradas", rotulo: "Entradas" },
  { para: "/pedidos", rotulo: "Pedidos" },
  { para: "/pedidos-salvos", rotulo: "Pedidos salvos" },
  { para: "/precificacao", rotulo: "Precificação" },
];

export default function App() {
  const [usuario, setUsuario] = useState(null);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState(null);
  const navegar = useNavigate();

  const verificarSessao = useCallback(async () => {
    setCarregando(true);
    setErro(null);
    try {
      const { usuario } = await api.sessao();
      setUsuario(usuario);
    } catch (e) {
      // 401 aqui é o caso normal de quem ainda não entrou, não uma falha:
      // vira tela de login, não mensagem de erro.
      if (e.status !== 401) setErro(e.detalhe);
      setUsuario(null);
    } finally {
      setCarregando(false);
    }
  }, []);

  useEffect(() => { verificarSessao(); }, [verificarSessao]);

  useEffect(() => {
    const aoExpirar = () => { setUsuario(null); navegar("/", { replace: true }); };
    window.addEventListener(SESSAO_EXPIROU, aoExpirar);
    return () => window.removeEventListener(SESSAO_EXPIROU, aoExpirar);
  }, [navegar]);

  if (carregando) return <Carregando>Verificando sessão…</Carregando>;
  if (erro) return <Erro mensagem={erro} aoTentarDeNovo={verificarSessao} />;
  if (!usuario) return <Login aoEntrar={setUsuario} />;

  return (
    <div className="mx-auto min-h-screen max-w-app border-x border-gray-200 bg-white">
      <Cabecalho usuario={usuario} aoSair={() => { api.sair().finally(() => setUsuario(null)); }} />
      <Abas />
      <main>
        <Routes>
          <Route path="/" element={<Navigate to="/alertas" replace />} />
          <Route path="/alertas" element={<Alertas />} />
          <Route path="/monitoramento" element={<EmConstrucao tela="Monitoramento" etapa={10} />} />
          <Route path="/entradas" element={<EmConstrucao tela="Entradas" etapa={10} />} />
          <Route path="/pedidos" element={<EmConstrucao tela="Pedidos" etapa={9} />} />
          <Route path="/pedidos-salvos" element={<EmConstrucao tela="Pedidos salvos" etapa={9} />} />
          <Route path="/precificacao" element={<EmConstrucao tela="Precificação" etapa={8} />} />
          <Route path="/produto/:codigo" element={<EmConstrucao tela="Decisão do SKU" etapa={8} />} />
          <Route path="*" element={<Navigate to="/alertas" replace />} />
        </Routes>
      </main>
    </div>
  );
}

function Cabecalho({ usuario, aoSair }) {
  return (
    <header className="sticky top-0 z-30 flex items-center justify-between gap-3 bg-navy px-4 py-3 text-white">
      <div className="min-w-0">
        <h1 className="truncate text-lg font-bold leading-tight">Compras CEDEP</h1>
        <p className="truncate text-xs text-white/70">{usuario.nome}</p>
      </div>
      <button
        type="button"
        onClick={aoSair}
        className="flex shrink-0 items-center gap-1.5 rounded-md bg-white/10 px-2.5 py-1.5 text-sm font-medium"
      >
        <LogOut size={14} aria-hidden="true" />
        <span className="hidden sm:inline">Sair</span>
      </button>
    </header>
  );
}

/* Responsividade de CSS, não booleano manual.
 *
 * O protótipo mantém dois blocos de JSX por tela e alterna com um botão
 * (`modoDesktop`), o que obriga toda mudança a ser feita duas vezes e já fez as
 * duas versões divergirem em três pontos (§6/§8). Aqui a marcação é uma só: no
 * celular a barra é rolável na horizontal, na mesa ela simplesmente cabe. */
function Abas() {
  return (
    <nav className="sticky top-[57px] z-20 overflow-x-auto border-b border-gray-200 bg-white">
      <ul className="flex min-w-max">
        {ABAS.map((a) => (
          <li key={a.para}>
            <NavLink
              to={a.para}
              className={({ isActive }) =>
                `block whitespace-nowrap px-4 py-3 text-sm font-medium transition-colors ${
                  isActive
                    ? "border-b-2 border-navy text-navy"
                    : "border-b-2 border-transparent text-cinza-neutro hover:text-gray-900"
                }`
              }
            >
              {a.rotulo}
            </NavLink>
          </li>
        ))}
      </ul>
    </nav>
  );
}
