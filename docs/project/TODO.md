# Project Todo List

**Last Updated**: 2026-04-06
**Status**: Static Sites First - Dynamic App Deferred

## Legend
- [ ] Not started
- [x] Completed
- [!] In progress / Blocked
- [-] Cancelled / Deferred

---

## PHASE 1: Static Sites (IMMEDIATE FOCUS)

### 1. Prepare Pi Directory Structure
- [ ] SSH to Pi and create directory structure:
  ```bash
  mkdir -p /home/applepie/server/apps/static/portfolio/public
  mkdir -p /home/applepie/server/logs/nginx
  mkdir -p /home/applepie/server/data/uploads  # For future dynamic app
  mkdir -p /home/applepie/server/db  # For future dynamic app
  mkdir -p /home/applepie/server/registry  # Already in docker-compose
  ```
- [ ] Create Docker network: `docker network create web` (if not exists)
- [ ] Verify permissions (pi user can write to these dirs)
- **Impact**: Pi ready to run infrastructure stack
- **Priority**: CRITICAL

### 2. Create Pi Setup Script (Automation) ✅
- [x] Created `scripts/setup-pi.sh`:
  - Creates all required directories (idempotent)
  - Creates Docker network `web` if not exists
  - Creates logrotate config for nginx logs
  - Prints instructions for next steps
- [x] Made executable: `chmod +x scripts/setup-pi.sh`
- [ ] Test on fresh Pi (or test environment)
- **Impact**: One-command Pi provisioning
- **Dependencies**: Task 1
- **Priority**: HIGH

### 3. Configure Cloudflare Tunnel
- [ ] Obtain `CLOUDFLARE_TUNNEL_TOKEN` from Cloudflare dashboard
- [ ] On Pi, create `/home/applepie/server/.env`:
  ```bash
  CLOUDFLARE_TUNNEL_TOKEN=your-token-here
  ```
- [ ] Verify `infrastructure/cloudflared/config.yml` has correct hostnames:
  - yourname.com → nginx
  - www.yourname.com → nginx
  - app.yourname.com → nginx (for future)
  - registry.yourname.com → nginx
  (blog removed from scope)
- **Impact**: Infrastructure can start with tunnel credentials
- **Dependencies**: Task 1
- **Priority**: CRITICAL

### 4. Start Infrastructure Stack
- [ ] From repository root on Pi: `docker compose -f infrastructure/docker-compose.yml up -d`
- [ ] Verify all services healthy: `docker compose -f infrastructure/docker-compose.yml ps`
- [ ] Check logs if any fail: `docker compose -f infrastructure/docker-compose.yml logs`
- [ ] Verify nginx is running: `docker compose -f infrastructure/docker-compose.yml logs nginx`
- [ ] Test nginx internally: `curl http://localhost` should return 404 (no site yet)
- **Impact**: Gateway, database, and registry running
- **Dependencies**: Tasks 1-3
- **Priority**: CRITICAL

### 5. Create Portfolio Content ✅
- [x] Created minimal HTML/CSS/JS in `apps/static/portfolio/public/` (index, about, projects, contact)
- [x] Added responsive styling and navigation
- **Impact**: Portfolio has placeholder content ready to deploy
- **Dependencies**: None
- **Priority**: COMPLETED

### 6. Deploy Portfolio to Pi
- [ ] If portfolio is in separate repo: `rsync -av dist/ pi@your-pi:/home/applepie/server/apps/static/portfolio/public/`
- [ ] If portfolio is in this repo: copy `apps/static/portfolio/public/` to Pi path above
- [ ] Verify files exist on Pi: `ls -la /home/applepie/server/apps/static/portfolio/public/`
- [ ] Check nginx config: `infrastructure/nginx/conf.d/portfolio.conf` should point to `/sites/portfolio` (mounted from host)
- **Impact**: Static site files in place
- **Dependencies**: Task 4 (nginx running), Task 5 (content ready)
- **Priority**: HIGH

### 7. Blog: Removed from Scope ✅
- [x] **Decision**: REMOVE blog (not implementing at this time)
- [x] Cleaned cloudflared config.yml (removed blog.yourname.com)
- [x] Removed blog references from README.md, OVERVIEW.md, ports.md
- [x] Removed blog path from .gitignore
- [x] Blog is out of scope for this phase
- **Impact**: Configuration clean, no dangling references
- **Dependencies**: None
- **Priority**: COMPLETED

