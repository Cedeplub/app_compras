# ============================================================================
# Instala/atualiza o vhost do Dashboard de Compras no nginx desta maquina.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File infra\instalar_nginx.ps1
#
# O que faz, NESTA ordem (nunca fora dela):
#   1. Backup de C:\nginx\conf\nginx.conf -> nginx.conf.bkp-<AAAAMMDD>
#      (padrao ja usado nesta maquina - existe um .bkp-20260728)
#   2. Copia infra\nginx\compras.conf para C:\nginx\conf\compras.conf
#   3. Acrescenta "include compras.conf;" dentro do http{} de nginx.conf,
#      se ainda nao estiver la (idempotente - nao duplica em execucao
#      repetida)
#   4. Roda "nginx -t"
#   5. SO SE o -t passar: "nginx -s reload"
#      Se o -t falhar: restaura o backup do nginx.conf, remove o
#      compras.conf copiado, e NAO recarrega - gestaosac.cdp.lub e
#      dre.cdp.lub sao producao de outras areas no MESMO nginx.conf; um
#      reload com config invalida os derrubaria junto.
#
# Requisitos: rodar como administrador; C:\nginx\nginx.exe existir.
#
# Para desfazer: infra\desinstalar_nginx.ps1
# ============================================================================

$NginxDir     = "C:\nginx"
$NginxConf    = Join-Path $NginxDir "conf\nginx.conf"
$NginxExe     = Join-Path $NginxDir "nginx.exe"
$ScriptDir    = Split-Path -Parent $PSCommandPath
$VhostOrigem  = Join-Path $ScriptDir "nginx\compras.conf"
$VhostDestino = Join-Path $NginxDir "conf\compras.conf"
$DataHoje     = Get-Date -Format "yyyyMMdd"
$Backup       = Join-Path $NginxDir "conf\nginx.conf.bkp-$DataHoje"

Write-Host ""
Write-Host "========================================================================="
Write-Host " INSTALAR VHOST NGINX - compras.cdp.lub"
Write-Host "========================================================================="
Write-Host ""

$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Host " [ERRO] Este script precisa rodar como Administrador."
    Write-Host " O que fazer: clique com o botao direito em PowerShell e escolha 'Executar como Administrador'."
    Exit 1
}

if (-not (Test-Path $NginxExe)) {
    Write-Host " [ERRO] Nao encontrei $NginxExe."
    Write-Host " O que fazer: confirme que o nginx esta instalado em C:\nginx nesta maquina."
    Exit 1
}
if (-not (Test-Path $NginxConf)) {
    Write-Host " [ERRO] Nao encontrei $NginxConf."
    Exit 1
}
if (-not (Test-Path $VhostOrigem)) {
    Write-Host " [ERRO] Nao encontrei $VhostOrigem."
    Write-Host " O que fazer: confirme que infra\nginx\compras.conf existe no repositorio."
    Exit 1
}

# --- 1. Backup, sempre, antes de qualquer mudanca -------------------------
Copy-Item $NginxConf $Backup -Force
Write-Host " Backup criado: $Backup"

# --- 2. Copia o vhost -----------------------------------------------------
Copy-Item $VhostOrigem $VhostDestino -Force
Write-Host " Vhost copiado para: $VhostDestino"

# --- 3. Acrescenta o include, se faltar ------------------------------------
$Conteudo = Get-Content $NginxConf -Raw
if ($Conteudo -notmatch "include\s+compras\.conf;") {
    # Mesmo padrao do "include mime.types;" ja existente no arquivo - prova
    # que caminho relativo a conf\ funciona sem precisar de caminho absoluto.
    $NovoConteudo = $Conteudo -replace "(http\s*\{)", "`$1`r`n    include       compras.conf;"
    Set-Content -Path $NginxConf -Value $NovoConteudo -NoNewline
    Write-Host " Linha 'include compras.conf;' acrescentada em nginx.conf."
} else {
    Write-Host " nginx.conf ja tinha o include - nao duplicado."
}

# --- 4. Testa antes de recarregar (NAO OPCIONAL) ---------------------------
Write-Host ""
Write-Host " Rodando 'nginx -t'..."
$TesteSaida = & $NginxExe -t -p $NginxDir -c "conf\nginx.conf" 2>&1
Write-Host $TesteSaida
$TesteOk = ($LASTEXITCODE -eq 0)

if (-not $TesteOk) {
    Write-Host ""
    Write-Host " [ERRO] 'nginx -t' falhou. Restaurando o backup e NAO recarregando."
    Copy-Item $Backup $NginxConf -Force
    Remove-Item $VhostDestino -Force -ErrorAction SilentlyContinue
    Write-Host " nginx.conf restaurado ao estado anterior. gestaosac.cdp.lub e dre.cdp.lub"
    Write-Host " nao foram afetados."
    Write-Host " O que fazer: corrija infra\nginx\compras.conf neste repositorio e rode"
    Write-Host "              este script de novo."
    Exit 1
}

