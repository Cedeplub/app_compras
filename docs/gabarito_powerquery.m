section Section1;

shared dCadastroTI = let
    Caminho = "C:\Users\felipeanjos\Claude\PLANILHA DE COMPRAS\",

    Pasta = Folder.Files(Caminho),

    Filtrados = Table.SelectRows(Pasta, each
        Text.StartsWith([Name], "relatorio_compras_")
        and Text.Lower([Extension]) = ".xlsx"
        and not Text.StartsWith([Name], "~$")),

    MaisRecente = Table.Sort(Filtrados, {{"Name", Order.Descending}}){0},

    Origem = Excel.Workbook(MaisRecente[Content], false),
    Planilha = Origem{[Item="Relatorio", Kind="Sheet"]}[Data],
    ComCabecalho = Table.PromoteHeaders(Planilha, [PromoteAllScalars = true]),

    Renomeado = Table.RenameColumns(ComCabecalho, {
        {"Cód. Produto", "CODIGO"}, {"Cód. Fábrica", "COD_FAB"}, {"Produto", "DESCRICAO"},
        {"Status", "STATUS"}, {"Unidade", "UNIDADE"}, {"Embalagem", "EMBALAGEM"},
        {"Embal. Compra", "EMBAL_COMPRA"}, {"Embal. Venda", "EMBAL_VENDA_TI"},
        {"Cód. Fornec.", "COD_FORNEC"}, {"Fornecedor", "FORNECEDOR_LEGAL"},
        {"UF Origem", "UF_ORIGEM"}, {"Cód. Depto", "CODEPTO"}, {"Departamento", "DEPARTAMENTO_TXT"},
        {"Cód. Tributação", "COD_TRIBUTACAO"}, {"Tributação", "TRIBUTACAO"}, {"NCM", "NCM"},
        {"Cód. Trib. PIS/COFINS", "CODTRIBPISCOFINS"}, {"Trib. PIS/COFINS", "DESCRICAOTRIBPISCOFINS"},
        {"Qt. Pedida", "QT_PEDIDA"}, {"Qt. Bloqueada", "QT_BLOQUEADA"}, {"Qt. Avaria", "QT_AVARIA"},
        {"Qt. Reservada", "QT_RESERVADA"}, {"Qt. Disponível", "QT_DISPONIVEL"},
        {"Dt. Últ. Entrada", "DT_ULT_ENTRADA"}, {"Qt. Últ. Entrada", "QT_ULT_ENTRADA"},
        {"Custo Últ. Ent.", "CUSTO_ULT_ENT"}, {"Vl. Últ. Ent.", "VL_ULT_ENT"},
        {"PV Atacado", "PV_ATACADO"}, {"PV Varejo", "PV_VAREJO"},
        {"Dt. Últ. Saída", "DT_ULT_SAIDA"}, {"Qt. Últ. Saída", "QT_ULT_SAIDA"},
        {"Peso Líq. (kg)", "PESO_UNITARIO_KG"}, {"Qt. Palete", "QT_PALETE"}}),

    // FORNECEDOR usa o texto do Departamento, nao o Fornecedor Legal
    ComFornecedor = Table.AddColumn(Renomeado, "FORNECEDOR", each [DEPARTAMENTO_TXT]),

    Selecionado = Table.SelectColumns(ComFornecedor, {
        "CODIGO","COD_FAB","DESCRICAO","STATUS","UNIDADE","EMBALAGEM","EMBAL_COMPRA",
        "EMBAL_VENDA_TI","COD_FORNEC","FORNECEDOR_LEGAL","UF_ORIGEM","CODEPTO","DEPARTAMENTO_TXT",
        "COD_TRIBUTACAO","TRIBUTACAO","NCM","CODTRIBPISCOFINS","DESCRICAOTRIBPISCOFINS",
        "QT_PEDIDA","QT_BLOQUEADA","QT_AVARIA","QT_RESERVADA","QT_DISPONIVEL",
        "DT_ULT_ENTRADA","QT_ULT_ENTRADA","CUSTO_ULT_ENT","VL_ULT_ENT","PV_ATACADO","PV_VAREJO",
        "FORNECEDOR","DT_ULT_SAIDA","QT_ULT_SAIDA","PESO_UNITARIO_KG","QT_PALETE"}),

    Limpo = Table.SelectRows(Selecionado, each
        [CODIGO] <> null and (try Number.From([CODIGO]) is number otherwise false)),

    Tipado = Table.TransformColumnTypes(Limpo, {
        {"CODIGO", Int64.Type}, {"CODEPTO", Int64.Type}, {"COD_TRIBUTACAO", Int64.Type},
        {"CODTRIBPISCOFINS", Int64.Type}, {"QT_DISPONIVEL", type number}, {"QT_PEDIDA", type number},
        {"QT_BLOQUEADA", type number}, {"QT_AVARIA", type number}, {"QT_RESERVADA", type number},
        {"QT_ULT_ENTRADA", type number}, {"QT_ULT_SAIDA", type number}, {"CUSTO_ULT_ENT", type number},
        {"VL_ULT_ENT", type number}, {"PV_ATACADO", type number}, {"PV_VAREJO", type number},
        {"EMBAL_COMPRA", type number}, {"PESO_UNITARIO_KG", type number}, {"QT_PALETE", type number},
        {"DT_ULT_ENTRADA", type date}, {"DT_ULT_SAIDA", type date}}),

    Unico = Table.Distinct(Tipado, {"CODIGO"})
