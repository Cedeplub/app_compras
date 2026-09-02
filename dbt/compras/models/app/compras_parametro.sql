-- ─────────────────────────────────────────────────────────────────────────────
-- COMPRAS_PARAMETRO — os parâmetros do modelo que a TELA precisa conhecer.
-- Grão: 1 linha, larga (o mesmo formato de int_parametro).
--
-- Por que existe: o protótipo .jsx chumba três constantes no código —
-- FATOR_PRAZO_ATACADO = 1.0317, FATOR_PRAZO_VAREJO = 1.086435 e COMISSAO = 0.04
-- (PROTOTIPO.md §4.6). São os mesmos números que já vivem em seed_parametros e
-- que o dbt usa para calcular margem e preço sugerido. Deixá-los duplicados no
-- front cria o pior defeito possível neste sistema: a tela calcula a margem com
-- 4% enquanto o banco calcula com outro valor, ninguém vê diferença de forma, e
-- o preço sai errado com aparência de certo.
--
-- Esta é uma camada de CONTRATO: só entra o que a tela usa, e renomear coluna
-- aqui quebra o dashboard. int_parametro tem 20 colunas; a tela precisa destas.
-- ─────────────────────────────────────────────────────────────────────────────

with parametro as (
    select * from {{ ref('int_parametro') }}
),

-- ⚠ O mês de referência sai do DADO (max(mes) da série mensal), não de
-- `sysdate`. A tela usa isto para rotular as barras do mini-gráfico de venda
-- com o nome do mês — "ago/26" em vez de "M-1", que obriga o comprador a contar
-- de cabeça. Se o rótulo viesse do relógio do dispositivo, um build atrasado
-- faria a tela nomear como "setembro" uma barra que é de agosto: o pior tipo de
-- erro, porque o número está certo e só o nome mente.
referencia as (
    select max(mes) as mes_referencia from {{ ref('int_venda_mensal') }}
),

final as (
    select
        -- usados na fórmula de margem que a tela refaz a cada tecla digitada
        p.pis_cofins                as PIS_COFINS,
        p.comissao                  as COMISSAO,

        -- "a prazo" = "à vista" x fator. Vêm prontos da tabela de vendas do
        -- Winthor, definidos pela diretoria; não são cálculo de juros feito
        -- aqui (PROTOTIPO.md §5, confirmado com o Diretor de Compras).
        p.fator_prazo               as FATOR_PRAZO_ATACADO,
        p.fator_prazo_varejo        as FATOR_PRAZO_VAREJO,

        -- margem alvo quando ninguém decidiu ainda, e os limiares que a tela
        -- usa para pintar de vermelho
        p.margem_alvo_padrao        as MARGEM_ALVO_PADRAO,
        p.margem_alerta_min         as MARGEM_ALERTA_MIN,
        p.margem_critica_min        as MARGEM_CRITICA_MIN,

        -- cobertura: alvo padrão quando o departamento não tem regra
        p.cobertura_alvo_padrao     as COBERTURA_ALVO_PADRAO,

        -- O protótipo pinta a cobertura de vermelho quando
        -- `mesesCobertura < coberturaAlvo * 0,6`, com o 0,6 repetido como número
        -- mágico em 3 lugares (PROTOTIPO.md §5/§9). É regra de negócio de
        -- verdade — limiar de alerta visual —, então virou linha de
        -- seed_parametros com o mesmo valor. Quando a diretoria quiser 0,5,
        -- muda no CSV e roda `dbt seed`; nada de código.
        p.cobertura_critica_fracao  as COBERTURA_CRITICA_FRACAO,

        r.mes_referencia            as MES_REFERENCIA
      from parametro p
     cross join referencia r
)

select * from final
