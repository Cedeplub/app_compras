--------------------------------------------------------------------------------
-- 03_tabelas_pedido.sql
--
-- Etapa 9 do ciclo v2 (v2/PLANO.md §2.4, §"Etapa 9"): cria a entidade "pedido"
-- que hoje não existe no banco. APP_DECISAO_PEDIDO (02_tabelas_app.sql) tem PK
-- em ID_PRODUTO e por isso só guarda "a última quantidade decidida por SKU" —
-- gravar de novo sobrescreve. Não agrupa itens, não tem fornecedor dono, não
-- tem status, não tem histórico. Este script cria as três tabelas que faltam:
-- APP_PEDIDO (o cabeçalho), APP_PEDIDO_ITEM (as linhas) e
-- APP_PEDIDO_STATUS_HIST (o rastro da máquina de estados).
--
-- Mesmas convenções de 02_tabelas_app.sql, não repetidas aqui em detalhe:
-- idempotente via checagem em USER_TABLES/USER_INDEXES antes de criar; colunas
-- de chave técnica em GENERATED ALWAYS AS IDENTITY (nunca BY DEFAULT, ver o
-- porquê no cabeçalho de 02_tabelas_app.sql); rodar conectado como COMPRAS;
-- evolução de schema depois de publicado é ALTER em script de migração à
-- parte, nunca editando este arquivo.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 1. APP_PEDIDO — cabeçalho do pedido de compra.
--
-- DONO DO PEDIDO: FORNECEDOR (varchar2, texto do departamento — igual a
-- COMPRAS_PEDIDO.FORNECEDOR/dim_produto.fornecedor). Não existe id numérico de
-- departamento em lugar nenhum do modelo (confirmado em
-- dbt/compras/models/marts/dim_produto.sql e schema.yml: FORNECEDOR é sempre o
-- texto do PCDEPTO, "regra 7" do CONTEXTO.md) — inventar uma FK para uma
-- entidade que não existe seria pior que gravar o texto direto. Um pedido é
-- sempre de UM fornecedor/departamento (PROTOTIPO.md §2.4 e §5, "Um pedido
-- salvo por fornecedor" — exigência do formato de importação da rotina 220 do
-- Winthor): salvar um carrinho com itens de departamentos diferentes cria um
-- APP_PEDIDO por departamento, isso é responsabilidade da aplicação na hora do
-- INSERT, não deste schema.
--
-- STATUS é a máquina de estados linear e reversível do protótipo (§2.5):
-- Rascunho -> Orçamento Enviado -> Fechado -> Exportado, um passo por vez, com
-- desfazer simétrico de um passo. O CHECK abaixo garante só o domínio de
-- valores válidos — a ORDEM da transição (não pular etapa, não voltar dois)
-- é responsabilidade da aplicação, registrada em APP_PEDIDO_STATUS_HIST; um
-- CHECK não consegue expressar "depende do valor anterior" sem trigger, e o
-- projeto prefere manter essa lógica em Python e auditável (mesmo raciocínio
-- do comentário de APP_USUARIO.ativo em 02_tabelas_app.sql: regra de negócio
-- fica no app, não em trigger).
--
-- Editável só em Rascunho/Orçamento Enviado (campo vira texto em
-- Fechado/Exportado): também é regra de tela, não de banco — não há CHECK nem
-- trigger impedindo UPDATE nos itens de um pedido Fechado, pela mesma razão
-- acima. O schema não finge arbitrar uma regra de UI.
--------------------------------------------------------------------------------
declare
    v_existe number;
begin
    select count(*) into v_existe from user_tables where table_name = 'APP_PEDIDO';
    if v_existe = 0 then
        execute immediate q'[
            create table app_pedido (
                id_pedido       number          generated always as identity,
                fornecedor      varchar2(60)    not null,
                status          varchar2(30)    default 'Rascunho' not null,
                criado_em       timestamp       default systimestamp not null,
                criado_por      varchar2(60)    not null,
                atualizado_em   timestamp       default systimestamp not null,
                atualizado_por  varchar2(60)    not null,
                constraint pk_app_pedido primary key (id_pedido),
                constraint ck_app_pedido_status
                    check (status in ('Rascunho', 'Orçamento Enviado', 'Fechado', 'Exportado'))
            )
        ]';
    end if;
end;
/

declare
    v_existe number;
begin
    select count(*) into v_existe from user_indexes where index_name = 'IX_APP_PEDIDO_STATUS';
    if v_existe = 0 then
        execute immediate
            'create index ix_app_pedido_status on app_pedido (status)';
    end if;
end;
/

declare
    v_existe number;
begin
    select count(*) into v_existe from user_indexes where index_name = 'IX_APP_PEDIDO_FORNECEDOR';
    if v_existe = 0 then
        execute immediate
            'create index ix_app_pedido_fornecedor on app_pedido (fornecedor)';
    end if;