in
    Unico;

shared fVendaMes = let
    Caminho = "C:\Users\felipeanjos\Claude\PLANILHA DE COMPRAS\",

    Pasta = Folder.Files(Caminho),
    Filtrados = Table.SelectRows(Pasta, each
        Text.StartsWith([Name], "relatorio_mensal_")
        and Text.Lower([Extension]) = ".xlsx"
        and not Text.StartsWith([Name], "~$")),
    MaisRecente = Table.Sort(Filtrados, {{"Name", Order.Descending}}){0},

    Origem = Excel.Workbook(MaisRecente[Content], false),
    Planilha = Origem{[Item="Relatorio", Kind="Sheet"]}[Data],
    ComCabecalho = Table.PromoteHeaders(Planilha, [PromoteAllScalars = true]),

    Renomeado = Table.RenameColumns(ComCabecalho, {
        {"Mês", "MES"}, {"Cód. Produto", "CODIGO"}, {"Qt. Faturada", "QT_FAT"},
        {"Qt. Devolvida", "QT_DEV"}, {"Qt. Líquida", "QTD"}, {"Vl. Líquido", "VALOR"},
        {"Dias s/ Estoque (Fil. 2)", "DIAS_SEM_ESTOQUE"}, {"Clientes Atacado", "CLI_ATACADO"},
        {"Clientes Varejo", "CLI_VAREJO"}, {"Fora de Linha", "FORA_DE_LINHA"}}),

    Tipado = Table.TransformColumnTypes(Renomeado, {
        {"MES", type date}, {"CODIGO", Int64.Type}, {"QTD", type number}, {"VALOR", type number},
        {"QT_FAT", type number}, {"QT_DEV", type number}, {"DIAS_SEM_ESTOQUE", type number},
        {"CLI_ATACADO", Int64.Type}, {"CLI_VAREJO", Int64.Type}}),

    // QTD e VALOR ja sao Liquido (Qt. Liquida / Vl. Liquido) - NUNCA trocar por Faturada/Faturado
    MesAtual = List.Max(Tipado[MES]),

    MesesPT = {"jan","fev","mar","abr","mai","jun","jul","ago","set","out","nov","dez"},
    Rotulo = (dt as date) as text =>
        MesesPT{Date.Month(dt)-1} & "/" & Text.PadStart(Text.From(Number.Mod(Date.Year(dt), 100)), 2, "0"),

    ComOffset = Table.AddColumn(Tipado, "OFFSET", each
        (Date.Year(MesAtual)*12+Date.Month(MesAtual))
        - (Date.Year([MES])*12+Date.Month([MES])) - 1),

    Fechados = Table.SelectRows(ComOffset, each [OFFSET] >= 0),

    ComRotuloQ = Table.AddColumn(Fechados, "COL_Q", each
        "Q" & Text.PadStart(Text.From([OFFSET]), 2, "0") & "_" &
        Rotulo(Date.AddMonths(MesAtual, -([OFFSET]+1)))),
    PivQ = Table.Pivot(
        Table.SelectColumns(Table.SelectRows(ComRotuloQ, each [OFFSET] <= 11),
            {"CODIGO", "COL_Q", "QTD"}),
        List.Distinct(Table.SelectRows(ComRotuloQ, each [OFFSET]<=11)[COL_Q]),
        "COL_Q", "QTD", List.Sum),

    ComRotuloV = Table.AddColumn(Fechados, "COL_V", each
        "V" & Text.PadStart(Text.From([OFFSET]), 2, "0") & "_" &
        Rotulo(Date.AddMonths(MesAtual, -([OFFSET]+1)))),
    PivV = Table.Pivot(
        Table.SelectColumns(Table.SelectRows(ComRotuloV, each [OFFSET] <= 5),
            {"CODIGO", "COL_V", "VALOR"}),
        List.Distinct(Table.SelectRows(ComRotuloV, each [OFFSET]<=5)[COL_V]),
        "COL_V", "VALOR", List.Sum),

    // TX_DEVOLUCAO_3M e' o UNICO campo que usa Faturada - por definicao, e' taxa sobre o bruto
    Dev3 = Table.Group(Table.SelectRows(Fechados, each [OFFSET] < 3), {"CODIGO"}, {
        {"FAT3", each List.Sum([QT_FAT]), type number},
        {"DEV3", each List.Sum([QT_DEV]), type number}}),
    ComTaxa = Table.AddColumn(Dev3, "TX_DEVOLUCAO_3M", each
        if [FAT3] = 0 then 0 else [DEV3] / [FAT3]),
    TaxaFinal = Table.SelectColumns(ComTaxa, {"CODIGO", "TX_DEVOLUCAO_3M"}),

    Atual = Table.SelectColumns(Table.SelectRows(Tipado, each [MES] = MesAtual),
        {"CODIGO", "QTD", "VALOR", "CLI_ATACADO", "CLI_VAREJO", "DIAS_SEM_ESTOQUE", "FORA_DE_LINHA"}),
    AtualRen = Table.RenameColumns(Atual, {{"QTD","QATUAL"}, {"VALOR","VATUAL"},
        {"CLI_ATACADO","CLI_ATAC_ATUAL"}, {"CLI_VAREJO","CLI_VAR_ATUAL"},
        {"DIAS_SEM_ESTOQUE","DIAS_SEM_EST_ATUAL"}}),

    Mes0 = Table.SelectColumns(Table.SelectRows(Fechados, each [OFFSET] = 0),
        {"CODIGO", "CLI_ATACADO", "CLI_VAREJO", "DIAS_SEM_ESTOQUE"}),
    Mes0Ren = Table.RenameColumns(Mes0, {{"CLI_ATACADO","CLI_ATAC_00"},
        {"CLI_VAREJO","CLI_VAR_00"}, {"DIAS_SEM_ESTOQUE","DIAS_SEM_EST_00"}}),

    // base da juncao: TODO codigo que apareceu em qualquer mes (fechado ou atual) -
    // nao so quem tem historico fechado. Sem isso, produto com venda so no mes
    // atual (primeira venda, sem historico) nunca aparece na tabela final.
    TodosCodigos = Table.Distinct(Table.SelectColumns(Tipado, {"CODIGO"})),

    JQ = Table.NestedJoin(TodosCodigos, {"CODIGO"}, PivQ, {"CODIGO"}, "q", JoinKind.LeftOuter),
    EQ = Table.ExpandTableColumn(JQ, "q", List.RemoveItems(Table.ColumnNames(PivQ), {"CODIGO"})),

    J1 = Table.NestedJoin(EQ, {"CODIGO"}, PivV, {"CODIGO"}, "v", JoinKind.LeftOuter),
    E1 = Table.ExpandTableColumn(J1, "v", List.RemoveItems(Table.ColumnNames(PivV), {"CODIGO"})),

    J2 = Table.NestedJoin(E1, {"CODIGO"}, AtualRen, {"CODIGO"}, "a", JoinKind.LeftOuter),
    E2 = Table.ExpandTableColumn(J2, "a",
        {"QATUAL","VATUAL","CLI_ATAC_ATUAL","CLI_VAR_ATUAL","DIAS_SEM_EST_ATUAL","FORA_DE_LINHA"}),

    J3 = Table.NestedJoin(E2, {"CODIGO"}, TaxaFinal, {"CODIGO"}, "d", JoinKind.LeftOuter),
    E3 = Table.ExpandTableColumn(J3, "d", {"TX_DEVOLUCAO_3M"}),

    J4 = Table.NestedJoin(E3, {"CODIGO"}, Mes0Ren, {"CODIGO"}, "m0", JoinKind.LeftOuter),
    E4 = Table.ExpandTableColumn(J4, "m0", {"CLI_ATAC_00","CLI_VAR_00","DIAS_SEM_EST_00"}),

    // ordem explicita, do mais recente ao mais antigo - Table.Pivot NAO garante isso sozinho
    ColunasQ = {"Q00","Q01","Q02","Q03","Q04","Q05","Q06","Q07","Q08","Q09","Q10","Q11"},
    ColunasV = {"V00","V01","V02","V03","V04","V05"},
    NomesQ = List.Transform({0..11}, (n) => "Q" & Text.PadStart(Text.From(n), 2, "0") & "_" & Rotulo(Date.AddMonths(MesAtual, -(n+1)))),
    NomesV = List.Transform({0..5}, (n) => "V" & Text.PadStart(Text.From(n), 2, "0") & "_" & Rotulo(Date.AddMonths(MesAtual, -(n+1)))),

    SemNulo = Table.ReplaceValue(E4, null, 0, Replacer.ReplaceValue,
        List.RemoveItems(Table.ColumnNames(E4), {"CODIGO", "FORA_DE_LINHA"})),
    SemNuloTxt = Table.ReplaceValue(SemNulo, null, "N", Replacer.ReplaceValue, {"FORA_DE_LINHA"}),

    ComMed02 = Table.AddColumn(SemNuloTxt, "MED02", each List.Sum(List.Transform({0..1}, (k)=>Record.Field(_, NomesQ{k})))/2),
    ComMed03 = Table.AddColumn(ComMed02, "MED03", each List.Sum(List.Transform({0..2}, (k)=>Record.Field(_, NomesQ{k})))/3),
    ComMed04 = Table.AddColumn(ComMed03, "MED04", each List.Sum(List.Transform({0..3}, (k)=>Record.Field(_, NomesQ{k})))/4),
    ComMed06 = Table.AddColumn(ComMed04, "MED06", each List.Sum(List.Transform({0..5}, (k)=>Record.Field(_, NomesQ{k})))/6),
    ComMed09 = Table.AddColumn(ComMed06, "MED09", each
        if List.Count(NomesQ) >= 9 then List.Sum(List.Transform({0..8}, (k)=>Record.Field(_, NomesQ{k})))/9 else null),
    ComMed12 = Table.AddColumn(ComMed09, "MED12", each
        if List.Count(NomesQ) >= 12 then List.Sum(List.Transform({0..11}, (k)=>Record.Field(_, NomesQ{k})))/12 else null),

    // passo final: forca a ordem exata das 35 colunas, nao importa a ordem que os passos anteriores geraram
    OrdemFinal = {"CODIGO"} & NomesQ & NomesV &
        {"QATUAL","VATUAL","CLI_ATAC_ATUAL","CLI_VAR_ATUAL","DIAS_SEM_EST_ATUAL","FORA_DE_LINHA",
         "TX_DEVOLUCAO_3M","CLI_ATAC_00","CLI_VAR_00","DIAS_SEM_EST_00",
         "MED02","MED03","MED04","MED06","MED09","MED12"},
    Final = Table.ReorderColumns(ComMed12, OrdemFinal)
in
    Final;