# Traefik

Reverse proxy for every web service on JP-Dell. CrowdSec runs in the same stack and reads Traefik's access logs.

## Quick start
1. Copy `.env.example` to `.env` and update values.
2. Ensure the external Docker network `public_net` exists.
3. Start the stack.

## Two paths in

Every service has one hostname, `https://<service>.azuleluna.xyz`, and two ways to reach it. Each path lands on its own Traefik entrypoint, so each service has two routers.

| Client | DNS answer | Path | Entrypoint | TLS ends at |
|---|---|---|---|---|
| Off the LAN | Cloudflare | Cloudflare edge → Cloudflare Tunnel (`cloudflared`) → `http://traefik:80` | `web` | Cloudflare |
| On the LAN | UDM Pro local record (`10.10.1.167` / `2603:9001:d00:2b79:eef4:bbff:fed4:d18c`) | Client → host port 443 → Traefik | `websecure` | Traefik, with the Let's Encrypt wildcard `*.azuleluna.xyz` |

The tunnel sends plain HTTP to `web`. The `web` routers therefore have no TLS settings and must stay that way, or the tunnel path breaks.

Traefik publishes host ports 80 and 443. To free them, the Unraid web GUI was moved to 4080 (HTTP) and 4443 (HTTPS) in `/boot/config/ident.cfg`.

## Adding a service

1. Attach the service to a network Traefik is on, and set `traefik.docker.network` to it.
2. Don't publish `ports:` for the web UI.
3. Add a `web` router for the tunnel and a `-lan` twin on `websecure` for LAN clients:

```yaml
labels:
  - traefik.enable=true
  - traefik.docker.network=internal_net
  - traefik.http.routers.myapp.rule=Host(`myapp.${DOMAIN}`)
  - traefik.http.routers.myapp.entrypoints=web
  - traefik.http.routers.myapp.middlewares=crowdsec@file
  - traefik.http.routers.myapp-lan.rule=Host(`myapp.${DOMAIN}`)
  - traefik.http.routers.myapp-lan.entrypoints=websecure
  - traefik.http.routers.myapp-lan.service=myapp
  - traefik.http.routers.myapp-lan.middlewares=crowdsec@file
  - traefik.http.services.myapp.loadbalancer.server.port=8080
```

Rules for the twin:

- Give it the same `rule` and `middlewares` as the `web` router.
- Always set `.service=` explicitly. Traefik only links routers to a container's service on its own while the container has exactly one service.
- **Don't add `tls=true`, `tls.certresolver` or `tls.domains`.** A `websecure` router with no TLS settings of its own inherits the entrypoint's defaults: resolver `letsencrypt` plus the wildcard domains. Setting any TLS label, even a bare `tls=true`, turns that inheritance off. Such a router then never requests a cert and gets Traefik's self-signed default instead.
- It uses the same hostname as the `web` router, so routes behind `authentik@file` don't need a second Authentik provider.

4. To make LAN clients take the direct path, add the UDM records described below. Without them, LAN clients keep using the tunnel and the twin router sits idle.

## Static config (`traefik.yml`)

The static config lives at `${APPDATA_PATH}/traefik/traefik.yml` and isn't in git. When it exists, Traefik ignores the `command:` flags in the compose file. The LAN path needs these parts of it:

```yaml
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"
    http:
      # encodedCharacters: ... sits at this same level
      tls:
        certResolver: letsencrypt
        domains:
          - main: azuleluna.xyz
            sans:
              - "*.azuleluna.xyz"

certificatesResolvers:
  letsencrypt:
    acme:
      email: <ACME email>
      storage: /etc/traefik/acme/acme.json
      dnsChallenge:
        provider: cloudflare
        resolvers:
          - "1.1.1.1:53"
          - "1.0.0.1:53"
```

- The DNS-01 challenge uses `CF_DNS_API_TOKEN` from the compose environment.
- `resolvers` makes Traefik check challenge propagation against Cloudflare's public DNS. Without it, the check can go to the UDM, which answers `azuleluna.xyz` names with its local overrides.
- `acme.json` also holds older per-host certs for `traefik`, `jenkins` and `auth`. For those hosts, Traefik serves the exact-match cert instead of the wildcard and keeps renewing it. That's expected.

## LAN DNS (UDM Pro)

Add the records in UniFi Network > Settings > Policy Table > DNS. Each hostname that should take the LAN path needs both:

- A: `10.10.1.167`
- AAAA: `2603:9001:d00:2b79:eef4:bbff:fed4:d18c`

Without the AAAA record, the UDM passes AAAA queries upstream, and dual-stack clients prefer Cloudflare's IPv6 address over the local A record. A CNAME to one host that has both records also works.

The IPv6 address is built from the prefix the ISP delegates. If that prefix changes, update the AAAA records.

Android Private DNS and iCloud Private Relay bypass the UDM's DNS. Turn them off on home Wi-Fi.

## Checking the LAN path

On JP-Dell:

```sh
docker port traefik      # expect 443/tcp -> 0.0.0.0:443 and [::]:443
jq '.letsencrypt.Certificates[].domain' /mnt/user/appdata/traefik/acme/acme.json
# expect { "main": "azuleluna.xyz", "sans": ["*.azuleluna.xyz"] }
docker logs traefik --since 5m 2>&1 | grep -iE 'acme|obtain|error'   # if the wildcard is missing
```

From a LAN machine, run `curl -vI https://nextcloud.azuleluna.xyz`. It should connect to `10.10.1.167` or the `2603:…d18c` address and show `SSL certificate verify ok` with a Let's Encrypt issuer.

## Notes
- The Traefik dashboard is protected by basic auth defined in `TRAEFIK_DASHBOARD_AUTH`.
