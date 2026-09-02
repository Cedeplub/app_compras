import { useCallback, useEffect, useState } from "react";
import { Navigate, Route, Routes, useLocation, useNavigate } from "react-router-dom";
import { api, SESSAO_EXPIROU } from "./api/cliente.js";
import { Carregando, Erro } from "./componentes/Basicos.jsx";
import Cabecalho from "./componentes/Cabecalho.jsx";
import BarraAbas from "./componentes/BarraAbas.jsx";
import Login from "./telas/Login.jsx";
import Alertas from "./telas/Alertas.jsx";
import EmConstrucao from "./telas/EmConstrucao.jsx";

/* Esqueleto do app.
 *
 * Navegação em dois níveis, como no protótipo (§2): a ÁREA troca pelo menu ☰ do
 * cabeçalho, e a ABA só existe dentro da área "painel", na BarraAbas.
 *
 * Diferença deliberada: aqui cada tela tem URL. No protótipo nenhuma URL muda,
 * então o botão voltar do navegador sai do app e F5 devolve tudo ao estado
 * inicial (§7). Com rota de verdade, o comprador manda o link de um produto
 * para o Diretor e recarregar não perde o lugar.
 */

const TITULOS = {
  "/painel/alertas": {
    titulo: "Painel do dia",
    // No protótipo o subtítulo é a string fixa "sexta-feira, 28 de agosto"
    // (§8: `HOJE` é chumbado). Aqui é a data real.
    subtitulo: () => new Date().toLocaleDateString("pt-BR",
      { weekday: "long", day: "numeric", month: "long" }),
  },
  "/painel/monitoramento": { titulo: "Monitoramento", subtitulo: () => "Faturamento, peso e quantidade" },
  "/painel/entradas": { titulo: "Entradas recentes", subtitulo: () => "Últimas movimentações de estoque" },
  "/pedidos": { titulo: "Pedidos", subtitulo: () => "Decisão de compra — visão ampla" },
  "/pedidos-salvos": { titulo: "Pedidos Salvos", subtitulo: () => "Status, orçamento e envio pro Winthor" },
  "/precificacao": { titulo: "Precificação", subtitulo: () => "Decisão de preço — visão ampla" },
};

const areaDaRota = (caminho) =>
  caminho.startsWith("/painel") ? "painel"
    : caminho.startsWith("/pedidos-salvos") ? "pedidos_salvos"
    : caminho.startsWith("/pedidos") ? "pedidos"
    : caminho.startsWith("/precificacao") ? "precificacao"
    : null;

export default function App() {
  const [usuario, setUsuario] = useState(null);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState(null);
  const [contadorAlertas, setContadorAlertas] = useState(null);
  const navegar = useNavigate();
  const { pathname } = useLocation();

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

  // Contador do badge vermelho da aba Alertas. Uma consulta leve (uma linha) só
  // para o agregado — o `resumo` vale para o filtro inteiro, não para a página.
  useEffect(() => {
    if (!usuario) return;
    // Os MESMOS filtros da tela de Alertas, `categoria` inclusive. Sem ela o
    // badge contava 3,5k enquanto o KPI da tela dizia 2.982 — dois números para
    // a mesma pergunta, e o comprador sem saber qual acreditar.
    api.produtos({ soComAlerta: true, status: "Ativo", categoria: "DECISAO", porPagina: 1 })
      .then((d) => setContadorAlertas(d.resumo?.comAlerta ?? null))
      .catch(() => setContadorAlertas(null));   // badge é enfeite: falhar aqui não é erro de tela
  }, [usuario]);

  if (carregando) return <Carregando>Verificando sessão…</Carregando>;
  if (erro) return <Erro mensagem={erro} aoTentarDeNovo={verificarSessao} />;
  if (!usuario) return <Login aoEntrar={setUsuario} />;

  const area = areaDaRota(pathname);
  const t = TITULOS[pathname];

  return (
    <div className="mx-auto flex min-h-screen max-w-app flex-col border-x border-gray-200 bg-white">
      <Cabecalho
        titulo={t?.titulo ?? "Compras CEDEP"}
        subtitulo={t?.subtitulo?.()}
        areaAtual={area}
        usuario={usuario}
        aoSair={() => { api.sair().finally(() => setUsuario(null)); }}
      />

      {/* A ordem no DOM é cabeçalho → conteúdo → abas, que é a ordem do
          celular (barra no rodapé). Na mesa, `md:order-*` sobe a barra para
          logo abaixo do cabeçalho sem duplicar marcação. */}
      <main className="flex-1 md:order-3">
        <Routes>
          <Route path="/" element={<Navigate to="/painel/alertas" replace />} />
          <Route path="/painel" element={<Navigate to="/painel/alertas" replace />} />
          <Route path="/painel/alertas" element={<Alertas />} />
          <Route path="/painel/monitoramento" element={<EmConstrucao tela="Monitoramento" etapa={10} />} />
          <Route path="/painel/entradas" element={<EmConstrucao tela="Entradas" etapa={10} />} />
          <Route path="/pedidos" element={<EmConstrucao tela="Pedidos" etapa={9} />} />
          <Route path="/pedidos-salvos" element={<EmConstrucao tela="Pedidos salvos" etapa={9} />} />
          <Route path="/precificacao" element={<EmConstrucao tela="Precificação" etapa={8} />} />
          <Route path="/produto/:codigo" element={<EmConstrucao tela="Decisão do SKU" etapa={8} />} />
          <Route path="*" element={<Navigate to="/painel/alertas" replace />} />
        </Routes>
      </main>

      {/* As três abas só existem dentro do Painel — é o que o segundo nível de
          navegação significa. Fora dele, a barra não aparece. */}
      {/* A própria BarraAbas carrega `order-last md:order-none`: no celular vai
          para o fim (rodapé), na mesa volta para junto do cabeçalho, porque o
          <main> tem `md:order-3`. Envolvê-la num `display:contents` anularia o
          `order`, já que o elemento deixa de gerar caixa. */}
      {area === "painel" && <BarraAbas contadorAlertas={contadorAlertas} />}
    </div>
  );
}
