# AI

Fully-local AI stack — no big-tech cloud APIs. Local models (Ollama) plus a
private web-search layer (SearXNG) so the assistant can still answer real-world
questions, exposed through a local chat UI (Open WebUI) and reusable by Home
Assistant and n8n.

## Services

| Service | Image | Purpose |
|---|---|---|
| **ollama** | `ollama/ollama` | Local LLM runtime (GPU). Shared by Open WebUI, Postiz/n8n, and Home Assistant. |
| **searxng** | `searxng/searxng` | Private metasearch — the "call out to the world" layer, no tracking/accounts. |
| **open-webui** | `ghcr.io/open-webui/open-webui` | Local ChatGPT-style UI for Ollama, with SearXNG-backed web search + citations. |

Nothing here talks to OpenAI/Google/Anthropic. SearXNG is the only component
that reaches the internet, and it does so anonymously on your behalf.

## Architecture

```
Open WebUI ─┐
Home Assistant ─┼─► ollama (local models, GPU)
n8n ─────────┘        │
                      └─► searxng (private web search) ─► the internet (anonymized)
```

## `.env` additions

```
# openssl rand -hex 32
SEARXNG_SECRET=<random-hex>
OPENWEBUI_SECRET_KEY=<random-hex>
```
`TZ`, `DOMAIN`, `APPDATA_PATH`, and `HOST_HOSTNAME` are already defined globally.

---

## One-time migration: `ollama-postiz` → generic `ollama`

Ollama used to live in `services/automation/postiz-stack` as `ollama-postiz`.
It now lives here as a generic `ollama`. Migrate **without re-downloading models**:

```bash
# 1. Remove the old container (its definition is gone from postiz-stack)
docker rm -f ollama-postiz

# 2. Move the model data to the generic appdata path (preserves pulled models)
mv /mnt/user/appdata/postiz-stack/ollama /mnt/user/appdata/ollama

# 3. Bring up the generic ollama
cd services/ai/ollama && docker-compose --env-file ../../../.env up -d

# 4. Redeploy postiz-stack so n8n reconnects (it now reaches http://ollama:11434)
cd ../../automation/postiz-stack && docker-compose --env-file ../../../.env up -d
```

**Home Assistant:** update the Ollama integration URL from
`http://ollama-postiz:11434` → **`http://ollama:11434`**
(Settings → Devices & Services → Ollama → Configure).

Verify: `docker exec ollama ollama list` should show your existing models.

---

## Deploy

```bash
# SearXNG — seed its config first (enables the JSON API, sets the secret)
mkdir -p /mnt/user/appdata/searxng
cp services/ai/searxng/settings.yml /mnt/user/appdata/searxng/settings.yml
cd services/ai/searxng && docker-compose --env-file ../../../.env up -d

# Open WebUI
cd ../open-webui && docker-compose --env-file ../../../.env up -d
```

- **Chat UI:** `https://chat.${DOMAIN}` — create the first account (it becomes admin), pick a model, toggle **Web Search** in a chat to use SearXNG.
- **Search:** `https://search.${DOMAIN}` — the SearXNG UI (also the JSON API at `/search?q=...&format=json`).

---

## Home Assistant "call out" (live real-world answers), fully local

Keep device control on HA's built-in intents (instant, reliable). For live
questions, route through n8n so you sidestep HA's flaky on-device tool loop:

```
HA (fallback) ─► n8n webhook ─► SearXNG (JSON) ─► ollama (summarize) ─► answer back to HA (spoken)
```

Sketch of the n8n workflow (you already run n8n in the postiz-stack):
1. **Webhook** node — receives `{ "query": "..." }` from HA.
2. **HTTP Request** node — `GET http://searxng:8080/search?q={{$json.query}}&format=json`.
3. **HTTP Request** (or Ollama) node — POST the query + top results to
   `http://ollama:11434/api/generate` with a "answer using these results" prompt.
4. **Respond to Webhook** — return the model's text.

In Home Assistant, call that webhook from an intent script / automation for
questions the built-in agent can't answer, and speak the response.

## Notes

- **VRAM (8 GB):** only `ollama` uses the GPU; SearXNG and Open WebUI are CPU/RAM
  only. Keep Ollama to 7–8B Q4 models.
- **Image tags** are starting pins — if a pull 404s, check the current tag;
  Renovate also proposes bumps automatically.
