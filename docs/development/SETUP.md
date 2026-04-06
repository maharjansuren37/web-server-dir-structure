# Local Development Setup

This guide helps you set up a local development environment that mirrors production.

## Prerequisites

- **Raspberry Pi OS**: 64-bit (Bookworm or later)
- **Docker**: 20.10+
- **Docker Compose**: v2.0+
- **Git**: For version control
- **make** (optional): For convenience commands

## Initial Server Setup (Fresh Pi)

### 1. OS Installation

1. Download Raspberry Pi OS Lite 64-bit
2. Flash to SD card using Raspberry Pi Imager
3. Enable SSH: create empty file `ssh` in boot partition
4. Configure WiFi (optional): create `wpa_supplicant.conf` in boot partition
5. Boot Pi, get IP address from router or `arp -a`

### 2. First Login & Updates

```bash
ssh pi@raspberrypi.local  # Or IP address
# Default password: raspberry (change immediately!)

# Change password
passwd

# Update system
sudo apt update && sudo apt upgrade -y

# Set timezone
sudo timedatectl set-timezone Your/Timezone

# Install required packages
sudo apt install -y docker.io docker-compose-v2 git curl htop logrotate
```

### 3. Docker Configuration

```bash
# Add pi user to docker group (no sudo needed for docker)
sudo usermod -aG docker pi
# Log out and back in for group change to take effect

# Enable Docker to start on boot
sudo systemctl enable docker
sudo systemctl start docker

# Verify
docker --version
docker compose version
```

### 4. Create Directory Structure

```bash
# Clone repository
cd ~
git clone <your-repo-url> web-server
cd web-server

# Create persistent directories (outside Git)
mkdir -p ~/apps/static/portfolio/public
mkdir -p ~/data/uploads/app
mkdir -p ~/logs/nginx
mkdir -p ~/db
mkdir -p ~/releases/dynamic/app/{web,api}
mkdir -p ~/backups

# Set permissions (adjust as needed)
sudo chown -R pi:pi ~/apps ~/data ~/logs ~/db ~/releases ~/backups
```

### 5. Configure Environment

```bash
# Create root .env file
cp infrastructure/registry/.env.example ~/.env
cp infrastructure/gateway/.env.example ~/.env

# Edit with actual values
nano ~/.env
# Add:
# CLOUDFLARE_TUNNEL_TOKEN=your-actual-token
# POSTGRES_USER=postgres
# POSTGRES_PASSWORD=strong-password-here
# REGISTRY_USERNAME=admin
# REGISTRY_PASSWORD=strong-password
# DOMAIN=yourname.com

# Create release env files (for app slots)
# Copy examples
cp apps/dynamic/appname/api/.env.example ~/releases/dynamic/app/api/blue.env
cp apps/dynamic/appname/api/.env.example ~/releases/dynamic/app/api/green.env
cp apps/dynamic/appname/web/.env.example ~/releases/dynamic/app/web/blue.env
cp apps/dynamic/appname/web/.env.example ~/releases/dynamic/app/web/green.env

# Edit with database credentials
nano ~/releases/dynamic/app/api/blue.env
# Add DB_PASSWORD, JWT_SECRET, ADMIN_USER, ADMIN_PASS_HASH

# Copy same to green.env (usually identical)
cp ~/releases/dynamic/app/api/blue.env ~/releases/dynamic/app/api/green.env
cp ~/releases/dynamic/app/web/blue.env ~/releases/dynamic/app/web/green.env
```

### 6. Create Docker Network

```bash
docker network create web
# Verify
docker network ls | grep web
```

---

## Running Locally (Full Stack)

### Start Gateway Services

```bash
cd ~/web-server/infrastructure/gateway
docker compose up -d
# This starts nginx and cloudflared

# Verify
docker compose ps
```

**Note**: Cloudflared will fail without valid `CLOUDFLARE_TUNNEL_TOKEN`. For local development without tunnel, comment out cloudflared service in `docker-compose.yml` and test nginx directly:

```bash
# On Pi or another machine:
curl http://localhost:80/health  # Will fail if cloudflared required
# Instead, access nginx directly on port 80 (cloudflared proxies to it)
```

