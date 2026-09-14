# ============================================================================
# Instala/atualiza o servico NSSM "app_compras" (uvicorn, SEM --reload).
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File infra\instalar_servico.ps1
#
# Molde: o servico "relatorio_compras" ja em producao nesta maquina
# (LocalSystem, StartMode Auto, Application = python.exe do sistema).
#
# Requisitos:
#   - Rodar como administrador
#   - nssm.exe em C:\tools\nssm\nssm.exe (ja existe nesta maquina)
#   - Python do sistema no PATH (a API nao usa venv - teste.bat tambem chama
#     "python" direto)
#   - .env presente na raiz do projeto, com ORA_PASSWORD preenchido
#   - Porta 8020 livre no endereco <BIND> abaixo (ver infra\README.md, passo 1)
#
# Para desfazer: infra\desinstalar_servico.ps1
# ============================================================================

# --------------------------------------------------------------- <BIND> ---
# Ja em 127.0.0.1 - quem expoe o app na rede e o nginx (proxy reverso), nao
# o uvicorn direto. Isto e o certo em producao.
#
# O orfao de 25/08/2026 (PID 2240, 0.0.0.0:8020) sumiu no reinicio de
# 09/09/2026, como esperado. Mas o taskkill do PID 2508 (14/09/2026, feito
# pelo usuario para derrubar os processos antigos) CRIOU outro orfao, que
# ficou preso em 192.168.0.50:8020 - esse socket nao morre sozinho e nao
# tem processo dono (confirmado: Get-CimInstance nao acha PID 2508).
#
# Testado em 14/09/2026 antes de instalar:
#     127.0.0.1      LIVRE
#     0.0.0.0        LIVRE
#     192.168.0.50   OCUPADO (WinError 10048) - orfao do PID 2508
#
# Ou seja, o acidente do taskkill deixou a maquina exatamente na
# configuracao que era esperada so depois de um reinicio: 192.168.0.50:8020
# ficou indisponivel para o uvicorn, entao o bind passa a ser 127.0.0.1 (e
# o nginx, escutando em 0.0.0.0:80, quem alcanca o app pelo proxy_pass).
# Se algum dia alguem tentar usar 192.168.0.50:8020 direto e encontrar
# WinError 10048, NAO e defeito de configuracao - e esse orfao antigo, que
# so some em outro reinicio.
#
# infra\nginx\compras.conf tem a MESMA constante, no MESMO valor, no
# proxy_pass - troque as duas juntas.
$BIND = "127.0.0.1"

$NssmExe      = "C:\tools\nssm\nssm.exe"
$ServicoNome  = "app_compras"
$ScriptDir    = Split-Path -Parent $PSCommandPath
$ProjetoRaiz  = Split-Path -Parent $ScriptDir
$PythonExe    = "C:\Program Files\Python313\python.exe"
$LogsDir      = Join-Path $ProjetoRaiz "logs"
$DbtProfiles  = "C:\Users\Administrator\.dbt"

Write-Host ""
Write-Host "========================================================================="
Write-Host " INSTALAR SERVICO - app_compras"
Write-Host "========================================================================="
Write-Host ""
Write-Host " Raiz do projeto: $ProjetoRaiz"
Write-Host " BIND (uvicorn):  $BIND"
Write-Host ""

# --- Administrador ----------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Host " [ERRO] Este script precisa rodar como Administrador."
    Write-Host " O que fazer: clique com o botao direito em PowerShell e escolha 'Executar como Administrador'."
    Exit 1
}

# --- nssm.exe -----------------------------------------------------------
if (-not (Test-Path $NssmExe)) {
    Write-Host " [ERRO] Nao encontrei $NssmExe."
    Write-Host " O que fazer: confirme que o NSSM esta instalado nesse caminho, ou ajuste `$NssmExe neste script."
    Exit 1
}

# --- python.exe -----------------------------------------------------------
if (-not (Test-Path $PythonExe)) {
    Write-Host " [ERRO] Nao encontrei $PythonExe."
    Write-Host " O que fazer: rode 'where python' e ajuste `$PythonExe neste script para o caminho real."
    Exit 1
}

