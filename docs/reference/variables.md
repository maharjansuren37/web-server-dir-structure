# Environment Variables Reference

This document lists all environment variables used across the infrastructure.

## Global (Root `.env` on Pi)

Located at `/home/applepie/server/.env/` (not in repository).

| Variable               | Required | Default | Description |
|------------------------|----------|---------|-------------|
| `CLOUDFLARE_TUNNEL_TOKEN` | Yes | - | Cloudflare Tunnel authentication token |
| `POSTGRES_USER`        | Yes | - | PostgreSQL admin user |
| `POSTGRES_PASSWORD`    | Yes | - | PostgreSQL admin password |
| `REGISTRY_USERNAME`    | Yes | - | Docker registry username |
| `REGISTRY_PASSWORD`    | Yes | - | Docker registry password |
| `DOMAIN`               | Yes | - | Primary domain (e.g., `yourname.com`) |
| `WEB_NETWORK_NAME`     | No | `web` | Docker network name |

## Dynamic App Web (`releases/dynamic/app/web/*.env`)

Environment file for web container (blue and green slots).

| Variable               | Required | Default | Description |
|------------------------|----------|---------|-------------|
| `NODE_ENV`             | No | `production` | Node.js environment |
| `PORT`                 | No | `3000` | Application port (internal) |
| `API_URL`              | Yes | - | Backend API URL (e.g., `http://app_api:3001`) |
| `NEXT_PUBLIC_API_URL`  | No | - | Public API URL (e.g., `https://app.yourname.com/api`) |
| `JWT_SECRET`           | Yes | - | Secret for signing JWTs |
| (App-specific vars)    | Varies | - | Additional app config |

**Example**: `releases/dynamic/app/web/blue.env`
```bash
NODE_ENV=production
PORT=3000
API_URL=http://app_api_blue:3001
NEXT_PUBLIC_API_URL=https://app.yourname.com/api
JWT_SECRET=your-secret-key-here
```

## Dynamic App API (`releases/dynamic/app/api/*.env`)

Environment file for API container (blue and green slots).

| Variable               | Required | Default | Description |
|------------------------|----------|---------|-------------|
| `NODE_ENV`             | No | `production` | Node.js environment |
| `PORT`                 | No | `3001` | Application port |
| `DB_HOST`              | Yes | `postgres` | PostgreSQL hostname |
| `DB_PORT`              | Yes | `5432` | PostgreSQL port |
| `DB_NAME`              | Yes | `app_db` | Database name |
| `DB_USER`              | Yes | `app_user` | Database user |
| `DB_PASSWORD`          | Yes | - | Database password |
| `JWT_SECRET`           | Yes | - | Secret for signing JWTs |
| `ADMIN_USER`           | Yes | - | Admin username |
| `ADMIN_PASS_HASH`      | Yes | - | bcrypt hash of admin password |
| `UPLOAD_DIR`           | No | `/uploads` | Upload directory path |
| (App-specific vars)    | Varies | - | Additional app config |

**Example**: `releases/dynamic/app/api/green.env`
```bash
NODE_ENV=production
PORT=3001
DB_HOST=postgres
DB_PORT=5432
DB_NAME=app_db
DB_USER=app_user
DB_PASSWORD=strongpassword
JWT_SECRET=another-secret-key
ADMIN_USER=admin
ADMIN_PASS_HASH=$2b$12$<bcrypt-hash-here>
UPLOAD_DIR=/uploads
```

## Docker Registry (`infrastructure/registry/.env`)

| Variable               | Required | Default | Description |
|------------------------|----------|---------|-------------|
| `REGISTRY_HTTP_ADDR`   | No | `:5000` | Registry listen address |
| `REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY` | No | `/var/lib/registry` | Storage path |
| `REGISTRY_STORAGE_DELETE_ENABLED` | No | `false` | Allow image deletion |
| `REGISTRY_AUTH`        | No | `htpasswd` | Authentication method |
| `REGISTRY_AUTH_HTPASSWD_REALM` | No | `Registry` | Auth realm |
| `REGISTRY_AUTH_HTPASSWD_PATH` | Yes | - | Path to `.htpasswd` file |
| `REGISTRY_HTTP_TLS_CERTIFICATE` | No | - | TLS cert path |
| `REGISTRY_HTTP_TLS_KEY` | No | - | TLS key path |
| `REGISTRY_LOG_ACCESSLOG_DISABLED` | No | `false` | Disable access logs |

---

## Notes

1. **Security**: All `.env` files containing secrets should be:
   - Listed in `.gitignore`
   - Never committed to Git
   - Backed up securely (encrypted backups)

2. **Blue-Green Slots**:
   - Each slot (blue, green) has its own environment file
   - Files are read-only during container runtime
   - Located at `/home/applepie/server/releases/dynamic/app/{web,api}/` on Pi
   - Updated during deployment via `scripts/deploy-app.sh`

3. **Current Active Slot**:
   - Tracked in: `/home/applepie/server/releases/dynamic/app/{web,api}/current_slot`
   - Contains text: `blue` or `green`
   - Used by deployment script and operators

4. **Current Deployed Version**:
   - Tracked in: `/home/applepie/server/releases/dynamic/app/{web,api}/current_version`
   - Contains version tag (e.g., `v1.2.3`)
   - Used for rollback decisions

5. **Nginx Upstreams**:
   - `infrastructure/gateway/nginx/upstreams/app_web.conf` → points to `app_web_{slot}:3000`
   - `infrastructure/gateway/nginx/upstreams/app_api.conf` → points to `app_api_{slot}:3001`
   - Must be manually updated or by deployment script

6. **Secret Management Plan** (future):
   - Consider Docker secrets or HashiCorp Vault
   - Use SOPS for encrypted secrets in Git (if needed)
   - Implement credential rotation policies

---

## Variable Templates

### `.env.example` (root, for local development)
```bash
# Cloudflare Tunnel
CLOUDFLARE_TUNNEL_TOKEN=

# PostgreSQL
POSTGRES_USER=postgres
POSTGRES_PASSWORD=

# Docker Registry
REGISTRY_USERNAME=admin
REGISTRY_PASSWORD=

# Domain
DOMAIN=yourname.com
```

### `web/.env.example`
```bash
NODE_ENV=production
PORT=3000
API_URL=http://app_api:3001
NEXT_PUBLIC_API_URL=https://app.yourname.com/api
JWT_SECRET=
```

### `api/.env.example`
```bash
NODE_ENV=production
PORT=3001
DB_HOST=postgres
DB_PORT=5432
DB_NAME=app_db
DB_USER=app_user
DB_PASSWORD=
JWT_SECRET=
ADMIN_USER=admin
ADMIN_PASS_HASH=
UPLOAD_DIR=/uploads
```

---

## Validation

Test environment file syntax:
```bash
# Check for required variables
grep -E '^[A-Z_]+=' .env | grep -v '^#' | wc -l  # Should match expected count

# Validate no placeholder values remain
grep -E '(your-tunnel-id|yourname\.com|CHANGE_ME|xxx)' .env && echo "ERROR: Placeholder values detected"
```

---

**Important**: Never commit actual `.env` files with secrets to the repository. Use `.env.example` for templates. Store production secrets securely on the Pi at `/home/applepie/server/.env/` and in release files.
