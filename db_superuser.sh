#!/bin/bash
# Simple PostgreSQL Superuser Grant Script
# This is a simplified script to ensure the database user has superuser privileges

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

DB_USER="apple_app"

echo -e "${YELLOW}Setting superuser privilege for $DB_USER...${NC}"
sudo -u postgres psql -c "ALTER USER $DB_USER WITH SUPERUSER;" 2>/dev/null || \
psql -U postgres -c "ALTER USER $DB_USER WITH SUPERUSER;" 2>/dev/null

echo -e "${GREEN}Restarting the service...${NC}"
supervisorctl restart apple-subscription

echo -e "${YELLOW}Done! Check if the service is running with:${NC}"
echo -e "${YELLOW}supervisorctl status apple-subscription${NC}"
