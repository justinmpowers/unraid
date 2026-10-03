# Alertmanager

Sends Prometheus alerts to ntfy. Rules live in [../prometheus/rules/](../prometheus/rules/), routing in [alertmanager.yml](alertmanager.yml).

| Severity | ntfy priority | Repeats every |
|---|---|---|
| `critical` | high | 2h |
| `warning` | default | 12h |

Every alert also sends a "resolved" message when it clears. A critical alert suppresses the warning with the same name (e.g. disk <5% hides disk <15%).

## ntfy setup (once)

ntfy denies anonymous access, so Alertmanager and Kopia need a user with write access:

```bash
docker exec -it ntfy ntfy user add alerts                   # prompts for a password
docker exec ntfy ntfy access alerts 'homelab-*' write-only
docker exec ntfy ntfy token add --label=alertmanager alerts   # prints tk_...
```

Give your own ntfy user read access, then subscribe to `homelab-alerts` and `homelab-backups` in the ntfy app:

```bash
docker exec ntfy ntfy access <your-user> 'homelab-*' read-only
```

## Deploy

1. Copy the configs to the server and add the token:
   ```bash
   mkdir -p ${OBSERVABILITY_PATH}/alertmanager/config ${OBSERVABILITY_PATH}/alertmanager/data
   cp alertmanager.yml ${OBSERVABILITY_PATH}/alertmanager/config/
   echo -n 'tk_...' > ${OBSERVABILITY_PATH}/alertmanager/config/ntfy_token

   mkdir -p ${OBSERVABILITY_PATH}/prometheus/config/rules
   cp ../prometheus/prometheus.yml ${OBSERVABILITY_PATH}/prometheus/config/
   cp ../prometheus/rules/*.yml ${OBSERVABILITY_PATH}/prometheus/config/rules/
   cp ../alloy/config.alloy ${OBSERVABILITY_PATH}/alloy/config/
   ```
   Make sure the files are readable by `PUID:PGID`, since Alertmanager and Prometheus run as that user.
2. Deploy the `monitoring-alertmanager` stack. It needs `TZ`, `DOMAIN`, `OBSERVABILITY_PATH`, `PUID` and `PGID`.
3. Reload Prometheus (`docker restart prometheus`) and restart `GrafanaAlloy`.
4. Add an Authentik Proxy Provider and Application for `https://alertmanager.${DOMAIN}`, the same way as Alloy, and add it to the embedded outpost.
5. Check:
   - Prometheus → **Status → Rule health**: four groups (`host`, `containers`, `monitoring`, `traefik`), no errors.
   - Prometheus query `prometheus_notifications_alertmanagers_discovered` returns `1`.
   - Send a test notification:
     ```bash
     docker exec alertmanager amtool alert add TestAlert severity=warning host=JP-Dell \
       --annotation=summary="Test alert from Alertmanager" --alertmanager.url=http://localhost:9093
     ```
     It should arrive in `homelab-alerts` within about 30 seconds.

## Kopia backup failures

Kopia sends its own notifications, so a failed snapshot reaches ntfy directly. Run once per Kopia container:

```bash
for c in kopia-backblaze kopia-truenas; do
  docker exec $c kopia notification profile configure webhook \
    --profile-name=ntfy \
    --endpoint="http://ntfy:80/homelab-backups" \
    --method=POST \
    --http-header="Authorization:Bearer tk_..." \
    --http-header="Title:Kopia ($c)" \
    --format=txt \
    --min-severity=warning
  docker exec $c kopia notification profile test --profile-name=ntfy
done
```

The Kopia stack must be redeployed first so it joins `monitoring_net` and can reach `ntfy`.

## Uptime Kuma

Uptime Kuma checks are separate from these alerts. To get them in ntfy too: Uptime Kuma → **Settings → Notifications → Setup Notification** → type **ntfy**, server `http://ntfy:80`, topic `homelab-alerts`, access token from above. Turn on **Default enabled** and **Apply on all existing monitors**.

## Silencing

To mute an alert during maintenance, open `https://alertmanager.${DOMAIN}` → **New Silence**, and match on `alertname` or `name`.
