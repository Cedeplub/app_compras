--------------------------------------------------------------------------------
-- 05_tabelas_lote_preco.sql
--
-- Etapa 12 do ciclo v2 (v2/PROMPT_ETAPA_12_PRECOS_DEFINIDOS.md §4, §5): cria a
-- entidade "lote de preços" que hoje não existe no banco. APP_DECISAO_PRECO
-- tem PK em ID_PRODUTO e por isso só guarda "o último preço decidido por
-- SKU" — gravar de novo sobrescreve. Não agrupa itens, não tem dono, não tem
-- status, não tem caminho até quem digita o preço no Winthor (rotina 201).
-- Mesmo impasse que a antiga APP_DECISAO_PEDIDO tinha antes da Etapa 9, e
-- mesma resposta (§4.1): entidade nova, a antiga intacta. APP_DECISAO_PRECO e
-- APP_DECISAO_PRECO_HIST não são tocadas por este script — continuam sendo o
-- que volta para o modelo no próximo dbt run (CONTEXTO.md §6 regra 10); o
-- lote é o que sai da diretoria em direção a quem digita no Winthor.
--
-- Este script cria as três tabelas que faltam: APP_LOTE_PRECO (o cabeçalho),
-- APP_LOTE_PRECO_ITEM (as linhas, com o snapshot "de -> para" por canal) e
-- APP_LOTE_PRECO_STATUS_HIST (o rastro da máquina de estados).
--
-- Mesmas convenções de 02_tabelas_auth.sql, 03_tabelas_decisao.sql e
-- 04_tabelas_pedido.sql, não repetidas aqui em detalhe: idempotente via
-- checagem em USER_TABLES/USER_INDEXES antes de criar; colunas de chave
-- técnica em GENERATED ALWAYS AS IDENTITY (nunca BY DEFAULT); rodar
-- conectado como COMPRAS; evolução de schema depois de publicado é ALTER em
-- script de migração à parte, nunca editando este arquivo.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 1. APP_LOTE_PRECO — cabeçalho do lote de preços.
--
-- STATUS é a máquina de estados do lote — só dois valores graváveis:
-- Rascunho -> Enviado (ajuste de 2026-09-10, decisão do usuário posterior à
-- Etapa 12: não há usuário no app para quem aplica o preço no Winthor, então
-- ninguém dá o clique de "marcar aplicado no Winthor"; a resposta foi que ninguém deveria
-- dar esse clique). "Aplicado" NÃO é um terceiro valor do domínio — é uma
-- CONCLUSÃO MEDIDA, por item, comparando PV_*_NOVO (APP_LOTE_PRECO_ITEM) com
-- COMPRAS_PEDIDO.PV_ATACADO/PV_VAREJO na leitura (join, tolerância 0,005,
-- sem tabela nova, §4.5). A lista de lotes mostra "12 de 15 aplicados"; essa
-- afirmação não é gravada em lugar nenhum, nem aqui nem em
-- APP_LOTE_PRECO_STATUS_HIST. Contrapartida honesta dessa escolha: a
-- conferência tem a idade do último build do dbt — um preço aplicado às 10h
-- aparece como pendente até a carga seguinte.
--
-- Um lote em Rascunho acumula itens de várias chamadas do mesmo usuário
-- (§4.3: "Definir preços" sem idLote cria, com idLote acrescenta) — por isso
-- não há dono (usuário) nesta tabela: quem grava e quem lê já resolve isso
-- por CRIADO_POR, e a regra "um Rascunho por usuário" é da aplicação na hora
-- do INSERT (mesmo raciocínio de APP_PEDIDO quanto a "um pedido por
-- fornecedor" — regra de aplicação, não de banco).
--
-- OBSERVACAO é o recado livre do Diretor para quem digita no Winthor — por
-- exemplo, uma ressalva sobre um item que não entra no arquivo da 201 (§4.6).
--------------------------------------------------------------------------------
declare
    v_existe number;
begin
    select count(*) into v_existe from user_tables where table_name = 'APP_LOTE_PRECO';
    if v_existe = 0 then
        execute immediate q'[
            create table app_lote_preco (
                id_lote         number          generated always as identity,
                status          varchar2(20)    default 'Rascunho' not null,
                observacao      varchar2(400),
                criado_em       timestamp       default systimestamp not null,
                criado_por      varchar2(60)    not null,
                atualizado_em   timestamp       default systimestamp not null,
                atualizado_por  varchar2(60)    not null,
                constraint pk_app_lote_preco primary key (id_lote),
                constraint ck_app_lote_preco_status
                    check (status in ('Rascunho', 'Enviado'))
            )
        ]';
    end if;
