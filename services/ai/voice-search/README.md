# Voice Web Search (local)

Ask the Home Assistant Voice PE live real-world questions, answered fully
locally: **HA → n8n → SearXNG → Ollama → spoken answer**. No big-tech APIs.

Device control stays on HA's built-in intents (instant); only "look up …"
phrasings are routed out to the search pipeline, so you never depend on the
flaky on-device LLM tool loop.

```
"Okay Nabu, look up who won the game last night"
   Voice PE → HA (WebSearch intent) → n8n webhook
        → SearXNG (private search, JSON) → Ollama (summarize) → answer → HA speaks it
```

## Prerequisites
- `ai-ollama`, `ai-searxng` deployed (this category), with a model pulled
  (`docker exec ollama ollama pull qwen2.5:7b`).
- n8n running (postiz-stack) and Home Assistant with the Voice PE set up.

## 1. Import the n8n workflow
1. n8n → **Workflows → Import from File** → `n8n-web-search.json`.
2. Open it and **Activate** (top-right). This publishes the production webhook at
   **`https://n8n.<your-domain>/webhook/web-search`**.
3. The workflow calls `http://searxng:8080` and `http://ollama:11434` over
   `internal_net` (n8n already sits there). Change the model in the **Ollama**
   node if you didn't pull `qwen2.5:7b` — `/api/generate` isn't tool-calling, so
   qwen2.5 is fine here.

## 2. Home Assistant config
- Copy `homeassistant/custom_sentences/en/web_search.yaml` →
  `/config/custom_sentences/en/web_search.yaml`.
- Merge `homeassistant/rest_command.yaml` under `rest_command:` and
  `homeassistant/intent_script.yaml` under `intent_script:` in
  `configuration.yaml` (or `!include` them). **Edit the domain** in
  `rest_command.yaml` to your `n8n.<domain>`.
- **Reachability:** HA is on `iot_net`, n8n on `internal_net`, so HA calls n8n
  via its public Traefik hostname (`https://n8n.<domain>/webhook/web-search`).
  If you'd rather keep it off the reverse proxy, attach HA to `internal_net`
  (or n8n to `iot_net`) and use `http://n8n:5678/webhook/web-search`.
- **Restart / reload** HA to load the config.

## 3. Pipeline
Set the Assist pipeline's conversation agent to **Home Assistant** (built-in) —
custom sentences match there instantly and reliably. (If you keep the Ollama
agent, enable *Prefer handling commands locally* so these sentences still match
first.)

## Test
- Type in Assist chat, then by voice: **"look up the capital of Iceland"**,
  **"search the web for tomorrow's weather in Detroit"**.
- Trace failures in n8n's **Executions** tab (see the SearXNG results and the
  Ollama response per run).

## Notes
- SearXNG must have the JSON format enabled (it is, via this category's
  `settings.yml`) or the workflow's search step returns HTML and fails.
- Keep answers short — the prompt already asks for 1–2 spoken sentences.
