# Disaster Recovery Procedures

## Recovery Time Objective (RTO)
- **Tier 1** (full outage): 4 hours
- **Tier 2** (partial outage): 1 hour
- **Tier 3** (data loss): 24 hours

## Recovery Point Objective (RPO)
- **Database**: Daily backup (potential loss of up to 24 hours)
- **Uploads**: Daily backup (potential loss of up to 24 hours)
- **Static sites**: Git repository (zero loss)
- **Configurations**: Git repository (zero loss)

## Scenario 1: Complete Server Failure (Raspberry Pi Dead)

### Symptoms
- Pi unresponsive (no ping, no SSH)
- SD card corrupted
- Hardware failure

### Recovery Steps

1. **Replace hardware**:
   - Acquire new Raspberry Pi (same architecture: ARM64)
   - Install Raspberry Pi OS (64-bit)
   - Configure SSH, basic networking

2. **Clone repository**:
```bash
git clone <your-repo-url> /home/applepie/server/web-server
cd /home/applepie/server/web-server
```

3. **Run setup script**:
```bash
# (To be created in Task 19)
chmod +x scripts/setup-pi.sh
sudo ./scripts/setup-pi.sh
```

4. **Restore secrets**:
   - Retrieve `.env` from backup or password manager
   - Place in `/home/applepie/server/.env/`
   - Verify contents match pre-failure values

5. **Restore database**:
```bash
# From latest backup
tar -xzf /path/to/backup/db-YYYY-MM-DD.tar.gz -C /home/applepie/server/db/
# Or use restore script: scripts/restore.sh --db-only
docker compose -f /home/applepie/server/apps/pi-server/docker-compose.yml up -d postgres
# Verify database is running
docker exec postgres psql -U postgres -l
```

6. **Restore uploads**:
```bash
tar -xzf /path/to/backup/uploads-YYYY-MM-DD.tar.gz -C /home/applepie/server/data/
```

7. **Deploy static sites**:
```bash
cd portfolio
sh scripts/deploy.sh  # From static site repo
```

8. **Deploy dynamic app**:
   - Push images to registry (or pull from remote if registry on separate server)
   - If registry was on same Pi, rebuild and push images from CI
   - Run: `sh scripts/deploy-app.sh <version-tag>`
   - Or follow manual deployment procedure (see below)

9. **Verify**:
   - All sites accessible
   - Uploads working
   - API functional
   - Database queries succeed

---

## Scenario 2: Database Corruption / Data Loss

### Symptoms
- Application errors on database operations
- `psql` shows missing tables or corrupted data
- Sudden database size spike

### Recovery Steps

1. **Stop API containers** (to prevent further writes):
```bash
docker compose -f /home/applepie/server/apps/dynamic/appname/docker-compose.yml stop app_web_blue app_web_green app_api_blue app_api_green
```

2. **Verify backup integrity**:
```bash
ls -la /home/applepie/server/backups/db/
# Should see: db-YYYY-MM-DD.sql.gz or db-YYYY-MM-DD.tar.gz
```

3. **Restore database**:
```bash
# Drop existing database
docker exec postgres dropdb -U postgres app_db

# Create fresh database
docker exec postgres createdb -U postgres app_db

# Restore from backup
# Option A: SQL file
zcat /home/applepie/server/backups/db-2026-04-05.sql.gz | docker exec -i postgres psql -U postgres app_db

# Option B: Custom format (pg_dump -Fc)
# Use pg_restore inside container
docker cp /home/applepie/server/backups/db-2026-04-05.dump postgres:/tmp/
docker exec postgres pg_restore -U postgres -d app_db /tmp/db-2026-04-05.dump
```

4. **Verify restoration**:
```bash
docker exec postgres psql -U postgres -d app_db -c "\dt"
# Should list tables
```

5. **Restart API containers**:
```bash
docker compose -f /home/applepie/server/apps/dynamic/appname/docker-compose.yml start app_web_blue app_web_green app_api_blue app_api_green
```

6. **Test application**:
```bash
curl https://app.yourname.com/api/health
# Should return 200 OK
```

---

## Scenario 3: Uploads Lost / Directory Corrupted

### Symptoms
- Uploaded images/files missing
- 404 errors on upload URLs
- Uploads API returns errors

### Recovery Steps

1. **Stop Nginx** (to prevent further uploads):
```bash
docker compose -f /home/applepie/server/apps/pi-server/docker-compose.yml stop nginx
```

2. **Stop API containers**:
```bash
docker compose -f /home/applepie/server/apps/dynamic/appname/docker-compose.yml stop app_api_blue app_api_green
```

3. **Restore uploads from backup**:
```bash
# Remove corrupted uploads
rm -rf /home/applepie/server/data/uploads/app/*

# Restore from backup
tar -xzf /home/applepie/server/backups/uploads-YYYY-MM-DD.tar.gz -C /home/applepie/server/data/uploads/
# Should extract to: /home/applepie/server/data/uploads/app/
```

4. **Verify permissions**:
```bash
chown -R 1000:1000 /home/applepie/server/data/uploads/app  # Adjust UID/GID to match container
chmod -R 755 /home/applepie/server/data/uploads/app
```

5. **Restart services**:
```bash
docker compose -f /home/applepie/server/apps/dynamic/appname/docker-compose.yml start
docker compose -f /home/applepie/server/apps/pi-server/docker-compose.yml start nginx
```