end;
/

declare
    v_existe number;
begin
    select count(*) into v_existe from user_indexes where index_name = 'IX_APP_LOTE_PRECO_STATUS';
    if v_existe = 0 then
        execute immediate
            'create index ix_app_lote_preco_status on app_lote_preco (status)';
    end if;
end;
/

--------------------------------------------------------------------------------
-- UX_APP_LOTE_PRECO_RASCUNHO — NÃO é índice de performance. É a regra de
-- negócio "um lote em Rascunho por usuário" (§4.3) garantida NO BANCO,
-- porque o serviço sozinho não consegue: `app/servicos/lote_preco.py`
-- procura um Rascunho de CRIADO_POR com `select ... for update` antes de
-- decidir se cria ou acrescenta, mas Oracle não bloqueia linha que ainda não
-- existe. Com zero Rascunhos do usuário, duas requisições simultâneas leem
-- vazio, nenhuma tem o que travar, e as duas inserem — dois documentos onde
-- devia haver um, exatamente o defeito que a regra existe para impedir (dois
-- arquivos de importação para quem digita no Winthor). O `for update` só
-- serializa a partir do segundo lote; este índice cobre o primeiro, que é o
-- caso mais comum (primeiro clique do dia).
--
-- Índice único FUNCIONAL, não em CRIADO_POR direto: a expressão
-- `case when status = 'Rascunho' then criado_por end` só produz valor
-- não-nulo nas linhas em Rascunho. Oracle não indexa (e não checa unicidade
-- de) uma chave totalmente nula, então lotes Enviado ficam de fora do
-- índice e nunca conflitam entre si nem com um Rascunho — a regra vale só
-- para o estado que importa.
--
-- Se este CREATE UNIQUE INDEX falhar com ORA-01452/ORA-00001 numa base já
-- povoada, o dado NÃO permite o índice: existe hoje mais de um Rascunho do
-- mesmo CRIADO_POR. Não é para limpar isso por conta própria aqui — é para
-- parar e reportar, porque decidir qual dos Rascunhos duplicados sobrevive
-- é decisão de negócio (qual lote o Diretor queria), não de banco.
--
-- Nome com até 30 caracteres (limite de identificador Oracle 19c): o
-- backend (`app/servicos/lote_preco.py`) captura a violação ORA-00001 desta
-- corrida e reage acrescentando ao lote que venceu — identificado PELO NOME
-- deste índice, não por posição, então o nome abaixo é contrato entre banco
-- e aplicação.
--------------------------------------------------------------------------------
declare
    v_existe number;
begin
    select count(*) into v_existe from user_indexes where index_name = 'UX_APP_LOTE_PRECO_RASCUNHO';
    if v_existe = 0 then
        execute immediate q'[
            create unique index ux_app_lote_preco_rascunho
                on app_lote_preco (case when status = 'Rascunho' then criado_por end)
        ]';
    end if;
end;
/

--------------------------------------------------------------------------------
-- Migração idempotente — ajuste de 2026-09-10: este script já rodou em
-- produção com o domínio antigo de STATUS (3 valores, incluindo 'Aplicado').
-- O bloco "if v_existe = 0" acima pula o CREATE numa segunda execução, então
-- editar sozinho o texto do CREATE TABLE não muda a constraint que já está
-- no banco. Este bloco dropa e recria CK_APP_LOTE_PRECO_STATUS com o
-- domínio novo (2 valores) toda vez que o script roda. Quem instala do zero
-- nunca chega a ver o domínio antigo — o CREATE TABLE acima já nasce certo —
-- e não precisa deste bloco; quem já rodou o script precisa dele para a
-- migração acontecer. Mesmo raciocínio se repete mais abaixo para
-- CK_APP_LOTE_HIST_ANT e CK_APP_LOTE_HIST_NOV.
--------------------------------------------------------------------------------
begin
    execute immediate 'alter table app_lote_preco drop constraint ck_app_lote_preco_status';
