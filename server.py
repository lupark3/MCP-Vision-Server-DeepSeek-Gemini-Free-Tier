#!/usr/bin/env python3
"""
MCP Vision Server — DeepSeek + Gemini Free Tier Integration

Adiciona capacidade de analise de imagens ao Claude CLI com DeepSeek,
usando um MCP server como ponte para a API Gemini (free tier, custo zero).

Caracteristicas:
- Fallback automatico: 2 chaves API + 2 modelos em cadeia
- Classificacao inteligente de erros (429 quota, 503 overloaded, 403 auth)
- Suporte a imagem local, URL ou base64
- Zero dependencias alem do pacote MCP Python SDK

Licenca: MIT
"""

import base64
import json
import mimetypes
import urllib.request
import urllib.error
import os
from pathlib import Path

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent

# ============================================================
# Configuracao — customize aqui ou via variaveis de ambiente
# ============================================================

API_KEY_1 = os.environ.get("VISION_API_KEY_1", "")
API_KEY_2 = os.environ.get("VISION_API_KEY_2", "")

MODEL_PRIMARY = "gemini-3.1-flash-lite"
MODEL_FALLBACK = "gemini-2.5-flash-lite"

# Cadeia de fallback: [(chave, modelo), ...]
FALLBACK_CHAIN = [
    (API_KEY_1, MODEL_PRIMARY),
    (API_KEY_1, MODEL_FALLBACK),
    (API_KEY_2, MODEL_PRIMARY),
    (API_KEY_2, MODEL_FALLBACK),
]

# ============================================================
# Logica de chamada a API Gemini
# ============================================================


def _call_gemini(key: str, model: str, image_data: bytes, mime_type: str, prompt: str) -> str:
    """Chama a API Gemini para analise de imagem. Levanta excecao em erro."""
    img_b64 = base64.b64encode(image_data).decode()
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}"
    payload = json.dumps({
        "contents": [{
            "parts": [
                {"text": prompt},
                {"inline_data": {"mime_type": mime_type, "data": img_b64}}
            ]
        }]
    }).encode()
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    resp = urllib.request.urlopen(req, timeout=90)
    result = json.loads(resp.read())
    return result["candidates"][0]["content"]["parts"][0]["text"]


def _classify_error(e: urllib.error.HTTPError) -> str:
    """Classifica o erro HTTP da API Gemini."""
    code = e.code
    if code in (401, 403):
        return "auth"
    if code == 429:
        return "quota"
    if code == 503:
        return "overloaded"
    return "other"


def analyze_with_fallback(image_data: bytes, mime_type: str, prompt: str) -> dict:
    """Executa a cadeia de fallback completa.

    Logica:
    - 403/401 (chave invalida): abandona a chave, vai pra proxima
    - 429 (cota esgotada): tenta proximo modelo, depois proxima chave
    - 503 (modelo saturado): tenta proximo modelo
    """
    last_error = None
    tried = []

    for key, model in FALLBACK_CHAIN:
        if not key:
            continue
        key_masked = key[:12] + "..." if len(key) > 12 else key
        attempt = f"key={key_masked} model={model}"
        tried.append(attempt)
        try:
            text = _call_gemini(key, model, image_data, mime_type, prompt)
            return {
                "success": True,
                "text": text,
                "model_used": model,
                "key_used": key_masked,
                "attempts": tried,
            }
        except urllib.error.HTTPError as e:
            error_type = _classify_error(e)
            err_body = {}
            try:
                err_body = json.loads(e.read())
            except Exception:
                pass
            last_error = f"[{e.code}] {error_type}: {err_body.get('error', {}).get('message', str(e))}"
            if error_type == "auth":
                break  # nao adianta tentar outros modelos com chave invalida
            continue
        except Exception as e:
            last_error = str(e)
            continue

    return {
        "success": False,
        "text": "",
        "error": last_error,
        "attempts": tried,
    }


def _load_image(source: str) -> tuple[bytes, str]:
    """Carrega imagem de arquivo local, URL ou base64 inline."""
    if source.startswith("data:"):
        header, b64 = source.split(",", 1)
        mime = header.split(":")[1].split(";")[0]
        return base64.b64decode(b64), mime
    elif source.startswith("http://") or source.startswith("https://"):
        req = urllib.request.Request(source, headers={"User-Agent": "Mozilla/5.0"})
        resp = urllib.request.urlopen(req, timeout=30)
        data = resp.read()
        mime = resp.headers.get("Content-Type", "image/png")
        return data, mime
    else:
        path = Path(source).expanduser().resolve()
        if not path.exists():
            raise FileNotFoundError(f"Arquivo nao encontrado: {path}")
        mime, _ = mimetypes.guess_type(str(path))
        if not mime:
            mime = "image/png"
        return path.read_bytes(), mime


# ============================================================
# MCP Server
# ============================================================

server = Server("vision-fallback")


@server.list_tools()
async def list_tools():
    return [
        Tool(
            name="analyze_image",
            description=(
                "Analisa uma imagem usando IA com fallback automatico de modelo e API key. "
                "Suporta imagens locais, URLs ou base64. "
                f"Cadeia: {MODEL_PRIMARY} -> {MODEL_FALLBACK} com 2 chaves API."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "imageSource": {
                        "type": "string",
                        "description": "Caminho local, URL ou data URI (base64) da imagem",
                    },
                    "prompt": {
                        "type": "string",
                        "description": "Instrucao ou pergunta sobre a imagem",
                    },
                },
                "required": ["imageSource", "prompt"],
            },
        )
    ]


@server.call_tool()
async def call_tool(name: str, arguments: dict):
    if name != "analyze_image":
        raise ValueError(f"Ferramenta desconhecida: {name}")

    image_source = arguments.get("imageSource", "")
    prompt = arguments.get("prompt", "Descreva esta imagem em detalhes.")

    try:
        image_data, mime_type = _load_image(image_source)
    except Exception as e:
        return [TextContent(type="text", text=f"Erro ao carregar imagem: {e}")]

    result = analyze_with_fallback(image_data, mime_type, prompt)

    if result["success"]:
        output = (
            f"{result['text']}\n\n"
            f"---\n"
            f"Modelo usado: {result['model_used']}\n"
            f"Cadeia tentada: {', '.join(result['attempts'])}"
        )
    else:
        output = (
            f"Falha em todas as tentativas de analise.\n"
            f"Erro final: {result.get('error', 'desconhecido')}\n"
            f"Cadeia tentada: {', '.join(result['attempts'])}"
        )

    return [TextContent(type="text", text=output)]


async def main():
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream, server.create_initialization_options())


if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
