#!/usr/bin/env bash
set -e

# ============================================================
# MCP Vision Server — Instalador Linux/macOS
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  MCP Vision Server — Instalador${NC}"
echo -e "${CYAN}  DeepSeek + Gemini Free Tier${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

# --- Python check ---
PYTHON=""
for cmd in python3 python; do
    if command -v "$cmd" &>/dev/null; then
        PYTHON="$cmd"
        break
    fi
done

if [ -z "$PYTHON" ]; then
    echo -e "${RED}Erro: Python 3 nao encontrado. Instale Python 3.10+ primeiro.${NC}"
    exit 1
fi

PYTHON_PATH=$(command -v "$PYTHON")
PYTHON_VER=$("$PYTHON" --version 2>&1)
echo -e "Python: ${GREEN}$PYTHON_PATH${NC} ($PYTHON_VER)"

# --- Install MCP SDK ---
echo -e "\n${YELLOW}Instalando dependencia MCP...${NC}"
"$PYTHON" -m pip install mcp --quiet 2>/dev/null
if "$PYTHON" -c "from mcp.server import Server" 2>/dev/null; then
    echo -e "MCP SDK: ${GREEN}OK${NC}"
else
    echo -e "${RED}Erro ao instalar pacote MCP. Execute manualmente: $PYTHON -m pip install mcp${NC}"
    exit 1
fi

# --- API Keys ---
echo ""
echo -e "${CYAN}Configuracao das chaves API Gemini${NC}"
echo -e "Obtenha chaves gratuitas em: ${YELLOW}https://aistudio.google.com/apikey${NC}"
echo ""

read -r -p "Chave API primaria (obrigatoria): " KEY1
if [ -z "$KEY1" ]; then
    echo -e "${RED}Erro: Pelo menos uma chave API e necessaria.${NC}"
    exit 1
fi

read -r -p "Chave API secundaria (opcional, Enter para pular): " KEY2

# --- Directories ---
SERVER_DIR="$HOME/.claude/mcp-servers/vision-fallback"
mkdir -p "$SERVER_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/server.py" ]; then
    cp "$SCRIPT_DIR/server.py" "$SERVER_DIR/server.py"
    echo -e "server.py: ${GREEN}copiado para $SERVER_DIR/${NC}"
else
    echo -e "${RED}Erro: server.py nao encontrado no diretorio atual.${NC}"
    echo -e "Certifique-se de executar este script do diretorio mcp-server/"
    exit 1
fi

# --- Build MCP config ---
CLAUDE_JSON="$HOME/.claude.json"

if [ -f "$CLAUDE_JSON" ]; then
    echo -e "claude.json: ${GREEN}encontrado${NC}"
else
    echo -e "claude.json: ${YELLOW}nao encontrado, criando...${NC}"
    echo '{}' > "$CLAUDE_JSON"
fi

# Build env block
if [ -n "$KEY2" ]; then
    ENV_BLOCK=$(cat <<EOF
        "VISION_API_KEY_1": "$KEY1",
        "VISION_API_KEY_2": "$KEY2"
EOF
)
else
    ENV_BLOCK=$(cat <<EOF
        "VISION_API_KEY_1": "$KEY1"
EOF
)
fi

MCP_ENTRY=$(cat <<EOF
    "ai-vision": {
      "type": "stdio",
      "command": "$PYTHON",
      "args": [
        "$SERVER_DIR/server.py"
      ],
      "env": {
$ENV_BLOCK
      }
    }
EOF
)

# --- Inject into claude.json using Python ---
"$PYTHON" << PYEOF
import json, sys

with open("$CLAUDE_JSON", "r") as f:
    config = json.load(f)

if "mcpServers" not in config:
    config["mcpServers"] = {}

config["mcpServers"]["ai-vision"] = {
    "type": "stdio",
    "command": "$PYTHON",
    "args": ["$SERVER_DIR/server.py"],
    "env": {"VISION_API_KEY_1": "$KEY1"}
}
if "$KEY2":
    config["mcpServers"]["ai-vision"]["env"]["VISION_API_KEY_2"] = "$KEY2"

with open("$CLAUDE_JSON", "w") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)

print("Configuracao injetada no claude.json")
PYEOF

# --- Done ---
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Instalacao concluida!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "Servidor instalado em: ${CYAN}$SERVER_DIR${NC}"
echo -e "Chaves configuradas: ${GREEN}1${NC}$([ -n "$KEY2" ] && echo -e " + ${GREEN}1${NC} secundaria")"
echo ""
echo -e "${YELLOW}Reinicie o Claude CLI para ativar o servidor.${NC}"
echo -e "Apos reiniciar, teste com:"
echo -e "  ${CYAN}Descreva detalhadamente a imagem /caminho/foto.png${NC}"
echo ""
