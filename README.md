## Docker Containers Running on Pi

`infrastructure/docker-compose.yml`
  nginx                              ← serves static + proxies dynamic
  cloudflared                        ← tunnel to Cloudflare
  postgres                           ← app database
  registry                           ← self-hosted image registry

`apps/dynamic/appname/web/docker-compose.yml`
  app_web_blue        :3000 (inactive)
  app_web_green       :3000 (active slot)

`apps/dynamic/appname/api/docker-compose.yml`
  app_api_blue        :3001 (inactive)
  app_api_green       :3001 (active slot)

## Docker Network

network: web
  │
  ├── cloudflared                    ← only entry from internet
  ├── nginx                          ← routes all traffic
  ├── postgres                       ← internal only
  ├── registry                       ← internal only
  ├── app_web_*                      ← internal only
  └── app_api_*                      ← internal only

## yourname.com
  → serves /home/applepie/server/apps/static/portfolio/public/ directly

app.yourname.com
  /            → app_web_{slot}:3000
  /api/        → app_api_{slot}:3001
  /uploads/    → served directly from /home/applepie/server/data/uploads/app/

registry.yourname.com
  → registry:5000

## Quick Start (Static Portfolio)

1. On Pi, run setup script:
   ```bash
   cd ~/web-server
   ./scripts/setup-pi.sh
   ```

2. Create `.env` on Pi:
   ```bash
   nano /home/applepie/server/.env
   # Add CLOUDFLARE_TUNNEL_TOKEN from Cloudflare
   ```

3. Start infrastructure:
   ```bash
   docker compose -f infrastructure/docker-compose.yml up -d
   ```

4. Deploy portfolio content:
   ```bash
   # From this repo, copy built files to Pi:
   rsync -av apps/static/portfolio/public/ pi@your-pi:/home/applepie/server/apps/static/portfolio/public/
   ```

5. Verify:
   ```bash
   curl https://yourname.com  # Should return HTML
   ```

## Request Flow

### Static Site

```
Browser → yourname.com
    ↓
Cloudflare (SSL)
    ↓
cloudflared tunnel
    ↓
nginx → /sites/portfolio (mounted from /home/applepie/server/apps/static/portfolio/public/)
    ↓
response
```

### Dynamic App (Future)

```
Browser → app.yourname.com
    ↓
Cloudflare (SSL)
    ↓
nginx
    ↓
  /api/* → app_api_{blue|green}:3001 → postgres:5432
  /*    → app_web_{blue|green}:3000
  /uploads → /home/applepie/server/data/uploads/app/
    ↓
response
```

## Blue-Green Deployment (Dynamic App)

Two parallel slots (blue, green). Only one active at a time.

Switch procedure:
1. Deploy new version to inactive slot
2. Wait for health checks
3. Update `infrastructure/upstreams/app_web.conf` to point to new slot
4. `docker exec infrastructure-nginx-1 nginx -s reload`
5. Update `/home/applepie/server/releases/dynamic/app/web/current_slot` and `current_version`

Active slot tracked in:
- `/home/applepie/server/releases/dynamic/app/web/current_slot`
- `/home/applepie/server/releases/dynamic/app/api/current_slot`

## Directory Structure (on Pi)

```
/home/applepie/server/
├── apps/
│   ├── static/
│   │   └── portfolio/
│   │       └── public/         ← static site files (index.html, css, js)
│   └── dynamic/
│       └── appname/
│           ├── web/docker-compose.yml
│           └── api/docker-compose.yml
├── data/
│   ├── uploads/app/            ← user uploads
│   └── db/                     ← PostgreSQL data
├── logs/
│   └── nginx/                  ← access.log, error.log
├── registry/                   ← Docker registry storage
├── releases/
│   └── dynamic/
│       └── app/
│           ├── web/
│           │   ├── blue.env
│           │   ├── green.env
│           │   ├── current_slot
│           │   └── current_version
│           └── api/ (same)
├── .env                        ← global secrets (CLOUDFLARE_TUNNEL_TOKEN, POSTGRES_PASSWORD)
└── scripts/                    ← deployment and maintenance scripts
```

