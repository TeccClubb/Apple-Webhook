#!/bin/bash
# Apple Subscription Service Deployment Script
# For Ubuntu/Debian-based systems
# Usage: bash deploy.sh

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - EDIT THESE VALUES
REPO_URL="https://github.com/TeccClubb/Apple-Webhook.git"
DEPLOY_PATH="/opt/apple-subscription-service"
DOMAIN="apple.safeprovpn.com"
APP_USER="appuser"  # User to run the service
APP_PORT=8000

# Apple configuration - THESE COME FROM YOUR LOCAL .env
APPLE_ISSUER_ID="c687c38b-7ca7-4e84-9cf9-782e7186d565"
APPLE_PRIVATE_KEY_ID="2G3MFFZW92"
APPLE_BUNDLE_ID="com.safeprovpn.ios"
APPLE_TEAM_ID="94323HA3GF"
APPLE_ENVIRONMENT="Production"  # or "Sandbox" for testing

# Generate a secure random key for JWT tokens
SECRET_KEY=$(openssl rand -hex 32)

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Apple Subscription Service Deployment     ${NC}"
echo -e "${BLUE}============================================${NC}"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

# Update system
echo -e "\n${GREEN}Updating system packages...${NC}"
apt-get update && apt-get upgrade -y

# Install dependencies
echo -e "\n${GREEN}Installing dependencies...${NC}"
apt-get install -y python3 python3-pip python3-venv nginx certbot python3-certbot-nginx \
                   git supervisor postgresql postgresql-contrib

# Create app user if it doesn't exist
if ! id -u "$APP_USER" &>/dev/null; then
    echo -e "\n${GREEN}Creating application user...${NC}"
    useradd -m -s /bin/bash "$APP_USER"
fi

# Create and setup PostgreSQL database
echo -e "\n${GREEN}Setting up PostgreSQL database...${NC}"
DB_PASSWORD=$(openssl rand -hex 16)
sudo -u postgres psql -c "CREATE DATABASE apple_subscriptions;"
sudo -u postgres psql -c "CREATE USER apple_app WITH ENCRYPTED PASSWORD '$DB_PASSWORD';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE apple_subscriptions TO apple_app;"

# Clone repository
echo -e "\n${GREEN}Cloning repository...${NC}"
if [ -d "$DEPLOY_PATH" ]; then
    echo -e "${YELLOW}Warning: Deploy directory already exists. Removing...${NC}"
    rm -rf "$DEPLOY_PATH"
fi
git clone "$REPO_URL" "$DEPLOY_PATH"

# Set up Python virtual environment
echo -e "\n${GREEN}Setting up Python virtual environment...${NC}"
cd "$DEPLOY_PATH"
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# Install production dependencies
pip install gunicorn psycopg2-binary

# Create keys directory if it doesn't exist
mkdir -p "$DEPLOY_PATH/keys"

# Check if the private key exists in the repository
echo -e "\n${GREEN}Checking Apple private key file...${NC}"
KEY_FILE="$DEPLOY_PATH/keys/AuthKey_${APPLE_PRIVATE_KEY_ID}.p8"

if [ -f "$KEY_FILE" ]; then
    echo -e "${GREEN}Apple private key found in repository.${NC}"
    # Set secure permissions
    chmod 600 "$KEY_FILE"
else
    echo -e "${YELLOW}Warning: Apple private key not found in repository.${NC}"
    echo -e "${YELLOW}You'll need to manually upload the private key to:${NC}"
    echo -e "${YELLOW}$KEY_FILE${NC}"
fi

# Create .env file
echo -e "\n${GREEN}Creating environment configuration...${NC}"
cat > "$DEPLOY_PATH/.env" << EOL
# Environment variables for Apple Subscription Service

# Server settings
HOST=127.0.0.1
PORT=${APP_PORT}
DEBUG=False
LOG_LEVEL=INFO

# Security
SECRET_KEY=${SECRET_KEY}
ACCESS_TOKEN_EXPIRE_MINUTES=1440

# Database
DATABASE_URL=postgresql://apple_app:${DB_PASSWORD}@localhost:5432/apple_subscriptions

