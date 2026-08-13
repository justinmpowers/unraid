# Home Assistant

## Quick start
1. Copy `.env.example` to `.env` and update values (including `UNRAID_HOST_IP`).
2. Start the stack.

## Networking
`home-assistant` runs on `network_mode: host` (not `iot_net`) so that mDNS/Zeroconf
discovery works for ESPHome devices (e.g. Home Assistant Voice Preview Edition),
HomeKit, and similar. `matter-server` already used host networking for the same
reason.

Because it's off `iot_net`, Traefik's Docker label provider can't discover it
automatically, so `homeassistant.${DOMAIN}` is routed via Traefik's **file
provider** instead of docker labels. Add the following to the `http:` section of
Traefik's `dynamic.yml` on the Unraid host (`${APPDATA_PATH}/traefik/dynamic.yml`,
outside this repo), replacing the IP with your `UNRAID_HOST_IP` and the entrypoint
with whichever one you use for other routers:

```yaml
http:
  routers:
    homeassistant:
      rule: "Host(`homeassistant.example.com`)"
      entryPoints:
        - web
      service: homeassistant
  services:
    homeassistant:
      loadBalancer:
        servers:
          - url: "http://192.168.1.10:8123"
```

If `dynamic.yml` already has an `http:` key (e.g. for the `default-headers` or
`crowdsec` middlewares), add `routers:` and `services:` as siblings under that
same `http:` key rather than duplicating it. Traefik picks up file provider
changes automatically - no restart needed.
