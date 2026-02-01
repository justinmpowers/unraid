# Traefik

## Quick start
1. Copy `.env.example` to `.env` and update values.
2. Ensure the external Docker network `public_net` exists.
3. Start the stack.

## Migrating a service
1. Attach the service to `public_net`.
2. Remove public `ports:` from the service.
3. Add Traefik labels. Example:

```
labels:
  - traefik.enable=true
  - traefik.http.routers.myapp.rule=Host(`myapp.${DOMAIN}`)
  - traefik.http.routers.myapp.entrypoints=websecure
  - traefik.http.routers.myapp.tls.certresolver=letsencrypt
  - traefik.http.routers.myapp.middlewares=default-headers@file
  - traefik.http.services.myapp.loadbalancer.server.port=8080
```

## Notes
- This stack uses Cloudflare DNS-01 for certificates. Ensure your DNS token is valid.
- The Traefik dashboard is protected by basic auth defined in `TRAEFIK_DASHBOARD_AUTH`.
