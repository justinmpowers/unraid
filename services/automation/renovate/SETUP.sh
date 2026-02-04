#!/bin/bash
# Self-Hosted Renovate Setup for Unraid
# This guide helps you run Renovate as a native Unraid service

set -e

echo "🤖 Renovate Self-Hosted Setup Guide"
echo "===================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check prerequisites
echo "📋 Checking prerequisites..."

if [ ! -f "services/automation/renovate/docker-compose.yml" ]; then
    echo -e "${RED}❌ docker-compose.yml not found${NC}"
    echo "Run from repository root directory"
    exit 1
fi

if [ ! -f ".env" ]; then
    echo -e "${RED}❌ .env file not found${NC}"
    echo "Please create .env file with required secrets"
    exit 1
fi

echo -e "${GREEN}✅ Prerequisites met${NC}"
echo ""

# Explain environment variables needed
echo "📝 Required Environment Variables (add to .env):"
echo "================================================"
echo ""
echo "Essential:"
echo "  GITHUB_TOKEN=your_github_pat_token"
echo "    └─ GitHub Personal Access Token for creating PRs"
echo "    └─ Scopes: repo, read:packages, workflow"
echo ""
echo "  DOCKER_HUB_USERNAME=your_docker_hub_username"
echo "    └─ Docker Hub username (avoid rate limits)"
echo ""
echo "  DOCKER_HUB_PASSWORD=your_docker_hub_pat"
echo "    └─ Docker Hub Personal Access Token"
echo ""
echo "Optional:"
echo "  RENOVATE_AUTODISCOVER_FILTER=justinmpowers/unraid"
echo "    └─ Restrict to specific repositories"
echo ""

# Deployment instructions
echo ""
echo "🚀 Deployment Steps:"
echo "==================="
echo ""
echo "1. Add secrets to .env file:"
echo "   vi .env"
echo ""
echo "2. Verify environment variables:"
echo "   grep -E 'GITHUB_TOKEN|DOCKER_HUB' .env"
echo ""
echo "3. Deploy Renovate:"
echo "   cd services/automation/renovate"
echo "   docker-compose --env-file ../../../.env up -d"
echo ""
echo "4. Check logs:"
echo "   docker-compose logs -f renovate"
echo ""
echo "5. Verify it's running:"
echo "   docker ps | grep renovate"
echo ""

# Configuration options
echo ""
echo "⚙️  Configuration:"
echo "================="
echo ""
echo "The docker-compose.yml uses environment variables from .env"
echo ""
echo "To customize Renovate behavior, edit docker-compose.yml:"
echo "  - RENOVATE_SCHEDULE: Change update schedule"
echo "  - RENOVATE_LABELS: Customize PR labels"
echo "  - RENOVATE_DEPENDENCY_DASHBOARD: Enable dashboard"
echo ""

# Monitoring
echo ""
echo "📊 Monitoring & Logs:"
echo "===================="
echo ""
echo "Real-time logs:"
echo "  docker-compose -f services/automation/renovate/docker-compose.yml logs -f renovate"
echo ""
echo "Check recent runs:"
echo "  docker-compose -f services/automation/renovate/docker-compose.yml logs --tail 50 renovate"
echo ""
echo "View all PRs created:"
echo "  Open: https://github.com/justinmpowers/unraid/pulls?q=is:pr+label:automated"
echo ""

# Troubleshooting
echo ""
echo "🔧 Troubleshooting:"
echo "=================="
echo ""
echo "If Renovate container won't start:"
echo "  1. Check env vars: docker-compose config"
echo "  2. Check logs: docker-compose logs renovate"
echo "  3. Verify GitHub token has correct scopes"
echo "  4. Ensure /mnt/user/github/unraid path exists"
echo ""
echo "If PRs aren't created:"
echo "  1. Check Docker registry authentication"
echo "  2. Verify GITHUB_TOKEN has 'repo' scope"
echo "  3. Check rate limits: curl -H 'Authorization: token TOKEN' https://api.github.com/rate_limit"
echo ""

echo ""
echo -e "${GREEN}✅ Setup guide complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Add required secrets to .env"
echo "  2. Deploy Renovate service"
echo "  3. Monitor logs for first run"
echo "  4. Check GitHub for update PRs"
echo ""
