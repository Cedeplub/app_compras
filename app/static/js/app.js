// Dashboard de Compras CEDEP — JS proprio, sem dependencia externa.
// Unica responsabilidade: dar feedback claro e imediato de gravado/erro nos
// campos que gravam por HTMX, ja que a resposta trocada por si so nao chama
// atencao do usuario (essencial no celular, com a mao ocupada segurando o
// aparelho). Nao faz nenhuma requisicao propria: so reage a eventos do htmx
// que ja aconteceu.
(function () {
  "use strict";

  function mostrarFeedback(host, texto, classe) {
    if (!host) return;
    var antigo = host.querySelector(".feedback-gravacao");
    if (antigo) antigo.remove();
    var aviso = document.createElement("div");
    aviso.className = "feedback-gravacao " + classe;
    aviso.setAttribute("role", "status");
    aviso.textContent = texto;
    host.appendChild(aviso);
    window.setTimeout(function () {
      if (aviso.parentNode) aviso.parentNode.removeChild(aviso);
    }, classe === "erro" ? 5000 : 2200);
  }

  // Sucesso: o alvo trocado (outerHTML) e' o proprio card/linha do produto -
  // o campo.form.campo-pedido acabou de ser recriado dentro dele.
  document.body.addEventListener("htmx:afterSwap", function (evt) {
    var alvo = evt.detail && evt.detail.target;
    if (!alvo || !alvo.id || alvo.id.indexOf("linha-") !== 0) return;
    var forms = alvo.querySelectorAll("form.campo-pedido");
    forms.forEach(function (form) {
      mostrarFeedback(form, "Gravado.", "ok");
    });
  });

  // Erro: a requisicao falhou (400/404) - htmx nao troca o conteudo, entao o
  // <form> que disparou o pedido ainda esta la, e e' nele que a mensagem entra.
  document.body.addEventListener("htmx:responseError", function (evt) {
    var elt = evt.detail && evt.detail.elt;
    var form = elt && elt.closest ? elt.closest("form") : null;
    var texto = "Não foi possível gravar. Tente novamente.";
    try {
      var corpo = JSON.parse(evt.detail.xhr.responseText);
      if (corpo && corpo.detail) texto = corpo.detail;
    } catch (erroIgnorado) {
      // resposta nao era JSON - mantem a mensagem generica
    }
    if (form) {
      mostrarFeedback(form, texto, "erro");
    } else {
      window.alert(texto);
    }
  });

  document.body.addEventListener("htmx:sendError", function (evt) {
    var elt = evt.detail && evt.detail.elt;
    var form = elt && elt.closest ? elt.closest("form") : null;
    mostrarFeedback(form, "Sem conexão com o servidor. Nada foi gravado.", "erro");
  });
})();