**In this repository** (configuration as code):
- `infrastructure/` – nginx, cloudflared, postgres, registry configs
- `apps/dynamic/appname/` – docker-compose files for dynamic app
- `scripts/` – automation scripts (setup-pi.sh, etc.)
- `apps/static/portfolio/public/` – portfolio source files (in repo for simplicity)

---

## Configuration

### Environment Variables

**Global** (`/home/applepie/server/.env`):
- `CLOUDFLARE_TUNNEL_TOKEN` – required
- `POSTGRES_USER` – default: postgres
- `POSTGRES_PASSWORD` – required
- `REGISTRY_USERNAME`, `REGISTRY_PASSWORD` – for registry auth

**Dynamic App** (`/home/applepie/server/releases/dynamic/app/{web,api}/*.env`):
See `docs/reference/variables.md` for full list.

### Nginx Configuration

- Main config: `infrastructure/nginx/nginx.conf`
- Server blocks: `infrastructure/nginx/conf.d/`
  - `portfolio.conf` – yourname.com → `/sites/portfolio`
  - `app.conf` – app.yourname.com → upstreams
  - `registry.conf` – registry.yourname.com → registry:5000
- Upstreams: `infrastructure/upstreams/`
  - `app_web.conf` – points to `app_web_blue:3000` or `app_web_green:3000`
  - `app_api.conf` – points to `app_api_blue:3001` or `app_api_green:3001`

---

## Common Commands

```bash
# Start all infrastructure
docker compose -f infrastructure/docker-compose.yml up -d

# Stop all infrastructure
docker compose -f infrastructure/docker-compose.yml down

# View logs
docker compose -f infrastructure/docker-compose.yml logs -f nginx
docker compose -f infrastructure/docker-compose.yml logs -f cloudflared

# Test nginx config
docker compose -f infrastructure/docker-compose.yml exec nginx nginx -t

# Reload nginx
docker compose -f infrastructure/docker-compose.yml exec nginx nginx -s reload

# Check Pi disk usage
df -h /home/applepie/server

# Check container resource usage
docker stats
```

---

## Backup & Restore

**Backup** (run daily via cron):
- PostgreSQL: `pg_dump -U postgres app_db > /home/applepie/server/backups/db-$(date +%F).sql.gz`
- Uploads: `tar -czf /home/applepie/server/backups/uploads-$(date +%F).tar.gz /home/applepie/server/data/uploads`
- Static sites: files already in Git; just backup if custom content
- Secrets: encrypt `/home/applepie/server/.env/`

**Restore**: See `docs/operations/RECOVERY.md`

---

## Security Notes

- Never commit `.env` files with secrets
- Use strong passwords for `POSTGRES_PASSWORD` and `REGISTRY_PASSWORD`
- Enable registry authentication (see Task 8 in TODO)
- Keep Pi OS updated: `sudo apt update && sudo apt upgrade`
- Consider enabling firewall (UFW) to block all except SSH (22)

---

## Troubleshooting

- **Sites not loading**: Check cloudflared container logs; verify tunnel token
- **502 errors**: Check if app containers running; verify upstream name in nginx config
- **404 errors**: Check file paths; verify nginx `root` matches volume mount
- **Permission denied**: Fix ownership: `sudo chown -R pi:pi /home/applepie/server`
- **Disk full**: Clean old logs, Docker images, uploads

See `docs/operations/RUNBOOK.md` for detailed troubleshooting.

---

## Status

- ✅ Static portfolio site (yourname.com) – **working**
- ✅ Docker infrastructure (nginx, cloudflared, postgres, registry) – **configured**
- ⏳ Dynamic app (app.yourname.com) – deferred
- 📝 Blog – removed from scope

See `docs/project/TODO.md` for current priorities and next steps.

---

**Last updated**: 2026-04-06
