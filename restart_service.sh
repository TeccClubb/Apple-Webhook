#!/bin/bash
# Script to restart service after modifying Apple notification handling code

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Apple Notification Handler Fix           ${NC}"
echo -e "${BLUE}============================================${NC}"

DEPLOY_PATH="/opt/apple-subscription-service"

# Check if we're in the right directory
if [ ! -d "${DEPLOY_PATH}/app/core" ]; then
    echo -e "${RED}Error: Directory structure not found. Make sure you're in the right location.${NC}"
    echo -e "${YELLOW}Expected path: ${DEPLOY_PATH}/app/core${NC}"
    exit 1
fi

# Backup original files
echo -e "${YELLOW}Backing up original files...${NC}"
cp -f ${DEPLOY_PATH}/app/core/apple_jws.py ${DEPLOY_PATH}/app/core/apple_jws.py.bak
cp -f ${DEPLOY_PATH}/app/api/routes/apple_webhook.py ${DEPLOY_PATH}/app/api/routes/apple_webhook.py.bak

echo -e "${GREEN}Original files backed up.${NC}"

# Restart the service
echo -e "\n${GREEN}Restarting the service...${NC}"
supervisorctl restart apple-subscription
sleep 5

# Check if the service is running
SERVICE_STATUS=$(supervisorctl status apple-subscription)
if [[ "$SERVICE_STATUS" == *"RUNNING"* ]]; then
    echo -e "${GREEN}✅ Service is now running!${NC}"
else
    echo -e "${RED}❌ Service is not running. Status: ${NC}"
    echo "$SERVICE_STATUS"
    
    echo -e "\n${YELLOW}Checking for errors in the log:${NC}"
    tail -n 20 "$DEPLOY_PATH/logs/gunicorn-error.log"
fi

echo -e "\n${GREEN}Now try making a purchase and monitor the notifications:${NC}"
echo -e "${YELLOW}sudo ./monitor_notifications.sh${NC}"
echo -e "\n${BLUE}============================================${NC}"