### Start Dynamic App

```bash
cd ~/web-server/apps/dynamic/appname/web
docker compose up -d

cd ../api
docker compose up -d
```

**Note**: For local testing without actual images, you can use simple nginx container as mock:

```yaml
# Temporary: apps/dynamic/appname/web/docker-compose.yml
services:
  app_web_blue:
    image: nginx:alpine
    ports:
      - "3000:3000"
    volumes:
      - ./mock-index.html:/usr/share/nginx/html/index.html
```

### Start PostgreSQL (in pi-server)

```bash
cd ~/web-server/apps/pi-server
docker compose up -d postgres
# Wait a few seconds for DB to initialize

# Initialize database
docker exec postgres createdb -U postgres app_db
docker exec postgres createuser -U postgres app_user
docker exec postgres psql -U postgres -c "ALTER USER app_user PASSWORD 'yourpassword';"
docker exec postgres psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE app_db TO app_user;"
```

### Test Everything

```bash
# Static site (if deployed)
curl http://localhost  # yourname.com → 200 OK

# API health
curl http://localhost:3001/health

# Web app (if deployed)
curl http://localhost:3000

# Check nginx routing
curl http://localhost/api/health  # Should proxy to :3001
```

---

## Development Workflow

### Making Changes to App Code

1. Develop in separate codebase (or submodule)
2. Build Docker image:
```bash
docker buildx build --platform linux/arm64 -t registry.yourname.com/app-web:dev ./web
```
3. Test locally on Pi:
```bash
docker tag registry.yourname.com/app-web:dev app_web_blue:dev
docker compose -f ~/web-server/apps/dynamic/appname/web/docker-compose.yml up -d
```
4. When ready, tag for production:
```bash
docker tag app-web:dev registry.yourname.com/app-web:v1.2.3
docker push registry.yourname.com/app-web:v1.2.3
```

### Testing Configuration Changes

**Nginx config**:
```bash
# Test syntax
docker exec gateway_nginx nginx -t

# Reload after edit
docker exec gateway_nginx nginx -s reload

# View logs
docker compose -f ~/web-server/infrastructure/gateway/docker-compose.yml logs -f nginx
```

**Docker Compose**:
```bash
# Validate
docker compose -f apps/dynamic/appname/web/docker-compose.yml config
```

---

## Troubleshooting Local Setup

| Issue | Solution |
|-------|----------|
| `permission denied` on docker commands | `newgrp docker` or logout/login |
| `network web not found` | `docker network create web` |
| Port already in use | `sudo lsof -i:80` or change port |
| Cloudflared container exits | Check `CLOUDFLARE_TUNNEL_TOKEN` in `~/.env` |
| Cannot connect to postgres | Verify `app_api` .env has correct `DB_HOST=postgres` |
| Health check keeps failing | Check app logs: `docker logs app_web_blue` |
| Nginx returns 502 | Verify upstream service is running; check `app_web.conf` upstream name |

---

## Useful Commands

```bash
# View all project containers
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Follow logs for all services (one terminal per service)
docker compose -f infrastructure/gateway/docker-compose.yml logs -f
docker compose -f apps/dynamic/appname/web/docker-compose.yml logs -f
docker compose -f apps/dynamic/appname/api/docker-compose.yml logs -f

# Exec into container
docker exec -it app_web_blue sh

# Stop everything
docker compose -f infrastructure/gateway/docker-compose.yml down
docker compose -f apps/dynamic/appname/web/docker-compose.yml down
docker compose -f apps/dynamic/appname/api/docker-compose.yml down
docker compose -f apps/pi-server/docker-compose.yml down

# Clean up (careful!)
docker system prune -a --volumes  # Deletes all unused images, containers, volumes
```

---

## Continuous Integration

See `docs/project/TODO.md` task #13 for CI/CD pipeline setup.

---

## Next Steps

After setup complete:
1. Implement backup strategy (Task #6)
2. Add health checks (Task #5)
3. Create deployment scripts (Task #11)
4. Test full blue-green deployment flow
