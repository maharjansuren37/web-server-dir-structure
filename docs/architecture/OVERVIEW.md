# Architecture Overview

## System Context

This infrastructure hosts multiple services on a Raspberry Pi:
- **Portfolio site** (static) - yourname.com
- **Dynamic application** (web + API) - app.yourname.com
- **Docker registry** - registry.yourname.com

All traffic flows through a **Cloudflare Tunnel** → **Nginx gateway** → appropriate backend.

## Network Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                     Cloudflare (SSL)
                           │
              ┌────────────▼────────────┐
              │  cloudflared tunnel     │
              │  (apps/pi-server/cloudflared) │
              └────────────┬────────────┘
                           │
                    ┌──────▼──────┐
                    │    Nginx    │
                    │   Gateway   │
                    │ (port 80)   │
                    └──────┬──────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
  ┌──────────┐      ┌──────────┐      ┌──────────┐
  │  Static  │      │   App    │      │ Registry │
  │  Sites   │      │   Web    │      │  (5000)  │
  │          │      │  (3000)  │      │          │
  │ /sites/  │      │          │      │          │
  │ portfolio│      │ /api/ →  │      │          │
  │          │      │   API    │      │          │
  │          │      │  (3001)  │      │          │
  └──────────┘      └──────────┘      └──────────┘
