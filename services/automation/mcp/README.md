# MCP Stack (Internal Only)

This stack runs multiple MCP servers behind a single internal Nginx gateway.
All MCP endpoints require a bearer token and are intended for internal clients only.

## Services

Core services (enabled by default):
- mcp-gateway
- mcp-filesystem
- mcp-github
- mcp-postgres
- mcp-fetch

Optional services (enabled with profile `optional`):
- mcp-sqlite
- mcp-docker
- mcp-playwright
- mcp-search

Optional PostgreSQL fanout services (enabled with profile `postgres-all`):
- mcp-postgres-manyfold
- mcp-postgres-authentik
- mcp-postgres-tandoor
- mcp-postgres-wikijs
- mcp-postgres-nextcloud
- mcp-postgres-j3d

> There is no git server in this stack. `mcp-server-git` depends on GitPython,
> which needs the `git` binary, and the `supercorp/supergateway` images do not
> ship one - the server exited with `Bad git executable` on every start.
> `mcp-filesystem` already exposes the same workspace path and `mcp-github`
> covers remote repositories. Note that `GIT_PYTHON_REFRESH=quiet`, which that
> error suggests, only hides the import failure: the server would report healthy
> and fail every git call.

## Required Environment Variables

Copy values from `.env.example` into your root `.env`:

- `APPDATA_PATH` (base for the gateway config mount, e.g. `/mnt/user/appdata`)
- `MCP_GATEWAY_TOKEN`
- `MCP_WORKSPACE_PATH`
- `MCP_MODELS_PATH`
- `MCP_GITHUB_TOKEN`
- `MCP_POSTGRES_URL`

Optional profile variables:
- `MCP_SQLITE_HOST_DIR`
- `MCP_SQLITE_PATH`
- `MCP_TAVILY_API_KEY`

Optional postgres-all variables:
- `MCP_POSTGRES_URL_MANYFOLD`
- `MCP_POSTGRES_URL_AUTHENTIK`
- `MCP_POSTGRES_URL_TANDOOR`
- `MCP_POSTGRES_URL_WIKIJS`
- `MCP_POSTGRES_URL_NEXTCLOUD`
- `MCP_POSTGRES_URL_J3D`

Recommended data root:
- Keep MCP data under `/mnt/user/appdata/mcp`.
- Example subfolders: `/mnt/user/appdata/mcp/workspace`, `/mnt/user/appdata/mcp/models`, `/mnt/user/appdata/mcp/sqlite`.

## Deploy

The gateway's nginx config is mounted from an absolute path
(`${APPDATA_PATH}/mcp/nginx/default.conf.template`), not a relative one. Copy it
into place before deploying:

```bash
mkdir -p /mnt/user/appdata/mcp/nginx
cp nginx/default.conf.template /mnt/user/appdata/mcp/nginx/default.conf.template
```

This matters for Portainer. A Git-backed stack is cloned inside the Portainer
container, so a relative mount resolves to a `/data/compose/...` path that does
not exist on the host; Docker then creates an empty directory there, nginx finds
no template, and silently serves its stock config on port 80. The `:8080/healthz`
healthcheck fails and the gateway shows as unhealthy with nothing in its log.
`APPDATA_PATH` must also be set in the Portainer stack's environment, or the
mount resolves to `/mcp/nginx/...` and fails the same way.

Confirm the template was rendered after deploying:

```bash
docker logs mcp-gateway 2>&1 | grep envsubst
```

From this folder:

```bash
docker compose up -d
```

To include optional services:

```bash
docker compose --profile optional up -d
```

To include all Postgres endpoints:

```bash
docker compose --profile postgres-all up -d
```

To include both optional tools and all Postgres endpoints:

```bash
docker compose --profile optional --profile postgres-all up -d
```

## Access Pattern

Gateway listens on port `8080` inside `internal_net`. Containers on that
network reach it directly at `http://mcp-gateway:8080`.

From the LAN it is served over HTTPS at `https://mcp.${DOMAIN}` by Traefik,
via a router on the `websecure` entrypoint only. There is deliberately no
`web` router: `web` is the entrypoint cloudflared forwards to, so adding one
would publish an endpoint that grants filesystem writes, a GitHub PAT and
Postgres access to the internet.

`mcp.${DOMAIN}` must resolve to the Unraid host's LAN address. Do not attach
`authentik@file` to this router - forward-auth redirects to a login page and
breaks bearer-token clients.

No host port is published. To probe locally without Traefik, uncomment the
loopback `ports` binding in `docker-compose.yml`.

MCP endpoint format:

```text
/<service>/mcp
```

Examples:
- `/filesystem/mcp`
- `/github/mcp`
- `/postgres/mcp`
- `/fetch/mcp`

Postgres fanout endpoints (profile `postgres-all`):
- `/postgres-manyfold/mcp`
- `/postgres-authentik/mcp`
- `/postgres-tandoor/mcp`
- `/postgres-wikijs/mcp`
- `/postgres-nextcloud/mcp`
- `/postgres-j3d/mcp`

Optional:
- `/sqlite/mcp`
- `/docker/mcp`
- `/playwright/mcp`
- `/search/mcp`

All requests must include:

```text
Authorization: Bearer <MCP_GATEWAY_TOKEN>
```

## Troubleshooting

**502 from every `/<service>/mcp` request, while `/healthz` returns 200.**
`proxy_pass` interpolates a variable, so nginx resolves backends per request
and needs a `resolver`. The template takes it from `NGINX_LOCAL_RESOLVERS`,
which the image only exports when `NGINX_ENTRYPOINT_LOCAL_RESOLVERS` is set in
the gateway's environment. Check for `no resolver defined to resolve mcp-...`
in `docker logs mcp-gateway`. A 502 reading `connect() failed` or
`Connection refused` instead means that backend container is down.

**404 from `https://mcp.<domain>/...` on the LAN.** The hostname is resolving
to Cloudflare, so the request arrives over the tunnel at the `web` entrypoint,
where this stack deliberately has no router. Unlike every other service here,
this one has no tunnel fallback, so the UDM Pro local DNS records are required,
not just a faster path - see `services/networking/traefik/README.md`. Both A
and AAAA are needed, or dual-stack clients prefer Cloudflare's IPv6 answer.
Confirm the route independently of DNS with
`curl --resolve mcp.<domain>:443:<lan-ip> https://mcp.<domain>/healthz`.

**401 on every request.** `MCP_GATEWAY_TOKEN` is empty, so the check rendered
as `"Bearer "`. Verify with
`docker exec mcp-gateway grep -q '"Bearer "' /etc/nginx/conf.d/default.conf`.

## Security Notes

- Keep this stack on `internal_net` only.
- Use read-only credentials where possible (GitHub token, Postgres user).
- Rotate `MCP_GATEWAY_TOKEN` periodically.
- Keep optional services disabled unless needed.
