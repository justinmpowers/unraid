# JP's Docker Compose Configurations

Comprehensive Docker Compose management for my Unraid server with 35+ containerized services, automated updates, and resource optimization.

## 🚀 Features

- **Complete Service Coverage**: 35+ services across 11 categories
- **Pinned Versions**: All services use specific versions, not `:latest`
- **Organized Structure**: Services grouped logically by function
- **Automated Updates**: Renovate opens weekly PRs for container updates (legacy Python script still available)
- **Resource Management**: CPU and memory limits on all containers
- **Docker Socket Security**: Using proxy instead of direct socket access
- **Git-Tracked**: All changes are reversible and auditable
- **Ephemeral Workers**: Jenkins with Docker-in-Docker for CI/CD

## 📁 Repository Structure

```
services/
├── automation/          # CI/CD and automation
│   ├── github-runner/   # Automated deployment runner
│   └── jenkins/         # Jenkins CI server with ephemeral agents
├── automotive/          # Tesla integration
│   └── teslamate/       # Tesla vehicle tracking
├── ecommerce/           # Online commerce
│   └── j3d/             # Order and filament tracker
├── gaming/              # Gaming services
│   └── mc-network/      # Minecraft server network
├── infrastructure/      # Core infrastructure
│   └── redis/           # In-memory cache
├── iot/                 # Smart home and IoT
│   ├── home-assistant/  # Home automation hub
│   ├── govee2mqtt/      # Govee bridge to MQTT/Home Assistant
│   ├── mosquitto/       # MQTT message broker
│   └── zigbee2mqtt/     # Zigbee to MQTT bridge
├── media/               # Media management
│   ├── immich/          # Photo and video management
│   └── romm/            # Game library manager
├── monitoring/          # Observability stack
│   ├── grafana/         # Dashboard and visualization
│   ├── loki/            # Log aggregation
│   ├── prometheus/      # Metrics collection
│   ├── promtail/        # Log collector
│   └── uptimekuma/      # Uptime monitoring
├── networking/          # Network services
│   ├── cloudflared/     # Cloudflare Tunnel
│   └── nginx-proxy-manager/  # Reverse proxy with SSL
├── productivity/        # Productivity tools
│   ├── actualserver/    # Budget management
│   ├── nextcloud/       # File sync and collaboration
│   ├── tandoor/         # Recipe management
│   └── wikijs/          # Personal wiki
├── security/            # Security and authentication
│   ├── authentik/       # Identity provider
│   └── vaultwarden/     # Password manager
└── utilities/           # Utility services
    ├── dashy/           # Service dashboard
    ├── filebrowser/     # File browser and manager
    ├── goaccess/        # Web analytics
    ├── honeygain/       # Passive income network
    ├── kopia/           # Backup and recovery
    └── portainer/       # Docker management UI
```

## 🔧 Service Categories & Resource Limits

### Light Services (0.25-0.5 CPU, 128-512MB RAM)
- Dashy, GoAccess, Honeygain, Cloudflared, Mosquitto, Govee2MQTT, Portainer
- These are dashboards, analytics, and lightweight utilities

### Medium Services (0.5-1 CPU, 512MB-2GB RAM)
- Redis, Prometheus, Loki, Promtail, Kopia, UptimeKuma, AutoKuma, FileBrowser
- Database caches, monitoring collectors, and general utilities

### Heavy Services (0.75-2 CPU, 1-4GB RAM)
- Nextcloud, Immich, Home Assistant, Jenkins, GitHub Runner, Minecraft Network, Grafana, Authentik
- Full applications, media processing, and resource-intensive services

## 🚀 CI/CD & Automation

### Jenkins Server
- **Location**: `services/automation/jenkins/`
- **Features**:
  - Ephemeral agents via Docker socket proxy
  - No direct Docker socket access (security best practice)
  - Automated CI/CD pipelines for deployments
  - 1.5 CPU / 2GB memory limit

### GitHub Actions Runner
- **Location**: `services/automation/github-runner/`
- **Features**:
  - Fresh environment for each job
  - Direct integration with justpow98/unraid repository
  - Automated update checks and deployment
  - 2 CPU / 2GB memory limit

### Automated Updates (Renovate)
- **Config**: `.github/renovate.json`
- **Workflow**: `.github/workflows/renovate.yml`
- **What it does**: Scans all `services/**/docker-compose.yml` images weekly (Sun 09:00 UTC), groups them into a single PR with labels `automated` and `container-updates`, and respects pinned versions.
- **Notes**: Use a repo-scoped `RENOVATE_TOKEN` (or `GH_TOKEN`) secret for the workflow. Major updates are labeled `breaking-change?` and not auto-merged.

### Legacy Update Script (manual)
- **Script**: `scripts/check-updates.py`
- **Features**:
  - Monitors 35+ services for new releases
  - GitHub API integration for version tracking
  - Registry-aware (Docker Hub, GHCR, custom registries)
  - Rate limit management
  - Jenkins and all services monitored

## 🔒 Security Features

- **Docker Socket Proxy**: Jenkins uses tecnativa/docker-socket-proxy for restricted access
- **Non-Root Services**: Services run as non-root where possible
- **Resource Limits**: CPU and memory limits prevent resource exhaustion
- **Environment Secrets**: Sensitive data in `.env` file
- **Privilege Isolation**: Services run with minimal required privileges
- **Database Isolation**: All databases only exposed to internal `db_net` - no host port exposure
- **Network Segmentation**: Services isolated by function (internal_net, db_net, iot_net, monitoring_net, public_net)

## 🛠️ Usage

### Deploy a Single Service
```bash
cd services/utilities/dashy
docker-compose --env-file ../../../.env up -d
```

### Deploy All Services
```bash
# Build network dependencies first
docker network create internal_net
docker network create monitoring_net
docker network create db_net
docker network create iot_net
docker network create teslamate_net
docker network create mc_net
docker network create public_net

# Deploy each service
for dir in services/*/*/; do
  cd "$dir"
  docker-compose --env-file ../../../.env up -d
  cd ../../..
done
```

### Check for Updates
```bash
python3 scripts/check-updates.py
```

### Deploy a Service Update
```bash
./scripts/deploy-service.sh services/utilities/dashy
```

## 📊 Monitoring

All services monitored via UptimeKuma with centralized logging via Loki and metrics via Prometheus.

## 📄 License

See LICENSE file for details

---

**Last Updated**: May 2026  
**Services**: 35+  
**Total CPU Limit**: ~25 cores  
**Total Memory Limit**: ~35GB
