# Deployment Procedures

## Table of Contents
- [Static Sites](#static-sites)
- [Dynamic Application](#dynamic-application)
- [Blue-Green Strategy](#blue-green-strategy)
- [Rollback](#rollback)
- [Deployment Automation](#deployment-automation)

---

## Static Sites

Static sites (portfolio) are deployed via direct file sync, not containers.

### Prerequisites
- SSH access to Pi
- Read access to `/home/applepie/server/apps/static/`
- Nginx running and configured

### Manual Deployment

```bash
# From the static site source directory (e.g., portfolio/)
# Ensure build artifacts are ready (e.g., `npm run build`)

# Dry run: see what would be transferred
rsync -av --dry-run --delete ./dist/ pi@your-pi-ip:/home/applepie/server/apps/static/portfolio/public/

# Actual deployment
rsync -av --delete ./dist/ pi@your-pi-ip:/home/applepie/server/apps/static/portfolio/public/

# Optional: Clear Nginx cache if using fastcgi_cache
# docker exec gateway_nginx rm -rf /var/cache/nginx/*

# Nginx serves files instantly (no reload needed for new files)
# But reload if you changed nginx config:
docker exec gateway_nginx nginx -s reload
```

### Using Deployment Script (planned)

```bash
./scripts/deploy-static.sh portfolio v1.2.3
# Arguments: <site-name> <version-tag>
# Does: rsync, cache clear, version record update
```

### Zero-Downtime with Symlink Switch

For atomic deployments:

```bash
# On Pi:
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
TARGET_DIR="/home/applepie/server/apps/static/portfolio/site-$TIMESTAMP"

# 1. Upload to timestamped directory
rsync -av ./dist/ pi@pi:$TARGET_DIR/

# 2. Update symlink atomically
ln -sfn $TARGET_DIR /home/applepie/server/apps/static/portfolio/site

# 3. Reload nginx if needed
docker exec gateway_nginx nginx -s reload

# 4. Clean up old releases (keep last 5)
ls -t /home/applepie/server/apps/static/portfolio/site-* | tail -n +6 | xargs rm -rf
```

---

## Dynamic Application

Dynamic app uses blue-green deployment with Docker containers.

### Prerequisites
- Docker images built and pushed to registry: `registry.yourname.com/app-web:tag`, `app-api:tag`
- SSH access to Pi
- Deployment script `scripts/deploy-app.sh` (or manual procedure)

### Manual Deployment (Step-by-Step)

#### 1. Determine Active Slot

```bash
cat /home/applepie/server/releases/dynamic/app/web/current_slot
# Output: "blue" or "green"
```

Let's say active slot is **blue** → deploy to **green**.

#### 2. Update Green Slot Environment

Edit: `/home/applepie/server/releases/dynamic/app/web/green.env`
```bash
# Update environment variables if needed (JWT_SECRET, API_URL, etc.)
# Usually unchanged between versions
```

Same for API: `/home/applepie/server/releases/dynamic/app/api/green.env`

#### 3. Update Docker Compose to Use New Image

Edit: `/home/applepie/server/apps/dynamic/appname/web/docker-compose.yml`

```yaml
services:
  app_web_green:
    image: registry.yourname.com/app-web:v1.2.3  # ← Change to new tag
    # ... rest unchanged
```

Same for API: `/home/applepie/server/apps/dynamic/appname/api/docker-compose.yml`

```yaml
services:
  app_api_green:
    image: registry.yourname.com/app-api:v1.2.3  # ← Change to new tag
```

#### 4. Deploy to Green Slot

```bash
cd /home/applepie/server/apps/dynamic/appname/web
docker compose pull  # Pull new image
docker compose up -d app_web_green  # Start only green

cd ../api
docker compose pull
docker compose up -d app_api_green
```

#### 5. Wait for Health Checks

```bash
# Monitor until healthy
watch -n 5 'docker ps --filter "name=app_web_green" --format "{{.Status}}"'

# Or manually check
docker inspect app_web_green | grep -A 10 "Health"
```

Health check should show `"Status": "healthy"`.

#### 6. Verify Green Slot is Working

```bash
# Test green container directly
curl -s http://localhost:3001/health  # API
curl -s http://localhost:3000/health  # Web

# You can test via upstream if you temporarily modify upstream to point to green:
# infrastructure/gateway/nginx/upstreams/app_web.conf:
#   server app_web_green:3000;
# nginx -s reload
```

#### 7. Switch Upstream to Green

Edit `infrastructure/gateway/nginx/upstreams/app_web.conf`:

```nginx
upstream app_web {
    server app_web_green:3000;  # Changed from blue to green
}
```

Same for `app_api.conf` if needed.

Reload Nginx:
```bash
docker exec gateway_nginx nginx -s reload
```

#### 8. Update Current Slot Records

```bash
# Mark green as active
echo "green" > /home/applepie/server/releases/dynamic/app/web/current_slot
echo "v1.2.3" > /home/applepie/server/releases/dynamic/app/web/current_version

echo "green" > /home/applepie/server/releases/dynamic/app/api/current_slot
echo "v1.2.3" > /home/applepie/server/releases/dynamic/app/api/current_version
```

#### 9. Verify Traffic is Flowing to Green

```bash
# Check nginx upstream
docker exec gateway_nginx cat /etc/nginx/upstreams/app_web.conf

# Check logs show requests to green
docker logs app_web_green --tail 20

# Test via public URL
curl -I https://app.yourname.com/health
```

#### 10. (Optional) Stop Blue Slot

To free resources:

```bash
cd /home/applepie/server/apps/dynamic/appname/web
docker compose stop app_web_blue
docker compose rm -f app_web_blue  # Remove container

cd ../api
docker compose stop app_api_blue
docker compose rm -f app_api_blue
```

Blue slot is now ready for next deployment.

---

### Automated Deployment Script

After implementing `scripts/deploy-app.sh`:

```bash
# Deploy version v1.2.3
./scripts/deploy-app.sh v1.2.3

# With dry-run
./scripts/deploy-app.sh v1.2.3 --dry-run

# With timeout override
./scripts/deploy-app.sh v1.2.3 --health-timeout 120

# What it does:
# 1. Determines current active slot from current_slot file
# 2. Sets inactive = opposite slot
# 3. Updates docker-compose for inactive slot with new image tag
# 4. Pulls and starts inactive slot containers
# 5. Polls health endpoint until healthy (timeout: 120s)
# 6. On success: switches upstream config, reloads nginx, updates current_slot/version
# 7. On failure: stops inactive slot, logs error, exits with error code
```

---

## Blue-Green Strategy

### Principles

1. **Two identical environments**: blue and green
2. **Only one is live** at a time (determined by nginx upstream)
3. **Deploy to idle slot**, validate, then switch
4. **Zero downtime**: switch is atomic (nginx reload)
5. **Instant rollback**: switch upstream back to previous slot

### Advantages

- No downtime during deployment
- Easy rollback (just switch upstream)
- Ability to test new version in production-like environment (by temporarily routing)
- Health checks validate before exposing to users

### Slot State Tracking

| File | Purpose | Values |
|------|---------|--------|
| `/home/applepie/server/releases/dynamic/app/web/current_slot` | Active web slot | `blue` or `green` |
| `/home/applepie/server/releases/dynamic/app/api/current_slot` | Active API slot | `blue` or `green` |
| `/home/applepie/server/releases/dynamic/app/web/current_version` | Deployed web version | Semantic version (e.g., `v1.2.3`) |
| `/home/applepie/server/releases/dynamic/app/api/current_version` | Deployed API version | Semantic version |

### Switching Traffic

```nginx
# upstream file determines active slot
upstream app_web {
    server app_web_blue:3000;   # → blue is live
    # or
    server app_web_green:3000;  # → green is live
}
```

After editing, reload nginx: `nginx -s reload` (atomic switch).

---

## Rollback

If new version has issues, roll back to previous version.

### Manual Rollback

1. **Identify previous version**:
```bash
cat /home/applepie/server/releases/dynamic/app/web/current_version  # e.g., v1.2.3 (new, broken)
# Look at git log or deployment history to find previous version, e.g., v1.2.2
```

2. **Switch to opposite slot** (if that slot still has old version):

```bash
# Determine current slot
CURRENT_SLOT=$(cat /home/applepie/server/releases/dynamic/app/web/current_slot)
if [ "$CURRENT_SLOT" = "blue" ]; then
  TARGET_SLOT="green"
else
  TARGET_SLOT="blue"
fi

# Update upstream to target slot
echo "server app_web_${TARGET_SLOT}:3000;" > infrastructure/gateway/nginx/upstreams/app_web.conf
echo "server app_api_${TARGET_SLOT}:3001;" > infrastructure/gateway/nginx/upstreams/app_api.conf

# Reload nginx
docker exec gateway_nginx nginx -s reload

# Update current_slot records
echo "$TARGET_SLOT" > /home/applepie/server/releases/dynamic/app/web/current_slot
# version file unchanged (still shows new version even though rolled back)

echo "Rolled back to $TARGET_SLOT"
```

3. **If both slots have new version** (both green and blue were updated during deploy):

Redeploy old version:
```bash
./scripts/deploy-app.sh v1.2.2  # Previous known-good version
```

### Automated Rollback Script (future)

```bash
./scripts/rollback.sh
# Automatically switches to previous slot or redeploys last known-good version
```

---

## Deployment Automation

### Script: `scripts/deploy-app.sh`

**To be implemented** (see Task 11). Features:

- Accepts version tag as argument
- Determines current active slot
- Deploys to inactive slot
- Health check polling with timeout
- Automatic switch and reload
- Atomic file updates for `current_slot` and `current_version`
- Rollback on failure
- Logging and notifications

### CI/CD Integration

GitHub Actions workflow:

```yaml
name: Deploy
on:
  push:
    branches: [main]
    tags: ['v*']

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build multi-arch images
        run: |
          docker buildx build --platform linux/arm64,linux/amd64 \
            -t registry.yourname.com/app-web:${{ github.ref_name }} \
            -t registry.yourname.com/app-web:latest \
            --push ./web
          # Same for api
      - name: Deploy to Pi
        if: github.ref == 'refs/tags/v*'
        run: |
          ssh pi@your-pi-ip './scripts/deploy-app.sh ${{ github.ref_name }}'
```

---

## Verification Checklist

After any deployment, verify:

- [ ] `docker ps` shows both web and api containers for active slot running
- [ ] `docker ps` also shows inactive slot containers (stopped or running old version)
- [ ] Container status: `Up X minutes` (no restart loops)
- [ ] Health check: `docker inspect app_web_green | grep -A2 Health` → `"Status": "healthy"`
- [ ] Nginx upstream: `cat infrastructure/gateway/nginx/upstreams/app_web.conf` → points to active slot
- [ ] Current slot file: `cat /home/applepie/server/releases/dynamic/app/web/current_slot` → matches upstream
- [ ] Public endpoint: `curl -f https://app.yourname.com/health` → 200 OK
- [ ] API endpoint: `curl -f https://app.yourname.com/api/health` → 200 OK
- [ ] Uploads working: upload test file, verify accessible
- [ ] Database queries: `curl https://app.yourname.com/api/users` (or similar)
- [ ] No errors in nginx log: `tail -n 50 /home/applepie/server/logs/nginx/error.log`
- [ ] No errors in container logs: `docker logs app_web_green --tail 50`

---

## Additional Resources

- [Blue-Green Deployment on Nginx](https://www.nginx.com/blog/blue-green-deployment/)
- [Docker Compose healthcheck docs](https://docs.docker.com/compose/compose-file/compose-file-v3/#healthcheck)
- [Runbook](RUNBOOK.md) for troubleshooting