exception
    when others then
        if sqlcode != -2443 then raise; end if;
end;
/

alter table app_lote_preco add constraint ck_app_lote_preco_status
    check (status in ('Rascunho', 'Enviado'));

comment on table app_lote_preco is
    'Cabeçalho do lote de preços: o documento que sai da decisão do Diretor em direção a quem digita no Winthor (rotina 201). Substitui, para esta finalidade, o modelo antigo (APP_DECISAO_PRECO, PK em ID_PRODUTO, uma linha por SKU sem agrupamento, sem status, sem documento) — PROMPT_ETAPA_12_PRECOS_DEFINIDOS.md §4.1. APP_DECISAO_PRECO/APP_DECISAO_PRECO_HIST continuam existindo e sendo gravadas junto (§4.2), este lote é a camada de cima.';
comment on column app_lote_preco.id_lote is
    'Chave técnica sequencial (IDENTITY, GENERATED ALWAYS — nunca aceita id explícito em uso normal, mesmo padrão de APP_PEDIDO.id_pedido).';
comment on column app_lote_preco.status is
    'Um de 2 valores válidos (CHECK ck_app_lote_preco_status): Rascunho (acumula itens, §4.3) e Enviado ("Marcar enviado", clique explícito, §4.3/§4.7). Não existe um terceiro valor "Aplicado" no domínio — decisão de desenho de 2026-09-10, não esquecimento nem simplificação: não há usuário no app para quem digita o preço no Winthor, e por isso ninguém dá esse clique; o app já tem como CONFERIR a aplicação de graça, comparando pv_*_novo de APP_LOTE_PRECO_ITEM com COMPRAS_PEDIDO.PV_ATACADO/PV_VAREJO (join, tolerância 0,005, §4.5). Um status clicável dizendo "já apliquei" conviveria, sem necessidade, com uma medição que já existe e tem mais lastro. Contrapartida honesta: essa conferência tem a idade do último build do dbt — um preço aplicado às 10h aparece pendente até a carga seguinte.';
comment on column app_lote_preco.observacao is
    'Recado livre do Diretor para quem digita os preços no Winthor — por exemplo, uma ressalva sobre item que não entra no arquivo de importação da rotina 201 e precisa de digitação manual (§4.6). Opcional.';
comment on column app_lote_preco.criado_em is
    'Timestamp de criação do lote (primeiro "Definir preços" sem idLote, ou o DecisaoSKU que abre um lote novo por não haver Rascunho do usuário, §4.2/§4.3).';
comment on column app_lote_preco.criado_por is
    'Login (APP_USUARIO.login) de quem criou o lote.';
comment on column app_lote_preco.atualizado_em is
    'Timestamp da última gravação neste cabeçalho (novo item acrescentado ao Rascunho, ou mudança de status).';
comment on column app_lote_preco.atualizado_por is
    'Login de quem fez a última alteração no lote.';

