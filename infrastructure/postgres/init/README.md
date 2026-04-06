# PostgreSQL Initialization Scripts

Place SQL scripts in this directory to initialize the database.

Naming convention: Use sequential numbering to control execution order:
- `01-schema.sql` - Create tables, indexes, constraints
- `02-seed.sql` - Insert initial data (optional)
- `03-extensions.sql` - Enable extensions (if needed)

These scripts will be executed automatically by the official PostgreSQL image on first startup (when `/docker-entrypoint-initdb.d/` is mounted).

## Mounting in docker-compose.yml

In `apps/pi-server/docker-compose.yml`, the postgres service should have:

```yaml
volumes:
  - ./postgres/init:/docker-entrypoint-initdb.d
  - /home/applepie/server/db:/var/lib/postgresql/data
```

The init scripts run only when the data directory is empty (first initialization). They do not run on subsequent starts.

## Database Configuration

The postgres service uses these environment variables (from `.env`):
- `POSTGRES_USER` - Administrative user (default: postgres)
- `POSTGRES_PASSWORD` - Password for POSTGRES_USER (required)
- `POSTGRES_DB` - Default database to create (optional, but we use `app_db`)

## Example: Create Application User

If your application uses a separate database user, create it in `01-schema.sql`:

```sql
-- 01-schema.sql
CREATE USER app_user WITH PASSWORD 'your-secure-password';
GRANT ALL PRIVILEGES ON DATABASE app_db TO app_user;
```

Then set your app's `DB_USER=app_user` and `DB_PASSWORD=your-secure-password` in the release env files.
