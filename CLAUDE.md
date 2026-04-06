# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Docker-based web server infrastructure repository** for a Raspberry Pi homelab deployment. The project manages:

- **Gateway layer**: Nginx reverse proxy + Cloudflared tunnel for external secure access
- **Dynamic applications**: Blue-green deployment strategy with Docker containers
- **Static sites**: Direct file serving via Nginx
- **Self-hosted Docker registry**: ARM-compatible container images
- **CI/CD deployment scripts**: Automated deployment workflows

**Target platform**: Raspberry Pi (ARM64 architecture)

## Architecture

### Network Topology

```
Internet → Cloudflare (SSL) → cloudflared tunnel → nginx (web network)
                                              ↓
                    ┌─────────────────────────┼─────────────────────────┐
                    ↓                         ↓                         ↓
                Static sites            Dynamic app              Docker registry
                (direct files)          (blue/green slots)       (registry.yourname.com)
```

### Component Breakdown

**Gateway** (`infrastructure/`)
- `nginx/nginx.conf`: Main Nginx configuration
- `nginx/conf.d/`: Site-specific server blocks:
  - `app.conf`: Routes app.yourname.com (API → app_api, web → app_web, uploads → /uploads)
  - `portfolio.conf`: Serves static portfolio site (yourname.com)
  - `registry.conf`: Proxies Docker registry (registry.yourname.com)
- `upstreams/`: Dynamic upstream definitions for blue-green routing
  - `app_web.conf`: Points to `app_web_blue:3000` (or app_web_green)
  - `app_api.conf`: Points to `app_api_blue:3001` (or app_api_green)
- `cloudflared/config.yml`: Cloudflare Tunnel configuration

**Dynamic Applications** (`apps/dynamic/appname/`)
- Template structure for deploying web and API services
- `web/docker-compose.yml`: Blue-green deployment for frontend (ports 3000)
- `api/docker-compose.yml`: Blue-green deployment for backend (port 3001, with uploads volume)
- Both use environment variables: `${BLUE_VERSION}` / `${GREEN_VERSION}` pointing to registry images
- Uploads are persisted to `/home/applepie/server/data/uploads/app`

**Registry** (`infrastructure/registry/`)
- Self-hosted Docker registry on port 5000
- `.env.example`: Registry configuration template

**Release Management** (`releases/`)
- Tracks current version and environment files for blue/green slots:
  - `releases/dynamic/app/web/{blue,green}.env`, `current_version`, `current_slot`
  - `releases/dynamic/app/api/{blue,green}.env`, `current_version`, `current_slot`
  - `releases/static/portfolio/current_version`

**Persistent Data** (on the Pi, NOT in this repo)
- `/home/applepie/server/apps/static/portfolio/public/` - static site files (tracked separately)
- `/home/applepie/server/data/uploads/` - user uploads
- `/home/applepie/server/db/` - PostgreSQL database files
- `/home/applepie/server/.env/` - secrets
- `/home/applepie/server/logs/nginx/` - Nginx access/error logs

## Development Workflow

### Daily Development

1. **Static site development**:
   ```bash
   cd portfolio
   sh scripts/dev.sh  # Local development server
   ```
   Deploy: `sh scripts/deploy.sh` → rsync to Pi → served instantly by Nginx

2. **Dynamic app development**:
   - Develop application code in separate repo
   - Build ARM64 Docker images: `docker buildx build --platform linux/arm64`
   - Push to registry: `docker push registry.yourname.com/app-web:tag`
   - Deploy: SSH to Pi, update `BLUE_VERSION` or `GREEN_VERSION` in docker-compose.yml, run `docker compose up -d`
   - Switch upstream in `infrastructure/gateway/nginx/upstreams/app_web.conf` to point to new slot

### Blue-Green Deployment

- Two parallel container sets: `app_web_blue` and `app_web_green` (same for API)
- Only one slot is active (pointed to by upstream config)
- Deploy to inactive slot, switch upstream when ready
- Current slot tracked in `releases/dynamic/app/web/current_slot` and `current_version`

### Local Testing

- Static sites: `http://localhost:3000` (from dev.sh)
- Gateway Nginx: Run docker compose in `infrastructure/` to test full stack locally (requires network setup)

## Common Commands

### Build & Deploy

```bash
# Build multi-arch Docker images for dynamic app
docker buildx build --platform linux/arm64 -t registry.yourname.com/app-web:latest .
docker buildx build --platform linux/arm64 -t registry.yourname.com/app-api:latest .

# Push to registry
docker push registry.yourname.com/app-web:latest
docker push registry.yourname.com/app-api:latest

# Deploy to Pi (after pushing)
ssh pi 'cd /home/applepie/server/apps/dynamic/appname && docker compose pull && docker compose up -d'

# Switch upstream to new slot (on Pi)
# Edit infrastructure/upstreams/app_web.conf to point to app_web_green (or blue)
# Then reload nginx: docker exec gateway_nginx nginx -s reload
```

