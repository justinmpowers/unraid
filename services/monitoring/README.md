# Monitoring

| Stack | Role |
|---|---|
| [alloy](alloy/) | Collects logs (→ Loki) and scrapes every metrics target (→ Prometheus) |
| [prometheus](prometheus/) | Stores metrics, evaluates [alert rules](prometheus/rules/) |
| [alertmanager](alertmanager/) | Routes alerts to ntfy |
| [loki](loki/) | Stores logs |
| [grafana](grafana/) | Dashboards; datasources and dashboards are [provisioned](grafana/provisioning/) |
| [ntfy](ntfy/) | Push notifications |
| [uptimekuma](uptimekuma/) | Up/down checks |

## Config files

Portainer deploys the compose files from git, but it can't mount files from the repo. Every config file under this folder is copied to `${OBSERVABILITY_PATH}` on the server instead. After changing any of them, run this on the Unraid host:

```bash
curl -fsSL https://raw.githubusercontent.com/justinmpowers/unraid/main/scripts/sync-monitoring-config.sh \
  | bash -s -- /mnt/user/appdata/observability
```

It reports what changed and which containers to restart. Pass a branch name as a second argument to test unmerged changes. Secrets such as `alertmanager/config/ntfy_token` aren't touched.

| Repo file | Server location |
|---|---|
| `alloy/config.alloy` | `alloy/config/config.alloy` |
| `alertmanager/alertmanager.yml` | `alertmanager/config/alertmanager.yml` |
| `prometheus/prometheus.yml`, `prometheus/rules/` | `prometheus/config/` |
| `loki/local-config.yaml` | `loki/config/local-config.yaml` |
| `grafana/provisioning/` | `grafana-provisioning/` |

## Grafana

- **Datasources** `prometheus`, `Loki` and `Alertmanager` come from [datasources.yml](grafana/provisioning/datasources/datasources.yml) and are read-only in the UI. Change them in git.
- **Dashboards** in [dashboards/json/](grafana/provisioning/dashboards/json/) appear in the **Homelab** folder. To change one, edit it in Grafana, use **Export → Export as JSON**, and replace the file in git. Saving in the UI is blocked for provisioned dashboards.
- **Sign-in** through Authentik is configured by `GF_AUTH_GENERIC_OAUTH_*` env vars in [docker-compose.yml](grafana/docker-compose.yml). The stack needs `GRAFANA_OAUTH_CLIENT_ID` and `GRAFANA_OAUTH_CLIENT_SECRET` (from the Authentik `grafana` provider). Settings saved under **Administration → Authentication** override the env vars, so leave that page alone.

## Loki storage

Logs before **2026-10-17** use the legacy `boltdb` index; from that date Loki writes the `tsdb`/`v13` format. Both are readable. After **2026-11-14** (28 days of retention later) the legacy period has no data left, and the `boltdb` schema entry, `storage_config.boltdb` and `table_manager` can be removed, and `allow_structured_metadata` turned on.
