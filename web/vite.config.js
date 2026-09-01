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
    port: 5173,
    proxy: {
      "/api": {
        target: "http://127.0.0.1:8020",
        changeOrigin: false,
      },
    },
  },
  build: {
    outDir: "../app/static/v2",
    emptyOutDir: true,
  },
});
