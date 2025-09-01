#!/bin/bash
# Script to update server code from GitHub repository

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Update Server from GitHub                ${NC}"
echo -e "${BLUE}============================================${NC}"

# Server connection details
SERVER_USER="root"
SERVER_HOST="ubuntu-4gb-nbg1-2"
REMOTE_PATH="/opt/apple-subscription-service"

# GitHub repository details
REPO_URL="https://github.com/TeccClubb/Apple-Webhook.git"
BRANCH="main"

echo -e "${YELLOW}Connecting to server and updating code...${NC}"

# Connect to the server and run update commands
ssh ${SERVER_USER}@${SERVER_HOST} << EOF
    echo -e "${YELLOW}Creating backup of critical files...${NC}"
    cd ${REMOTE_PATH}
    cp -f app/core/apple_jws.py app/core/apple_jws.py.backup_\$(date +%Y%m%d_%H%M%S)
    cp -f app/services/notification_processor.py app/services/notification_processor.py.backup_\$(date +%Y%m%d_%H%M%S)
    cp -f app/api/routes/apple_webhook.py app/api/routes/apple_webhook.py.backup_\$(date +%Y%m%d_%H%M%S)
    
    echo -e "${YELLOW}Checking for local changes...${NC}"
    if [ -n "\$(git status --porcelain)" ]; then
        echo -e "${YELLOW}Local changes detected. Stashing changes...${NC}"
        git stash
    fi
    
    echo -e "${GREEN}Pulling latest code from GitHub...${NC}"
    git fetch origin ${BRANCH}
    git reset --hard origin/${BRANCH}
    
    echo -e "${GREEN}Updating Python dependencies...${NC}"
    source venv/bin/activate
    pip install -r requirements.txt
    
    echo -e "${YELLOW}Restarting service...${NC}"
    supervisorctl restart apple-subscription
    
    echo -e "${GREEN}Checking service status...${NC}"
    supervisorctl status apple-subscription
    
    echo -e "${YELLOW}Recent logs:${NC}"
    tail -n 10 logs/gunicorn-error.log
EOF

echo -e "${GREEN}Update completed. You can now monitor notifications using:${NC}"
echo -e "${YELLOW}ssh ${SERVER_USER}@${SERVER_HOST} 'cd ${REMOTE_PATH} && ./monitor_notifications.sh'${NC}"
echo -e "${BLUE}============================================${NC}"