end;
/

comment on table app_pedido is
    'Cabeçalho de um pedido de compra: um fornecedor/departamento, um status, um autor. Substitui o modelo antigo (APP_DECISAO_PEDIDO, PK em ID_PRODUTO, uma linha por SKU sem agrupamento) para as telas de Pedidos Salvos do v2 (PROTOTIPO.md §2.4-2.8). Sempre de UM fornecedor só (exigência do formato de importação Winthor, rotina 220): a aplicação cria um APP_PEDIDO por departamento presente no carrinho ao salvar, nunca um pedido com fornecedores misturados.';
comment on column app_pedido.id_pedido is
    'Chave técnica sequencial (IDENTITY, GENERATED ALWAYS — nunca aceita id explícito em uso normal, mesmo padrão de APP_DECISAO_PRECO_HIST.id_hist).';
comment on column app_pedido.fornecedor is
    'Dono do pedido: o texto do departamento (equivalente a COMPRAS_PEDIDO.FORNECEDOR / dim_produto.fornecedor — CONTEXTO.md regra 7). Não é o fornecedor legal da nota fiscal (esse é numérico, CODFORNEC, e não existe neste modelo). Sem FK: não há tabela de departamentos no schema COMPRAS, e a lista de departamentos válidos já é validada no dbt/seed antes de chegar à tela.';
comment on column app_pedido.status is
    'Um de 4 valores válidos (CHECK ck_app_pedido_status), na ordem Rascunho -> Orçamento Enviado -> Fechado -> Exportado (PROTOTIPO.md §2.5). O CHECK só garante o domínio; a sequência da transição (um passo por vez, desfazer simétrico) é responsabilidade da aplicação e fica registrada, passo a passo, em APP_PEDIDO_STATUS_HIST.';
comment on column app_pedido.criado_em is
    'Timestamp de criação do pedido (equivalente a p.dataCriacao do protótipo — lá era a string fixa "28/08/26"; aqui é a data real).';
comment on column app_pedido.criado_por is
    'Login (APP_USUARIO.login) de quem salvou o carrinho que originou este pedido.';
comment on column app_pedido.atualizado_em is
    'Timestamp da última gravação neste cabeçalho (edição de item ou mudança de status). Não é tocado por INSERT/DELETE em APP_PEDIDO_ITEM que a aplicação não trate explicitamente como "toque no pedido".';
comment on column app_pedido.atualizado_por is
    'Login de quem fez a última alteração no pedido (edição ou mudança de status).';

--------------------------------------------------------------------------------
-- 2. APP_PEDIDO_ITEM — as linhas do pedido: produto, quantidade, preço.
--
-- CHAVE: (ID_PEDIDO, ID_PRODUTO), natural e composta — um produto aparece no
-- máximo uma vez por pedido. Isso é o que a tela "Adicionar produtos" já
-- assume (PROTOTIPO.md §2.7: "mescla no itens local (por código — quem já
-- existia é atualizado, quem é novo é acrescentado)"); a PK apenas torna essa
-- regra impossível de violar por acidente, sem precisar de um id técnico que
-- ninguém usaria.
--
-- QUANTIDADE congela a mesma decisão de projeto que APP_DECISAO_PEDIDO já
-- tomou (02_tabelas_app.sql, tabela 3, MELHORIA A5): PEDIDO é digitado na
-- unidade de EXIBIÇÃO (caixa, se o fornecedor é MASTER; unidade, senão -
-- PROTOTIPO.md §5 "calcularSugestaoPedido"), e a conversão pra unidades reais
-- (o que entra na coluna "quantidade" do arquivo Winthor - §5 "Regra de
-- exportação Winthor") depende de FATOR_EXIBICAO, que mora no cadastro do
-- produto/fornecedor e MUDA com o tempo. Um pedido Fechado ou Exportado é uma
-- decisão já tomada; se a linha só guardasse QUANTIDADE e a aplicação lesse o
-- fator atual do cadastro na hora de exportar, uma mudança de cadastro depois
-- do fechamento alteraria em silêncio a quantidade que vai pro Winthor da
-- mesma forma que alteraria APP_DECISAO_PEDIDO. Por isso o item também guarda
-- FATOR_EXIBICAO, congelado no instante em que a linha foi criada/atualizada:
-- quantidade em unidades = QUANTIDADE x FATOR_EXIBICAO, sempre lidos juntos
-- desta mesma linha.
--
-- PRECO_UNITARIO nasce de p.custoGerencial (PROTOTIPO.md §3.7) mas é editável
-- em tela enquanto o pedido está em Rascunho/Orçamento Enviado; é ele, não um
-- preço recalculado depois, que vai pra exportação Winthor. Por isso não há
-- FK nem lookup para nenhuma tabela de preço vigente: o valor é a própria
-- decisão, gravado aqui.
--
-- FK PARA APP_PEDIDO com ON DELETE CASCADE: um item nunca existe sem o
-- pedido dono, e "Excluir pedido" (§2.5, sem tela de confirmação hoje) precisa
-- remover as linhas junto — não faria sentido a aplicação orquestrar dois
-- DELETEs manualmente para um relacionamento que é sempre 1:N de posse total.
--
-- SEM FK para o catálogo de produtos (ID_PRODUTO = CODPROD do CEDEP): mesma
-- fronteira de projeto que já vale para APP_DECISAO_PRECO/APP_DECISAO_PEDIDO
-- (CONTEXTO.md §2, nada de schema cruzando pro CEDEP) e mesma razão de
-- negócio — um produto pode sair do catálogo (descontinuado) depois que o
-- pedido foi fechado/exportado, e o item precisa continuar existindo como
-- registro histórico do que foi decidido e enviado, mesmo que o produto não
-- exista mais para pedidos novos.
--------------------------------------------------------------------------------
declare
    v_existe number;
begin
    select count(*) into v_existe from user_tables where table_name = 'APP_PEDIDO_ITEM';
    if v_existe = 0 then
        execute immediate q'[
            create table app_pedido_item (
                id_pedido       number          not null,
                id_produto      number(10)      not null,
                quantidade      number(14,4)    not null,
                fator_exibicao  number(14,6)    not null,
                preco_unitario  number(14,4)    not null,
                criado_em       timestamp       default systimestamp not null,
                constraint pk_app_pedido_item primary key (id_pedido, id_produto),
                constraint fk_app_pedido_item_pedido foreign key (id_pedido)
                    references app_pedido (id_pedido) on delete cascade,
                constraint ck_app_pedido_item_qtd check (quantidade > 0),
                constraint ck_app_pedido_item_fat check (fator_exibicao > 0),
                constraint ck_app_pedido_item_prc check (preco_unitario > 0)
            )
        ]';
    end if;
