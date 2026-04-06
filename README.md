## Docker Containers Running on Pi
pi-server/docker-compose.yml
  nginx                              ← serves static + proxies dynamic
  cloudflared                        ← tunnel to Cloudflare
  postgres                           ← app database
  registry                           ← self hosted image registry

dynamic/app/docker-compose.yml
  app_web          :3000
  app_api          :3001

## Docker Network
network: web
  │
  ├── cloudflared                    ← only entry from internet
  ├── nginx                          ← routes all traffic
  ├── postgres                       ← internal only
  ├── registry                       ← internal only
  ├── app_web                        ← internal only
  └── app_api                        ← internal only

## yourname.com
  → serves /home/pi/apps/static/portfolio/site/ directly

blog.yourname.com
  → serves /home/pi/apps/static/blog/site/ directly

app.yourname.com
  /            → app_web:3000
  /api/        → app_api:3001
  /uploads/    → served directly from /home/pi/uploads/app/

registry.yourname.com
  → registry:5000
  
## CI/CD
Static site
  sh scripts/deploy.sh
    rsync files → pi:~/apps/static/portfolio/site/
    nginx serves instantly
    done

Dynamic site
  sh scripts/deploy.sh
    docker buildx build --platform linux/arm64
    docker push registry.yourname.com/app-web:latest
    docker push registry.yourname.com/app-api:latest
    ssh pi → docker compose pull → docker compose up -d
    done

## Request Flow
Static site
  Browser → yourname.com
      ↓
  Cloudflare (SSL)
      ↓
  cloudflared tunnel
      ↓
  nginx → reads files from apps/static/portfolio/site/
      ↓
  response

Dynamic site
  Browser → app.yourname.com
      ↓
  Cloudflare (SSL)
      ↓
  cloudflared tunnel
      ↓
  nginx
      ↓
    /api/    → app_api:3001 → postgres:5432
    /        → app_web:3000
    /uploads → reads files from uploads/app/
      ↓
  response

## Daily Flow
develop         cd portfolio && sh scripts/dev.sh
test locally    http://localhost:3000
commit          git add . && git commit -m "update"
push to github  git push origin main
deploy to pi    sh scripts/deploy.sh
live            yourname.com updated

## Rollback
### on your machine
docker pull ghcr.io/yourname/portfolio-web:v1.0.0

### ssh into pi
cd ~/apps/portfolio
### edit docker-compose.yml image tag to v1.0.0
docker compose up -d

## What Lives where
~/dev/                    write code
github.com                source code backup
registry.yourname.com     built ARM docker images
apps/pi-server/           server config (nginx, cloudflared, postgres)
apps/static/              static site files (served directly by nginx)
apps/dynamic/             compose files only (no source code)
uploads/                  user uploaded files (never wiped)
db/                       database files (never wiped)
registry/                 docker images (rebuilt from source anytime)
logs/                     debug and monitoring
.env/                     secrets (never in git)

## Backup Checklist
Must backup
  /home/pi/db/              database files
  /home/pi/uploads/         uploaded files
  /home/pi/.env/            secrets
  /home/pi/apps/static/     static site files

Not critical
  /home/pi/registry/        rebuild from source anytime
  /home/pi/logs/            not critical
  /home/pi/apps/dynamic/    just compose files, in git anyway
  /home/pi/apps/pi-server/  in git anyway

  
Cloudflare DNS

registry.yourname.com   A record → your home IP