6. **Test uploads**:
```bash
curl -I https://app.yourname.com/uploads/some-known-file.jpg
# Should return 200 OK
```

---

## Scenario 4: Configuration Accidentally Deleted / Corrupted

### Symptoms
- Containers fail to start
- Nginx errors on reload
- Unknown behavior

### Recovery Steps

1. **Restore from Git**:
```bash
cd /home/applepie/server/web-server
git status  # See what changed
git checkout -- infrastructure/ apps/pi-server/ scripts/
```

2. **Recreate missing directories** (if structure corrupted):
```bash
mkdir -p /home/applepie/server/apps/static/portfolio/public
mkdir -p /home/applepie/server/data/uploads/app
mkdir -p /home/applepie/server/logs/nginx
mkdir -p /home/applepie/server/db
mkdir -p /home/applepie/server/releases/dynamic/app/{web,api}
```

3. **Restore environment files**:
   - Retrieve from backup or password manager
   - Place in `/home/applepie/server/.env/` and `/home/applepie/server/releases/dynamic/app/{web,api}/`

4. **Recreate Docker network** (if deleted):
```bash
docker network create web
```

5. **Restart services**:
```bash
docker compose -f /home/applepie/server/apps/pi-server/docker-compose.yml up -d
docker compose -f /home/applepie/server/apps/dynamic/appname/docker-compose.yml up -d
```

6. **Verify configs**:
```bash
docker exec gateway_nginx nginx -t
docker compose -f /home/applepie/server/apps/pi-server/docker-compose.yml config
docker compose -f /home/applepie/server/apps/dynamic/appname/docker-compose.yml config
```

---

## Scenario 5: Registry Failure (Images Unavailable)

### Symptoms
- `docker pull` fails: `repository does not exist or may require 'docker login'`
- Deployment fails: `manifest for ... not found`
- Registry container crashes

### Recovery Steps

**Option A: Registry on same Pi (recover locally)**
1. Check registry container:
```bash
docker ps | grep registry
docker logs registry
```

2. If corrupted, rebuild:
```bash
docker-compose -f infrastructure/registry/docker-compose.yml down
docker-compose -f infrastructure/registry/docker-compose.yml up -d
# Registry storage should be persisted at /home/applepie/server/registry/
```

3. Verify images still exist:
```bash
ls -la /home/applepie/server/registry/docker/registry/v2/repositories/
```

**Option B: Registry lost; need to rebuild images** (worst case)
1. Pull code from Git
2. Rebuild Docker images locally or in CI:
```bash
docker buildx build --platform linux/arm64 -t registry.yourname.com/app-web:latest ./path/to/web
docker buildx build --platform linux/arm64 -t registry.yourname.com/app-api:latest ./path/to/api
```

3. Push to registry:
```bash
docker push registry.yourname.com/app-web:latest
docker push registry.yourname.com/app-api:latest
```

4. Redeploy using `scripts/deploy-app.sh`

---

## Scenario 6: Secrets Leaked / Security Incident

### Symptoms
- Accidental commit of `.env` to Git
- Unauthorized access detected
- Compromised credentials

### Immediate Actions

1. **Rotate all secrets**:
   - Generate new database password
   - Generate new JWT secret
   - Generate new admin password/hash
   - Generate new `CLOUDFLARE_TUNNEL_TOKEN` (create new tunnel)

2. **Update secrets on Pi**:
   - Update `/home/applepie/server/.env/`
   - Update `/home/applepie/server/releases/dynamic/app/{web,api}/*.env`
   - Update Cloudflare tunnel credentials
   - Update registry credentials

3. **Restart all services**:
```bash
docker compose -f /home/applepie/server/apps/pi-server/docker-compose.yml restart
docker compose -f /home/applepie/server/apps/dynamic/appname/docker-compose.yml restart
```

4. **Revoke old credentials**:
   - Invalidate old database user (if needed)
   - Revoke old JWT tokens in app logic (depends on app implementation)
   - Delete old Cloudflare tunnel

5. **Audit Git history** (if secrets were committed):
```bash
git log --oneline --grep="password"  # Find commits
# Use BFG or filter-branch to remove from history
# Force push (coordinate with team)
```

---

## Preventive Maintenance

### Daily
- Check backup logs for errors
- Monitor disk space: `df -h`
- Review error logs

### Weekly
- Test backup restore in isolated environment
- Review security logs (fail2ban if installed)
- Check for security updates: `apt list --upgradable`
- Verify all services are running

### Monthly
- Rotate logs manually if logrotate not working
- Test failover (deploy to inactive slot, verify switch)
- Review resource usage trends
- Update documentation

---

## Backup Restoration Testing

**DO NOT WAIT FOR DISASTER TO TEST BACKUPS**

Monthly drill:
1. Deploy fresh Pi in test environment
2. Restore from latest backup
3. Verify all services functional
4. Document gaps and improvement areas

---

## Emergency Contacts

| Role           | Contact | Notes                            |
|----------------|---------|----------------------------------|
| System Admin   |         | Primary responder               |
| DevOps         |         | CI/CD and registry              |
| On-call        |         | After hours                     |

** escalation path**: Triage → System Admin → DevOps → Emergency access (cloud provider, registrar)
