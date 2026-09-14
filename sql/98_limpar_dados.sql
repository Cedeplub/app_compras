--------------------------------------------------------------------------------
-- 98_limpar_dados.sql
--
-- Apaga o CONTEUDO de todas as tabelas APP_* do schema COMPRAS, sem apagar a
-- ESTRUTURA. DELETE, propositalmente, NAO TRUNCATE e NAO DROP: quem roda uma
-- limpeza precisa poder errar e dar ROLLBACK. Este script NAO COMMITA
-- sozinho — o COMMIT (ou ROLLBACK) é decisão de quem executa, depois de
-- conferir o resultado.
--
-- ORDEM DAS FKs, filho antes do pai — DELETE respeita a mesma ordem que uma
-- FK sem ON DELETE CASCADE exigiria, mesmo nas tabelas que têm CASCADE (não
-- depender do CASCADE torna o script correto também contra um schema onde o
-- CASCADE tenha sido removido por engano):
--   1. APP_SESSAO              (FK -> APP_USUARIO, cascade)
--   2. APP_AUDITORIA           (FK -> APP_USUARIO, sem cascade)
--   3. APP_PEDIDO_ITEM         (FK -> APP_PEDIDO, cascade)
--   4. APP_PEDIDO_STATUS_HIST  (FK -> APP_PEDIDO, cascade)
--   5. APP_PEDIDO              (pai de 3 e 4)
--   6. APP_LOTE_PRECO_ITEM         (FK -> APP_LOTE_PRECO, cascade)
--   7. APP_LOTE_PRECO_STATUS_HIST  (FK -> APP_LOTE_PRECO, cascade)
--   8. APP_LOTE_PRECO              (pai de 6 e 7)
--   9. APP_DECISAO_PRECO_HIST (sem FK, mas logicamente filha da decisão vigente)
--  10. APP_DECISAO_PRECO      (sem FK)
--  11. APP_ATUALIZACAO        (sem FK, independente)
--  12. APP_USUARIO            (pai de 1 e 2 — só depois de 1 e 2 estarem vazias)
--
-- Cada DELETE é precedido de uma checagem em USER_TABLES: se a tabela ainda
-- não existir (ex.: rodando contra uma base parcialmente instalada), o
-- DELETE é pulado em vez de falhar com ORA-00942.
--
-- APP_DECISAO_PEDIDO NÃO aparece aqui: deixou de existir na Etapa 14
-- (sql/00_LEIAME.md). Se este script for rodado contra uma base antiga que
-- ainda tenha essa tabela, ela não é tocada por este script — decida
-- separadamente se ela é dropada (não é responsabilidade deste arquivo).
--
-- Rodar conectado como COMPRAS.
--------------------------------------------------------------------------------

whenever sqlerror exit sql.sqlcode

--------------------------------------------------------------------------------
-- 1. APP_SESSAO
--------------------------------------------------------------------------------
declare
    v_existe number;
begin
    select count(*) into v_existe from user_tables where table_name = 'APP_SESSAO';
    if v_existe > 0 then
        execute immediate 'delete from app_sessao';
    end if;
end;
/

--------------------------------------------------------------------------------
-- 2. APP_AUDITORIA
--------------------------------------------------------------------------------
declare
    v_existe number;
begin
    select count(*) into v_existe from user_tables where table_name = 'APP_AUDITORIA';
    if v_existe > 0 then
        execute immediate 'delete from app_auditoria';
    end if;
end;
/

--------------------------------------------------------------------------------
-- 3. APP_PEDIDO_ITEM
--------------------------------------------------------------------------------
declare
    v_existe number;
begin
    select count(*) into v_existe from user_tables where table_name = 'APP_PEDIDO_ITEM';
    if v_existe > 0 then
        execute immediate 'delete from app_pedido_item';
    end if;
end;
/

--------------------------------------------------------------------------------
-- 4. APP_PEDIDO_STATUS_HIST
--------------------------------------------------------------------------------
declare
    v_existe number;
begin
    select count(*) into v_existe from user_tables where table_name = 'APP_PEDIDO_STATUS_HIST';
    if v_existe > 0 then
        execute immediate 'delete from app_pedido_status_hist';
    end if;
end;
/

--------------------------------------------------------------------------------
-- 5. APP_PEDIDO
--------------------------------------------------------------------------------
declare
    v_existe number;
begin
    select count(*) into v_existe from user_tables where table_name = 'APP_PEDIDO';
    if v_existe > 0 then
        execute immediate 'delete from app_pedido';
    end if;
end;
/

--------------------------------------------------------------------------------
-- 6. APP_LOTE_PRECO_ITEM
--------------------------------------------------------------------------------
declare
    v_existe number;
begin
    select count(*) into v_existe from user_tables where table_name = 'APP_LOTE_PRECO_ITEM';
    if v_existe > 0 then
        execute immediate 'delete from app_lote_preco_item';
    end if;
end;
/

--------------------------------------------------------------------------------
-- 7. APP_LOTE_PRECO_STATUS_HIST
--------------------------------------------------------------------------------
declare
    v_existe number;
begin
    select count(*) into v_existe from user_tables where table_name = 'APP_LOTE_PRECO_STATUS_HIST';
    if v_existe > 0 then
        execute immediate 'delete from app_lote_preco_status_hist';
    end if;
end;
/

--------------------------------------------------------------------------------
-- 8. APP_LOTE_PRECO
--------------------------------------------------------------------------------
declare
    v_existe number;
begin
    select count(*) into v_existe from user_tables where table_name = 'APP_LOTE_PRECO';
    if v_existe > 0 then
        execute immediate 'delete from app_lote_preco';
    end if;
end;
/

--------------------------------------------------------------------------------
-- 9. APP_DECISAO_PRECO_HIST
--------------------------------------------------------------------------------
declare
    v_existe number;
begin
    select count(*) into v_existe from user_tables where table_name = 'APP_DECISAO_PRECO_HIST';
    if v_existe > 0 then
        execute immediate 'delete from app_decisao_preco_hist';
    end if;
end;
/

--------------------------------------------------------------------------------
-- 10. APP_DECISAO_PRECO
--------------------------------------------------------------------------------
declare
    v_existe number;
begin
    select count(*) into v_existe from user_tables where table_name = 'APP_DECISAO_PRECO';
    if v_existe > 0 then
        execute immediate 'delete from app_decisao_preco';
    end if;
end;
/

--------------------------------------------------------------------------------
-- 11. APP_ATUALIZACAO
--------------------------------------------------------------------------------
declare
    v_existe number;
begin
    select count(*) into v_existe from user_tables where table_name = 'APP_ATUALIZACAO';
    if v_existe > 0 then
        execute immediate 'delete from app_atualizacao';
    end if;
end;
/

--------------------------------------------------------------------------------
-- 12. APP_USUARIO — por último: só chega aqui vazio de fato se 1 e 2 já
--     esvaziaram (APP_SESSAO por FK cascade, APP_AUDITORIA por FK sem
--     cascade — um usuário com linha em APP_AUDITORIA não pode ser
--     apagado enquanto ela existir).
--------------------------------------------------------------------------------
declare
    v_existe number;
begin
    select count(*) into v_existe from user_tables where table_name = 'APP_USUARIO';
    if v_existe > 0 then
        execute immediate 'delete from app_usuario';
    end if;
end;
/

--------------------------------------------------------------------------------
-- FIM — sem COMMIT. Confira as contagens (select count(*) from app_* ...) e
-- rode COMMIT explicitamente, ou ROLLBACK se algo aqui não era o esperado.
--------------------------------------------------------------------------------