```

**Network**: All services connected to `web` bridge network (internal only except nginx:80 → internet)

## Component Details

### 1. Gateway (`apps/pi-server/`)

**Nginx** (`nginx/`)
- Acts as reverse proxy and static file server
- Listens on port 80 (HTTP) – external SSL terminated by Cloudflared
- Routes based on hostname:
  - `yourname.com`, `www.yourname.com` → static files in `/sites/`
  - `app.yourname.com` → proxy to `app_web` (blue or green), `/api/` → `app_api`
  - `registry.yourname.com` → proxy to `registry:5000`
- Configuration modular:
  - `nginx.conf` – main config
  - `conf.d/*.conf` – server blocks
  - `upstreams/*.conf` – dynamic upstream definitions (blue-green routing)

**Cloudflared** (`cloudflared/`)
- Creates tunnel to Cloudflare
- Credentials stored in `/etc/cloudflared/credentials.json`
- Routes all hostnames to nginx
- Runs in container alongside nginx

### 2. Dynamic Application (`apps/dynamic/appname/`)

**Blue-Green Deployment Pattern**
Two parallel sets of containers ensure zero-downtime:
- `app_web_blue:3000` (frontend) + `app_api_blue:3001` (backend)
- `app_web_green:3000` (frontend) + `app_api_green:3001` (backend)

Only one slot is active at a time, determined by:
- `apps/pi-server/nginx/upstreams/app_web.conf`
- `apps/pi-server/nginx/upstreams/app_api.conf`

**Switch procedure**:
1. Deploy new version to inactive slot (update image tag)
2. Wait for health checks to pass
3. Update upstream config to point to new slot
4. Reload nginx
5. Update `releases/dynamic/app/{web,api}/current_slot` and `current_version`

**State tracking** (`releases/dynamic/app/`):
```
releases/
  dynamic/
    app/
      web/
        current_slot    # "blue" or "green"
        current_version # e.g., "v1.2.3"
        blue.env        # environment variables for blue slot
        green.env       # environment variables for green slot
      api/
        (same structure)
```

**Environment files**: Instead of storing in repo, these should be placed on Pi at `/home/applepie/server/releases/dynamic/app/{web,api}/` and mounted as read-only.

### 3. Docker Registry (`infrastructure/registry/`)

Self-hosted registry for ARM64 images:
- Listens on port 5000
- Storage: Local filesystem (or S3 if configured)
- Authentication: htpasswd (to be implemented)
- Images pushed from CI with tags: `registry.yourname.com/app-web:tag`
- Pulled by Pi during deployment

### 4. Static Sites

Not containerized – deployed directly to Pi filesystem:
- `portfolio` site → `/home/applepie/server/apps/static/portfolio/public/`

Nginx serves these directly from `/sites/` (mounted from `/home/applepie/server/apps/static/`).

**Deployment**: Simple rsync, zero-downtime with atomic symlink switch.

### 5. Database (PostgreSQL)

Reference: `apps/pi-server/postgres/` (to be created)
- Data stored in `/home/applepie/server/db/` (persistent volume)
- Shared network `web`
- API containers connect to `postgres:5432`
- Credentials in `.env` and `blue.env`/`green.env`

## Data Flow

### Dynamic App Request

```
User → app.yourname.com
      ↓
Cloudflared (SSL offload)
      ↓
Nginx Gateway
      ↓
  /api/* → nginx upstream app_api (blue or green slot)
          → container: app_api_{blue|green}:3001
          → reads/writes: /uploads (shared volume)
          → queries: postgres:5432
          → response

  /*    → nginx upstream app_web (blue or green slot)
          → container: app_web_{blue|green}:3000
          → reads/writes: /uploads (if needed)
          → calls API for data
          → response
```

### Static Site Request

```
User → yourname.com
      ↓
Cloudflared (SSL offload)
      ↓
Nginx Gateway
      ↓
  Root directory: /sites/portfolio (mounted from /home/applepie/server/apps/static/portfolio/public/)
  → try_files $uri $uri/ $uri.html
  → serve static files (HTML, CSS, JS, images)
```

### Upload Flow

1. User uploads via API endpoint
2. API container saves to `/uploads` (mounted volume at `/home/applepie/server/data/uploads/app`)
3. Nginx serves uploads from `/uploads/app/` with long cache TTL (30 days)

## Persistent Storage (on Pi, not in repo)

| Host Path                  | Mounted In                 | Purpose                          |
|----------------------------|----------------------------|----------------------------------|
| `/home/applepie/server/db/`             | postgres container         | Database files                   |
| `/home/applepie/server/data/uploads/`   | app_api containers         | User uploads                     |
| `/home/applepie/server/apps/static/`    | nginx container `/sites/`  | Static site files                |
| `/home/applepie/server/.env/`           | Various containers         | Secrets                          |
| `/home/applepie/server/releases/`       | app web/api containers     | Environment files (blue/green)   |
| `/home/applepie/server/logs/nginx/`     | nginx container            | Nginx access/error logs          |

## Security Model

**Network segmentation**: Internal `web` network not exposed externally. Only nginx port 80 is exposed to internet (via cloudflared).

**Secrets**: Stored in `/home/applepie/server/.env/` on Pi, mounted as env files or Docker secrets. Never in repository.

**Authentication**:
- HTTP basic auth planned for registry
- API authentication: JWT (in `.env.example`: `JWT_SECRET`)
- Admin credentials: `ADMIN_USER`, `ADMIN_PASS_HASH`

**SSL/TLS**:
- External: Cloudflare Tunnel provides SSL
- Internal: Currently HTTP; plan to add TLS between nginx and app containers

## Monitoring & Observability

**Currently planned**:
- Container health checks (docker-compose)
- Log rotation (logrotate)
- Metrics: cAdvisor + Prometheus + Grafana (future)

**Logs**:
- Nginx: `/home/applepie/server/logs/nginx/access.log`, `error.log`
- Containers: Docker logs (json-file driver)
- Application: stdout/stderr (collected by Docker)

## Deployment Strategy

**Blue-Green**:
- Two parallel environments (blue, green)
- Deploy to inactive, validate with health checks, switch upstream
- Rollback by switching back to previous slot
- Each slot has its own environment file (blue.env, green.env)

**Static Sites**:
- Direct file deployment (rsync)
- Atomic symlink switch for zero-downtime
- No containers involved

## Cross-Cutting Concerns

**Multi-arch**: All images built for `linux/arm64` (Raspberry Pi).

**Resource constraints**: Pi has limited CPU/memory; need to set container limits.

**Backup**: Database dumps, uploads directory, secrets. Daily cron.

**Disaster recovery**: Documented in `docs/operations/RECOVERY.md`.

## Future Enhancements

- Canary deployments (traffic splitting)
- Centralized logging (Loki)
- Configuration management (Ansible)
- Service mesh (if complexity grows)
- Observability stack (full Prometheus stack)
- Certificate auto-renewal (for registry)
