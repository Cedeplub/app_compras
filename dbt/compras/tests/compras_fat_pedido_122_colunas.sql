-- Testa que fat_pedido tem EXATAMENTE 122 colunas.
--
-- Falha que ele previne: o critério de aceite do projeto (CONTEXTO.md §7) é a
-- comparação célula a célula de 122 colunas x 8.772 linhas. O validador casa
-- coluna da planilha com coluna do banco pelo NOME - e uma coluna que suma
-- (renomeada, esquecida num refactor da junção) não reprova nada: ela
-- simplesmente deixa de ser comparada, e o relatório sai verde com menos
-- colunas do que devia. É a falha mais silenciosa possível neste projeto.
--
-- Aqui o número é literal de propósito, e não vem do gabarito por macro: 122 é
-- o contrato, e mudar o contrato tem de ser um ato deliberado que quebre este
-- teste e obrigue quem mexeu a explicar por quê.

select
    'fat_pedido' as tabela,
    count(*)     as qtd_colunas
  from user_tab_columns
 where table_name = 'FAT_PEDIDO'
having count(*) <> 122