# --- 5. So recarrega se o -t passou ---------------------------------------
# O reload (-s reload) e gracioso: as conexoes em curso terminam sozinhas,
# nao sao cortadas - importante porque gestaosac.cdp.lub e dre.cdp.lub estao
# no MESMO nginx.conf. Por isso ele continua sendo o caminho padrao aqui, e
# NAO trocamos por Restart-Service de cara.
#
# Mas nesta maquina o servico Nginx roda como LocalSystem, e uma sessao de
# Administrador nao consegue sinalizar o evento Global\ngx_reload_<pid> que o
# "-s reload" usa para avisar o master - o processo termina com
# "OpenEvent(...) failed (5: Access is denied)" e exit code != 0. Isso NAO e
# uma excecao rara, e o comportamento normal desta maquina (ver
# infra/README.md). Quando for exatamente esse erro, e so esse, caimos para
# "Restart-Service Nginx -Force": e seguro porque o "nginx -t" ja validou o
# config em disco linhas acima - so falta aplica-lo. Restart derruba as
# conexoes dos 3 vhosts por um instante (mais bruto que reload), mas e a
# alternativa real quando o reload gracioso esta bloqueado nesta maquina.
# Qualquer OUTRO motivo de falha do reload NAO aciona esse fallback - o script
# para e avisa, em vez de reiniciar as cegas por um erro que nao reconhece.
$ProcessosAntes = Get-Process nginx -ErrorAction SilentlyContinue | Select-Object Id, StartTime

Write-Host ""
Write-Host " 'nginx -t' passou. Recarregando..."
$ReloadSaida = & $NginxExe -s reload -p $NginxDir -c "conf\nginx.conf" 2>&1
$ReloadExit  = $LASTEXITCODE

if ($ReloadExit -ne 0) {
    Write-Host " [AVISO] 'nginx -s reload' terminou com codigo $ReloadExit :"
    Write-Host " $ReloadSaida"

    if ($ReloadSaida -match "Access is denied" -or $ReloadSaida -match "ngx_reload_") {
        Write-Host ""
        Write-Host " Causa conhecida nesta maquina (ver infra/README.md): o servico roda como"
        Write-Host " LocalSystem e esta sessao nao consegue sinalizar o evento de reload."
        Write-Host " Aplicando o fallback: 'Restart-Service Nginx -Force' (o config ja foi"
        Write-Host " validado pelo 'nginx -t' acima, entao reiniciar e seguro)."
        Restart-Service Nginx -Force
        Start-Sleep -Seconds 1
    } else {
        Write-Host ""
        Write-Host " [ERRO] O reload falhou por um motivo que NAO e o 'Access is denied'"
        Write-Host " conhecido nesta maquina. NAO vou reiniciar o servico as cegas."
        Write-Host " O que fazer: rode 'C:\nginx\nginx.exe -s reload' a mao, leia o erro,"
        Write-Host "              e so entao decida corrigir ou reiniciar o servico manualmente."
        Exit 1
    }
}

# --- Confirma que a mudanca REALMENTE entrou em vigor (nao so que o comando
#     nao deu erro) - compara os processos nginx de antes e depois. Um reload
#     bem-sucedido substitui os workers (PIDs novos); um restart substitui
#     tambem o master. Se nenhum PID novo aparecer, a config pode ter ficado
#     so no disco, nao em memoria.
Start-Sleep -Milliseconds 500
$IdsAntes       = @($ProcessosAntes | ForEach-Object { $_.Id })
$ProcessosDepois = Get-Process nginx -ErrorAction SilentlyContinue
$Aplicou = $false
foreach ($p in $ProcessosDepois) {
    if ($IdsAntes -notcontains $p.Id) { $Aplicou = $true }
}

if (-not $Aplicou) {
    Write-Host ""
    Write-Host " [ERRO] Nenhum processo nginx novo apareceu depois do reload/restart."
    Write-Host " Isso quer dizer que a configuracao pode ter ficado SO no disco, NAO em vigor."
    Write-Host " O que fazer: rode 'Get-Process nginx' e '$NginxExe -s reload' a mao para"
    Write-Host "              investigar antes de considerar isto instalado."
    Exit 1
}

Write-Host ""
Write-Host " nginx recarregado com sucesso - confirmado: processo(s) novo(s) no ar."
Write-Host " Confira: http://compras.cdp.lub/ e http://192.168.0.50/"
Write-Host " Confira tambem que gestaosac.cdp.lub e dre.cdp.lub continuam respondendo."
Write-Host ""