--------------------------------------------------------------------------------
-- 2. APP_LOTE_PRECO_ITEM — as linhas do lote: produto e preço "de -> para" por
-- canal (atacado, varejo).
--
-- CHAVE: (ID_LOTE, ID_PRODUTO), natural e composta — mesmo raciocínio de
-- APP_PEDIDO_ITEM (04_tabelas_pedido.sql): um produto aparece no máximo uma
-- vez no mesmo lote; acrescentar o mesmo produto de novo ao Rascunho é
-- responsabilidade da aplicação (atualizar a linha, não duplicar).
--
-- PV_*_ATUAL é SNAPSHOT, congelado no instante em que o item entra no lote —
-- não uma leitura ao vivo de COMPRAS_PEDIDO. Depois que o preço é aplicado no
-- Winthor e o próximo dbt run roda, COMPRAS_PEDIDO.PV_ATACADO/PV_VAREJO passa
-- a valer o preço NOVO; um "atual" lido ao vivo faria a coluna "de -> para" do
-- lote mostrar, depois de aplicado, "de R$ 66,00 para R$ 66,00" — mesmo
-- raciocínio do fator_exibicao congelado em APP_PEDIDO_ITEM (MELHORIA A5,
-- citado em §5 do prompt desta etapa).
--
-- PV_*_NOVO NULO significa "este canal não foi decidido neste item" — nunca
-- "manter o preço atual" (§4.4, divergência deliberada do protótipo do
-- Diretor). O arquivo de importação de cada canal (rotina 201) só traz os
-- itens com PV_*_NOVO não nulo naquele canal: reimportar um preço que
-- ninguém decidiu seria pedir, a quem digita no Winthor, uma alteração que ninguém pediu, e
-- reimportar valor igual ainda é alteração no histórico de preço do Winthor.
--
-- CHECK ck_app_lote_item_um garante que não existe item "vazio" (os dois
-- canais nulos) — todo item do lote decidiu pelo menos um canal.
--
-- FK PARA APP_LOTE_PRECO com ON DELETE CASCADE: mesma razão de
-- APP_PEDIDO_ITEM -> APP_PEDIDO, um item nunca existe sem o lote dono.
--
-- SEM FK para o catálogo de produtos (ID_PRODUTO = CODPROD do CEDEP): mesma
-- fronteira de projeto que já vale para APP_DECISAO_PRECO/APP_PEDIDO_ITEM
-- (CONTEXTO.md §2, nada de schema cruzando pro CEDEP), e mesma razão de
-- negócio: um produto pode sair do catálogo depois que o lote foi enviado, e
-- o item precisa continuar existindo como registro histórico do que foi
-- decidido.
--------------------------------------------------------------------------------
declare
    v_existe number;
begin
    select count(*) into v_existe from user_tables where table_name = 'APP_LOTE_PRECO_ITEM';
    if v_existe = 0 then
        execute immediate q'[
            create table app_lote_preco_item (
                id_lote          number          not null,
                id_produto       number(10)      not null,
                pv_atacado_atual number(14,4),
                pv_atacado_novo  number(14,4),
                pv_varejo_atual  number(14,4),
                pv_varejo_novo   number(14,4),
                criado_em        timestamp       default systimestamp not null,
                criado_por       varchar2(60)    not null,
                atualizado_em    timestamp       default systimestamp not null,
                atualizado_por   varchar2(60)    not null,
                constraint pk_app_lote_preco_item primary key (id_lote, id_produto),
                constraint fk_app_lote_item_lote foreign key (id_lote)
                    references app_lote_preco (id_lote) on delete cascade,
                constraint ck_app_lote_item_ata
                    check (pv_atacado_novo is null or pv_atacado_novo > 0),
                constraint ck_app_lote_item_var
                    check (pv_varejo_novo is null or pv_varejo_novo > 0),
                constraint ck_app_lote_item_um
                    check (pv_atacado_novo is not null or pv_varejo_novo is not null)
            )
        ]';
    end if;
end;
/

comment on table app_lote_preco_item is
    'Linhas de um lote de preços: produto e preço "de -> para" por canal (atacado, varejo). Uma linha por (ID_LOTE, ID_PRODUTO). Apagada junto com o lote (ON DELETE CASCADE em ID_LOTE). CHECK ck_app_lote_item_um garante que todo item decidiu ao menos um canal — não existe linha com os dois canais nulos.';
comment on column app_lote_preco_item.id_lote is
    'FK para APP_LOTE_PRECO. ON DELETE CASCADE: item nunca existe sem o lote dono.';
comment on column app_lote_preco_item.id_produto is
    'CODPROD do CEDEP. Sem FK física (fronteira do projeto, CONTEXTO.md §2) e de propósito: um produto pode sair do catálogo depois que o lote foi enviado, e o item precisa sobreviver como registro histórico do que foi decidido.';
