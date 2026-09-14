# ============================================================================
# Publica o front em producao: npm ci + npm run build + reinicio do servico.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File infra\publicar.ps1
#
# Este e o UNICO caminho para colocar um front novo no ar. O nginx serve
# app/static/v2 direto (infra\nginx\compras.conf) - sem rodar este script
# depois de mudar o codigo do front, quem visita continua vendo o build
# antigo, sem erro nenhum aparecer em lugar nenhum.
#
# "npm ci", NAO "npm install": ci respeita o package-lock.json exatamente
# como esta commitado; install pode subir versao dentro dos "^" do
# package.json e mudar o front numa operacao que deveria so publicar.
# ============================================================================

$ScriptDir   = Split-Path -Parent $PSCommandPath
$ProjetoRaiz = Split-Path -Parent $ScriptDir
$WebDir      = Join-Path $ProjetoRaiz "web"
$ServicoNome = "app_compras"

Write-Host ""
Write-Host "========================================================================="
Write-Host " PUBLICAR FRONT - app_compras"
Write-Host "========================================================================="
Write-Host ""

if (-not (Test-Path $WebDir)) {
    Write-Host " [ERRO] Nao encontrei $WebDir."
    Exit 1
}

Push-Location $WebDir
try {
    Write-Host " Rodando 'npm ci'..."
    npm ci
    if ($LASTEXITCODE -ne 0) {
        Write-Host " [ERRO] 'npm ci' falhou."
        Write-Host " O que fazer: confira se package-lock.json esta presente e integro, e se o Node esta no PATH."
        Exit 1
    }

    Write-Host ""
    Write-Host " Rodando 'npm run build'..."
    npm run build
    if ($LASTEXITCODE -ne 0) {
        Write-Host " [ERRO] 'npm run build' falhou."
        Write-Host " O que fazer: leia o erro acima - normalmente e erro de sintaxe introduzido no codigo do front."
        Exit 1
    }
} finally {
    Pop-Location
}

$IndexHtml = Join-Path $ProjetoRaiz "app\static\v2\index.html"
if (-not (Test-Path $IndexHtml)) {
    Write-Host " [ERRO] O build terminou mas nao encontrei $IndexHtml."
    Write-Host " O que fazer: confira outDir em web\vite.config.js (esperado: ../app/static/v2)."
    Exit 1
}
Write-Host ""
Write-Host " Build gerado em: $(Split-Path -Parent $IndexHtml)"

# O nginx serve os estaticos direto (sem cache de processo), entao o build
# novo ja vale para requisicoes futuras assim que os arquivos forem trocados.
# Mesmo assim reinicia-se o servico da API, para o caso de a publicacao ter
# vindo junto com mudanca de backend.
$Servico = Get-Service -Name $ServicoNome -ErrorAction SilentlyContinue
if ($Servico) {
    Write-Host ""
    Write-Host " Reiniciando servico $ServicoNome..."
    Restart-Service -Name $ServicoNome
    Start-Sleep -Seconds 2
    $Servico = Get-Service -Name $ServicoNome
    Write-Host " Status: $($Servico.Status)"
} else {
    Write-Host ""
    Write-Host " [AVISO] Servico '$ServicoNome' nao esta instalado - build publicado, nada para reiniciar."
    Write-Host "         (normal em ambiente de teste, antes de infra\instalar_servico.ps1)"
}

Write-Host ""
Write-Host " Publicacao concluida."
Write-Host ""
