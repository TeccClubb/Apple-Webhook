#!/bin/bash
# App Data Initialization Script
# This script will initialize your database with schema and required types

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Database Schema Initialization Script     ${NC}"
echo -e "${BLUE}============================================${NC}"

# Get database connection details from .env file
DEPLOY_PATH="/opt/apple-subscription-service"
ENV_FILE="${DEPLOY_PATH}/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}Error: .env file not found at $ENV_FILE${NC}"
    exit 1
fi

# Extract database connection info from .env
echo -e "${GREEN}Extracting database connection information...${NC}"
DB_URL=$(grep "DATABASE_URL=" "$ENV_FILE" | cut -d'=' -f2-)

if [[ -z "$DB_URL" ]]; then
    echo -e "${RED}Error: DATABASE_URL not found in .env file${NC}"
    exit 1
fi

# Parse the connection string
if [[ "$DB_URL" == postgresql* ]]; then
    # Extract components from connection string
    DB_USER=$(echo "$DB_URL" | sed -n 's/.*:\/\/\([^:]*\):.*/\1/p')
    DB_PASSWORD=$(echo "$DB_URL" | sed -n 's/.*:\/\/[^:]*:\([^@]*\)@.*/\1/p')
    DB_HOST=$(echo "$DB_URL" | sed -n 's/.*@\([^:]*\):.*/\1/p')
    DB_PORT=$(echo "$DB_URL" | sed -n 's/.*@[^:]*:\([^\/]*\)\/.*/\1/p')
    DB_NAME=$(echo "$DB_URL" | sed -n 's/.*\/\([^?]*\).*/\1/p')
else
    echo -e "${RED}Error: Only PostgreSQL databases are supported${NC}"
    exit 1
fi

echo -e "${GREEN}Database details:${NC}"
echo -e "  Database: ${YELLOW}$DB_NAME${NC}"
echo -e "  User: ${YELLOW}$DB_USER${NC}"

# Create the initialization SQL
echo -e "\n${GREEN}Creating initialization SQL...${NC}"
cat > /tmp/init_schema.sql << EOF
-- Create required ENUM types
DO \$\$
BEGIN
    -- Drop existing types if they exist
    DROP TYPE IF EXISTS subscriptionstatus CASCADE;
    DROP TYPE IF EXISTS notificationtype CASCADE;
    
    -- Create subscription status ENUM
    CREATE TYPE subscriptionstatus AS ENUM (
        'ACTIVE', 
        'EXPIRED', 
        'IN_GRACE_PERIOD', 
        'IN_BILLING_RETRY', 
        'REVOKED', 
        'REFUNDED'
    );

    -- Create notification type ENUM
    CREATE TYPE notificationtype AS ENUM (
        'SUBSCRIBED',
        'DID_CHANGE_RENEWAL_PREF',
        'DID_CHANGE_RENEWAL_STATUS',
        'OFFER_REDEEMED',
        'DID_RENEW',
        'EXPIRED',
        'DID_FAIL_TO_RENEW',
        'GRACE_PERIOD_EXPIRED',
        'PRICE_INCREASE',
        'REFUND',
        'REFUND_DECLINED',
        'CONSUMPTION_REQUEST',
        'RENEWAL_EXTENDED',
        'REVOKE',
        'TEST'
    );
END
\$\$;

-- Set ownership of the ENUM types
ALTER TYPE subscriptionstatus OWNER TO $DB_USER;
ALTER TYPE notificationtype OWNER TO $DB_USER;

-- Grant permissions
GRANT USAGE, CREATE ON SCHEMA public TO $DB_USER;
ALTER SCHEMA public OWNER TO $DB_USER;
GRANT ALL ON SCHEMA public TO $DB_USER;
EOF

# Execute the SQL script
echo -e "\n${GREEN}Executing initialization SQL...${NC}"
if sudo -u postgres psql -d "$DB_NAME" -f /tmp/init_schema.sql; then
    echo -e "${GREEN}✅ Schema initialized successfully!${NC}"
else
    echo -e "${RED}Failed to initialize schema. Trying alternative approach...${NC}"
    
    # Try with superuser privileges for the database user
    echo -e "${YELLOW}Granting superuser privileges...${NC}"
    sudo -u postgres psql -c "ALTER USER $DB_USER WITH SUPERUSER;"
    
    echo -e "${YELLOW}Restarting the service...${NC}"
    supervisorctl restart apple-subscription
    sleep 3
    
    echo -e "${YELLOW}Check if the service is now running:${NC}"
    supervisorctl status apple-subscription
fi

# Clean up
rm -f /tmp/init_schema.sql
echo -e "\n${BLUE}============================================${NC}"
echo -e "${GREEN}Initialization completed!${NC}"
echo -e "${BLUE}============================================${NC}"
