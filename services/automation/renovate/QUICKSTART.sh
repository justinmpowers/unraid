#!/bin/bash
# Quick Start Guide for Self-Hosted Renovate

echo "🤖 Self-Hosted Renovate - Quick Start"
echo "===================================="
echo ""

# Step 1: Prepare secrets
echo "✅ Step 1: Add secrets to .env"
echo "   Edit your .env file and add:"
echo "   GITHUB_TOKEN=ghp_xxx..."
echo "   DOCKER_HUB_USERNAME=yourusername"
echo "   DOCKER_HUB_PASSWORD=dckr_xxx..."
echo ""

# Step 2: Deploy
echo "✅ Step 2: Deploy Renovate"
echo "   cd services/automation/renovate"
echo "   docker-compose --env-file ../../../.env up -d"
echo ""

# Step 3: Verify
echo "✅ Step 3: Check it's running"
echo "   docker-compose logs -f renovate"
echo ""

# Step 4: Monitor
echo "✅ Step 4: Watch for PRs"
echo "   Open: https://github.com/justinmpowers/unraid/pulls?q=label:automated"
echo ""

echo "That's it! 🎉"
echo ""
echo "For detailed configuration, see: services/automation/renovate/README.md"