comment on column app_lote_preco_item.pv_atacado_atual is
    'Snapshot de COMPRAS_PEDIDO.PV_ATACADO no instante em que o item entrou no lote — congelado, não lido ao vivo. Depois que o preço é aplicado no Winthor e o dbt reconstrói, PV_ATACADO passa a valer o preço novo; um "atual" ao vivo faria a coluna "de -> para" mostrar "de R$ 66,00 para R$ 66,00" (mesmo raciocínio de APP_PEDIDO_ITEM.fator_exibicao, MELHORIA A5). NULO apenas se o produto não tinha PV_ATACADO no banco no momento do snapshot.';
comment on column app_lote_preco_item.pv_atacado_novo is
    'Preço de atacado decidido pelo Diretor para este item. NULO significa "atacado não foi decidido neste item" (§4.4) — nunca "manter o preço atual". O arquivo de importação da rotina 201 para o canal atacado só inclui itens com esta coluna não nula. CHECK: quando não nulo, tem que ser > 0.';
comment on column app_lote_preco_item.pv_varejo_atual is
    'Snapshot de COMPRAS_PEDIDO.PV_VAREJO no instante em que o item entrou no lote — mesmo congelamento e mesmo motivo de pv_atacado_atual.';
comment on column app_lote_preco_item.pv_varejo_novo is
    'Preço de varejo decidido pelo Diretor para este item. NULO significa "varejo não foi decidido neste item" (§4.4) — nunca "manter o preço atual". O arquivo de importação da rotina 201 para o canal varejo só inclui itens com esta coluna não nula. CHECK: quando não nulo, tem que ser > 0. CHECK ck_app_lote_item_um exige que pv_atacado_novo ou esta coluna seja não nula.';
comment on column app_lote_preco_item.criado_em is
    'Timestamp em que este item entrou no lote.';
comment on column app_lote_preco_item.criado_por is
    'Login (APP_USUARIO.login) de quem incluiu este item no lote.';
comment on column app_lote_preco_item.atualizado_em is
    'Timestamp da última gravação nesta linha (por exemplo, decisão de um segundo canal acrescentada depois, enquanto o lote ainda está em Rascunho).';
comment on column app_lote_preco_item.atualizado_por is
    'Login de quem fez a última alteração nesta linha.';

--------------------------------------------------------------------------------
-- 3. APP_LOTE_PRECO_STATUS_HIST — o caminho percorrido pela máquina de
-- estados do lote.
--
-- Mesmo raciocínio de APP_PEDIDO_STATUS_HIST (04_tabelas_pedido.sql): o
-- status sozinho, em APP_LOTE_PRECO, não conta a história de como o lote
-- chegou lá — esta tabela é o único lugar onde o par (STATUS_ANTERIOR,
-- STATUS_NOVO) fica registrado.
--
-- STATUS_ANTERIOR é NULLABLE: a primeira linha do histórico de um lote é a
-- própria criação (nasce em Rascunho, sem "de onde veio").
--
-- FK PARA APP_LOTE_PRECO com ON DELETE CASCADE, mesma razão de
-- APP_PEDIDO_STATUS_HIST: histórico de status de um lote que não existe mais
-- não tem valor de auditoria isolado.
--------------------------------------------------------------------------------
declare
    v_existe number;
begin
    select count(*) into v_existe from user_tables where table_name = 'APP_LOTE_PRECO_STATUS_HIST';
    if v_existe = 0 then
        execute immediate q'[
            create table app_lote_preco_status_hist (
                id_hist          number          generated always as identity,
                id_lote          number          not null,
                status_anterior  varchar2(20),
                status_novo      varchar2(20)    not null,
                alterado_em      timestamp       default systimestamp not null,
                alterado_por     varchar2(60)    not null,
                constraint pk_app_lote_preco_hist primary key (id_hist),
                constraint fk_app_lote_hist_lote foreign key (id_lote)
                    references app_lote_preco (id_lote) on delete cascade,
                constraint ck_app_lote_hist_ant
                    check (status_anterior in ('Rascunho', 'Enviado')),
                constraint ck_app_lote_hist_nov
                    check (status_novo in ('Rascunho', 'Enviado')),
                constraint ck_app_lote_hist_dif
                    check (status_anterior is null or status_anterior <> status_novo)
            )
        ]';
    end if;
