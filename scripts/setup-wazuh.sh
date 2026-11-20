#!/bin/bash
# Prepares ${APPDATA_PATH}/wazuh on the Unraid host for the security-wazuh Portainer stack.
# Safe to re-run. Every run re-syncs the config files from the repo. Certificates and indexer users are only
# created the first time. While the stack is running, it also applies the indexer security config, the
# index retention policy and the Wazuh role mapping for SSO users.
#
# Usage (on the server, as root):
#   curl -fsSL https://raw.githubusercontent.com/justinmpowers/unraid/main/scripts/setup-wazuh.sh \
#     | bash -s -- /mnt/user/appdata [branch]
#
# Variables (export before running):
#   WAZUH_INDEXER_PASSWORD, WAZUH_DASHBOARD_PASSWORD   first run only; same values as in the Portainer stack
#   NTFY_TOKEN='tk_...'                                install/replace the token for ntfy alerts
#   WAZUH_RETENTION_DAYS=90                            delete alert/archive/monitoring indices older than this
#   Single sign-on through Authentik (saved in config/oidc.env, so only needed once):
#     DOMAIN, WAZUH_OIDC_CLIENT_ID, WAZUH_OIDC_CLIENT_SECRET
#     optional overrides: WAZUH_URL, WAZUH_OIDC_DISCOVERY_URL, WAZUH_OIDC_LOGOUT_URL
#   WAZUH_OIDC_DISABLE=1                               remove single sign-on again

set -euo pipefail

APPDATA="${1:-/mnt/user/appdata}"
REF="${2:-main}"
BASE="$APPDATA/wazuh"
INDEXER_IMAGE="wazuh/wazuh-indexer:4.14.10"
CERTS_IMAGE="wazuh/wazuh-certs-generator:0.0.5"
UID_WAZUH=1000   # indexer and dashboard run as uid 1000 inside their images
GID_OSSEC=999    # group "wazuh" inside the manager image
RETENTION_DAYS="${WAZUH_RETENTION_DAYS:-90}"

[ "$(id -u)" -eq 0 ] || { echo "Run as root."; exit 1; }
[[ "$RETENTION_DAYS" =~ ^[1-9][0-9]*$ ]] || { echo "WAZUH_RETENTION_DAYS must be a whole number of days."; exit 1; }

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
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
if [ -n "${WAZUH_CONFIG_SRC:-}" ]; then
  src="$WAZUH_CONFIG_SRC"
else
  echo "Fetching services/security/wazuh from $REF..."
  curl -fsSL "https://codeload.github.com/justinmpowers/unraid/tar.gz/$REF" \
    | tar -xz -C "$tmp" --strip-components=4 --wildcards '*/services/security/wazuh/config/*'
  src="$tmp/config"
fi

mkdir -p "$BASE"/{config/indexer,config/dashboard,config/manager,certs,indexer/data,dashboard/config,dashboard/custom,manager/integrations}

changed=()
sync_file() {  # sync_file <src> <dest> <container to restart, or - for none>
  if ! cmp -s "$1" "$2" 2>/dev/null; then
    cp "$1" "$2"
    echo "  updated $2"
    changed+=("$3")
  fi
}

# render <template> <output> KEY=value...: replaces each __KEY__ literally (no regex, so secrets are safe).
render() {
  local tpl="$1" out="$2"; shift 2
  env -i "$@" awk '
    function replace_all(s, from, to,   out, i) {
      out = ""
      while ((i = index(s, from)) > 0) { out = out substr(s, 1, i - 1) to; s = substr(s, i + length(from)) }
      return out s
    }
    { for (k in ENVIRON) $0 = replace_all($0, "__" k "__", ENVIRON[k]); print }
  ' "$tpl" > "$out"
}

# --- Single sign-on settings (kept in config/oidc.env so later runs don't need them again) ---
oidc_env="$BASE/config/oidc.env"
if [ "${WAZUH_OIDC_DISABLE:-}" = 1 ]; then
  rm -f "$oidc_env"
  echo "  single sign-on disabled"
