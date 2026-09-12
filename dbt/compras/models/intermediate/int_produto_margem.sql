-- ─────────────────────────────────────────────────────────────────────────────
-- int_produto_margem — colunas CF a DC da aba `pedido` (menos as de alerta),
-- mais O, P, DP e DQ. Margem do preco de venda ATUAL, atacado e varejo.
--
-- Gabarito: docs/gabarito_pedido_formulas.txt. Mapa coluna a coluna:
--   CF PV_ATACADO                    dCadastroTI!$AB, vazio -> 0
--   CG MKP_ATACADO                   $CF2 / $BY2
--   CH MARGEM_ST_s/VALOR             cenario 1 - aliq CB, custo ($BV2+$BX2)
--   CI MARGEM_OFICIAL                cenario 2 - aliq CA, custo $BY2
--   CJ MARGEM_SEM_RED                cenario 3 - aliq CB, custo $BY2
--   CK GAP_FILIAL_pp                 ($CI2-$CJ2)*100
--   CM DIF_MC_pp                     ($CI2-$CH2)*100
--   O  NIVEL_BASE_MARGEM             faixa de $CJ2 contra os dois limiares
--   P  NIVEL_MARGEM                  O, agravado em 1 fora da curva A
--   CW PV_VAREJO                     dCadastroTI!$AC, vazio -> 0
--   CX MKP_VAREJO                    $CW2 / $BY2
--   CY MARGEM_ST_s/VALOR_VAREJO      cenario 1 - aliq CB, custo ($BV2+$BX2)
--   CZ MARGEM_SEM_RED_VAREJO         cenario 3 - aliq CB, custo $BY2
--   DA GAP_FILIAL_VAREJO_pp          ($CY2-$CZ2)*100
--   DC DIF_MC_VAREJO_pp              ($CY2-$CZ2)*100   <- identica a DA
--   DP NIVEL_BASE_MARGEM_VAREJO      faixa de $CZ2
--   DQ NIVEL_MARGEM_VAREJO           DP, agravado em 1 fora da curva A
-- (CL e DB, os CHECK_MARGEM_INSTAVEL*, sao da leva de alertas e leem P/DQ
-- daqui por ref(); CN..CV e DD..DJ, os precos sugeridos, sao de
-- int_produto_preco_sugerido.)
--
-- Grao: 1 linha por SKU. Espinha = int_produto_custo (= o cadastro inteiro).
--
-- ── A formula, uma so' para os cinco cenarios ───────────────────────────────
-- PDF 9.1:  margem = (PV - PV x (aliq_icms + piscof + comissao) - custo) / PV
-- Os cenarios NAO tem formulas diferentes. Eles diferem em exatamente DUAS
-- escolhas, e e' so' isso:
--
--   cenario         | aliquota de ICMS      | base de custo
--   ----------------|-----------------------|---------------------------
--   ST s/Valor (CH) | CB  ICMS_SEM_RED      | BV + BX (s/valor + Ingrax)
--   Oficial    (CI) | CA  ICMS_SAIDA_EF     | BY (custo gerencial)
--   Sem Reducao(CJ) | CB  ICMS_SEM_RED      | BY (custo gerencial)
--   ST s/Val VAREJO | CB  ICMS_SEM_RED      | BV + BX
--   Sem Red  VAREJO | CB  ICMS_SEM_RED      | BY
--
-- PIS/COFINS ($BZ2) e comissao (Parametros!$B$4) sao os MESMOS nos cinco.
--
-- ── Por que o varejo tem DOIS cenarios e nao tres ──────────────────────────
-- PDF 8.2 e CONTEXTO.md regra 3: o beneficio de REDUCAO DE BASE de ICMS vale
-- so' para as filiais de atacado/distribuidora (02 e 09 na documentacao de
-- negocio; '2' e '9' no dado, VARCHAR2(2) sem zero a esquerda). As demais
-- filiais, que vendem no varejo, nao tem o beneficio - por isso NAO EXISTE
-- "MARGEM_OFICIAL_VAREJO": o cenario "Oficial" e' justamente o das filiais com
-- reducao, e ele nao se aplica a quem vende no varejo. Criar essa coluna por
-- simetria seria inventar um numero que a planilha nao tem.
-- ── ⚠ DIVERGENCIA DELIBERADA DO ARQUIVO EM referencia/ (CH e CY) ───────────
-- Decidido pelo Diretor de Compras em 21/08/2026 (PENDENCIAS_DIRETORIA.md,
-- item 1; CONTEXTO.md 6.4). O cenario "ST s/Valor" usava $CA2 = ICMS_SAIDA_EF,
-- a aliquota COM reducao de base. Isso era ERRO NA PLANILHA: o regime de
-- substituicao tributaria e' mecanica separada do BENEFICIO de reducao de
-- base, e um nao deve carregar o outro. CH e CY passam a usar $CB2 =
-- ICMS_SEM_RED, a aliquota cheia. O Diretor ja corrigiu a formula na planilha
-- dele e atualizou a secao 9.1 do PDF.
-- O xlsx em referencia/ e' a versao ANTERIOR a essa correcao, entao CH e CY
-- DIVERGEM DELE DE PROPOSITO - nao e' defeito de porte, e nao deve ser
-- "consertado" de volta.
-- Efeito medido: itens em regime ST (ST_SUBSTITUTO e ST_RECOLHIDO) nao mudam
-- em NENHUM SKU - CA e CB ja eram identicas em 100% deles, porque a maioria
-- dos itens ST nao tem reducao disponivel. Quem muda sao ~1.240 SKUs de
-- MODALIDADE = 'NORMAL'. Consequencia aritmetica: fora do regime ST, CH passa
-- a ser IDENTICA a CJ e CY identica a CZ (mesma aliquota; o que resta e' a
-- diferenca de base de custo, que fora do ST e' zero). Isso e' o esperado -
-- ali nao existe distincao real entre os dois cenarios.
-- ⚠ Divergencia so' registrada, esta continua reproduzida como na planilha:
-- DA e DC tem formulas IDENTICAS
-- (($CY2-$CZ2)*100). No atacado as duas irmas sao diferentes - CK compara
-- Oficial x Sem Reducao e CM compara Oficial x ST s/Valor. Como o varejo nao
-- tem "Oficial", as duas colapsaram na mesma conta. Reproduzido como esta.
--
-- ── O "" do Excel, coluna a coluna ─────────────────────────────────────────
-- Toda margem comeca com `IF(OR($CF2=0, <custo>="", <aliquota>="", $BZ2=""),
-- "", ...)`. Sao quatro portas, e cada uma tem um motivo distinto:
--   PV = 0        -> nao ha preco de venda cadastrado: margem nao existe (e,
--                    de quebra, e' o que impede a divisao por zero - o guarda
--                    e' do proprio gabarito, nao um remendo meu);
--   custo   vazio -> a cadeia de custo apagou (sem MVA ou sem nota - ver
--                    int_produto_custo);
--   aliquota vazia-> COD_ICMS nao achou linha em dICMS (os 5 SKUs com
--                    codst = 0 - CONTEXTO.md 6.2). E' aqui que a margem deles
--                    sai em branco, de proposito;
--   PISCOF_EF vazio-> COD_PISCOF nao achou linha em dPISCOFINS.
-- Note que CI e CJ testam $BW2 (custo OFICIAL) mas usam $BY2 (custo
-- GERENCIAL) na conta, e CH testa $BV2 e usa $BV2+$BX2. Como BY so' e' nulo
-- quando BW e' nulo, o teste e' equivalente - mas esta escrito como no
-- gabarito, coluna testada = coluna do gabarito, para a conferencia celula a
-- celula nao depender desse raciocinio.
--
-- ── CG/CX | MKP: o unico ponto com divisao por zero possivel ───────────────
-- `IF(OR($BW2="",$BW2=0),"",$CF2/$BY2)` testa BW e divide por BY. Se BW fosse
-- diferente de zero e BY zero, o Excel devolveria #DIV/0! sem IFERROR. Isso
-- exige BX = -BW, impossivel (BX >= 0 sempre, BW >= 0 sempre). O
-- nullif(...,0) esta ali porque em Oracle divisao por zero e' ERRO DE
-- EXECUCAO (ORA-01476), nao uma celula com #DIV/0!: sem ele, o dia em que
-- essa combinacao aparecer o build inteiro cai. Com ele, sai NULL - que e'
-- como o validador ja le uma celula de erro do Excel.
--
-- ── O/P e DP/DQ | por que a margem vira NIVEL ──────────────────────────────
-- O = IF($CJ2="",0, IF($CJ2<0,3, IF($CJ2<B22,2, IF($CJ2<B21,1,0)))).
-- A escada e' avaliada do PIOR para o melhor e usa o PIOR CENARIO (CJ, sem
-- reducao) como base - nao a margem media nem a oficial. Os limiares sao
-- MARGEM_CRITICA_MIN (B22 = 5%) e MARGEM_ALERTA_MIN (B21 = 12%), os dois do
-- int_parametro. Margem em branco vira nivel 0, e nao "nivel maximo": SKU sem
-- tributacao mapeada nao dispara alerta de margem, dispara CHECK_TRIB.
-- P = IF(AND($AX2<>"A",$O2>0), MIN($O2+1,3), $O2): fora da curva A, um
-- problema de margem sobe UM degrau - o mesmo aperto de margem num item de
-- baixo giro e' pior, porque nao ha volume que o compense. O nivel nunca passa
-- de 3. P (e DQ) sao o que CL e DB traduzem em texto na leva de alertas.
-- ─────────────────────────────────────────────────────────────────────────────

with custo as (
    select * from {{ ref('int_produto_custo') }}
),

fiscal as (
    select * from {{ ref('int_produto_fiscal') }}
),

cadastro as (
    select * from {{ ref('int_cadastro_estoque') }}
),

classe_abc as (
    select * from {{ ref('int_produto_classe_abc') }}
),

parametro as (
    select * from {{ ref('int_parametro') }}
),

-- CF e CW, os dois precos de venda ATUAIS, e tudo que as cinco margens leem.
-- Reunidos numa CTE so' para que as formulas abaixo fiquem legiveis lado a
-- lado - a comparacao entre cenarios e' o ponto desta tabela.
entrada as (
    select
        c.codigo,
        nvl(cad.pv_atacado, 0)          as pv_atacado,     -- CF
        nvl(cad.pv_varejo,  0)          as pv_varejo,      -- CW
        f.icms_saida_ef,                                   -- CA (com reducao)
        f.icms_sem_red,                                    -- CB (cheia)
        f.piscof_ef,                                       -- BZ
        c.custo_tot_s_valor,                               -- BV
        c.custo_tot_oficial,                               -- BW
        c.custo_adicional_imagem,                          -- BX
        c.custo_tot_gerencial,                             -- BY
        abc.classe,                                        -- AX
        par.comissao,
        par.margem_alerta_min,
        par.margem_critica_min
      from custo c
      join fiscal f
        on f.codigo = c.codigo
      join cadastro cad
        on cad.codprod = c.codigo
      join classe_abc abc
        on abc.codigo = c.codigo
     cross join parametro par
),

-- As cinco margens e os dois markups. A partir daqui e' so' aritmetica sobre
-- estas colunas - por isso elas nascem juntas, numa passada.
margem as (
    select
        e.*,
        -- CG
        case when e.custo_tot_oficial is not null and e.custo_tot_oficial <> 0
             then e.pv_atacado / nullif(e.custo_tot_gerencial, 0)
        end                                                as mkp_atacado,
        -- CH | atacado, cenario ST s/Valor: aliquota CHEIA (correcao do
        -- Diretor de 21/08/2026 - ver cabecalho; era ICMS_SAIDA_EF), custo
        -- s/valor MAIS o ajuste Ingrax (que BV nao carrega)
        case when e.pv_atacado <> 0
              and e.custo_tot_s_valor is not null
              and e.icms_sem_red     is not null
              and e.piscof_ef        is not null
             then (  e.pv_atacado
                   - e.pv_atacado * (e.icms_sem_red + e.piscof_ef + e.comissao)
                   - (e.custo_tot_s_valor + e.custo_adicional_imagem)
                  ) / e.pv_atacado
        end                                                as margem_st_s_valor,
        -- CI | atacado, cenario Oficial: aliquota COM reducao (filiais 02/09),
        -- custo gerencial
        case when e.pv_atacado <> 0
              and e.custo_tot_oficial is not null
              and e.icms_saida_ef     is not null
              and e.piscof_ef         is not null
             then (  e.pv_atacado
                   - e.pv_atacado * (e.icms_saida_ef + e.piscof_ef + e.comissao)
                   - e.custo_tot_gerencial
                  ) / e.pv_atacado
        end                                                as margem_oficial,
        -- CJ | atacado, cenario Sem Reducao: aliquota CHEIA, custo gerencial.
        -- E' o PIOR cenario, e por isso a base de O/P.
        case when e.pv_atacado <> 0
              and e.custo_tot_oficial is not null
              and e.icms_sem_red      is not null
              and e.piscof_ef         is not null
             then (  e.pv_atacado
                   - e.pv_atacado * (e.icms_sem_red + e.piscof_ef + e.comissao)
                   - e.custo_tot_gerencial
                  ) / e.pv_atacado
        end                                                as margem_sem_red,
        -- CX
        case when e.custo_tot_oficial is not null and e.custo_tot_oficial <> 0
             then e.pv_varejo / nullif(e.custo_tot_gerencial, 0)
        end                                                as mkp_varejo,
        -- CY | varejo, cenario ST s/Valor. Aliquota CHEIA (correcao do Diretor
        -- de 21/08/2026 - ver cabecalho; era ICMS_SAIDA_EF). Agora coerente
        -- tambem com o PDF 8.2, que ja mandava o varejo usar sempre a cheia.
        case when e.pv_varejo <> 0
              and e.custo_tot_s_valor is not null
              and e.icms_sem_red      is not null
              and e.piscof_ef         is not null
             then (  e.pv_varejo
                   - e.pv_varejo * (e.icms_sem_red + e.piscof_ef + e.comissao)
                   - (e.custo_tot_s_valor + e.custo_adicional_imagem)
                  ) / e.pv_varejo
        end                                                as margem_st_s_valor_varejo,
        -- CZ | varejo, cenario Sem Reducao: a aliquota que o varejo de fato
        -- paga (PDF 8.2). Base de DP/DQ.
        case when e.pv_varejo <> 0
              and e.custo_tot_oficial is not null
              and e.icms_sem_red      is not null
              and e.piscof_ef         is not null
             then (  e.pv_varejo
                   - e.pv_varejo * (e.icms_sem_red + e.piscof_ef + e.comissao)
                   - e.custo_tot_gerencial
                  ) / e.pv_varejo
        end                                                as margem_sem_red_varejo
      from entrada e
),

-- Segunda passada: as comparacoes entre cenarios (CK, CM, DA, DC) e os niveis
-- de margem. O e DP nascem aqui, sozinhos, porque P e DQ os LEEM - reescrever
-- a escada de limiares dentro de P/DQ seria quatro copias da mesma regra para
-- divergirem no primeiro ajuste de limiar.
nivel as (
    select
        m.*,
        -- O | nivel base, do PIOR cenario de atacado (CJ). Limiares do
        -- int_parametro: nenhum 0,05 ou 0,12 escrito dentro do SQL.
        case when m.margem_sem_red is null                    then 0
             when m.margem_sem_red < 0                        then 3
             when m.margem_sem_red < m.margem_critica_min     then 2
             when m.margem_sem_red < m.margem_alerta_min      then 1
             else 0
        end                                                as nivel_base_margem,
        -- DP | mesmo criterio, sobre o pior cenario do VAREJO (CZ)
        case when m.margem_sem_red_varejo is null                 then 0
             when m.margem_sem_red_varejo < 0                     then 3
             when m.margem_sem_red_varejo < m.margem_critica_min  then 2
             when m.margem_sem_red_varejo < m.margem_alerta_min   then 1
             else 0
        end                                                as nivel_base_margem_varejo
      from margem m
),

final as (
    select
        n.codigo,
        n.nivel_base_margem,
        -- P | fora da curva A o problema de margem sobe UM degrau, teto 3
        case when n.classe <> 'A' and n.nivel_base_margem > 0
             then least(n.nivel_base_margem + 1, 3)
             else n.nivel_base_margem
        end                                                as nivel_margem,
        n.pv_atacado,
        n.mkp_atacado,
        n.margem_st_s_valor,
        n.margem_oficial,
        n.margem_sem_red,
        -- CK | quanto a reducao de base vale, em pontos percentuais de margem
        case when n.margem_oficial is not null and n.margem_sem_red is not null
             then (n.margem_oficial - n.margem_sem_red) * 100
        end                                                as gap_filial_pp,
        -- CM | Oficial x ST s/Valor, em pp de margem. Desde a correcao de
        -- 21/08/2026 os dois cenarios diferem em DUAS coisas (aliquota e base
        -- de custo), nao so' na base - o numero segue sendo o custo de sair do
        -- cenario Oficial para o cenario ST s/Valor, que e' o que a coluna diz.
        case when n.margem_st_s_valor is not null and n.margem_oficial is not null
             then (n.margem_oficial - n.margem_st_s_valor) * 100
        end                                                as dif_mc_pp,
        n.pv_varejo,
        n.mkp_varejo,
        n.margem_st_s_valor_varejo,
        n.margem_sem_red_varejo,
        -- DA
        case when n.margem_st_s_valor_varejo is not null
              and n.margem_sem_red_varejo    is not null
             then (n.margem_st_s_valor_varejo - n.margem_sem_red_varejo) * 100
        end                                                as gap_filial_varejo_pp,
        -- DC | formula IDENTICA a DA no gabarito - ver cabecalho
        case when n.margem_st_s_valor_varejo is not null
              and n.margem_sem_red_varejo    is not null
             then (n.margem_st_s_valor_varejo - n.margem_sem_red_varejo) * 100
        end                                                as dif_mc_varejo_pp,
        n.nivel_base_margem_varejo,
        -- DQ | mesmo agravamento de P, no varejo
        case when n.classe <> 'A' and n.nivel_base_margem_varejo > 0
             then least(n.nivel_base_margem_varejo + 1, 3)
             else n.nivel_base_margem_varejo
        end                                                as nivel_margem_varejo
      from nivel n
)

select * from final
