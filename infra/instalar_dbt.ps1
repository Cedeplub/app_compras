# ============================================================================
# Cria o venv do dbt da PROPRIA ARVORE (dbt\env_server).
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File infra\instalar_dbt.ps1
#
# O que faz:
#   python -m venv <ProjetoRaiz>\dbt\env_server
#   <...>\env_server\Scripts\pip install -r <ProjetoRaiz>\dbt\compras\requirements.txt
#
# Referencia (producao, dbt\env_server\pyvenv.cfg): Python 3.13.2, dbt 1.9.11.
#
# ⚠ ESTE E O UNICO SCRIPT DE infra/ QUE NAO LEVA A TRAVA DE RAIZ DOS OUTROS
# SEIS (instalar_servico.ps1, desinstalar_servico.ps1, instalar_nginx.ps1,
# desinstalar_nginx.ps1, agendar_atualizacao.ps1, publicar.ps1). A trava
# existe porque aqueles seis usam CONSTANTES de producao (nome do servico
# "app_compras", nome da Tarefa Agendada, porta 8020, o vhost do nginx
# compartilhado com gestaosac.cdp.lub e dre.cdp.lub) - rodar uma copia deles
# a partir de outra pasta mexe em recursos de PRODUCAO com o caminho de dev.
# Este script aqui nao toca em servico, em Tarefa Agendada nem em nginx: ele
# so cria um venv Python dentro da propria arvore onde e executado. Rodar da
# pasta de dev cria o venv de dev; rodar da pasta de producao cria o de
# producao. Nao ha como este script, por engano, mexer no ambiente errado -
# por isso ele deve poder rodar em qualquer arvore que precise de um
# dbt\env_server proprio (producao, dev, ou uma terceira copia futura).
# ============================================================================

$ScriptDir     = Split-Path -Parent $PSCommandPath
$ProjetoRaiz   = Split-Path -Parent $ScriptDir
$EnvServerDir  = Join-Path $ProjetoRaiz "dbt\env_server"
$Requirements  = Join-Path $ProjetoRaiz "dbt\compras\requirements.txt"
$PythonExe     = "C:\Program Files\Python313\python.exe"

Write-Host ""
Write-Host "========================================================================="
Write-Host " INSTALAR DBT - venv da arvore"
Write-Host "========================================================================="
Write-Host ""
Write-Host " Raiz do projeto: $ProjetoRaiz"
Write-Host " env_server:      $EnvServerDir"
Write-Host ""

# --- python.exe -------------------------------------------------------------
if (-not (Test-Path $PythonExe)) {
    Write-Host " [ERRO] Nao encontrei $PythonExe."
    Write-Host " O que fazer: rode 'where python' e ajuste `$PythonExe neste script para o caminho real."
    Exit 1
}

# --- requirements.txt ---------------------------------------------------------
if (-not (Test-Path $Requirements)) {
    Write-Host " [ERRO] Nao encontrei $Requirements."
    Write-Host " O que fazer: confirme que dbt\compras\requirements.txt existe nesta arvore."
    Exit 1
}

# --- Recusa rodar se env_server ja existir - idempotencia explicita, nao ---
#     silenciosa: um venv corrompido pela metade e pior que um erro claro.
if (Test-Path $EnvServerDir) {
    Write-Host " [ERRO] $EnvServerDir ja existe."
    Write-Host " O que fazer: apague a pasta a mao (Remove-Item -Recurse -Force `"$EnvServerDir`") e rode este script de novo."
    Exit 1
}

# --- Cria o venv --------------------------------------------------------------
Write-Host " Criando venv..."
& $PythonExe -m venv $EnvServerDir
if ($LASTEXITCODE -ne 0) {
    Write-Host " [ERRO] 'python -m venv' falhou."
    Write-Host " O que fazer: leia o erro acima e confirme que $PythonExe esta integro."
    Exit 1
}

# --- Instala as dependencias ---------------------------------------------------
$PipExe = Join-Path $EnvServerDir "Scripts\pip.exe"
if (-not (Test-Path $PipExe)) {
    Write-Host " [ERRO] O venv foi criado mas nao encontrei $PipExe."
    Write-Host " O que fazer: confira se a criacao do venv terminou sem erro acima."
    Exit 1
}

Write-Host ""
Write-Host " Instalando dependencias de $Requirements..."
& $PipExe install -r $Requirements
if ($LASTEXITCODE -ne 0) {
    Write-Host " [ERRO] 'pip install' falhou."
    Write-Host " O que fazer: leia o erro acima (rede, versao de pacote, etc)."
    Exit 1
}

# --- Confirma dbt.exe ----------------------------------------------------------
$DbtExe = Join-Path $EnvServerDir "Scripts\dbt.exe"
if (-not (Test-Path $DbtExe)) {
    Write-Host ""
    Write-Host " [ERRO] Instalacao terminou mas nao encontrei $DbtExe."
    Write-Host " O que fazer: confira o log do 'pip install' acima por falha silenciosa do pacote dbt-core."
    Exit 1
}

Write-Host ""
Write-Host " Instalado com sucesso. Versao:"
& $DbtExe --version
Write-Host ""