# CORS settings
ALLOWED_ORIGINS=["https://${DOMAIN}"]

# Apple specific settings
APPLE_ISSUER_ID=${APPLE_ISSUER_ID}
APPLE_PRIVATE_KEY_ID=${APPLE_PRIVATE_KEY_ID}
APPLE_PRIVATE_KEY_PATH=keys/AuthKey_${APPLE_PRIVATE_KEY_ID}.p8
APPLE_BUNDLE_ID=${APPLE_BUNDLE_ID}
APPLE_TEAM_ID=${APPLE_TEAM_ID}
APPLE_ENVIRONMENT=${APPLE_ENVIRONMENT}
EOL

# Create logs directory
mkdir -p "$DEPLOY_PATH/logs"

# Create a Gunicorn service file
echo -e "\n${GREEN}Creating Gunicorn service...${NC}"
cat > "/etc/supervisor/conf.d/apple-subscription.conf" << EOL
[program:apple-subscription]
directory=${DEPLOY_PATH}
command=${DEPLOY_PATH}/venv/bin/gunicorn -w 4 -k uvicorn.workers.UvicornWorker -b 127.0.0.1:${APP_PORT} main:app
user=${APP_USER}
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
stdout_logfile=${DEPLOY_PATH}/logs/gunicorn.log
stderr_logfile=${DEPLOY_PATH}/logs/gunicorn-error.log
EOL

# Create Nginx configuration
echo -e "\n${GREEN}Creating Nginx configuration...${NC}"
cat > "/etc/nginx/sites-available/${DOMAIN}" << EOL
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Additional configuration for WebSocket support if needed
    location /ws {
        proxy_pass http://127.0.0.1:${APP_PORT}/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOL

# Enable the Nginx site
ln -sf "/etc/nginx/sites-available/${DOMAIN}" "/etc/nginx/sites-enabled/"

# Set ownership
echo -e "\n${GREEN}Setting correct permissions...${NC}"
chown -R "$APP_USER":"$APP_USER" "$DEPLOY_PATH"

# Test Nginx configuration
echo -e "\n${GREEN}Testing Nginx configuration...${NC}"
nginx -t

if [ $? -ne 0 ]; then
    echo -e "${RED}Nginx configuration test failed. Please check the configuration.${NC}"
    exit 1
fi

# Reload supervisor to pick up the new configuration
echo -e "\n${GREEN}Reloading supervisor...${NC}"
supervisorctl reread
supervisorctl update

# Reload Nginx to pick up the new configuration
echo -e "\n${GREEN}Reloading Nginx...${NC}"
systemctl reload nginx

# Set up SSL with Certbot
echo -e "\n${GREEN}Setting up SSL with Certbot...${NC}"
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email admin@safeprovpn.com

# Security reminder about private keys in repositories
echo -e "\n${YELLOW}Security reminder:${NC}"
echo -e "Having private keys in a Git repository is generally not recommended for security."
echo -e "Consider removing the key from the repository and managing it separately."
echo -e "You can use environment variables or a secure secret management solution instead."

# Final check
echo -e "\n${GREEN}Checking service status...${NC}"
supervisorctl status apple-subscription

echo -e "\n${BLUE}============================================${NC}"
echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "${BLUE}============================================${NC}"
echo -e "Your Apple Subscription Service is now running at:"
echo -e "${GREEN}https://${DOMAIN}${NC}"
echo -e "\nAPI Documentation is available at:"
echo -e "${GREEN}https://${DOMAIN}/api/docs${NC}"
echo -e "\nTest the connection to Apple servers with:"
echo -e "${BLUE}curl https://${DOMAIN}/api/v1/test-connection${NC}"
echo -e "\n${YELLOW}Important:${NC}"
echo -e "1. Make sure your domain DNS is pointing to this server"
echo -e "2. Configure your App in App Store Connect to use this webhook URL:"
echo -e "   ${GREEN}https://${DOMAIN}/api/v1/webhook/apple${NC}"
echo -e "3. Monitor the logs with: ${BLUE}tail -f ${DEPLOY_PATH}/logs/gunicorn.log${NC}"
echo -e "\n${BLUE}============================================${NC}"