elif [ -n "${WAZUH_OIDC_CLIENT_ID:-}" ] || [ -n "${WAZUH_OIDC_CLIENT_SECRET:-}" ]; then
  : "${DOMAIN:?export DOMAIN (e.g. example.com) to configure single sign-on}"
  : "${WAZUH_OIDC_CLIENT_ID:?export WAZUH_OIDC_CLIENT_ID}"
  : "${WAZUH_OIDC_CLIENT_SECRET:?export WAZUH_OIDC_CLIENT_SECRET}"
  ( umask 077
    { echo "DOMAIN=$DOMAIN"
      echo "WAZUH_OIDC_CLIENT_ID=$WAZUH_OIDC_CLIENT_ID"
      echo "WAZUH_OIDC_CLIENT_SECRET=$WAZUH_OIDC_CLIENT_SECRET"
      for v in WAZUH_URL WAZUH_OIDC_DISCOVERY_URL WAZUH_OIDC_LOGOUT_URL; do
        [ -n "${!v:-}" ] && echo "$v=${!v}"
      done
    } > "$oidc_env" )
fi
declare -A oidc=()
if [ -f "$oidc_env" ]; then
  while IFS='=' read -r k v; do [ -n "$k" ] && oidc[$k]="$v"; done < "$oidc_env"
  d="${oidc[DOMAIN]}"
  : "${oidc[WAZUH_URL]:=https://wazuh.$d}"
  : "${oidc[WAZUH_OIDC_DISCOVERY_URL]:=https://auth.$d/application/o/wazuh/.well-known/openid-configuration}"
  : "${oidc[WAZUH_OIDC_LOGOUT_URL]:=https://auth.$d/application/o/wazuh/end-session/}"
fi

