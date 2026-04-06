# Quick Start Guide

This guide helps you get started with this Raspberry Pi web server infrastructure quickly.

## For New Contributors

1. **Read in order**:
   - [README.md](../README.md) – Project overview
   - [architecture/OVERVIEW.md](../architecture/OVERVIEW.md) – System design
   - [development/SETUP.md](../development/SETUP.md) – Local setup
   - [project/TODO.md](./TODO.md) – Current tasks and priorities

2. **First tasks** (pick one):
   - Fix Docker Compose network config (Task #1)
   - Create pi-server directory structure (Task #2)
   - Add health checks (Task #5)

3. **Ask questions**: Check [RUNBOOK.md](../operations/RUNBOOK.md) if stuck.

---

## For DevOps / Sysadmin

### Deploying to a New Raspberry Pi

1. **Provision Pi**:
   - Install Raspberry Pi OS 64-bit
   - Configure SSH, networking
   - Run `scripts/setup-pi.sh` (to be created)

2. **Configure secrets**:
   ```bash
   # On Pi
   mkdir -p ~/.env
   # Copy from secure source or:
   cp ~/web-server/.env.example.pi ~/.env
   # Edit with actual values: CLOUDFLARE_TUNNEL_TOKEN, POSTGRES_PASSWORD, etc.
   ```

3. **Start gateway**:
   ```bash
   cd ~/web-server/infrastructure/gateway
   docker compose up -d
   ```

4. **Start database**:
   ```bash
   cd ~/web-server/apps/pi-server
   docker compose up -d postgres
   # Initialize DB if needed
   ```

5. **Deploy dynamic app**:
   ```bash
   # First: Build and push images to registry
   docker buildx build --platform linux/arm64 -t registry.yourname.com/app-web:v1.0.0 ./path/to/web
   docker push registry.yourname.com/app-web:v1.0.0

   # Then on Pi:
   cd ~/web-server
   ./scripts/deploy-app.sh v1.0.0
   ```

6. **Deploy static site**:
   ```bash
   cd ~/web-server/static-site
   ./scripts/deploy.sh
   ```

7. **Verify**:
   ```bash
   curl https://yourname.com
   curl https://app.yourname.com/health
   curl https://registry.yourname.com/v2/_catalog
   ```

---

## Common Commands Reference

### Start/Stop Services

```bash
# Gateway (nginx + cloudflared)
docker compose -f infrastructure/gateway/docker-compose.yml up -d
docker compose -f infrastructure/gateway/docker-compose.yml down

# Dynamic app
docker compose -f apps/dynamic/appname/web/docker-compose.yml up -d
docker compose -f apps/dynamic/appname/api/docker-compose.yml up -d

# Database (pi-server)
docker compose -f apps/pi-server/docker-compose.yml up -d postgres
```

### Check Status

```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
docker network inspect web | grep -A 20 "Containers"
```

### View Logs

```bash
# Nginx
docker compose -f infrastructure/gateway/docker-compose.yml logs -f nginx

# App
docker logs app_web_green --tail 100

# All gateway services
docker compose -f infrastructure/gateway/docker-compose.yml logs -f
```

### Health Checks

```bash
# Direct from Pi
curl http://localhost:3000/health
curl http://localhost:3001/health

# Via nginx
curl http://localhost/health  # if configured
curl http://localhost/api/health

# Check Docker health status
docker ps --filter "status=unhealthy"
docker inspect app_web_blue | grep -A 5 Health
```

---

## File Locations (on Pi vs. in Repo)

| Path | Lives In | Purpose |
|------|----------|---------|
| `/home/applepie/server/.env` | **On Pi only** (not in repo) | Global secrets |
| `/home/applepie/server/releases/dynamic/app/web/blue.env` | **On Pi only** | Blue slot env |
| `/home/applepie/server/releases/dynamic/app/web/green.env` | **On Pi only** | Green slot env |
| `/home/applepie/server/releases/dynamic/app/web/current_slot` | **On Pi only** | Tracks active slot |
| `/home/applepie/server/apps/static/portfolio/public/` | **On Pi only** | Static site files |
| `/home/applepie/server/data/uploads/app/` | **On Pi only** | User uploads |
| `/home/applepie/server/logs/nginx/` | **On Pi only** | Nginx logs |
| `/home/applepie/server/db/` | **On Pi only** | PostgreSQL data |
| `infrastructure/gateway/nginx/conf.d/*.conf` | **In Repo** | Nginx server blocks |
| `infrastructure/gateway/nginx/upstreams/*.conf` | **In Repo** | Blue-green routing |
| `apps/pi-server/docker-compose.yml` | **In Repo** | Pi services (nginx, postgres) |
| `apps/dynamic/appname/web/docker-compose.yml` | **In Repo** | Web container definitions |
| `apps/dynamic/appname/api/docker-compose.yml` | **In Repo** | API container definitions |

**Key principle**: Configuration in Git, secrets and persistent data on Pi.

---

## Troubleshooting Quick Links

| Problem | See Also |
|---------|----------|
| Containers won't start | [RUNBOOK: Containers Won't Start](../operations/RUNBOOK.md#1-containers-wont-start) |
| Nginx 502/404 errors | [RUNBOOK: Nginx Errors](../operations/RUNBOOK.md#2-nginx-returns-502-bad-gateway) |
| Cloudflared disconnected | [RUNBOOK: Cloudflare Tunnel](../operations/RUNBOOK.md#4-cloudflare-tunnel-disconnected) |
| Uploads not working | [RUNBOOK: Uploads Broken](../operations/RUNBOOK.md#5-uploads-broken) |
| Database errors | [RUNBOOK: Database Connection](../operations/RUNBOOK.md#6-database-connection-fails) |
| Deployment fails | [DEPLOYMENT: Verification Checklist](../operations/DEPLOYMENT.md#verification-checklist) |
| Total server loss | [RECOVERY: Complete Server Failure](../operations/RECOVERY.md#scenario-1-complete-server-failure-raspberry-pi-dead) |

---

## Support & Resources

- **Architecture questions**: Read [architecture/OVERVIEW.md](../architecture/OVERVIEW.md)
- **Configuration details**: See [reference/variables.md](../reference/variables.md) and [reference/ports.md](../reference/ports.md)
- **Design decisions**: Review [architecture/DECISIONS.md](../architecture/DECISIONS.md)
- **TODOs**: Check [project/TODO.md](./TODO.md) for current priorities

---

## Next Steps

1. **If setting up new server**: Follow [development/SETUP.md](../development/SETUP.md)
2. **If fixing issues**: Pick a task from [project/TODO.md](./TODO.md) (Phase 1)
3. **If planning deployment**: Read [operations/DEPLOYMENT.md](../operations/DEPLOYMENT.md)
4. **If preparing for production**: Complete Phase 1 and 2 tasks from [project/TODO.md](./TODO.md)

---

**Last updated**: 2026-04-06
