#!/bin/bash

# Pi Server Setup Script
# This script prepares a fresh Raspberry Pi for running the web server infrastructure.
# It creates required directories and the Docker network.

set -e  # Exit on error

# Base directory
BASE_DIR="/home/applepie/server"
cd "$BASE_DIR" 2>/dev/null || {
    echo "Creating base directory: $BASE_DIR"
    sudo mkdir -p "$BASE_DIR"
    sudo chown -R "$(whoami)":"$(whoami)" "$BASE_DIR"
}

echo "=== Raspberry Pi Server Setup ==="
echo "Base directory: $BASE_DIR"
echo

# Create required directories
echo "Creating directory structure..."

mkdir -p "$BASE_DIR/apps/static/portfolio/public"
mkdir -p "$BASE_DIR/data/uploads/app/images"
mkdir -p "$BASE_DIR/data/uploads/app/avatars"
mkdir -p "$BASE_DIR/db"
mkdir -p "$BASE_DIR/logs/nginx"
mkdir -p "$BASE_DIR/registry"
mkdir -p "$BASE_DIR/releases/dynamic/app/web"
mkdir -p "$BASE_DIR/releases/dynamic/app/api"
mkdir -p "$BASE_DIR/scripts"

echo "✓ Directories created"
echo

# Create Docker network if it doesn't exist
echo "Checking Docker network..."
if command -v docker &> /dev/null; then
    if docker ps &> /dev/null; then
        if ! docker network ls | grep -q "^web"; then
            echo "Creating Docker network 'web'..."
            docker network create web
            echo "✓ Network 'web' created"
        else
            echo "✓ Network 'web' already exists"
        fi
    else
        echo "⚠ Docker daemon not running. Start Docker first: sudo systemctl start docker"
    fi
else
    echo "⚠ Docker not installed. Install Docker first: sudo apt install docker.io docker-compose-v2"
fi
echo

# Create sample .env file if it doesn't exist
ENV_FILE="$BASE_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "Creating sample .env file at $ENV_FILE"
    cat > "$ENV_FILE" << EOF
# Cloudflare Tunnel credentials
# Get this from: https://dash.cloudflare.com/ -> Zero Trust -> Tunnels
CLOUDFLARE_TUNNEL_TOKEN=your-tunnel-token-here

# PostgreSQL credentials
POSTGRES_USER=postgres
POSTGRES_PASSWORD=change-this-to-secure-password

# Docker Registry credentials
REGISTRY_USERNAME=admin
REGISTRY_PASSWORD=change-this-to-secure-password

# Domain (optional - currently hardcoded in configs)
DOMAIN=yourname.com
EOF
    echo "✓ Sample .env created"
    echo
    echo "IMPORTANT: Edit $ENV_FILE and replace placeholder values with real credentials!"
else
    echo "✓ .env file already exists"
fi
echo

# Create sample release tracking files for dynamic app (for future use)
echo "Setting up release tracking structure (for dynamic app)..."

WEB_BLUE_ENV="$BASE_DIR/releases/dynamic/app/web/blue.env"
WEB_GREEN_ENV="$BASE_DIR/releases/dynamic/app/web/green.env"
WEB_CURRENT_SLOT="$BASE_DIR/releases/dynamic/app/web/current_slot"
WEB_CURRENT_VERSION="$BASE_DIR/releases/dynamic/app/web/current_version"

if [ ! -f "$WEB_BLUE_ENV" ]; then
    echo "BLUE_VERSION=v1.0.0" > "$WEB_BLUE_ENV"
    echo "✓ Created $WEB_BLUE_ENV"
fi

if [ ! -f "$WEB_GREEN_ENV" ]; then
    echo "GREEN_VERSION=v1.0.0" > "$WEB_GREEN_ENV"
    echo "✓ Created $WEB_GREEN_ENV"
fi

if [ ! -f "$WEB_CURRENT_SLOT" ]; then
    echo "blue" > "$WEB_CURRENT_SLOT"
    echo "✓ Created $WEB_CURRENT_SLOT"
fi

if [ ! -f "$WEB_CURRENT_VERSION" ]; then
    echo "v1.0.0" > "$WEB_CURRENT_VERSION"
    echo "✓ Created $WEB_CURRENT_VERSION"
fi

# Same for API
API_BLUE_ENV="$BASE_DIR/releases/dynamic/app/api/blue.env"
API_GREEN_ENV="$BASE_DIR/releases/dynamic/app/api/green.env"
API_CURRENT_SLOT="$BASE_DIR/releases/dynamic/app/api/current_slot"
API_CURRENT_VERSION="$BASE_DIR/releases/dynamic/app/api/current_version"

if [ ! -f "$API_BLUE_ENV" ]; then
    echo "BLUE_VERSION=v1.0.0" > "$API_BLUE_ENV"
    echo "✓ Created $API_BLUE_ENV"
fi

if [ ! -f "$API_GREEN_ENV" ]; then
    echo "GREEN_VERSION=v1.0.0" > "$API_GREEN_ENV"
    echo "✓ Created $API_GREEN_ENV"
fi

if [ ! -f "$API_CURRENT_SLOT" ]; then
    echo "blue" > "$API_CURRENT_SLOT"
    echo "✓ Created $API_CURRENT_SLOT"
fi

if [ ! -f "$API_CURRENT_VERSION" ]; then
    echo "v1.0.0" > "$API_CURRENT_VERSION"
    echo "✓ Created $API_CURRENT_VERSION"
fi

echo

# Create sample .env files for app compose files (to be placed in apps/dynamic/appname/)
echo "Note: You'll also need to create .env files in the app docker-compose directories:"
echo "  - apps/dynamic/appname/web/.env"
echo "  - apps/dynamic/appname/api/.env"
echo
echo "Sample content:"
echo "BLUE_VERSION=\${BLUE_VERSION:-latest}"
echo "GREEN_VERSION=\${GREEN_VERSION:-latest}"
echo

# Logrotate config
echo "Log rotation:"
echo "If you want automatic log rotation, create /etc/logrotate.d/nginx-pi with:"
echo
echo "  $BASE_DIR/logs/nginx/*.log {"
echo "      daily"
echo "      rotate 7"
echo "      compress"
echo "      missingok"
echo "      notifempty"
echo "      sharedscripts"
echo "      postrotate"
echo "          docker exec \$(docker ps --filter \"name=nginx\" --format \"{{.Names}}\" | head -1) nginx -s reopen 2>/dev/null || true"
echo "      endscript"
echo "  }"
echo

echo "=== Setup Complete ==="
echo
echo "Next steps:"
echo "1. Edit $ENV_FILE and add your actual credentials"
echo "2. Build or obtain Docker images for your app (if using dynamic app)"
echo "3. Start the infrastructure:"
echo "   cd $BASE_DIR/../.. (to repository root)"
echo "   docker compose -f infrastructure/docker-compose.yml up -d"
echo "4. Deploy portfolio content to $BASE_DIR/apps/static/portfolio/public/"
echo "5. Test: https://yourname.com"
echo
echo "For dynamic app (future):"
echo "   - Create database initialization scripts"
echo "   - Build and push app images to registry"
echo "   - Create app .env files in apps/dynamic/appname/{web,api}/"
echo "   - Start app containers"