end;
/

declare
    v_existe number;
begin
    select count(*) into v_existe from user_indexes where index_name = 'IX_APP_LOTE_HIST_LOTE';
    if v_existe = 0 then
        execute immediate
            'create index ix_app_lote_hist_lote on app_lote_preco_status_hist (id_lote, alterado_em)';
    end if;
end;
/

--------------------------------------------------------------------------------
-- Migração idempotente — mesmo ajuste de 2026-09-10 e mesmo motivo do bloco
-- de migração de APP_LOTE_PRECO.status acima: esta tabela também já existe
-- em produção com o domínio antigo (3 valores). Como STATUS_NOVO/
-- STATUS_ANTERIOR só registram transições de APP_LOTE_PRECO.status, e esse
-- status nunca mais assume 'Aplicado' (item acima), o histórico também não
-- pode — do contrário o CHECK ficaria mais permissivo que a realidade que
-- ele descreve. Quem instala do zero não precisa deste bloco (o CREATE
-- acima já nasce com 2 valores); quem já rodou o script precisa.
--------------------------------------------------------------------------------
begin
    execute immediate 'alter table app_lote_preco_status_hist drop constraint ck_app_lote_hist_ant';
exception
    when others then
        if sqlcode != -2443 then raise; end if;
end;
/

begin
    execute immediate 'alter table app_lote_preco_status_hist drop constraint ck_app_lote_hist_nov';
exception
    when others then
        if sqlcode != -2443 then raise; end if;
end;
/

alter table app_lote_preco_status_hist add constraint ck_app_lote_hist_ant
    check (status_anterior in ('Rascunho', 'Enviado'));

alter table app_lote_preco_status_hist add constraint ck_app_lote_hist_nov
    check (status_novo in ('Rascunho', 'Enviado'));

comment on table app_lote_preco_status_hist is
    'Todo passo da máquina de estados de um lote de preços (Rascunho -> Enviado). Nunca é alterada nem apagada pela aplicação — só cresce, exceto pelo ON DELETE CASCADE quando o próprio lote é excluído. Não existe transição para "Aplicado" registrada aqui: desde 2026-09-10 isso é conclusão medida na leitura (join com COMPRAS_PEDIDO, §4.5), nunca um passo gravado — nem por clique humano, nem por processo automático.';
comment on column app_lote_preco_status_hist.id_hist is
    'Chave técnica sequencial (IDENTITY, GENERATED ALWAYS), sem significado de negócio.';
comment on column app_lote_preco_status_hist.id_lote is
    'FK para APP_LOTE_PRECO. ON DELETE CASCADE: histórico de status de um lote excluído não tem valor isolado.';
comment on column app_lote_preco_status_hist.status_anterior is
    'Status de onde o lote saiu nesta transição. NULL só na primeira linha de cada lote (a criação, que nasce em Rascunho sem "de onde veio"). CHECK no mesmo domínio de 2 valores de APP_LOTE_PRECO.status (Rascunho, Enviado) — não existe transição registrada para "Aplicado" (§4.5, comment da tabela).';
comment on column app_lote_preco_status_hist.status_novo is
    'Status para onde o lote foi nesta transição. CHECK no mesmo domínio de 2 valores de APP_LOTE_PRECO.status (Rascunho, Enviado). CHECK ck_app_lote_hist_dif garante que toda linha represente uma mudança real.';
comment on column app_lote_preco_status_hist.alterado_em is
    'Timestamp da transição.';
comment on column app_lote_preco_status_hist.alterado_por is
    'Login (APP_USUARIO.login) de quem alterou o status do lote. Nunca é preenchida por um processo automático de "aplicado" — essa conclusão não gera linha nesta tabela (§4.5, comment da tabela).';
