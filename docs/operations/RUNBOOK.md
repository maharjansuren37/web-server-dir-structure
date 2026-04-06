# Runbook: Troubleshooting Guide

**When something breaks, start here.**

## Quick Diagnostic Commands

```bash
# Check what containers are running
docker compose -f /home/applepie/server/apps/pi-server/docker-compose.yml ps
docker compose -f /home/applepie/server/apps/dynamic/appname/docker-compose.yml ps

# View container logs
docker compose -f /home/applepie/server/apps/pi-server/docker-compose.yml logs -f nginx
docker compose -f /home/applepie/server/apps/dynamic/appname/docker-compose.yml logs -f app_web_blue

# Check container health status
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Test nginx config
docker exec gateway_nginx nginx -t

# Reload nginx config
docker exec gateway_nginx nginx -s reload

# Test connectivity from nginx to upstreams
docker exec gateway_nginx curl -s -o /dev/null -w "%{http_code}" http://app_web:3000

# Check Docker network
docker network inspect web

# View Pi resource usage
docker stats
htop

# Check disk space
df -h
du -sh /home/applepie/server/data/uploads/

# Check nginx access/error logs
tail -f /home/applepie/server/logs/nginx/access.log
tail -f /home/applepie/server/logs/nginx/error.log
```

## Common Issues & Solutions

### 1. Containers Won't Start

**Symptoms**: `docker compose up` fails; `docker ps` doesn't show containers.

**Diagnose**:
```bash
# Check compose config syntax
docker compose -f /path/to/docker-compose.yml config

# Check container logs for failed starts
docker compose logs [service_name]

# Check if port already in use
docker compose ps
sudo netstat -tulpn | grep :80  # Or :3000, :3001, :5000
```

**Common fixes**:
- Invalid YAML syntax → fix indentation
- Missing environment variables → check `.env` file
- Port conflict → stop other service or change port
- Network doesn't exist → `docker network create web`
- Invalid image → `docker pull` or rebuild

---

### 2. Nginx Returns 502 Bad Gateway

**Symptoms**: Site loads but shows 502; upstream connection failed.

**Diagnose**:
```bash
# Check nginx error log
tail -n 50 /home/applepie/server/logs/nginx/error.log

# Check if upstream container is running
docker compose ps app_web_blue  # or app_web_green

# Check if app is listening
docker exec app_web_blue netstat -tuln | grep :3000

# Test from nginx container
docker exec gateway_nginx curl -v http://app_web:3000
```

**Common fixes**:
- Upstream container not running → `docker compose up app_web_blue`
- App crashed → check app logs: `docker logs app_web_blue`
- Wrong upstream name in nginx config → verify `infrastructure/gateway/nginx/upstreams/app_web.conf`
- App not listening on `0.0.0.0` (should not be `127.0.0.1`)
- Health check failing → fix health endpoint or increase timeout
- Network issue → verify containers on same `web` network

---

### 3. Nginx Returns 404

**Symptoms**: 404 Not Found for valid URLs.

**Diagnose**:
```bash
# Check which server block is handling request
docker exec gateway_nginx cat /etc/nginx/conf.d/*.conf | grep -A5 "server_name"

# Check root directory exists
docker exec gateway_nginx ls -la /sites/portfolio

# Test static file path
docker exec gateway_nginx ls -la /sites/portfolio/index.html

# Verify nginx config has correct root
docker exec gateway_nginx grep "root" /etc/nginx/conf.d/portfolio.conf
```

**Common fixes**:
- Wrong `root` path in nginx config → correct to proper mount
- Files not deployed → `rsync` or copy static files
- Missing `index` directive → add `index index.html;`
- `try_files` misconfiguration → adjust pattern

---

### 4. Cloudflare Tunnel Disconnected

**Symptoms**: Sites unreachable from internet; local access works.

**Diagnose**:
```bash
# Check cloudflared container
docker logs infrastructure-cloudflared  # or container name

# Check tunnel status
docker exec cloudflared cloudflared tunnel info

# Verify credentials file exists on Pi
ls -la /etc/cloudflared/credentials.json
```

