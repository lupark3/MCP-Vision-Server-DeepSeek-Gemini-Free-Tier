# MCP Vision Server — DeepSeek + Gemini Free Tier

Adiciona analise de imagens ao Claude CLI usando modelos de texto puro (DeepSeek, etc.) via MCP + Gemini API gratuita.

## Como funciona

```
Claude CLI (DeepSeek)
  -> analyze_image("foto.png")
  -> MCP Server (Python, stdio)
  -> Gemini API (free tier, custo zero)
  -> descricao textual
  -> DeepSeek responde como se tivesse "visto" a imagem
```

## Fallback automatico

O servidor tenta 4 combinacoes em cadeia antes de desistir:

```
key1 + gemini-3.1-flash-lite  (RPM 15, RPD 500)
  -> 429/503 -> key1 + gemini-2.5-flash-lite  (RPM 10, RPD 20)
  -> 429 cota -> key2 + gemini-3.1-flash-lite
  -> 429/503 -> key2 + gemini-2.5-flash-lite
  -> falha todas -> erro descritivo
```

| Erro | Significado | Acao |
|------|-------------|------|
| 403/401 | Chave invalida | Abandona a chave |
| 429 | Cota diaria esgotada | Proximo modelo/chave |
| 503 | Modelo saturado | Proximo modelo |

## Instalacao

### Pre-requisitos (todas as plataformas)

- Python 3.10+
- 1 ou 2 chaves API Gemini (gratuitas, sem cartao de credito)
- Claude CLI instalado

Obtenha as chaves em: https://aistudio.google.com/apikey

### Instalacao automatica (recomendado)

#### Linux / macOS

```bash
chmod +x install.sh
./install.sh
```

O script pergunta as chaves API (1 obrigatoria, 1 opcional) e configura tudo automaticamente.

#### Windows (PowerShell)

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\install.ps1
```

O script pergunta as chaves API (1 obrigatoria, 1 opcional) e configura tudo automaticamente.

### Instalacao manual

Caso prefira controle total, siga os passos abaixo.

#### Linux / macOS

```bash
python3 -m pip install mcp
mkdir -p ~/.claude/mcp-servers/vision-fallback
cp server.py ~/.claude/mcp-servers/vision-fallback/server.py
```

Adicione ao `~/.claude.json` no objeto `mcpServers`:

```json
"ai-vision": {
  "type": "stdio",
  "command": "python3",
  "args": [
    "/home/seu-usuario/.claude/mcp-servers/vision-fallback/server.py"
  ],
  "env": {
    "VISION_API_KEY_1": "sua-chave-1",
    "VISION_API_KEY_2": "sua-chave-2"
  }
}
```

Se tiver apenas 1 chave, remova a linha `VISION_API_KEY_2`.

Reinicie o Claude CLI.

#### Windows

```powershell
python -m pip install mcp
mkdir %USERPROFILE%\.claude\mcp-servers\vision-fallback
copy server.py %USERPROFILE%\.claude\mcp-servers\vision-fallback\server.py
```

Adicione ao `%USERPROFILE%\.claude.json` no objeto `mcpServers`:

```json
"ai-vision": {
  "type": "stdio",
  "command": "python",
  "args": [
    "C:\\Users\\SeuUsuario\\.claude\\mcp-servers\\vision-fallback\\server.py"
  ],
  "env": {
    "VISION_API_KEY_1": "sua-chave-1",
    "VISION_API_KEY_2": "sua-chave-2"
  }
}
```

Use o caminho absoluto real, nao `%USERPROFILE%`. Se tiver apenas 1 chave, remova `VISION_API_KEY_2`.

Reinicie o Claude CLI.

## Verificacao

Apos reiniciar, abra o gerenciador de MCPs (`/mcp` no Claude CLI). O servidor `ai-vision` deve aparecer com 1 ferramenta (`analyze_image`).

Teste basico:
```
Descreva detalhadamente a imagem /caminho/para/foto.png
```

O resultado inclui metadados ao final:
```
Modelo usado: gemini-3.1-flash-lite
Cadeia tentada: key=AIzaSyAwR8kF... model=gemini-3.1-flash-lite
```

## Modelos Gemini Free Tier (maio/2026)

| Modelo | RPM | TPM | RPD | Visao |
|--------|-----|-----|-----|-------|
| Gemini 3.1 Flash-Lite | 15 | 250K | 500 | Sim |
| Gemini 2.5 Flash-Lite | 10 | 250K | 20 | Sim |
| Gemini 2.5 Flash | 5 | 250K | 20 | Sim |
| Gemini 3.5 Flash | 5 | 250K | 20 | Sim |

Consulte seus limites em: https://aistudio.google.com/rate-limit

## Customizacao

Para usar modelos diferentes, edite as constantes no inicio do `server.py`:

```python
MODEL_PRIMARY = "gemini-3.5-flash"
MODEL_FALLBACK = "gemini-2.5-flash"
```

Para usar apenas 1 chave API, deixe `VISION_API_KEY_2` vazia. A cadeia pula entradas com chave vazia automaticamente.

## Troubleshooting

| Problema | Solucao |
|----------|---------|
| MCP server nao aparece | Verifique `python -c "from mcp.server import Server"` |
| Erro 403 em todas as tentativas | Chave API invalida. Gere uma nova em aistudio.google.com |
| Erro 429 em todas as tentativas | Cota diaria esgotada para ambas as chaves. Aguarde reset (meia-noite UTC) |
| Erro "model is no longer available" | Atualize MODEL_PRIMARY/FALLBACK no server.py com modelos ativos |

## Licenca

MIT — veja [LICENSE](LICENSE).
