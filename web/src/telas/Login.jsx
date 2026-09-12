import { useState } from "react";
import { api } from "../api/cliente.js";
import { Erro } from "../componentes/Basicos.jsx";

export default function Login({ aoEntrar }) {
  const [login, setLogin] = useState("");
  const [senha, setSenha] = useState("");
  const [erro, setErro] = useState(null);
  const [enviando, setEnviando] = useState(false);

  async function enviar(e) {
    e.preventDefault();
    setEnviando(true);
    setErro(null);
    try {
      const { usuario } = await api.entrar(login, senha);
      aoEntrar(usuario);
    } catch (err) {
      setErro(err.detalhe);
    } finally {
      setEnviando(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-50 p-4">
      <form onSubmit={enviar} className="w-full max-w-sm rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
        <h1 className="text-xl font-bold text-navy">Compras CEDEP</h1>
        <p className="mt-1 text-sm text-cinza-neutro">Entre para continuar.</p>

        {erro && <div className="-mx-2 mt-3"><Erro mensagem={erro} /></div>}

        <label className="mt-5 block text-sm font-medium text-gray-700" htmlFor="login">Login</label>
        <input
          id="login" name="login" autoComplete="username" required autoFocus
          value={login} onChange={(e) => setLogin(e.target.value)}
          className="mt-1 w-full rounded-md border border-gray-300 px-3 py-2 text-md"
        />

        <label className="mt-3 block text-sm font-medium text-gray-700" htmlFor="senha">Senha</label>
        <input
          id="senha" name="senha" type="password" autoComplete="current-password" required
          value={senha} onChange={(e) => setSenha(e.target.value)}
          className="mt-1 w-full rounded-md border border-gray-300 px-3 py-2 text-md"
        />

        <button
          type="submit" disabled={enviando}
          className="mt-5 w-full rounded-md bg-navy py-2.5 text-md font-semibold text-white disabled:opacity-40"
        >
          {enviando ? "Entrando…" : "Entrar"}
        </button>
      </form>
    </div>
  );
}