**Common fixes**:
- Expired/invalid `CLOUDFLARE_TUNNEL_TOKEN` → update `.env` and restart container
- Credentials file missing → recreate tunnel in Cloudflare dashboard, update config
- Cloudflare service issue → check status.cloudflare.com
- Restart cloudflared: `docker compose restart cloudflared`

---

### 5. Uploads Broken

**Symptoms**: Uploads fail, or uploaded files not accessible.

**Diagnose**:
```bash
# Check uploads directory exists and has permissions
ls -la /home/applepie/server/data/uploads/app/

# Check uploads are being written
ls -la /home/applepie/server/data/uploads/app/

# Check nginx upload alias
docker exec gateway_nginx cat /etc/nginx/conf.d/app.conf | grep -A3 "location /uploads"

# Test upload URL directly
curl -I https://app.yourname.com/uploads/test.jpg

# Check api container can write
docker exec app_api_blue touch /uploads/test.txt
```

**Common fixes**:
- Volume not mounted → verify `volumes:` in api docker-compose
- Permission denied → `chown -R 1000:1000 /home/applepie/server/data/uploads` (adjust to container UID)
- Wrong alias path → nginx config should have `alias /uploads/app/;`
- Disk full → `df -h`, clean up files

---

### 6. Database Connection Fails

**Symptoms**: API logs show "connection refused" or "password authentication failed".

**Diagnose**:
```bash
# Check postgres container
docker compose -f /home/applepie/server/apps/pi-server/docker-compose.yml ps postgres

# Check postgres logs
docker compose -f /home/applepie/server/apps/pi-server/docker-compose.yml logs postgres

# Test connection from api container
docker exec app_api_blue sh -c "apk add --no-cache postgresql-client 2>/dev/null || apt-get install -y postgresql-client 2>/dev/null || pip install psycopg2-binary 2>/dev/null; nc -z postgres 5432 && echo OK || echo FAIL"

# Check environment variables in api container
docker exec app_api_blue env | grep DB_
```

**Common fixes**:
- Postgres not running → `docker compose up postgres`
- Wrong credentials → update `DB_URL` in `.env` file
- Database not created → `docker exec postgres createdb -U postgres app_db`
- Network issue → verify both on `web` network: `docker network inspect web`
- Password authentication failed → reset password in postgres

---

### 7. Blue-Green Switch Doesn't Work

**Symptoms**: Deploy script runs but traffic still goes to old version.

**Diagnose**:
```bash
# Check which slot is marked as current
cat /home/applepie/server/releases/dynamic/app/web/current_slot

# Check upstream config
cat infrastructure/gateway/nginx/upstreams/app_web.conf

# Are they different? If yes, nginx needs reload
docker exec gateway_nginx nginx -s reload

# Verify upstream is pointing to correct slot
docker exec gateway_nginx cat /etc/nginx/upstreams/app_web.conf

# Check both slots are running
docker compose -f /home/applepie/server/apps/dynamic/appname/docker-compose.yml ps | grep app_web
```

**Common fixes**:
- Upstream config not updated → fix `current_slot` and nginx upstream file
- Nginx not reloaded → `docker exec gateway_nginx nginx -s reload`
- Inactive slot not running → `docker compose up app_web_green` (or blue)
- Health check failing → check app_web_green logs
- Wrong container names in upstream → verify service names in compose file

---

### 8. High Memory Usage / Pi Slow

**Symptoms**: Pi becomes unresponsive, high load, containers restart.

**Diagnose**:
```bash
# Check memory usage
free -h
docker stats

# Check swap usage
swapon -s
free -h

# Check which containers use most memory
docker stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# Check kernel logs for OOM killer
dmesg | grep -i "killed process"
```

