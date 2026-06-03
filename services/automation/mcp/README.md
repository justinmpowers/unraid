# MCP Stack (Internal Only)

This stack runs multiple MCP servers behind a single internal Nginx gateway.
All MCP endpoints require a bearer token and are intended for internal clients only.

## Services

Core services (enabled by default):
- mcp-gateway
- mcp-filesystem
- mcp-git
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

## Required Environment Variables

Copy values from `.env.example` into your root `.env`:

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

Gateway listens on port `8080` inside `internal_net`.
If you need host-local access for testing, uncomment the `ports` binding in `docker-compose.yml`.

MCP endpoint format:

```text
/<service>/mcp
```

Examples:
- `/filesystem/mcp`
- `/git/mcp`
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

## Security Notes

- Keep this stack on `internal_net` only.
- Use read-only credentials where possible (GitHub token, Postgres user).
- Rotate `MCP_GATEWAY_TOKEN` periodically.
- Keep optional services disabled unless needed.
