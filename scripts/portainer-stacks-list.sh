#!/bin/bash
# Prints Portainer Git stack config for every service — copy/paste into the UI.

REPO_URL="https://github.com/justinmpowers/unraid"
REPO_BRANCH="main"
SKIP="automation/github-runner"

echo "Portainer Git Stack Configuration"
echo "Repository: $REPO_URL"
echo "Branch:     $REPO_BRANCH"
echo "=================================================="

while IFS= read -r compose_file; do
  service_dir=$(dirname "$compose_file")
  rel_dir=$(echo "$service_dir" | sed 's|^\./||')

  # Skip the runner
  [[ "$rel_dir" == *"$SKIP"* ]] && continue

  stack_name=$(echo "$rel_dir" | sed 's|services/||; s|/|-|')

  echo ""
  echo "  Stack name:   $stack_name"
  echo "  Compose path: $compose_file"
  echo "  Env file:     $rel_dir/.env"

done < <(find services -name "docker-compose.yml" | sort)

echo ""
echo "=================================================="
echo "Total stacks: $(find services -name 'docker-compose.yml' | grep -v "$SKIP" | wc -l | tr -d ' ')"