### 8. Verify Static Sites Working
- [ ] Test portfolio: `curl https://yourname.com` should return HTML
- [ ] Test www: `curl https://www.yourname.com` should return HTML
- [ ] Check nginx logs: `docker compose -f infrastructure/docker-compose.yml logs nginx` for errors
- [ ] Check nginx access log: `tail -f /home/applepie/server/logs/nginx/access.log`
- [ ] Test from browser externally (via Cloudflare tunnel)
- **Impact**: Confirm portfolio site is live
- **Dependencies**: Tasks 4-6, 7 (blog cleanup)
- **Priority**: CRITICAL

### 9. Static Site Deployment Automation
- [ ] Create `scripts/deploy-static.sh`:
  ```bash
  ./scripts/deploy-static.sh portfolio /path/to/build/output
  # Does: rsync to Pi, optionally update version file, clear Cloudflare cache
  ```
- [ ] Add support for multiple sites (portfolio, blog)
- [ ] Test deployment with dry-run mode
- [ ] Document usage in README
- **Impact**: Easy static site updates
- **Dependencies**: Task 8 (manual deploy works)
- **Priority**: MEDIUM

---

## PHASE 2: Dynamic App (DEFERRED - Future Work)

**NOTE**: All dynamic app tasks are postponed until static sites are working. Below is the deferred task list (DO NOT WORK ON YET).

### D1. Database Initialization (Deferred)
- [ ] Create SQL initialization scripts in `infrastructure/postgres/init/`:
  - [ ] `01-schema.sql` - Create application tables
  - [ ] `02-seed.sql` - Optional initial data
- [ ] Create application user with least-privilege permissions
- **Impact**: Database ready for app
- **Priority**: LOW (deferred)

### D2. App Docker Images
- [ ] Build web app image: `registry.yourname.com/app-web:latest` (from separate app repo)
- [ ] Build api app image: `registry.yourname.com/app-api:latest`
- [ ] Push both images to registry
- **Impact**: Images available for deployment
- **Priority**: LOW (deferred)

### D3. Release Tracking Files on Pi
- [ ] Create `/home/applepie/server/releases/dynamic/app/{web,api}/` directories
- [ ] Create blue.env and green.env files with version placeholders
- [ ] Create `current_slot` and `current_version` files
- [ ] Create `apps/dynamic/appname/{web,api}/.env` on Pi with BLUE_VERSION/GREEN_VERSION
- **Impact**: Blue-green deployment ready
- **Priority**: LOW (deferred)

### D4. Deploy Dynamic Stack
- [ ] Start app web and api containers
- [ ] Verify health endpoints responding
- [ ] Test full stack: static → nginx → app → database
- **Impact**: Dynamic app running
- **Dependencies**: D1-D3, static sites working
- **Priority**: LOW (deferred)

### D5. Blue-Green Deployment Automation
- [ ] Create `scripts/deploy-app-web.sh` and `deploy-app-api.sh`
- [ ] Implement slot switching logic
- [ ] Test zero-downtime deployment
- **Impact**: Automated deployments
- **Dependencies**: D4
- **Priority**: LOW (deferred)

---

## PHASE 3: Security & Hardening (After Both Phases)

### 10. Nginx Security Headers (Both Static & Dynamic)
- [ ] Add to `infrastructure/nginx/nginx.conf`:
  - `add_header X-Content-Type-Options "nosniff" always;`
  - `add_header X-Frame-Options "DENY" always;`
  - `add_header Referrer-Policy "strict-origin-when-cross-origin" always;`
  - `server_tokens off;`
- [ ] Test: `docker compose -f infrastructure/docker-compose.yml exec nginx nginx -t`
- [ ] Reload nginx
- **Impact**: Improved security
- **Dependencies**: Task 8 (static sites working)
- **Priority**: HIGH

### 11. Registry Authentication
- [ ] Verify `REGISTRY_AUTH=htpasswd` in `infrastructure/docker-compose.yml`
- [ ] Create htpasswd credentials: `docker run --rm --entrypoint htpasswd httpd:2 -bB /auth/htpasswd registryuser PASSWORD`
- [ ] Mount is already configured; just need to create the file on Pi at `/home/applepie/server/registry/auth/htpasswd`
- [ ] Test: `docker login registry.yourname.com`
- **Impact**: Registry secure
- **Dependencies**: Task 4 (registry running)
- **Priority**: HIGH

