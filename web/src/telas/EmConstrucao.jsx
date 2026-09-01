import { Construction } from "lucide-react";

/* Tela honesta para rota que ainda não foi construída.
 *
 * A alternativa seria esconder o item do menu até a etapa chegar. Mostrar o
 * caminho inteiro desde já deixa visível o tamanho do que falta — e diz qual
 * etapa entrega o quê, em vez de deixar a pessoa clicando num link morto. */
export default function EmConstrucao({ tela, etapa }) {
  return (
    <div className="flex flex-col items-center gap-3 p-12 text-center">
      <Construction size={24} className="text-ambar" aria-hidden="true" />
      <h2 className="text-lg font-semibold text-gray-800">{tela}</h2>
      <p className="max-w-sm text-sm text-cinza-neutro">
        Entra na <strong>Etapa {etapa}</strong> do ciclo v2. O plano e a ordem das
        etapas estão em <code className="rounded bg-gray-100 px-1">v2/PLANO.md</code>.
      </p>
    </div>
  );
}
