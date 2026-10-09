-- Testa que o ICMS de saída COM redução de base nunca supera o SEM redução.
--
-- Origem: o aviso de margem mínima pedido pelo Diretor de Compras em
-- 09/10/2026 (item 4). Ele pede o alerta "pelo pior cenário", e o pior cenário
-- precisa ser resolvido em DOIS lugares: na tela, que recebe a lista inteira
-- de cenários e calcula a menor margem; e no servidor, que resolve um só
-- cenário para a aplicação em lote (`contrato._cenario_pior`) porque a lista
-- não cabe nos 4.552 itens do filtro.
--
-- As duas resoluções só são equivalentes por causa desta desigualdade:
--
--   Oficial e Sem Redução usam o MESMO custo (`custo_tot_gerencial`). O que os
--   separa é a alíquota. Se `icms_saida_ef <= icms_sem_red`, então Oficial tem
--   SEMPRE margem maior ou igual — e NUNCA é o pior cenário. Aí o pior é
--   decidido só entre ST s/Valor e Sem Redução, que compartilham a alíquota e
--   se separam pelo custo: comparação que não depende do preço, e por isso
--   resolvível no servidor.
--
-- Se esta desigualdade cair, `_cenario_pior` passa a poder devolver um cenário
-- que não é o pior, e o aviso de margem CALA justamente onde deveria falar —
-- em silêncio, porque o número devolvido continua plausível. É o tipo de
-- defeito que só aparece quando alguém vende abaixo da margem e ninguém
-- entende por que a tela não avisou.
--
-- Medido em 09/10/2026: 0 violações em 4.553 ativos.
--
-- A desigualdade é fiscal, não empírica: redução de base de cálculo só
-- DIMINUI o imposto de saída. Um produto sem redução tem as duas colunas
-- iguais, e o `<=` é o que acomoda esse caso — a maioria.
--
-- Tolerância de 1e-6: as duas são NUMBER com mesma origem, então a folga é só
-- para resíduo de arredondamento, não para diferença de medida.

select
    codigo,
    icms_saida_ef,
    icms_sem_red,
    'ICMS com reducao MAIOR que sem reducao' as motivo
  from {{ ref('int_produto_fiscal') }}
 where icms_saida_ef is not null
   and icms_sem_red  is not null
   and icms_saida_ef > icms_sem_red + 0.000001
