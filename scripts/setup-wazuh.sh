#!/bin/bash
# Prepares ${APPDATA_PATH}/wazuh on the Unraid host for the security-wazuh Portainer stack.
# Safe to re-run: it re-syncs the config files from the repo and only generates the certificates
# and indexer users the first time.
#
# Usage (on the server, as root):
#   export WAZUH_INDEXER_PASSWORD='...' WAZUH_DASHBOARD_PASSWORD='...'   # first run only
#   curl -fsSL https://raw.githubusercontent.com/justinmpowers/unraid/main/scripts/setup-wazuh.sh \
#     | bash -s -- /mnt/user/appdata [branch]
#
# Optional: export NTFY_TOKEN='tk_...' to install/replace the token used for alert notifications.

set -euo pipefail

APPDATA="${1:-/mnt/user/appdata}"
REF="${2:-main}"
BASE="$APPDATA/wazuh"
INDEXER_IMAGE="wazuh/wazuh-indexer:4.14.10"
CERTS_IMAGE="wazuh/wazuh-certs-generator:0.0.5"
UID_WAZUH=1000   # indexer and dashboard run as uid 1000 inside their images

[ "$(id -u)" -eq 0 ] || { echo "Run as root."; exit 1; }

# --- Kernel setting the indexer (OpenSearch) refuses to start without ---
if [ "$(sysctl -n vm.max_map_count)" -lt 262144 ]; then
  sysctl -w vm.max_map_count=262144
fi
if [ -f /boot/config/go ] && ! grep -q 'vm.max_map_count' /boot/config/go; then
  echo 'sysctl -w vm.max_map_count=262144' >> /boot/config/go
  echo "Added vm.max_map_count to /boot/config/go so it survives reboots."
fi

# --- Fetch the repo's Wazuh config ---
# Set WAZUH_CONFIG_SRC=<checkout>/services/security/wazuh/config to use a local clone instead.
if [ -n "${WAZUH_CONFIG_SRC:-}" ]; then
  src="$WAZUH_CONFIG_SRC"
else
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  echo "Fetching services/security/wazuh from $REF..."
  curl -fsSL "https://codeload.github.com/justinmpowers/unraid/tar.gz/$REF" \
    | tar -xz -C "$tmp" --strip-components=4 --wildcards '*/services/security/wazuh/config/*'
  src="$tmp/config"
fi

mkdir -p "$BASE"/{config/indexer,config/dashboard,config/manager,certs,indexer/data,dashboard/config,dashboard/custom,manager/integrations}

changed=()
sync_file() {  # sync_file <src> <dest> <container>
  if ! cmp -s "$1" "$2" 2>/dev/null; then
    cp "$1" "$2"
    echo "  updated $2"
    changed+=("$3")
  fi
}
sync_file "$src/certs.yml"                          "$BASE/config/certs.yml"                          -
sync_file "$src/indexer/opensearch.yml"             "$BASE/config/indexer/opensearch.yml"             wazuh-indexer
sync_file "$src/dashboard/opensearch_dashboards.yml" "$BASE/config/dashboard/opensearch_dashboards.yml" wazuh-dashboard
sync_file "$src/manager/ossec.conf"                 "$BASE/config/manager/ossec.conf"                 wazuh-manager
sync_file "$src/manager/custom-ntfy"                "$BASE/manager/integrations/custom-ntfy"          wazuh-manager

# Inside the manager image, group "wazuh" is gid 999; integrations must be root:wazuh 750.
chown 0:999 "$BASE/manager/integrations/custom-ntfy"
chmod 750 "$BASE/manager/integrations/custom-ntfy"
if [ -n "${NTFY_TOKEN:-}" ]; then
  printf '%s' "$NTFY_TOKEN" > "$BASE/manager/integrations/ntfy_token"
  echo "  wrote ntfy token"
fi
if [ -f "$BASE/manager/integrations/ntfy_token" ]; then
  chown 0:999 "$BASE/manager/integrations/ntfy_token"
  chmod 640 "$BASE/manager/integrations/ntfy_token"
fi

# --- TLS certificates (first run only) ---
if [ ! -f "$BASE/certs/root-ca.pem" ]; then
  echo "Generating TLS certificates..."
  docker run --rm \
    -e CERT_TOOL_VERSION=4.14 \
    -v "$BASE/certs:/certificates/" \
    -v "$BASE/config/certs.yml:/config/certs.yml:ro" \
    "$CERTS_IMAGE"
fi
chown -R "$UID_WAZUH:$UID_WAZUH" "$BASE/certs"
chmod 750 "$BASE/certs"
find "$BASE/certs" -type f -exec chmod 440 {} +

# --- Indexer users (first run only: later changes need securityadmin.sh, see the README) ---
users="$BASE/config/indexer/internal_users.yml"
if [ ! -f "$users" ]; then
  : "${WAZUH_INDEXER_PASSWORD:?export WAZUH_INDEXER_PASSWORD (same value as in the Portainer stack)}"
  : "${WAZUH_DASHBOARD_PASSWORD:?export WAZUH_DASHBOARD_PASSWORD (same value as in the Portainer stack)}"
  hash() {
    docker run --rm -e PW="$1" --entrypoint bash "$INDEXER_IMAGE" -c \
      'JAVA_HOME=/usr/share/wazuh-indexer/jdk bash /usr/share/wazuh-indexer/plugins/opensearch-security/tools/hash.sh -p "$PW"' \
      2>/dev/null | grep -E '^\$2[aby]\$' | tail -n1
  }
  echo "Hashing indexer passwords..."
  admin_hash=$(hash "$WAZUH_INDEXER_PASSWORD")
  kibana_hash=$(hash "$WAZUH_DASHBOARD_PASSWORD")
  [ -n "$admin_hash" ] && [ -n "$kibana_hash" ] || { echo "Password hashing failed."; exit 1; }
  ADMIN_HASH="$admin_hash" KIBANA_HASH="$kibana_hash" awk '
    { gsub(/__ADMIN_HASH__/, ENVIRON["ADMIN_HASH"]); gsub(/__KIBANASERVER_HASH__/, ENVIRON["KIBANA_HASH"]); print }
  ' "$src/indexer/internal_users.yml.tmpl" > "$users"
  echo "  wrote $users"
fi
chown "$UID_WAZUH:$UID_WAZUH" "$users"
chmod 640 "$users"

chown -R "$UID_WAZUH:$UID_WAZUH" "$BASE/indexer" "$BASE/dashboard" "$BASE/config/indexer" "$BASE/config/dashboard"

echo
if [ ${#changed[@]} -eq 0 ]; then
  echo "Config already up to date."
else
  restart=$(printf '%s\n' "${changed[@]}" | grep -v '^-$' | sort -u | tr '\n' ' ')
  echo "If the stack is already running, restart to apply:  docker restart $restart"
fi