# --- Config files ---
cat "$src/dashboard/opensearch_dashboards.yml" > "$tmp/dashboards.yml"
if [ ${#oidc[@]} -gt 0 ]; then
  render "$src/dashboard/oidc.yml.tmpl" "$tmp/oidc.yml" \
    OIDC_DISCOVERY_URL="${oidc[WAZUH_OIDC_DISCOVERY_URL]}" OIDC_CLIENT_ID="${oidc[WAZUH_OIDC_CLIENT_ID]}" \
    OIDC_CLIENT_SECRET="${oidc[WAZUH_OIDC_CLIENT_SECRET]}" WAZUH_URL="${oidc[WAZUH_URL]}" \
    OIDC_LOGOUT_URL="${oidc[WAZUH_OIDC_LOGOUT_URL]}"
  cat "$tmp/oidc.yml" >> "$tmp/dashboards.yml"
  render "$src/indexer/security_config.yml.tmpl" "$tmp/security_config.yml" \
    OIDC_ENABLED=true OIDC_DISCOVERY_URL="${oidc[WAZUH_OIDC_DISCOVERY_URL]}"
else
  render "$src/indexer/security_config.yml.tmpl" "$tmp/security_config.yml" \
    OIDC_ENABLED=false OIDC_DISCOVERY_URL="https://sso.invalid/.well-known/openid-configuration"
fi

sync_file "$src/certs.yml"                   "$BASE/config/certs.yml"                          -
sync_file "$src/indexer/opensearch.yml"      "$BASE/config/indexer/opensearch.yml"             wazuh-indexer
sync_file "$tmp/security_config.yml"         "$BASE/config/indexer/security_config.yml"        -
sync_file "$src/indexer/roles_mapping.yml"   "$BASE/config/indexer/roles_mapping.yml"          -
sync_file "$tmp/dashboards.yml"              "$BASE/config/dashboard/opensearch_dashboards.yml" wazuh-dashboard
sync_file "$src/manager/ossec.conf"          "$BASE/config/manager/ossec.conf"                 wazuh-manager
sync_file "$src/manager/custom-ntfy"         "$BASE/manager/integrations/custom-ntfy"          wazuh-manager

# Integrations must be root:wazuh 750.
chown "0:$GID_OSSEC" "$BASE/manager/integrations/custom-ntfy"
chmod 750 "$BASE/manager/integrations/custom-ntfy"
if [ -n "${NTFY_TOKEN:-}" ]; then
  printf '%s' "$NTFY_TOKEN" > "$BASE/manager/integrations/ntfy_token"
  echo "  wrote ntfy token"
fi
if [ -f "$BASE/manager/integrations/ntfy_token" ]; then
  chown "0:$GID_OSSEC" "$BASE/manager/integrations/ntfy_token"
  chmod 640 "$BASE/manager/integrations/ntfy_token"
fi

# Custom decoders/rules go into the manager's etc/, which the image only populates when that directory is
# empty. So install them only after the stack has started once; before that, writing here would break it.
if [ -f "$BASE/manager/etc/ossec.conf" ]; then
  for f in unifi_decoders.xml:decoders unifi_rules.xml:rules unraid_decoders.xml:decoders unraid_rules.xml:rules; do
    dest="$BASE/manager/etc/${f#*:}/${f%%:*}"
    sync_file "$src/manager/${f%%:*}" "$dest" wazuh-manager
    chown "$GID_OSSEC:$GID_OSSEC" "$dest"
    chmod 660 "$dest"
  done
else
  echo "  NOTE: start the security-wazuh stack once, then re-run this script to install the custom rules."
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
  render "$src/indexer/internal_users.yml.tmpl" "$users" ADMIN_HASH="$admin_hash" KIBANASERVER_HASH="$kibana_hash"
  echo "  wrote $users"
fi

chown -R "$UID_WAZUH:$UID_WAZUH" "$BASE/indexer" "$BASE/dashboard" "$BASE/config/indexer" "$BASE/config/dashboard"
chmod 640 "$users" "$BASE/config/indexer/security_config.yml" "$BASE/config/indexer/roles_mapping.yml" \
  "$BASE/config/dashboard/opensearch_dashboards.yml"

# --- Live changes: need the stack running ---
running() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = true ]; }
ICERTS=/usr/share/wazuh-indexer/config/certs
icurl() {  # curl against the indexer with the admin client certificate (no password needed)
  docker exec -i wazuh-indexer curl -sS --cacert "$ICERTS/root-ca.pem" --cert "$ICERTS/admin.pem" \
    --key "$ICERTS/admin-key.pem" -H 'Content-Type: application/json' "$@"
}

echo
if ! running wazuh-indexer; then
  echo "Indexer not running: deploy/start the security-wazuh stack, then re-run this script to apply the"
  echo "security config, retention policy and SSO role mapping."
