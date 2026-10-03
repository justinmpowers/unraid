# Alloy

Collects logs and metrics for the monitoring stack. Replaces Promtail.

| Container | Role |
|---|---|
| `GrafanaAlloy` | Ships Docker, syslog and Traefik access logs to Loki; scrapes metrics and remote-writes them to Prometheus |
| `node-exporter` | Host metrics (CPU, memory, disks, network). Host network so interface stats are the host's |
| `cadvisor` | Per-container CPU, memory, network and I/O |

Scrape targets and log sources live in [config.alloy](config.alloy), so they're versioned here instead of only on the server.

## Deploy

1. Copy the config to the server:
   ```bash
   mkdir -p ${OBSERVABILITY_PATH}/alloy/config ${OBSERVABILITY_PATH}/alloy/data
   cp config.alloy ${OBSERVABILITY_PATH}/alloy/config/
   ```
2. Redeploy the `monitoring-prometheus` stack. It needs `--web.enable-remote-write-receiver`.
3. Stop and delete the `monitoring-promtail` stack in Portainer.
4. Deploy the `monitoring-alloy` stack. It needs `TZ`, `DOMAIN`, `OBSERVABILITY_PATH` and `APPDATA_PATH`.
5. Check `https://alloy.${DOMAIN}`: every component should be healthy.

Port `9101` (node-exporter) must be free on the host. 9100 is avoided because Unraid's Prometheus Node Exporter plugin uses it.

## Traefik metrics

Traefik reads its static config from `${APPDATA_PATH}/traefik/traefik.yml`, which isn't in git. Add this there and restart Traefik:

```yaml
log:
  level: INFO

metrics:
  prometheus:
    addEntryPointsLabels: true
    addRoutersLabels: true
    addServicesLabels: true
```

Metrics are served on the existing `traefik` entrypoint (`:8080/metrics`), which Alloy scrapes. When a static config file is present, Traefik ignores the `command:` flags in the compose file. So `--log.level=DEBUG` there has no effect, and the level is whatever `traefik.yml` says.

## Labels

| Source | Labels |
|---|---|
| Docker logs | `job="docker"`, `container`, `compose_project`, `compose_service`, `stream`, `level` (when detected) |
| Files | `job="syslog"`, `job="traefik-access"` |
| Everything | `host="JP-Dell"` |

Grafana dashboards that filtered on Promtail's labels may need their queries updated.

Suggested dashboards: **Node Exporter Full** (1860) and **cAdvisor exporter** (14282).

## Reload after config changes

```bash
curl -X POST http://GrafanaAlloy:12345/-/reload   # from a container on monitoring_net
```
