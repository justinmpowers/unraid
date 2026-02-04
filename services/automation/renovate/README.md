# Self-Hosted Renovate for Unraid

This directory contains a Docker Compose setup for running Renovate as a native Unraid service instead of using GitHub Actions.

## Overview

**What is Renovate?**
Renovate automatically checks for container updates and creates PRs with new versions.

**Why Self-Host?**
- **Cost**: Eliminates GitHub Actions minutes (Renovate is small but recurring)
- **Control**: Runs directly on your Unraid hardware
- **Simplicity**: One less GitHub Actions workflow to manage
- **Reliability**: No GitHub Actions queue delays

**Trade-offs:**
- Requires manual secret management
- Uses Unraid system resources
- Needs git access on Unraid

## Quick Start

### 1. Add Required Secrets to `.env`

```bash
# Edit your root .env file and add:
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
DOCKER_HUB_USERNAME=yourusername
DOCKER_HUB_PASSWORD=dckr_xxxxxxxxxxxxxxxxxxxx
```

### 2. Deploy Renovate

```bash
cd services/automation/renovate
docker-compose --env-file ../../../.env up -d
```

### 3. Check Logs

```bash
docker-compose logs -f renovate
```

## Configuration

The container respects the Renovate configuration in the repository root:
- `renovate.json` - Main Renovate config (extends config:recommended)
- `.github/renovate.json` - Alternative location (if used)

Environment variables in `docker-compose.yml` override config file settings.

### Key Settings

| Setting | Value | Purpose |
|---------|-------|---------|
| `RENOVATE_SCHEDULE` | `after 09:00 on Sunday` | Weekly update check |
| `RENOVATE_LABELS` | `automated,container-updates` | PR labels for filtering |
| `RENOVATE_BRANCH_PREFIX` | `renovate/` | Branch naming |
| `RENOVATE_AUTODISCOVER` | `true` | Auto-find repos (if configured) |

### Environment Variables Reference

**Required:**
- `GITHUB_TOKEN` - GitHub Personal Access Token
  - Scopes: `repo`, `read:packages`, `workflow`
  - Used for creating PRs and accessing repo
  
- `DOCKER_HUB_USERNAME` - Docker Hub username
  - For authenticated Docker Hub access
  - Avoids 200 pulls/6h rate limit
  
- `DOCKER_HUB_PASSWORD` - Docker Hub Personal Access Token
  - Create at https://hub.docker.com/settings/security

**Optional:**
- `RENOVATE_AUTODISCOVER_FILTER` - Limit to specific repos
  - Example: `justinmpowers/unraid`
  - Useful if running for multiple repositories

## Monitoring

### View Logs

```bash
# Real-time logs
docker-compose logs -f renovate

# Last 50 lines
docker-compose logs --tail 50 renovate

# Specific time period
docker-compose logs --since 1h renovate
```

### Check Container Status

```bash
docker ps | grep renovate
```

### View Created PRs

Visit: https://github.com/justinmpowers/unraid/pulls?q=is:pr+label:automated

## Troubleshooting

### Container won't start

```bash
# Check docker-compose syntax
docker-compose config

# Check logs for errors
docker-compose logs renovate

# Verify env vars are loaded
docker-compose config | grep GITHUB_TOKEN
```

### No PRs being created

1. **Check GitHub token:**
   ```bash
   curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/rate_limit
   ```

2. **Check Docker registry access:**
   - Verify `DOCKER_HUB_USERNAME` and `DOCKER_HUB_PASSWORD` are set
   - Test manually: `echo "$DOCKER_HUB_PASSWORD" | docker login -u "$DOCKER_HUB_USERNAME" --password-stdin`

3. **Check repository permissions:**
   - GitHub token needs `repo` scope
   - Must have push access to the repository

4. **Check Renovate logs for errors:**
   ```bash
   docker-compose logs renovate | grep -i error
   ```

### High Resource Usage

If Renovate is using too much CPU:
1. Reduce `cpus` limit in docker-compose.yml
2. Increase `RENOVATE_SCHEDULE` interval
3. Check if Docker registry is slow

## Integration with GitHub Actions

You can run **both** self-hosted Renovate and GitHub Actions Renovate, or **just one**:

### Option A: Self-Hosted Only (Recommended)
- Keep Renovate container running on Unraid
- Delete/disable `.github/workflows/renovate.yml`
- Lower cost, simpler setup

### Option B: GitHub Actions Only (Current)
- Delete `services/automation/renovate/` folder
- Keep `.github/workflows/renovate.yml`
- No Unraid resource usage

### Option C: Both Running
- GitHub Actions for backup
- Self-hosted for primary updates
- Both create PRs (may have duplicate efforts)

## Maintenance

### Update Renovate Version

Edit `docker-compose.yml` and change the image version:

```yaml
services:
  renovate:
    image: renovate/renovate:39.2.0  # Update this version
```

Then redeploy:
```bash
docker-compose pull
docker-compose up -d
```

### Rotate Secrets

If you change Docker Hub or GitHub tokens:
1. Update `.env` file
2. Restart the container: `docker-compose restart renovate`

## Advanced Configuration

### Custom Renovate Config

For advanced settings beyond environment variables, create `.renovaterc.json` in this directory:

```json
{
  "extends": ["config:recommended"],
  "dependencyDashboard": true,
  "rangeStrategy": "pin",
  "packageRules": [
    {
      "matchUpdateTypes": ["major"],
      "labels": ["breaking-change?"],
      "prPriority": -1
    }
  ]
}
```

Then uncomment in docker-compose.yml:
```yaml
volumes:
  - ./renovaterc.json:/home/renovate/.renovaterc.json:ro
```

### Multiple Repositories

Set `RENOVATE_AUTODISCOVER: true` and optionally filter with:
```yaml
RENOVATE_AUTODISCOVER_FILTER: "org/*"  # All repos in org
```

## Cost Savings Comparison

| Method | Cost | Effort |
|--------|------|--------|
| GitHub Actions (current) | ~$0.36/month (Renovate only) | Low |
| Self-Hosted on Unraid | ~$0 (uses existing hardware) | Medium |
| Both (redundancy) | Same as GitHub Actions + Unraid power | High |

**Result:** Self-hosted saves minimal cost but gives you more control and learning.

## Links

- [Renovate Documentation](https://docs.renovatebot.com/)
- [Docker Image](https://hub.docker.com/r/renovate/renovate)
- [Self-Hosted Setup Guide](https://docs.renovatebot.com/self-hosted-configuration/)