end;
/

comment on table app_pedido_item is
    'Linhas de um pedido: produto, quantidade (unidade de exibição) e preço unitário. Uma linha por (ID_PEDIDO, ID_PRODUTO) — adicionar o mesmo produto de novo ao mesmo pedido atualiza a linha existente, é a aplicação (PROTOTIPO.md §2.7) que decide, nunca duplica. Apagada junto com o pedido (ON DELETE CASCADE em ID_PEDIDO); zerar a quantidade em tela remove a linha (não existe linha com quantidade 0, CHECK ck_app_pedido_item_qtd).';
comment on column app_pedido_item.id_pedido is
    'FK para APP_PEDIDO. ON DELETE CASCADE: item nunca existe sem o pedido dono.';
comment on column app_pedido_item.id_produto is
    'CODPROD do CEDEP. Sem FK física (fronteira do projeto, CONTEXTO.md §2) e de propósito: um produto pode sair do catálogo depois que o pedido foi fechado/exportado, e o item precisa sobreviver como registro histórico do que foi decidido.';
comment on column app_pedido_item.quantidade is
    'Quantidade digitada pelo comprador, na unidade de EXIBIÇÃO do produto (caixa fechada se o fornecedor é MASTER, unidade senão — PROTOTIPO.md §5), não a unidade real de estoque. CHECK > 0: quantidade zero não é gravada, é removida da linha pela aplicação (onBlur/botão remover, §2.6). Para a quantidade em unidades reais (o que vai na exportação Winthor), multiplicar por FATOR_EXIBICAO desta mesma linha.';
comment on column app_pedido_item.fator_exibicao is
    'Snapshot do fator de conversão (EMBAL_COMPRA quando o fornecedor é MASTER, senão 1) vigente no instante em que esta linha foi gravada/atualizada — mesmo raciocínio e mesma necessidade de congelamento que APP_DECISAO_PEDIDO.fator_exibicao (02_tabelas_app.sql, MELHORIA A5): recalcular com o fator atual do cadastro depois que o pedido foi fechado/exportado mudaria em silêncio uma quantidade já enviada ao Winthor. CHECK > 0.';
comment on column app_pedido_item.preco_unitario is
    'Preço unitário decidido para este item (nasce de custoGerencial no momento em que o produto entra no pedido — PROTOTIPO.md §3.7 — e é editável em tela enquanto o pedido está em Rascunho/Orçamento Enviado). É este valor, não um preço recalculado depois, que vai na coluna de preço do arquivo de exportação Winthor. CHECK > 0.';
