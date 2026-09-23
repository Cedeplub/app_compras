# ============================================================================
# Para e remove o servico NSSM "app_compras".
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File infra\desinstalar_servico.ps1
#
# Depois de rodar isto, o caminho de volta e o modo de desenvolvimento:
# teste.bat (API, 8020) - nao depende de nada instalado.
# ============================================================================

$NssmExe     = "C:\tools\nssm\nssm.exe"
$ServicoNome = "app_compras"
$ScriptDir   = Split-Path -Parent $PSCommandPath
$ProjetoRaiz = Split-Path -Parent $ScriptDir

# --- Trava de raiz: este script so pode operar a producao -------------------
# O nome do servico acima e constante de producao. Uma copia deste script
# rodada da pasta de dev ainda assim pararia/removeria o servico "app_compras"
# de PRODUCAO. Por isso a trava: nada de escape.
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
Write-Host " DESINSTALAR SERVICO - app_compras"
Write-Host "========================================================================="
Write-Host ""

$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Host " [ERRO] Este script precisa rodar como Administrador."
    Write-Host " O que fazer: clique com o botao direito em PowerShell e escolha 'Executar como Administrador'."
    Exit 1
}

if (-not (Test-Path $NssmExe)) {
    Write-Host " [ERRO] Nao encontrei $NssmExe."
    Write-Host " O que fazer: ajuste `$NssmExe neste script para o caminho real do nssm.exe."
    Exit 1
}

$Servico = Get-Service -Name $ServicoNome -ErrorAction SilentlyContinue
if (-not $Servico) {
    Write-Host " Servico '$ServicoNome' nao existe - nada a fazer."
    Exit 0
}

Write-Host " Parando servico..."
& $NssmExe stop $ServicoNome
Start-Sleep -Seconds 2

Write-Host " Removendo servico..."
& $NssmExe remove $ServicoNome confirm

$AindaExiste = Get-Service -Name $ServicoNome -ErrorAction SilentlyContinue
if ($AindaExiste) {
    Write-Host " [ERRO] O servico ainda aparece em Get-Service apos a remocao."
    Write-Host " O que fazer: rode 'sc query $ServicoNome' e, se preciso, 'sc delete $ServicoNome'."
    Exit 1
}

Write-Host ""
Write-Host " Servico removido com sucesso."
Write-Host " Para subir de novo em modo de desenvolvimento: teste.bat (na raiz do projeto)."
Write-Host ""
