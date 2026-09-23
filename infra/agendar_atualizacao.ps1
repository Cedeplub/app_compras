# ============================================================================
# Cria/atualiza Tarefa Agendada para atualizar dados do dbt
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File infra\agendar_atualizacao.ps1
#
# Ou com botão direito em Abrir com PowerShell (se ExecutionPolicy permitir)
#
# Requisitos:
#   - Rodar como administrador
#   - Python acessível no PATH
#   - Arquivo dbt\atualizar.py existente
# ============================================================================

# Descobrir a raiz do projeto a partir do local deste script
$ScriptDir = Split-Path -Parent $PSCommandPath
$ProjetoRaiz = Split-Path -Parent $ScriptDir

# --- Trava de raiz: este script so pode operar a producao -------------------
# O nome da tarefa abaixo e constante de producao. Uma copia deste script
# rodada da pasta de dev sequestraria a Tarefa Agendada de PRODUCAO,
# apontando-a para rodar o dbt.atualizar.py de dev. Por isso a trava: nada de
# escape.
$RaizProducao = "C:\Users\Administrator\Desktop\app_compras_v2"
$RaizAtual    = [IO.Path]::GetFullPath($ProjetoRaiz).TrimEnd('\')
if ($RaizAtual -ne [IO.Path]::GetFullPath($RaizProducao).TrimEnd('\')) {
    Write-Host " [ERRO] Este script so pode rodar a partir de $RaizProducao (producao)."
    Write-Host " Pasta detectada: $RaizAtual"
    Write-Host " O que fazer: para o ambiente de desenvolvimento, suba por teste_dev.bat - nao por scripts de infra/."
    Exit 1
}

Write-Host ""
Write-Host "========================================================================="
Write-Host " AGENDADOR DE ATUALIZAÇÃO - app_compras"
Write-Host "========================================================================="
Write-Host ""
Write-Host " Raiz do projeto: $ProjetoRaiz"
Write-Host ""

# Verificar se é administrador
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Host " [ERRO] Este script precisa rodar como Administrador."
    Write-Host " O que fazer: Clique com botão direito em 'PowerShell' e escolha 'Executar como Administrador'."
    Write-Host ""
    Exit 1
}

# Verificar se Python existe
try {
    $PythonVersao = python --version 2>&1
    Write-Host " Python encontrado: $PythonVersao"
} catch {
    Write-Host " [ERRO] Python não encontrado no PATH."
    Write-Host " O que fazer: Instale o Python ou adicione ao PATH e tente de novo."
    Write-Host ""
    Exit 1
}

# Verificar se atualizar.py existe
$AtulizarPy = Join-Path (Join-Path $ProjetoRaiz "dbt") "atualizar.py"
if (-not (Test-Path $AtulizarPy)) {
    Write-Host " [ERRO] Arquivo não encontrado: $AtulizarPy"
    Write-Host " O que fazer: Verifique se o arquivo dbt/atualizar.py existe."
    Write-Host ""
    Exit 1
}

# Nome da tarefa
$TarefaNome = "CEDEP - app_compras - atualizar dados"

# DBT_PROFILES_DIR explícito: a tarefa roda como SYSTEM, e SYSTEM não tem
# perfil próprio em ~/.dbt (C:\Windows\System32\config\systemprofile\.dbt
# não existe neste servidor). O perfil real de quem preparou o ambiente
# dbt está em C:\Users\Administrator\.dbt - hardcoded aqui de propósito,
# porque não há como SYSTEM "descobrir" isso sozinho. Se o perfil for
# movido, este caminho precisa mudar junto (e o teste do item 1 refeito).
$DbtProfilesDir = "C:\Users\Administrator\.dbt"
if (-not (Test-Path (Join-Path $DbtProfilesDir "profiles.yml"))) {
    Write-Host " [ERRO] profiles.yml não encontrado em $DbtProfilesDir"
    Write-Host " O que fazer: ajuste `$DbtProfilesDir neste script para o diretório real do perfil dbt."
    Write-Host ""
    Exit 1
}

Write-Host " Arquivo: $AtulizarPy"
Write-Host ""
Write-Host " Tarefa: $TarefaNome"
Write-Host " Horários: 06:00 e 13:00 (diariamente)"
Write-Host " Executar como: SYSTEM"
Write-Host " DBT_PROFILES_DIR: $DbtProfilesDir"
Write-Host " Tempo limite: 120 minutos (soma dos timeouts internos de seed+run+test"
Write-Host "               é no máximo 90 min - este teto tem que ficar ACIMA disso,"
Write-Host "               senão o Agendador mata o processo antes do finally rodar"
Write-Host "               e a linha em APP_ATUALIZACAO fica EM_ANDAMENTO para sempre)."
Write-Host ""

# Criar/atualizar a Tarefa Agendada
try {
    # Desregistrar tarefa anterior se existir (para recriá-la do zero)
    try {
        Unregister-ScheduledTask -TaskName $TarefaNome -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host " Tarefa anterior removida."
    } catch {
        # Não existe ainda
    }

    # Definir Principal (SYSTEM com RunLevel Highest)
    $Principal = New-ScheduledTaskPrincipal `
        -UserId "SYSTEM" `
        -RunLevel Highest

    # Definir Action: python dbt\atualizar.py --origem agendado
    #
    # Executado via cmd.exe /c "set DBT_PROFILES_DIR=...&& python ..." (em vez
    # de invocar python diretamente) porque New-ScheduledTaskAction não tem
    # parâmetro de variável de ambiente - isto é o jeito explícito e
    # verificável de garantir que o processo agendado (rodando como SYSTEM,
    # sem ~/.dbt próprio) enxergue o profiles.yml real. atualizar.py também
    # repassa DBT_PROFILES_DIR ao subprocesso dbt.exe (com fallback para
    # ~/.dbt quando a variável não existir - caso do uso manual).
    $ArgumentoAcao = "/c set ""DBT_PROFILES_DIR=$DbtProfilesDir""&& python ""$AtulizarPy"" --origem agendado"
    $Action = New-ScheduledTaskAction `
        -Execute "cmd.exe" `
        -Argument $ArgumentoAcao `
        -WorkingDirectory $ProjetoRaiz

    # Definir Triggers: 06:00 e 13:00
    $Trigger1 = New-ScheduledTaskTrigger -Daily -At "06:00"
    $Trigger2 = New-ScheduledTaskTrigger -Daily -At "13:00"

    # Definir Settings: StartWhenAvailable e ExecutionTimeLimit
    #
    # 120 minutos: TEM que ficar acima da soma dos timeouts internos do
    # atualizar.py (30min/fase x 3 fases = 90min no pior caso), nunca abaixo -
    # se o Agendador matar o processo primeiro, nenhum `finally` do Python
    # roda e a linha em APP_ATUALIZACAO fica EM_ANDAMENTO para sempre (o
    # próprio defeito 1, agora pela porta dos fundos). Build completo medido
    # em produção: 235s e 276s - 120min é folga de sobra, não o tempo normal.
    $Settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 120)

    # Registrar tarefa
    Register-ScheduledTask `
        -TaskName $TarefaNome `
        -Principal $Principal `
        -Action $Action `
        -Trigger $Trigger1, $Trigger2 `
        -Settings $Settings `
        -ErrorAction Stop | Out-Null

    Write-Host " Tarefa registrada com sucesso!"
    Write-Host ""

    # Exibir detalhes
    Write-Host "========================================================================="
    Write-Host " DETALHES DA TAREFA"
    Write-Host "========================================================================="
    Write-Host ""

    $Tarefa = Get-ScheduledTask -TaskName $TarefaNome
    Write-Host " Nome:   $($Tarefa.TaskName)"
    Write-Host " Estado: $($Tarefa.State)"
    Write-Host ""

    Write-Host " Gatilhos:"
    $Tarefa.Triggers | ForEach-Object {
        if ($_ | Get-Member StartBoundary -ErrorAction SilentlyContinue) {
            $Inicio = $_.StartBoundary
            Write-Host "   $Inicio"
        }
    }
    Write-Host ""

    # Próxima execução
    $TarefaInfo = Get-ScheduledTask -TaskName $TarefaNome | Get-ScheduledTaskInfo
    Write-Host " Próxima execução: $($TarefaInfo.NextRunTime)"
    Write-Host ""

    Write-Host "========================================================================="
    Write-Host " COMO TESTAR"
    Write-Host "========================================================================="
    Write-Host ""
    Write-Host " 1. Executar manualmente:"
    Write-Host "    schtasks /run /tn ""$TarefaNome"""
    Write-Host ""
    Write-Host " 2. Verificar status:"
    Write-Host "    schtasks /query /tn ""$TarefaNome"" /v /fo LIST"
    Write-Host ""
    Write-Host " 3. Ver logs da última execução:"
    Write-Host "    Get-ScheduledTaskInfo -TaskName ""$TarefaNome"""
    Write-Host ""
    Write-Host "========================================================================="
    Write-Host ""

} catch {
    Write-Host " [ERRO] Falha ao registrar tarefa: $($_.Exception.Message)"
    Write-Host " O que fazer: Verifique se está rodando como Administrador."
    Write-Host ""
    Exit 1
}
