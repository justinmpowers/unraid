#!/bin/bash
# Copies the monitoring stack's config files from this repo into ${OBSERVABILITY_PATH} on the Unraid host.
# Portainer Git stacks can't bind-mount files from the repo, so configs live on disk and this keeps them in sync.
#
# Usage (on the server):
#   curl -fsSL https://raw.githubusercontent.com/justinmpowers/unraid/main/scripts/sync-monitoring-config.sh \
#     | bash -s -- /mnt/user/appdata/observability [branch]
#
# Secrets (e.g. alertmanager/config/ntfy_token) are never touched.

set -euo pipefail

OBS="${1:?usage: sync-monitoring-config.sh <OBSERVABILITY_PATH> [branch]}"
REF="${2:-main}"
OWNER="${PUID:-99}:${PGID:-100}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Fetching services/monitoring from $REF..."
curl -fsSL "https://codeload.github.com/justinmpowers/unraid/tar.gz/$REF" \
  | tar -xz -C "$tmp" --strip-components=3 --wildcards '*/services/monitoring/*'

changed=()

# sync_file <repo path under services/monitoring> <destination dir> <component>
sync_file() {
  local src="$tmp/$1" dest
  dest="$2/$(basename "$1")"
  mkdir -p "$2"
  if ! cmp -s "$src" "$dest" 2>/dev/null; then
    cp "$src" "$dest"
    echo "  updated $dest"
    changed+=("$3")
  fi
}

# sync_dir <repo dir under services/monitoring> <destination dir> <component>
# The destination is fully managed: files removed from the repo are removed here too.
sync_dir() {
  local src="$tmp/$1" dest="$2"
  if ! diff -rq "$src" "$dest" >/dev/null 2>&1; then
    rm -rf "$dest"
    mkdir -p "$(dirname "$dest")"
    cp -r "$src" "$dest"
    echo "  updated $dest/"
    changed+=("$3")
  fi
}

sync_file alloy/config.alloy               "$OBS/alloy/config"        GrafanaAlloy
sync_file alertmanager/alertmanager.yml    "$OBS/alertmanager/config" alertmanager
sync_file prometheus/prometheus.yml        "$OBS/prometheus/config"   prometheus
sync_dir  prometheus/rules                 "$OBS/prometheus/config/rules" prometheus
sync_file loki/local-config.yaml           "$OBS/loki/config"         GrafanaLoki
sync_dir  grafana/provisioning             "$OBS/grafana-provisioning" Grafana

chown -R "$OWNER" "$OBS/alertmanager/config" "$OBS/prometheus/config" "$OBS/loki/config" "$OBS/grafana-provisioning"

if [ ${#changed[@]} -eq 0 ]; then
  echo "Everything already up to date."
else
  restart=$(printf '%s\n' "${changed[@]}" | sort -u | tr '\n' ' ')
  echo
  echo "Restart to apply:  docker restart $restart"
fi