# --- .env -----------------------------------------------------------------
$EnvPath = Join-Path $ProjetoRaiz ".env"
if (-not (Test-Path $EnvPath)) {
    Write-Host " [ERRO] Nao encontrei $EnvPath."
    Write-Host " O que fazer: copie .env.exemplo para .env e preencha ORA_PASSWORD antes de instalar o servico."
    Exit 1
}

# --- profiles.yml do dbt (o botao Atualizar dados precisa dele) -----------
if (-not (Test-Path (Join-Path $DbtProfiles "profiles.yml"))) {
    Write-Host " [ERRO] profiles.yml nao encontrado em $DbtProfiles."
    Write-Host " O que fazer: ajuste `$DbtProfiles neste script para o diretorio real do perfil dbt."
    Exit 1
}

# --- logs\ ------------------------------------------------------------------
if (-not (Test-Path $LogsDir)) {
    New-Item -ItemType Directory -Path $LogsDir | Out-Null
    Write-Host " Pasta de logs criada: $LogsDir"
}

# --- Reinstalacao idempotente: remove servico anterior, se houver ---------
$ServicoExistente = Get-Service -Name $ServicoNome -ErrorAction SilentlyContinue
if ($ServicoExistente) {
    Write-Host " Servico ja existia - parando e removendo para recriar do zero."
    & $NssmExe stop $ServicoNome 2>$null | Out-Null
    Start-Sleep -Seconds 2
    & $NssmExe remove $ServicoNome confirm 2>$null | Out-Null
}

# --- Instala ----------------------------------------------------------------
Write-Host ""
Write-Host " Instalando servico..."
& $NssmExe install $ServicoNome $PythonExe

# Sem --reload: em producao o reload reinicia o processo a cada toque em
# arquivo e mascara falha de startup.
& $NssmExe set $ServicoNome AppParameters "-m uvicorn app.main:app --host $BIND --port 8020"
& $NssmExe set $ServicoNome AppDirectory $ProjetoRaiz
& $NssmExe set $ServicoNome DisplayName "Dashboard de Compras (app_compras, webapp 8020)"
& $NssmExe set $ServicoNome Start SERVICE_AUTO_START
& $NssmExe set $ServicoNome ObjectName LocalSystem

# Log com rotacao: servico sem log e servico que falha em silencio.
& $NssmExe set $ServicoNome AppStdout (Join-Path $LogsDir "servico.out.log")
& $NssmExe set $ServicoNome AppStderr (Join-Path $LogsDir "servico.err.log")
& $NssmExe set $ServicoNome AppRotateFiles 1
& $NssmExe set $ServicoNome AppRotateOnline 1
& $NssmExe set $ServicoNome AppRotateSeconds 86400
& $NssmExe set $ServicoNome AppRotateBytes 10485760

# Reinicia sozinho se o processo cair sozinho.
& $NssmExe set $ServicoNome AppExit Default Restart

# DBT_PROFILES_DIR: o botao "Atualizar dados" chama dbt/atualizar.py, que
# HERDA o ambiente do servico. Rodando como LocalSystem, Path.home() aponta
# para o perfil do sistema, onde nao ha profiles.yml - sem isto o botao
# falharia em producao num caminho que funcionava em teste (CONTEXTO.md).
& $NssmExe set $ServicoNome AppEnvironmentExtra "DBT_PROFILES_DIR=$DbtProfiles"

Write-Host ""
Write-Host " Iniciando servico..."
& $NssmExe start $ServicoNome
Start-Sleep -Seconds 2

$Servico = Get-Service -Name $ServicoNome -ErrorAction SilentlyContinue
if ($Servico) {
    Write-Host ""
    Write-Host " Status: $($Servico.Status) / $($Servico.StartType)"
    Write-Host ""
    Write-Host " Confira o log em caso de duvida:"
    Write-Host "   $(Join-Path $LogsDir 'servico.out.log')"
    Write-Host "   $(Join-Path $LogsDir 'servico.err.log')"
} else {
    Write-Host " [ERRO] Servico nao apareceu em Get-Service apos a instalacao."
    Write-Host " O que fazer: rode '$NssmExe status $ServicoNome' para ver o motivo."
    Exit 1
}