### 12. Backup Strategy
- [ ] Create `scripts/backup.sh`:
  - PostgreSQL dump (when DB exists)
  - Uploads directory tar (when used)
  - Static sites tar
  - Secrets backup (.env)
  - Retention policy
- [ ] Create `scripts/restore.sh`
- [ ] Add cron job on Pi: `0 2 * * * /home/applepie/server/scripts/backup.sh`
- [ ] Test backup and restore
- **Impact**: Data protection
- **Dependencies**: Task 8 (static sites), D1 (database when added)
- **Priority**: HIGH

### 13. Log Rotation
- [ ] Create `/etc/logrotate.d/nginx-pi` on Pi:
  ```
  /home/applepie/server/logs/nginx/*.log {
      daily
      rotate 7
      compress
      missingok
      notifempty
      sharedscripts
      postrotate
          docker exec infrastructure-nginx-1 nginx -s reopen 2>/dev/null || true
      endscript
  }
  ```
- [ ] Test: `logrotate -f /etc/logrotate.d/nginx-pi`
- **Impact**: Prevent disk full
- **Dependencies**: Task 4
- **Priority**: HIGH

---

## Phase 4: Documentation & Quality

### 14. Pre-commit Hooks (Local Dev)
- [ ] Set up `.pre-commit-config.yaml` with yamllint, trailing-whitespace, secrets scanner
- [ ] Install pre-commit: `pre-commit install`
- **Impact**: Catch errors before commit
- **Dependencies**: None
- **Priority**: MEDIUM

### 15. Runbook & Troubleshooting (Update for Static-First)
- [ ] Update `docs/operations/RUNBOOK.md` to focus on static site issues first
- [ ] Add section: "Static site returns 404" (check file paths, nginx root)
- [ ] Add section: "Static site not deploying" (check rsync, permissions)
- [ ] Keep dynamic app sections but mark as future
- **Impact**: Better troubleshooting
- **Dependencies**: Task 8
- **Priority**: MEDIUM

### 16. Deployment Documentation
- [ ] Update `docs/operations/DEPLOYMENT.md` with:
  - Static site deployment procedure (current, working)
  - Note that dynamic app deployment is not yet implemented
  - Manual steps for now
- **Impact**: Clear deployment docs
- **Dependencies**: Task 8
- **Priority**: MEDIUM

### 17. Update README.md
- [ ] Reflect static-first approach
- [ ] Remove or strike-through dynamic app sections until implemented
- [ ] Add current status: "Static sites (portfolio) are fully functional"
- **Impact**: Accurate project documentation
- **Dependencies**: Task 8
- **Priority**: MEDIUM

---

## Missing Components & Decisions Needed

### 18. Blog: Implement or Remove?
**DECISION NEEDED ASAP** - blocks Task 7
- Current: blog.yourname.com in cloudflared config but no server block or content
- Option A: Implement - create `infrastructure/nginx/conf.d/blog.conf`, add content
- Option B: Remove - delete from cloudflared config, docs, structure.md
- **Priority**: CRITICAL (decide now)

### 19. Portfolio Content Source
**DECISION NEEDED** - affects Task 5
- Separate repository? (recommended)
- Submodule?
- In this repo?
- If separate: update README with link and deployment instructions
- **Priority**: HIGH

### 20. Domain Parameterization
**OPTIONAL** - can do later
- Currently hardcoded: `yourname.com`, `app.yourname.com`, etc.
- For single homelab, hardcoded is fine
- If parameterizing later, implement template system
- **Priority**: LOW

---

## Quick-Start (Static Sites Only)

**To get portfolio live**:

1. [ ] Run `scripts/setup-pi.sh` on Pi (creates dirs, network)
2. [ ] Create `/home/applepie/server/.env` with `CLOUDFLARE_TUNNEL_TOKEN=xxx`
3. [ ] `docker compose -f infrastructure/docker-compose.yml up -d` on Pi
4. [ ] Deploy portfolio content to `/home/applepie/server/apps/static/portfolio/public/`
5. [ ] Test: `curl https://yourname.com` → should see portfolio
6. [ ] Done! Dynamic app deferred to later phase.

---

**Strategy**: Get static portfolio serving end-to-end first. Then add blog (if keeping). Then tackle dynamic app as separate phase.

**Current blockers**: Cloudflare tunnel token, decision on blog, actual portfolio content.
