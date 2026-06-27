#!/bin/bash
# Generates a trimmed .env for each stack containing only the variables it uses.
# Usage: ./scripts/generate-stack-envs.sh [path/to/root/.env] [services/dir]
#
# Output: services/<category>/<name>/.env  (already in .gitignore via *.env)

set -euo pipefail

ROOT_ENV="${1:-.env}"
SERVICES_DIR="${2:-services}"

if [ ! -f "$ROOT_ENV" ]; then
  echo "Error: root .env not found at '$ROOT_ENV'"
  echo "Usage: $0 [.env] [services/]"
  exit 1
fi

generated=0
skipped=0

while IFS= read -r compose_file; do
  service_dir=$(dirname "$compose_file")
  stack=$(echo "$service_dir" | sed 's|services/||; s|/|-|')

  # Extract every variable name referenced as ${VAR} or ${VAR:-default}
  vars=$(grep -oP '\$\{\K[A-Z0-9_a-z]+' "$compose_file" | sort -u)

  if [ -z "$vars" ]; then
    skipped=$((skipped + 1))
    continue
  fi

  out="$service_dir/.env"
  > "$out"  # truncate / create

  while IFS= read -r var; do
    # Match exact key= line in root .env, skip comments
    line=$(grep -E "^${var}=" "$ROOT_ENV" | head -1 || true)
    [ -n "$line" ] && echo "$line" >> "$out"
  done <<< "$vars"

  if [ -s "$out" ]; then
    count=$(wc -l < "$out" | tr -d ' ')
    echo "✅ $stack  →  $out  ($count vars)"
    generated=$((generated + 1))
  else
    rm "$out"
    skipped=$((skipped + 1))
  fi

done < <(find "$SERVICES_DIR" -name "docker-compose.yml" | sort)

echo ""
echo "Done — $generated stack .env files written, $skipped skipped (no vars or no matches)."
