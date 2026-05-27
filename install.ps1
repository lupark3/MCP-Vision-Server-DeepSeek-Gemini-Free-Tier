# ============================================================
# MCP Vision Server — Instalador Windows
# ============================================================
# Execute no PowerShell:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   .\install.ps1

$ErrorActionPreference = "Stop"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  MCP Vision Server — Instalador Windows" -ForegroundColor Cyan
Write-Host "  DeepSeek + Gemini Free Tier" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# --- Python check ---
$python = $null
foreach ($cmd in @("python", "python3")) {
    $found = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($found) {
        $python = $cmd
        break
    }
}

if (-not $python) {
    Write-Host "Erro: Python 3 nao encontrado. Instale Python 3.10+ primeiro." -ForegroundColor Red
    Write-Host "https://www.python.org/downloads/" -ForegroundColor Yellow
    exit 1
}

$pythonPath = (Get-Command $python).Source
$pythonVer = & $python --version 2>&1
Write-Host "Python: $pythonPath ($pythonVer)" -ForegroundColor Green

# --- Install MCP SDK ---
Write-Host ""
Write-Host "Instalando dependencia MCP..." -ForegroundColor Yellow
& $python -m pip install mcp --quiet 2>$null
$check = & $python -c "from mcp.server import Server; print('ok')" 2>&1
if ($check -eq "ok") {
    Write-Host "MCP SDK: OK" -ForegroundColor Green
} else {
    Write-Host "Erro ao instalar pacote MCP. Execute manualmente: $python -m pip install mcp" -ForegroundColor Red
    exit 1
}

# --- API Keys ---
Write-Host ""
Write-Host "Configuracao das chaves API Gemini" -ForegroundColor Cyan
Write-Host "Obtenha chaves gratuitas em: https://aistudio.google.com/apikey" -ForegroundColor Yellow
Write-Host ""

$key1 = Read-Host "Chave API primaria (obrigatoria)"
if (-not $key1) {
    Write-Host "Erro: Pelo menos uma chave API e necessaria." -ForegroundColor Red
    exit 1
}

$key2 = Read-Host "Chave API secundaria (opcional, Enter para pular)"

# --- Directories ---
$serverDir = "$env:USERPROFILE\.claude\mcp-servers\vision-fallback"
New-Item -ItemType Directory -Force -Path $serverDir | Out-Null

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourcePy = Join-Path $scriptDir "server.py"
if (Test-Path $sourcePy) {
    Copy-Item $sourcePy $serverDir -Force
    Write-Host "server.py: copiado para $serverDir" -ForegroundColor Green
} else {
    Write-Host "Erro: server.py nao encontrado em $scriptDir" -ForegroundColor Red
    Write-Host "Certifique-se de executar este script do diretorio mcp-server\" -ForegroundColor Red
    exit 1
}

# --- Build MCP config ---
$claudeJson = "$env:USERPROFILE\.claude.json"

if (-not (Test-Path $claudeJson)) {
    Write-Host "claude.json: nao encontrado, criando..." -ForegroundColor Yellow
    '{}' | Set-Content $claudeJson -Encoding UTF8
} else {
    Write-Host "claude.json: encontrado" -ForegroundColor Green
}

# Read, update, write JSON
$config = Get-Content $claudeJson -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not $config.mcpServers) {
    $config | Add-Member -MemberType NoteProperty -Name "mcpServers" -Value @{} -Force
}

$envBlock = @{ "VISION_API_KEY_1" = $key1 }
if ($key2) {
    $envBlock["VISION_API_KEY_2"] = $key2
}

$serverEntry = @{
    type = "stdio"
    command = "python"
    args = @($serverDir + "\server.py")
    env = $envBlock
}

$config.mcpServers | Add-Member -MemberType NoteProperty -Name "ai-vision" -Value $serverEntry -Force

$config | ConvertTo-Json -Depth 4 | Set-Content $claudeJson -Encoding UTF8
Write-Host "Configuracao injetada no claude.json" -ForegroundColor Green

# --- Done ---
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Instalacao concluida!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Servidor instalado em: $serverDir" -ForegroundColor Cyan
if ($key2) {
    Write-Host "Chaves configuradas: 1 primaria + 1 secundaria" -ForegroundColor Green
} else {
    Write-Host "Chaves configuradas: 1 primaria" -ForegroundColor Green
}
Write-Host ""
Write-Host "Reinicie o Claude CLI para ativar o servidor." -ForegroundColor Yellow
Write-Host "Apos reiniciar, teste com:" -ForegroundColor Yellow
Write-Host "  Descreva detalhadamente a imagem C:\Users\SeuUsuario\Pictures\foto.png" -ForegroundColor Cyan
Write-Host ""
