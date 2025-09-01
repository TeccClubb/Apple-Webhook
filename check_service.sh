#!/bin/bash
# Helper script to check the status of your Apple Subscription Service
# Usage: bash check_service.sh

# Terminal colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${GREEN}Apple Subscription Service Status Check${NC}"
echo -e "${BLUE}==================================================${NC}"

echo -e "\n${GREEN}Checking service status:${NC}"
supervisorctl status apple-subscription

echo -e "\n${GREEN}Checking Nginx status:${NC}"
systemctl status nginx | grep "Active:"

echo -e "\n${GREEN}Checking database connectivity:${NC}"
sudo -u postgres psql -c "\l" | grep apple_subscriptions

echo -e "\n${GREEN}Testing API connectivity:${NC}"
curl -s http://localhost:8000/health

echo -e "\n${GREEN}Testing Apple connection:${NC}"
curl -s http://localhost:8000/api/v1/test-connection

echo -e "\n${GREEN}Recent logs:${NC}"
tail -n 20 /opt/apple-subscription-service/logs/gunicorn.log

echo -e "\n${BLUE}==================================================${NC}"
echo -e "${GREEN}Connection test URL: https://apple.safeprovpn.com/api/v1/test-connection${NC}"
echo -e "${GREEN}API Documentation: https://apple.safeprovpn.com/api/docs${NC}"
echo -e "${BLUE}==================================================${NC}"