**Common fixes**:
- Memory limits too high → adjust `mem_limit` in docker-compose
- Memory leak in app → restart container, investigate app logs
- Add swap: `sudo fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile`
- Limit Docker container memory → add `mem_limit` to compose
- Reduce number of running containers (stop registry if not used)
- Upgrade Pi to more RAM (Pi 4/5 with 4GB+)

---

### 9. Disk Space Full

**Symptoms**: Deployments fail, logs not written, containers crash.

**Diagnose**:
```bash
# Check disk usage
df -h
du -sh /home/applepie/server/data/uploads/
du -sh /home/applepie/server/logs/
docker system df

# Find large files
find /home/applepie/server -type f -size +100M -exec ls -lh {} \;
find /home/applepie/server/logs -type f -mtime +30 -exec ls -lh {} \;

# Check Docker space
docker system prune -a --dry-run
```

**Common fixes**:
- Clean old logs → logrotate or delete old logs
- Clean Docker → `docker system prune -a`
- Clean uploads → archive/delete old uploads
- Expand SD card or use external USB drive
- Move persistent data to external drive

---

### 10. HTTPS/SSL Issues

**Symptoms**: Browser warns about certificate, HTTP doesn't redirect to HTTPS.

**Diagnose**:
```bash
# Check Cloudflare SSL/TLS mode (dashboard)
# Should be "Full (strict)" if nginx has TLS, or "Flexible" if nginx is HTTP

# Check if nginx is serving HTTPS (if configured)
curl -I https://yourname.com

# Check Cloudflared tunnel status
docker logs infrastructure-cloudflared

# Check SSL cert expiry (if self-hosted)
docker exec nginx openssl x509 -in /etc/nginx/ssl/cert.pem -noout -dates
```

**Common fixes**:
- Cloudflare SSL mode mismatched → adjust in Cloudflare dashboard
- Cloudflared credentials expired → recreate tunnel
- Nginx SSL cert expired → renew (Let's Encrypt certbot)
- Mixed content → ensure all assets load via HTTPS

---

## Emergency Procedures

### Bring Up All Services

```bash
cd /home/applepie/server/apps/pi-server
docker compose up -d
cd /home/applepie/server/apps/dynamic/appname
docker compose up -d
# Switch to correct slot
# Reload nginx
```

### Emergency Rollback

```bash
# 1. Identify previous working version
cat /home/applepie/server/releases/dynamic/app/web/current_version

# 2. Switch upstream to previous slot (if not already)
echo "server app_web_blue:3000;" > infrastructure/gateway/nginx/upstreams/app_web.conf
# or use green

# 3. Reload nginx
docker exec gateway_nginx nginx -s reload

# 4. Deploy old version
./scripts/deploy-app.sh v1.0.0  # previous version tag
```

### Access Database Directly (Emergency)

```bash
docker exec -it postgres psql -U postgres
\c app_db
SELECT * FROM users LIMIT 10;
\q
```

### Restore from Backup

See `docs/operations/RECOVERY.md`.

---

## Log Analysis Cheatsheet

**Nginx access log format**: `$remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent"`

**Common status codes**:
- `200` – OK
- `302` – Redirect
- `404` – Not found
- `500` – Internal server error (app crashed)
- `502` – Bad gateway (upstream not responding)
- `503` – Service unavailable (upstream down)
- `504` – Gateway timeout (upstream too slow)

**Useful grep patterns**:
```bash
# 5xx errors in last hour
grep "$(date '+%d/%b/%Y:%H')" /home/applepie/server/logs/nginx/access.log | grep " 50[0-9] "

# Slow requests (>1s)
awk '$NF > 1' /home/applepie/server/logs/nginx/access.log

# Most frequent IPs
awk '{print $1}' /home/applepie/server/logs/nginx/access.log | sort | uniq -c | sort -nr | head
```

---

## Contact & Escalation

If issue cannot be resolved with this runbook:
1. Check `docs/architecture/OVERVIEW.md` for system understanding
2. Check `docs/operations/RECOVERY.md` for disaster scenarios
3. Examine recent changes (`git log -p -5`)
4. Reach out for support: [Contact info to be added]