comment on column app_pedido_item.criado_em is
    'Timestamp em que esta linha foi gravada pela última vez (inclusão do produto no pedido, ou atualização de quantidade/preço/fator via "Adicionar produtos"/edição de detalhe).';

--------------------------------------------------------------------------------
-- 3. APP_PEDIDO_STATUS_HIST — o caminho percorrido pela máquina de estados.
--
-- A máquina é REVERSÍVEL (Rascunho <-> Orçamento Enviado <-> Fechado <->
-- Exportado, um passo de cada vez), então STATUS em APP_PEDIDO sozinho não
-- conta a história: não dá pra saber, só olhando o status atual, se um pedido
-- em "Orçamento Enviado" chegou ali avançando do Rascunho ou voltando do
-- Fechado. Esta tabela é o único lugar onde esse caminho fica registrado —
-- por isso guarda o par (STATUS_ANTERIOR, STATUS_NOVO) e não só o novo valor.
--
-- STATUS_ANTERIOR é NULLABLE: a primeira linha do histórico de um pedido é a
-- própria criação (nasce em Rascunho), sem "de onde veio".
--
-- FK PARA APP_PEDIDO com ON DELETE CASCADE, mesma razão de APP_PEDIDO_ITEM:
-- histórico de status de um pedido que não existe mais não tem valor de
-- auditoria isolado (diferente de APP_AUDITORIA, que é a trilha geral do
-- dashboard e sobrevive à exclusão do que auditou — aqui o rastro É sobre
-- este pedido específico, não faz sentido preservá-lo órfão).
--------------------------------------------------------------------------------
declare
    v_existe number;
begin
    select count(*) into v_existe from user_tables where table_name = 'APP_PEDIDO_STATUS_HIST';
    if v_existe = 0 then
        execute immediate q'[
            create table app_pedido_status_hist (
                id_hist          number          generated always as identity,
                id_pedido        number          not null,
                status_anterior  varchar2(30),
                status_novo      varchar2(30)    not null,
                alterado_em      timestamp       default systimestamp not null,
                alterado_por     varchar2(60)    not null,
                constraint pk_app_pedido_status_hist primary key (id_hist),
                constraint fk_app_pedido_hist_pedido foreign key (id_pedido)
                    references app_pedido (id_pedido) on delete cascade,
                constraint ck_app_pedido_hist_ant
                    check (status_anterior in ('Rascunho', 'Orçamento Enviado', 'Fechado', 'Exportado')),
                constraint ck_app_pedido_hist_nov
                    check (status_novo in ('Rascunho', 'Orçamento Enviado', 'Fechado', 'Exportado')),
                constraint ck_app_pedido_hist_dif
                    check (status_anterior is null or status_anterior <> status_novo)
            )
        ]';
    end if;
end;
/

declare
    v_existe number;
begin
    select count(*) into v_existe from user_indexes where index_name = 'IX_APP_PEDIDO_HIST_PEDIDO';
    if v_existe = 0 then
        execute immediate
            'create index ix_app_pedido_hist_pedido on app_pedido_status_hist (id_pedido, alterado_em)';
    end if;
end;
/

comment on table app_pedido_status_hist is
    'Todo passo da máquina de estados de um pedido (Rascunho -> Orçamento Enviado -> Fechado -> Exportado, reversível um passo por vez). Nunca é alterada nem apagada pela aplicação — só cresce, exceto pelo ON DELETE CASCADE quando o próprio pedido é excluído. É o único lugar do banco onde se sabe se um pedido chegou ao status atual avançando ou voltando.';
comment on column app_pedido_status_hist.id_hist is
    'Chave técnica sequencial (IDENTITY, GENERATED ALWAYS), sem significado de negócio.';
comment on column app_pedido_status_hist.id_pedido is
    'FK para APP_PEDIDO. ON DELETE CASCADE: histórico de status de um pedido excluído não tem valor isolado (diferente de APP_AUDITORIA, que é a trilha geral do dashboard).';
comment on column app_pedido_status_hist.status_anterior is
    'Status de onde o pedido saiu nesta transição. NULL só na primeira linha de cada pedido (a criação, que nasce em Rascunho sem "de onde veio"). CHECK no mesmo domínio de 4 valores de APP_PEDIDO.status.';
comment on column app_pedido_status_hist.status_novo is
    'Status para onde o pedido foi nesta transição (avanço ou desfazer — os dois usam esta mesma tabela, a direção se infere comparando com STATUS_ANTERIOR). CHECK no mesmo domínio de 4 valores de APP_PEDIDO.status. CHECK ck_app_pedido_hist_dif garante que toda linha represente uma mudança real.';
comment on column app_pedido_status_hist.alterado_em is
    'Timestamp da transição.';
comment on column app_pedido_status_hist.alterado_por is
    'Login (APP_USUARIO.login) de quem avançou ou desfez o status.';