### Nginx Configuration

```bash
# Test Nginx config
docker exec pi-server-nginx nginx -t
# or if using container name from compose project
docker exec <project>_nginx_1 nginx -t

# Reload Nginx without downtime
docker exec pi-server-nginx nginx -s reload

# View logs (on Pi)
tail -f /home/applepie/server/logs/nginx/access.log
tail -f /home/applepie/server/logs/nginx/error.log
```

### Docker Management

```bash
# View running containers (on Pi)
docker compose -f /home/applepie/server/apps/dynamic/appname/web/docker-compose.yml ps
docker compose -f /home/applepie/server/apps/dynamic/appname/api/docker-compose.yml ps
docker compose -f /home/applepie/server/apps/pi-server/docker-compose.yml ps

# View logs for specific service
docker compose -f /home/applepie/server/apps/dynamic/appname/web/docker-compose.yml logs -f app_web_blue
docker compose -f /home/applepie/server/apps/pi-server/docker-compose.yml logs -f nginx
```

### Registry

```bash
# Login to registry (on Pi or CI)
docker login registry.yourname.com

# Pull images
docker pull registry.yourname.com/app-web:latest
```

## Important Files & Directories

| Path | Purpose |
|------|---------|
| `infrastructure/nginx/conf.d/app.conf` | Main app routing rules |
| `infrastructure/upstreams/app_web.conf` | Blue-green slot selector for web |
| `infrastructure/upstreams/app_api.conf` | Blue-green slot selector for API |
| `apps/dynamic/appname/web/docker-compose.yml` | Web container definitions |
| `apps/dynamic/appname/api/docker-compose.yml` | API container definitions |
| `infrastructure/docker-compose.yml` | Gateway services (nginx, cloudflared, postgres, registry) |
| `releases/dynamic/app/web/current_slot` | Active slot (blue or green) |
| `releases/dynamic/app/api/current_version` | Current deployed version |

## Configuration

### Environment Variables

- **Gateway**: `CLOUDFLARE_TUNNEL_TOKEN` (in `/home/applepie/server/.env/` on Pi)
- **Dynamic app**: `BLUE_VERSION` / `GREEN_VERSION` (in `.env` files in `apps/dynamic/appname/{web,api}/` on Pi)
- **Registry**: See `apps/pi-server/registry/.env.example`
- **PostgreSQL**: `POSTGRES_USER`, `POSTGRES_PASSWORD` (in `/home/applepie/server/.env/` on Pi)

**Secrets management**: All secrets stored in `/home/applepie/server/.env/` on the Pi - never commit to git.

## Notes

- All Docker images must be built for `linux/arm64` (Raspberry Pi)
- The `web` network is shared across all services; defined in `apps/pi-server/docker-compose.yml`
- Uploads are stored on the Pi at `/home/applepie/server/data/uploads/app` and served by Nginx at `/uploads/`
- Static sites are deployed directly to `/home/applepie/server/apps/static/portfolio/public/` and served by Nginx from `/sites/portfolio`
- The gateway Nginx config is mounted read-only from this repository; changes require reloading the container

## Rollback Procedure

1. Identify previous version tag (from `releases/dynamic/app/web/current_version`)
2. On your machine: `docker pull registry.yourname.com/app-web:<previous-tag>`
3. SSH to Pi: Update `BLUE_VERSION` or `GREEN_VERSION` in `apps/dynamic/appname/web/.env` (or docker-compose override)
4. Ensure upstream points to the correct slot (if not already): edit `apps/pi-server/nginx/upstreams/app_web.conf`
5. Reload nginx: `docker exec pi-server-nginx nginx -s reload` (or appropriate container name)
6. Run: `docker compose -f /home/applepie/server/apps/dynamic/appname/web/docker-compose.yml up -d`
7. Verify: `releases/dynamic/app/web/current_version` should match

## CI/CD Considerations

The deployment workflow (from README):
- **Static site**: `sh scripts/deploy.sh` → rsync files to Pi → Nginx serves instantly
- **Dynamic site**: Build ARM64 images → push to registry → SSH to Pi → `docker compose pull && docker compose up -d`

Ensure CI environment has:
- `docker/build-push-action` with `platforms: linux/arm64`
- SSH access to Pi
- Registry credentials

## Troubleshooting

### Container communication issues
- Verify all services are on the `web` network: `docker network inspect web`
- Check upstream config points to correct slot: `cat apps/pi-server/nginx/upstreams/app_web.conf`

### Uploads not appearing
- Verify volume mount: `/home/applepie/server/data/uploads/app:/uploads` in api docker-compose.yml
- Check Nginx alias: `/uploads/app/` in app.conf

### Deployment stuck on old version
- Check which slot is active: `cat releases/dynamic/app/web/current_slot`
- Verify upstream matches active slot
- Check container status: `docker compose -f /home/applepie/server/apps/dynamic/appname/web/docker-compose.yml ps`