else
  for i in $(seq 1 60); do
    icurl -o /dev/null -f "https://wazuh.indexer:9200/_cluster/health" 2>/dev/null && break
    [ "$i" = 60 ] && { echo "Indexer did not become ready."; exit 1; }
    sleep 3
  done

  # The indexer and dashboard fetch Authentik's discovery document themselves; if they can't, the dashboard
  # refuses to start. Check from inside the stack's network before going further.
  if [ ${#oidc[@]} -gt 0 ]; then
    if docker exec wazuh-indexer curl -sf -o /dev/null "${oidc[WAZUH_OIDC_DISCOVERY_URL]}"; then
      echo "  Authentik discovery URL reachable from the stack"
    else
      echo "  WARNING: ${oidc[WAZUH_OIDC_DISCOVERY_URL]} is not reachable from wazuh-indexer."
      echo "           Check the Authentik provider slug (wazuh) and that auth.${oidc[DOMAIN]} resolves from containers."
      echo "           The dashboard will not start until it is. Re-run with WAZUH_OIDC_DISABLE=1 to back out."
    fi
  fi

  # Security config and role mapping: only read from these files when the security index is first created,
  # so later changes are pushed with securityadmin.sh. Skipped when nothing changed since the last push.
  stamp="$BASE/config/indexer/.security-applied"
  sum=$(cat "$BASE/config/indexer/security_config.yml" "$BASE/config/indexer/roles_mapping.yml" | md5sum | cut -d' ' -f1)
  if [ "$(cat "$stamp" 2>/dev/null)" != "$sum" ]; then
    echo "Applying indexer security config..."
    for f in config:config rolesmapping:roles_mapping; do
      docker exec wazuh-indexer bash -c "JAVA_HOME=/usr/share/wazuh-indexer/jdk \
        /usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \
        -f /usr/share/wazuh-indexer/config/opensearch-security/${f#*:}.yml -t ${f%%:*} \
        -icl -nhnv -cacert $ICERTS/root-ca.pem -cert $ICERTS/admin.pem -key $ICERTS/admin-key.pem" \
        | grep -E 'Done with success|ERR|rror' || true
    done
    echo "$sum" > "$stamp"
    changed+=(wazuh-dashboard)
  fi

  # Retention: an ISM policy that deletes Wazuh indices older than RETENTION_DAYS.
  policy=$(sed "s/__DAYS__/$RETENTION_DAYS/g" "$src/indexer/ism_retention.json")
  current=$(icurl "https://wazuh.indexer:9200/_plugins/_ism/policies/wazuh-retention" 2>/dev/null || true)
  if ! grep -q '"_seq_no"' <<<"$current"; then
    icurl -X PUT "https://wazuh.indexer:9200/_plugins/_ism/policies/wazuh-retention" --data-binary @- <<<"$policy" >/dev/null
    echo "  created retention policy: $RETENTION_DAYS days"
  elif ! grep -q "after $RETENTION_DAYS days" <<<"$current"; then
    seq=$(grep -o '"_seq_no":[0-9]*' <<<"$current" | cut -d: -f2)
    term=$(grep -o '"_primary_term":[0-9]*' <<<"$current" | cut -d: -f2)
    icurl -X PUT "https://wazuh.indexer:9200/_plugins/_ism/policies/wazuh-retention?if_seq_no=$seq&if_primary_term=$term" \
      --data-binary @- <<<"$policy" >/dev/null
    echo "  updated retention policy: $RETENTION_DAYS days"
  fi
  # New indices pick the policy up from its template; attach it to existing ones too.
  icurl -X POST "https://wazuh.indexer:9200/_plugins/_ism/add/wazuh-alerts-*,wazuh-archives-*,wazuh-monitoring-*,wazuh-statistics-*" \
    -d '{"policy_id":"wazuh-retention"}' | grep -o '"updated_indices":[0-9]*' | sed 's/^/  retention policy: /' || true

  # SSO users get their Wazuh app permissions from the API's RBAC: map the wazuh-admins group to administrator.
  if [ ${#oidc[@]} -gt 0 ] && running wazuh-manager; then
    docker exec wazuh-manager bash -c '
      api=https://localhost:55000
      token=$(curl -sk -u "wazuh-wui:$API_PASSWORD" -X POST "$api/security/user/authenticate?raw=true")
      auth="Authorization: Bearer $token"
      if ! curl -sk -H "$auth" "$api/security/rules?search=wazuh-admins" | grep -q "\"name\": *\"wazuh-admins\""; then
        id=$(curl -sk -H "$auth" -H "Content-Type: application/json" -X POST "$api/security/rules" \
          -d "{\"name\":\"wazuh-admins\",\"rule\":{\"FIND\":{\"backend_roles\":\"wazuh-admins\"}}}" \
          | grep -o "\"id\": *[0-9]*" | head -1 | grep -o "[0-9]*$")
        [ -n "$id" ] || { echo "  could not create the wazuh-admins API rule"; exit 1; }
        curl -sk -H "$auth" -X POST "$api/security/roles/1/rules?rule_ids=$id" >/dev/null
        echo "  mapped SSO group wazuh-admins to the Wazuh administrator role"
      fi'
  fi
fi

echo
if [ ${#changed[@]} -eq 0 ]; then
  echo "Config already up to date."
else
  restart=$(printf '%s\n' "${changed[@]}" | grep -v '^-$' | sort -u | tr '\n' ' ')
  [ -n "$restart" ] && echo "Restart to apply:  docker restart $restart"
fi
