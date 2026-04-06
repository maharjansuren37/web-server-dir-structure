# Network Ports & Services Reference

## Overview

| Service | Container Port | Host Port | Protocol | External Access |
|---------|----------------|-----------|----------|-----------------|
| Nginx (gateway) | 80 | 80 | HTTP | Via Cloudflare Tunnel only |
| Cloudflared tunnel | N/A (outbound) | N/A | HTTPS | Tunnel initiation to Cloudflare |
| Docker Registry | 5000 | 5000 | HTTP | Via Cloudflare Tunnel |
| App Web (blue/green) | 3000 | (internal only) | HTTP | Proxied via nginx |
| App API (blue/green) | 3001 | (internal only) | HTTP | Proxied via nginx |
| PostgreSQL | 5432 | (internal only) | TCP | Internal only |
| cAdvisor (monitoring) | 8080 | 8080 (optional) | HTTP | Internal (or via nginx) |
| Prometheus (monitoring) | 9090 | 9090 (optional) | HTTP | Internal (or via nginx) |
| Grafana (monitoring) | 3000 | 3001 (conflict) | HTTP | Internal (or via nginx) |

**Key**: All application ports (3000, 3001, 5432) are **not exposed** to host network. They only exist on the internal `web` Docker bridge network. Nginx is the only externally accessible service (port 80), but that's not directly exposed either – it's behind Cloudflare Tunnel.

---

## Service Access Methods

### External (Internet) Access

All external traffic goes through Cloudflare Tunnel:

```
User → https://yourname.com → Cloudflare → cloudflared tunnel → nginx:80
```

**No ports open on firewall**. Cloudflare connects outbound to your Pi.

**URL to Service Mapping**:

| URL | Route | Backend |
|-----|-------|---------|
| `https://yourname.com` | `/` | nginx `/sites/portfolio/` |
| `https://app.yourname.com` | `/` | nginx → `app_web:3000` |
| `https://app.yourname.com/api/` | `/api/*` | nginx → `app_api:3001` |
| `https://app.yourname.com/uploads/` | `/uploads/*` | nginx → `/home/applepie/server/data/uploads/app/` |
| `https://registry.yourname.com` | `/` | nginx → `registry:5000` |

### Internal (Pi) Access

For debugging, you can access services directly on the Pi:

```bash
# Nginx (port 80)
curl http://localhost:80
curl http://localhost/health  # if health endpoint configured

# App Web (on active slot)
curl http://localhost:3000  # If nginx not running, direct access
# Or via Docker network:
docker exec gateway_nginx curl http://app_web:3000

# App API
curl http://localhost:3001/health

# PostgreSQL
sudo -u postgres psql

# Docker Registry
curl http://localhost:5000/v2/_catalog

# List Docker networks (see web network)
docker network ls
docker network inspect web
```

---

## Nginx Configuration (infrastructure/gateway/nginx/)

### Ports

- ** listens **: 80 (HTTP)
- ** does not listen on  **: 443 – SSL is handled by Cloudflared upstream

### Server Blocks

| File | server_name | root | proxied_to |
|------|-------------|------|------------|
| `portfolio.conf` | `yourname.com`, `www.yourname.com` | `/sites/portfolio` | direct file serve |
| `app.conf` | `app.yourname.com` | N/A | `http://app_web:3000` (/) and `http://app_api:3001` (/api/) |
| `registry.conf` | `registry.yourname.com` | N/A | `http://registry:5000` |

### Upstreams (Dynamic Routing)

`upstreams/app_web.conf`:
```nginx
upstream app_web {
    server app_web_blue:3000;  # or app_web_green
}
```

`upstreams/app_api.conf`:
```nginx
upstream app_api {
    server app_api_blue:3001;  # or app_api_green
}
```

---

## Docker Network: `web`

All containers must be connected to the `web` bridge network to communicate:

```bash
# View network
docker network inspect web

# Should list:
# - infrastructure-gateway-nginx-1
# - infrastructure-gateway-cloudflared-1
# - app_web_blue
# - app_web_green
# - app_api_blue
# - app_api_green
# - registry
# - postgres
```

If container not on network, add it:
```bash
docker network connect web <container_name>
```

---

## Firewall Configuration (if needed)

By default, **no firewall rules** because Cloudflare Tunnel uses outbound only. But if you want additional security:

```bash
# Check UFW status
sudo ufw status

# Allow only SSH (22) and block everything else (optional – tunnel still works because outbound)
sudo ufw allow 22/tcp
sudo ufw --force enable

# Note: Cloudflared initiates outbound connections, so inbound blocking doesn't affect tunnel.
```

---

## Port Conflicts

### Symptom
```
Error starting userland proxy: listen tcp 0.0.0.0:80: bind: address already in use
```

### Cause
Another service already bound to port 80 (often Apache2, lighttpd, or another nginx).

### Fix
```bash
# Find what's using port 80
sudo lsof -i :80
sudo netstat -tulpn | grep :80

# Stop the service
sudo systemctl stop apache2
# Or: sudo systemctl stop nginx (if duplicate)

# Disable on boot
sudo systemctl disable apache2
```

---

## Changing Ports

If you need to change exposed ports:

1. **Nginx external port** (not recommended, nginx must be 80 for Cloudflare):
   - Change in `infrastructure/gateway/docker-compose.yml`:
     ```yaml
     services:
       nginx:
         ports:
           - "8080:80"  # Host 8080 → Container 80
     ```
   - Update Cloudflared tunnel config to route to `http://nginx:8080` instead of `:80`
   - Update firewall rules

2. **Registry port**:
   - Change in `infrastructure/registry/docker-compose.yml`:
     ```yaml
     services:
       registry:
         ports:
           - "5001:5000"  # Host 5001 → Container 5000
     ```
   - Update `infrastructure/gateway/nginx/conf.d/registry.conf`:
     ```nginx
     location / {
         proxy_pass http://registry:5001;  # ← change
     }
     ```
   - Update registry client URLs: `docker login registry.yourname.com:5001`

3. **Internal app ports** (3000, 3001):
   - Change in `apps/dynamic/appname/{web,api}/docker-compose.yml`:
     ```yaml
     services:
       app_web_blue:
         ports: []  # Remove ports section entirely (services internal-only)
     ```
   - Update upstream configs if changed
   - Usually **do not expose** app ports externally; keep internal only

---

## Monitoring Ports

Optional monitoring services (not yet implemented):

| Service | Port | Path | Purpose |
|---------|------|------|---------|
| cAdvisor | 8080 | `/` | Container resource metrics |
| Prometheus | 9090 | `/` | Metrics collection |
| Grafana | 3001 (conflict) | `/` | Metrics visualization |
| Portainer | 9000 | `/` | Docker UI (if needed) |

These should be added to `infrastructure/docker-compose.yml` on the `web` network.

---

## SSL/TLS Notes

### Cloudflare Tunnel (External)

- Cloudflare provides SSL termination
- Pi never sees HTTPS traffic (only HTTP from cloudflared)
- Nginx receives HTTP on port 80
- No certificates needed on Pi for external SSL

### Internal TLS (Optional but Recommended)

If you want to encrypt traffic between nginx and app containers:

1. Generate self-signed certs:
```bash
mkdir -p /home/applepie/server/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /home/applepie/server/ssl/nginx.key \
  -out /home/applepie/server/ssl/nginx.crt \
  -subj "/CN=nginx"
```

2. Mount in nginx container:
```yaml
services:
  nginx:
    volumes:
      - /home/applepie/server/ssl/nginx.crt:/etc/nginx/ssl/nginx.crt:ro
      - /home/applepie/server/ssl/nginx.key:/etc/nginx/ssl/nginx.key:ro
```

3. Update nginx config to listen on 443:
```nginx
server {
    listen 443 ssl;
    ssl_certificate /etc/nginx/ssl/nginx.crt;
    ssl_certificate_key /etc/nginx/ssl/nginx.key;
    # ... rest of config
}
```

4. Update proxy_pass to use `https://app_web:3000` and add:
```nginx
proxy_ssl_verify off;  # For self-signed, or provide CA
```

---

## Port Summary by Environment

| Environment | External Access | Nginx Port | Cloudflared | App Ports | Notes |
|-------------|-----------------|------------|-------------|-----------|-------|
| **Local dev** | Direct | 80 (or 8080) | Disabled | 3000, 3001 | Direct curl to localhost |
| **Production** | Cloudflare Tunnel only | 80 | Enabled | internal only | No host ports exposed; use tunnel URLs |

---

**See Also**: `docs/operations/RUNBOOK.md` for port-related troubleshooting.
