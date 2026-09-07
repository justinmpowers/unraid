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

> **Deployment:** every service here is a **Portainer Git stack** pulled from
> this repo — no local `docker-compose` CLI. Stack names follow
> `ai-<name>` (`ai-ollama`, `ai-searxng`, `ai-open-webui`).

## `.env` additions

Add these to the **root `.env`**, then regenerate the per-stack env files:

```
# openssl rand -hex 32
SEARXNG_SECRET=<random-hex>
OPENWEBUI_SECRET_KEY=<random-hex>
```
```bash
./scripts/generate-stack-envs.sh      # writes services/ai/<name>/.env for each stack
```
`TZ`, `DOMAIN`, `APPDATA_PATH`, and `HOST_HOSTNAME` are already defined globally.

---

## One-time migration: `ollama-postiz` → generic `ollama`

Ollama used to live in `services/automation/postiz-stack` as `ollama-postiz`.
It now lives here as a generic `ollama`. Migrate **without re-downloading models**:

On the Unraid host, prep the container + model data:
```bash
# 1. Remove the old container (its definition is gone from postiz-stack)
docker rm -f ollama-postiz

# 2. Move the model data to the SSD cache pool (CACHE_PATH, e.g. /mnt/cache),
#    preserving pulled models. Match this to your CACHE_PATH value.
mv /mnt/user/appdata/postiz-stack/ollama /mnt/cache/ollama
```

Then, in **Portainer**:
3. **Add stack** `ai-ollama` (compose path `services/ai/ollama/docker-compose.yml`,
   env `services/ai/ollama/.env`) and **Deploy**.
4. Open the **`automation-postiz-stack`** stack and **Pull and redeploy** so n8n
   reconnects — it now reaches the generic container at `http://ollama:11434`.

**Home Assistant:** update the Ollama integration URL from
`http://ollama-postiz:11434` → **`http://ollama:11434`**
(Settings → Devices & Services → Ollama → Configure).

Verify: `docker exec ollama ollama list` should show your existing models.

---

## Deploy

**SearXNG** — seed its config on the host first (enables the JSON API + secret),
then deploy the stack in Portainer:
```bash
mkdir -p /mnt/user/appdata/searxng
cp services/ai/searxng/settings.yml /mnt/user/appdata/searxng/settings.yml
```
In **Portainer → Add stack**, create each stack from this repo (branch `main`):

| Stack | Compose path | Env file |
|---|---|---|
| `ai-searxng` | `services/ai/searxng/docker-compose.yml` | `services/ai/searxng/.env` |
| `ai-open-webui` | `services/ai/open-webui/docker-compose.yml` | `services/ai/open-webui/.env` |

- **Chat UI:** `https://chat.${DOMAIN}` — create the first account (it becomes admin), pick a model, toggle **Web Search** in a chat to use SearXNG.
- **Search:** `https://search.${DOMAIN}` — the SearXNG UI (also the JSON API at `/search?q=...&format=json`).

---

## Home Assistant "call out" (live real-world answers), fully local

Keep device control on HA's built-in intents (instant, reliable). For live
questions, route through n8n so you sidestep HA's flaky on-device tool loop:

```
HA (fallback) ─► n8n webhook ─► SearXNG (JSON) ─► ollama (summarize) ─► answer back to HA (spoken)
```

**Ready-made files** are in [`voice-search/`](voice-search/) — import
`n8n-web-search.json` into n8n and drop the Home Assistant config
(`custom_sentences` + `rest_command` + `intent_script`) into `/config`. See
[`voice-search/README.md`](voice-search/README.md) for the full walkthrough.

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
- **Storage:** `ollama` (large model files) and `open-webui` (SQLite DB) use
  `${CACHE_PATH}` — the SSD cache pool, direct path — for speed and to keep the
  database off the array. Ensure the cache pool is excluded from the Mover, and
  watch free space (each 7–8B model is ~5 GB). SearXNG's tiny config stays on
  `${APPDATA_PATH}`.
- **Image tags** are starting pins — if a pull 404s, check the current tag;
  Renovate also proposes bumps automatically.
