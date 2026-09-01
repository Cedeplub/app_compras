import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// O front roda em 5173 em desenvolvimento e conversa com o FastAPI em 8020.
// O proxy existe para que o navegador veja UMA origem só: sem ele, o cookie de
// sessão (HttpOnly, SameSite=Lax) não acompanharia as chamadas de /api e toda
// tela cairia em 401 — um sintoma que parece bug de autenticação e é de CORS.
//
// Em produção não há proxy nem 5173: o `npm run build` gera arquivos estáticos
// que o próprio FastAPI serve, e aí a origem já é uma só de verdade.
export default defineConfig({
  plugins: [react()],
  server: {
    // 0.0.0.0 = escuta em todas as interfaces, nao so em localhost. E' o que
    // permite abrir http://192.168.0.50:5173 de outro computador ou do celular.
    // O acesso e' limitado pela regra de firewall a sub-rede local, e nao pelo
    // bind: servidor de DESENVOLVIMENTO serve codigo-fonte e source maps, entao
    // nao deve sair da LAN. Em producao nao existe este servidor - o `npm run
    // build` gera estaticos que o proprio FastAPI serve.
    host: "0.0.0.0",
    port: 5173,
    proxy: {
      "/api": {
        // ⚠ Aponta para o IP DA REDE, nao para 127.0.0.1, e ha um motivo
        // especifico desta maquina: existe um socket orfao escutando em
        // 0.0.0.0:8020 desde 25/08/2026, cujo processo dono (PID 2240) nao
        // existe mais. Ele nao responde a nada, mas impede tanto o bind em
        // 0.0.0.0 quanto o atendimento de 127.0.0.1:8020. Com o uvicorn preso
        // ao IP especifico (--host 192.168.0.50), o bind convive com o orfao e
        // o proxy tem de procura-lo la.
        //
        // Some quando a maquina for reiniciada (ou o socket for liberado por
        // ferramenta tipo Process Explorer); dai `API_ALVO` volta a poder ser
        // http://127.0.0.1:8020.
        target: process.env.API_ALVO || "http://192.168.0.50:8020",
        changeOrigin: false,
      },
    },
  },
  build: {
    outDir: "../app/static/v2",
    emptyOutDir: true,
  },
});
