#!/bin/bash
# PostgreSQL Permissions Fix Script for Apple Subscription Service
# This script fixes the "permission denied for schema public" error

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  PostgreSQL Permissions Fix Script        ${NC}"
echo -e "${BLUE}============================================${NC}"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

# Get database connection details from .env file
DEPLOY_PATH="/opt/apple-subscription-service"
ENV_FILE="${DEPLOY_PATH}/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}Error: .env file not found at $ENV_FILE${NC}"
    
    # Ask if the user wants to input database details manually
    read -p "Would you like to enter database details manually? (y/n): " manual_input
    if [[ "$manual_input" != "y" && "$manual_input" != "Y" ]]; then
        echo -e "${RED}Exiting script.${NC}"
        exit 1
    fi
    
    read -p "Enter PostgreSQL database name: " DB_NAME
    read -p "Enter PostgreSQL username: " DB_USER
    read -p "Enter PostgreSQL host (default: localhost): " DB_HOST
    DB_HOST=${DB_HOST:-localhost}
    read -p "Enter PostgreSQL port (default: 5432): " DB_PORT
    DB_PORT=${DB_PORT:-5432}
else
    # Extract database connection info from .env
    echo -e "${GREEN}Extracting database connection information...${NC}"
    DB_URL=$(grep "DATABASE_URL=" "$ENV_FILE" | cut -d'=' -f2-)

    if [[ -z "$DB_URL" ]]; then
        echo -e "${RED}Error: DATABASE_URL not found in .env file${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Found database URL: $DB_URL${NC}"

    # Parse the connection string
    if [[ "$DB_URL" == postgresql* ]]; then
        # Extract components from connection string
        DB_USER=$(echo "$DB_URL" | sed -n 's/.*:\/\/\([^:]*\):.*/\1/p')
        DB_PASSWORD=$(echo "$DB_URL" | sed -n 's/.*:\/\/[^:]*:\([^@]*\)@.*/\1/p')
        DB_HOST=$(echo "$DB_URL" | sed -n 's/.*@\([^:]*\):.*/\1/p')
        DB_PORT=$(echo "$DB_URL" | sed -n 's/.*@[^:]*:\([^\/]*\)\/.*/\1/p')
        DB_NAME=$(echo "$DB_URL" | sed -n 's/.*\/\([^?]*\).*/\1/p')
        
        if [[ -z "$DB_HOST" ]]; then DB_HOST="localhost"; fi
        if [[ -z "$DB_PORT" ]]; then DB_PORT="5432"; fi
    else
        echo -e "${RED}Error: Only PostgreSQL databases are supported${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}Database details to use:${NC}"
echo -e "  Database: ${YELLOW}$DB_NAME${NC}"
echo -e "  User: ${YELLOW}$DB_USER${NC}"
echo -e "  Host: ${YELLOW}$DB_HOST${NC}"
echo -e "  Port: ${YELLOW}$DB_PORT${NC}"

# Verify database connection
echo -e "\n${GREEN}Verifying database connection...${NC}"
# First try to connect as postgres user with peer authentication (no password)
if sudo -u postgres psql -c "\l" 2>/dev/null | grep -q "$DB_NAME"; then
    echo -e "${GREEN}Database '$DB_NAME' exists.${NC}"
    DB_EXISTS=true
else
    # Try connecting with postgres password if peer authentication fails
    echo -e "${YELLOW}Could not verify database using peer authentication.${NC}"
    echo -e "${YELLOW}Checking if database exists using alternative method...${NC}"
    
    # Check if psql can connect to postgres database directly
    if psql -U postgres -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
        echo -e "${GREEN}Database '$DB_NAME' exists.${NC}"
        DB_EXISTS=true
    else
        echo -e "${YELLOW}Could not verify database existence automatically.${NC}"
        read -p "Does the database '$DB_NAME' already exist? (y/n): " db_exists_response
        if [[ "$db_exists_response" == "y" || "$db_exists_response" == "Y" ]]; then
            DB_EXISTS=true
        else
            DB_EXISTS=false
            
            # Ask if the user wants to create the database
            read -p "Would you like to create the database '$DB_NAME'? (y/n): " create_db
            if [[ "$create_db" == "y" || "$create_db" == "Y" ]]; then
                echo -e "${YELLOW}Attempting to create database...${NC}"
                echo -e "${YELLOW}Please provide the PostgreSQL postgres user password if prompted.${NC}"
                
                # Try different methods to create the database
                if sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;" 2>/dev/null; then
                    echo -e "${GREEN}Database created successfully using peer authentication.${NC}"
                    DB_EXISTS=true
                elif createdb -U postgres "$DB_NAME" 2>/dev/null; then
                    echo -e "${GREEN}Database created successfully using createdb.${NC}"
                    DB_EXISTS=true
                else
                    echo -e "${RED}Could not create database automatically.${NC}"
                    echo -e "${YELLOW}Please run the following command manually:${NC}"
                    echo -e "${YELLOW}sudo -u postgres createdb $DB_NAME${NC}"
                    echo -e "${YELLOW}Or if your PostgreSQL requires a password:${NC}"
                    echo -e "${YELLOW}createdb -U postgres $DB_NAME${NC}"
                    read -p "Press Enter after creating the database manually, or Ctrl+C to exit..." _
                    DB_EXISTS=true
                fi
            else
                echo -e "${RED}Cannot continue without a database. Exiting.${NC}"
                exit 1
            fi
        fi
    fi
fi

# Verify user exists
echo -e "\n${GREEN}Checking if user '$DB_USER' exists...${NC}"
USER_EXISTS=false

# Try different methods to check if user exists
if sudo -u postgres psql -c "\du" 2>/dev/null | grep -q "$DB_USER"; then
    echo -e "${GREEN}User '$DB_USER' exists.${NC}"
    USER_EXISTS=true
elif psql -U postgres -c "\du" 2>/dev/null | grep -q "$DB_USER"; then
    echo -e "${GREEN}User '$DB_USER' exists.${NC}"
    USER_EXISTS=true
else
    echo -e "${YELLOW}Could not verify if user exists automatically.${NC}"
    read -p "Does the database user '$DB_USER' already exist? (y/n): " user_exists_response
    if [[ "$user_exists_response" == "y" || "$user_exists_response" == "Y" ]]; then
        USER_EXISTS=true
    else
        echo -e "${YELLOW}User '$DB_USER' does not exist${NC}"
        
        # Ask if the user wants to create the database user
        read -p "Would you like to create the database user '$DB_USER'? (y/n): " create_user
        if [[ "$create_user" == "y" || "$create_user" == "Y" ]]; then
            # Generate a random password if needed
            if [[ -z "$DB_PASSWORD" ]]; then
                DB_PASSWORD=$(openssl rand -hex 16)
            fi
            
            echo -e "${GREEN}Creating user '$DB_USER' with a password...${NC}"
            echo -e "${YELLOW}Please provide the PostgreSQL postgres user password if prompted.${NC}"
            
            # Try different methods to create the user
            if sudo -u postgres psql -c "CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASSWORD';" 2>/dev/null; then
                echo -e "${GREEN}User created successfully using peer authentication.${NC}"
                USER_EXISTS=true
            elif psql -U postgres -c "CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASSWORD';" 2>/dev/null; then
                echo -e "${GREEN}User created successfully.${NC}"
                USER_EXISTS=true
            else
                echo -e "${RED}Could not create user automatically.${NC}"
                echo -e "${YELLOW}Please run the following command manually:${NC}"
                echo -e "${YELLOW}sudo -u postgres psql -c \"CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASSWORD';\"${NC}"
                echo -e "${YELLOW}Or if your PostgreSQL requires a password:${NC}"
                echo -e "${YELLOW}psql -U postgres -c \"CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASSWORD';\"${NC}"
                read -p "Press Enter after creating the user manually, or Ctrl+C to exit..." _
                USER_EXISTS=true
            fi
            
            # Update the .env file if it exists
            if [ -f "$ENV_FILE" ]; then
                echo -e "${GREEN}Updating DATABASE_URL in .env file...${NC}"
                sed -i "s|DATABASE_URL=.*|DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME|" "$ENV_FILE"
                echo -e "${GREEN}Updated .env file with new credentials.${NC}"
            else
                echo -e "${YELLOW}No .env file to update. Remember your credentials:${NC}"
                echo -e "User: ${YELLOW}$DB_USER${NC}"
                echo -e "Password: ${YELLOW}$DB_PASSWORD${NC}"
            fi
        else
            echo -e "${RED}Cannot proceed without a valid database user. Exiting.${NC}"
            exit 1
        fi
    fi
fi

# Create SQL script to grant permissions
echo -e "\n${GREEN}Creating SQL script to fix permissions...${NC}"
SQL_SCRIPT=$(cat << EOF
-- Make the user a superuser temporarily as the most reliable fix
ALTER USER $DB_USER WITH SUPERUSER;

-- Revoke public permission that might be interfering
REVOKE CREATE ON SCHEMA public FROM public;

-- Grant ownership of the schema to the user
ALTER SCHEMA public OWNER TO $DB_USER;

-- Grant all privileges on the schema to the user
GRANT ALL ON SCHEMA public TO $DB_USER;

-- Grant necessary privileges for creating ENUM types
GRANT CREATE ON SCHEMA public TO $DB_USER;
GRANT USAGE ON SCHEMA public TO $DB_USER;

-- Grant specific type creation privileges
GRANT ALL ON TYPE pg_catalog.text TO $DB_USER;
GRANT ALL ON TYPE pg_catalog.varchar TO $DB_USER; 
GRANT ALL ON TYPE pg_catalog.anyenum TO $DB_USER;

-- Grant permissions for future objects
ALTER DEFAULT PRIVILEGES FOR USER postgres IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;
ALTER DEFAULT PRIVILEGES FOR USER postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;
ALTER DEFAULT PRIVILEGES FOR USER postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO $DB_USER;
ALTER DEFAULT PRIVILEGES FOR USER postgres IN SCHEMA public GRANT ALL ON TYPES TO $DB_USER;

-- Set search_path for the user
ALTER USER $DB_USER SET search_path TO public;

-- Grant database ownership
ALTER DATABASE $DB_NAME OWNER TO $DB_USER;

-- Pre-create the ENUM types that are failing
DO \$\$
BEGIN
    DROP TYPE IF EXISTS subscriptionstatus CASCADE;
    DROP TYPE IF EXISTS notificationtype CASCADE;
    
    CREATE TYPE subscriptionstatus AS ENUM ('ACTIVE', 'EXPIRED', 'IN_GRACE_PERIOD', 'IN_BILLING_RETRY', 'REVOKED', 'REFUNDED');
    CREATE TYPE notificationtype AS ENUM ('SUBSCRIBED', 'DID_CHANGE_RENEWAL_PREF', 'DID_CHANGE_RENEWAL_STATUS', 
                                         'OFFER_REDEEMED', 'DID_RENEW', 'EXPIRED', 'DID_FAIL_TO_RENEW', 
                                         'GRACE_PERIOD_EXPIRED', 'PRICE_INCREASE', 'REFUND', 'REFUND_DECLINED', 
                                         'CONSUMPTION_REQUEST', 'RENEWAL_EXTENDED', 'REVOKE', 'TEST');
END
\$\$;

-- Set ownership of the ENUM types to the app user
ALTER TYPE subscriptionstatus OWNER TO $DB_USER;
ALTER TYPE notificationtype OWNER TO $DB_USER;
EOF
)

# Write the SQL to a temporary file
TMP_SQL="/tmp/fix_permissions.sql"
echo "$SQL_SCRIPT" > "$TMP_SQL"

# Execute the SQL script as the postgres user
echo -e "\n${GREEN}Applying database permission fixes...${NC}"
echo -e "${YELLOW}Please provide the PostgreSQL postgres user password if prompted.${NC}"

# Try different methods to apply permissions
PERMISSIONS_FIXED=false

# Method 1: Using sudo -u postgres (peer authentication)
if sudo -u postgres psql -d "$DB_NAME" -f "$TMP_SQL" 2>/dev/null; then
    echo -e "${GREEN}✅ PostgreSQL permissions fixed successfully using peer authentication!${NC}"
    PERMISSIONS_FIXED=true
# Method 2: Direct psql connection (password authentication)
elif psql -U postgres -d "$DB_NAME" -f "$TMP_SQL" 2>/dev/null; then
    echo -e "${GREEN}✅ PostgreSQL permissions fixed successfully!${NC}"
    PERMISSIONS_FIXED=true
# Method 3: Using the actual database user if it has sufficient privileges
elif psql -U "$DB_USER" -d "$DB_NAME" -h "$DB_HOST" -p "$DB_PORT" -f "$TMP_SQL" 2>/dev/null; then
    echo -e "${GREEN}✅ PostgreSQL permissions fixed successfully using $DB_USER!${NC}"
    PERMISSIONS_FIXED=true
else
    echo -e "${RED}❌ Failed to apply PostgreSQL permission fixes automatically${NC}"
    echo -e "${YELLOW}Trying alternate approach...${NC}"
    
    # Try alternate approach - make the user a superuser temporarily
    echo -e "\n${GREEN}Trying to grant superuser privileges temporarily...${NC}"
    TEMP_SQL=$(cat << EOF
-- Temporary solution: Make user a superuser
ALTER USER $DB_USER WITH SUPERUSER;

-- Pre-create the ENUM types that are failing (superuser can always do this)
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'subscriptionstatus') THEN
        CREATE TYPE subscriptionstatus AS ENUM ('ACTIVE', 'EXPIRED', 'IN_GRACE_PERIOD', 'IN_BILLING_RETRY', 'REVOKED', 'REFUNDED');
        ALTER TYPE subscriptionstatus OWNER TO $DB_USER;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notificationtype') THEN
        CREATE TYPE notificationtype AS ENUM ('SUBSCRIBED', 'DID_CHANGE_RENEWAL_PREF', 'DID_CHANGE_RENEWAL_STATUS', 
                                              'OFFER_REDEEMED', 'DID_RENEW', 'EXPIRED', 'DID_FAIL_TO_RENEW', 
                                              'GRACE_PERIOD_EXPIRED', 'PRICE_INCREASE', 'REFUND', 'REFUND_DECLINED', 
                                              'CONSUMPTION_REQUEST', 'RENEWAL_EXTENDED', 'REVOKE', 'TEST');
        ALTER TYPE notificationtype OWNER TO $DB_USER;
    END IF;
END
\$\$;
EOF
)
    echo "$TEMP_SQL" > "$TMP_SQL"
    
    # Try different methods to grant superuser
    if sudo -u postgres psql -d "postgres" -f "$TMP_SQL" 2>/dev/null; then
        echo -e "${GREEN}✅ Granted temporary superuser privileges using peer authentication${NC}"
        PERMISSIONS_FIXED=true
    elif psql -U postgres -d "postgres" -f "$TMP_SQL" 2>/dev/null; then
        echo -e "${GREEN}✅ Granted temporary superuser privileges${NC}"
        PERMISSIONS_FIXED=true
    else
        echo -e "${RED}❌ Automatic permission fixes failed${NC}"
        echo -e "${YELLOW}You'll need to run the following commands manually:${NC}"
        echo -e "${YELLOW}-------------------------------${NC}"
        echo -e "${YELLOW}sudo -u postgres psql -d $DB_NAME${NC}"
        echo -e "${YELLOW}Then enter these SQL commands:${NC}"
        echo -e "${YELLOW}$(cat "$TMP_SQL")${NC}"
        echo -e "${YELLOW}-------------------------------${NC}"
        echo -e "${YELLOW}Or alternatively, to make the user a superuser:${NC}"
        echo -e "${YELLOW}sudo -u postgres psql -c \"ALTER USER $DB_USER WITH SUPERUSER;\"${NC}"
        
        read -p "Have you manually fixed the permissions? (y/n): " manual_fix
        if [[ "$manual_fix" == "y" || "$manual_fix" == "Y" ]]; then
            PERMISSIONS_FIXED=true
        else
            echo -e "${RED}Cannot continue without fixing permissions. Exiting.${NC}"
            exit 1
        fi
    fi
    
    if [ "$PERMISSIONS_FIXED" = true ]; then
        echo -e "${YELLOW}⚠️ Warning: The database user now has superuser privileges.${NC}"
        echo -e "${YELLOW}⚠️ This is a security risk and should be revoked after the app is working.${NC}"
    fi
fi

# Check if we should drop and recreate tables as a last resort
echo -e "\n${YELLOW}Would you like to drop and recreate all tables if permissions are still an issue? (y/n):${NC} "
read -p "" drop_tables
if [[ "$drop_tables" == "y" || "$drop_tables" == "Y" ]]; then
    echo -e "\n${RED}⚠️ WARNING: This will delete all existing data! ⚠️${NC}"
    read -p "Are you absolutely sure? Type 'yes' to confirm: " confirm_drop
    
    if [[ "$confirm_drop" == "yes" ]]; then
        echo -e "${YELLOW}Creating drop tables script...${NC}"
        DROP_SQL=$(cat << EOF
-- Drop all tables in the correct order
DROP TABLE IF EXISTS notification_history CASCADE;
DROP TABLE IF EXISTS subscriptions CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- Drop the ENUM types
DROP TYPE IF EXISTS subscriptionstatus CASCADE;
DROP TYPE IF EXISTS notificationtype CASCADE;
EOF
)
        echo "$DROP_SQL" > "/tmp/drop_tables.sql"
        
        echo -e "${RED}Dropping all tables...${NC}"
        if sudo -u postgres psql -d "$DB_NAME" -f "/tmp/drop_tables.sql" 2>/dev/null; then
            echo -e "${GREEN}Tables dropped successfully.${NC}"
        elif psql -U postgres -d "$DB_NAME" -f "/tmp/drop_tables.sql" 2>/dev/null; then
            echo -e "${GREEN}Tables dropped successfully.${NC}"
        elif psql -U "$DB_USER" -d "$DB_NAME" -h "$DB_HOST" -p "$DB_PORT" -f "/tmp/drop_tables.sql" 2>/dev/null; then
            echo -e "${GREEN}Tables dropped successfully.${NC}"
        else
            echo -e "${RED}Failed to drop tables. You may need to do this manually.${NC}"
        fi
    fi
fi

# Check if supervisor is installed and the service exists
if command -v supervisorctl &> /dev/null && supervisorctl status apple-subscription &> /dev/null; then
    # Restart the service
    echo -e "\n${GREEN}Restarting the service...${NC}"
    supervisorctl restart apple-subscription
    sleep 5

    # Check if the service is running now
    SERVICE_STATUS=$(supervisorctl status apple-subscription)
    if [[ "$SERVICE_STATUS" == *"RUNNING"* ]]; then
        echo -e "${GREEN}✅ Service is now running!${NC}"
    else
        echo -e "${RED}❌ Service is not running. Status: ${NC}"
        echo "$SERVICE_STATUS"
        
        echo -e "\n${YELLOW}Checking for errors in the log:${NC}"
        if [ -f "$DEPLOY_PATH/logs/gunicorn-error.log" ]; then
            tail -n 20 "$DEPLOY_PATH/logs/gunicorn-error.log"
        else
            echo -e "${RED}Log file not found. Check your supervisor configuration.${NC}"
        fi
        
        # Offer option to view last 50 lines of logs if service isn't running
        echo -e "\n${YELLOW}Would you like to see more detailed logs? (y/n): ${NC}"
        read -p "" view_more_logs
        if [[ "$view_more_logs" == "y" || "$view_more_logs" == "Y" ]]; then
            echo -e "\n${GREEN}Showing last 50 lines of error log:${NC}"
            if [ -f "$DEPLOY_PATH/logs/gunicorn-error.log" ]; then
                tail -n 50 "$DEPLOY_PATH/logs/gunicorn-error.log"
            fi
        fi
    fi
fi

# Check if Nginx is installed and running
if command -v systemctl &> /dev/null && systemctl list-unit-files | grep -q nginx; then
    echo -e "\n${GREEN}Checking Nginx status...${NC}"
    NGINX_STATUS=$(systemctl is-active nginx)
    if [ "$NGINX_STATUS" = "active" ]; then
        echo -e "${GREEN}✅ Nginx is running. Reloading configuration...${NC}"
        systemctl reload nginx
    else
        echo -e "${YELLOW}⚠️ Nginx is not running. Starting...${NC}"
        systemctl start nginx
    fi
fi

echo -e "\n${BLUE}============================================${NC}"
echo -e "${GREEN}Fix completed!${NC}"
echo -e "${BLUE}============================================${NC}"

# Provide information about how to test the fix
echo -e "To verify the fix, try accessing these endpoints (adjust domain if needed):"
echo -e "1. ${YELLOW}curl https://apple.safeprovpn.com/health${NC}"
echo -e "2. ${YELLOW}curl https://apple.safeprovpn.com/api/v1/test-connection${NC}"

# Provide security reminder if superuser privileges were granted
if [[ "$TEMP_SQL" == *"SUPERUSER"* ]]; then
    echo -e "\n${RED}⚠️ SECURITY REMINDER ⚠️${NC}"
    echo -e "The database user $DB_USER was granted superuser privileges."
    echo -e "After verifying that the application is working, you should revoke these privileges:"
    echo -e "${YELLOW}sudo -u postgres psql -c \"ALTER USER $DB_USER WITH NOSUPERUSER;\"${NC}"
fi

echo -e "\n${YELLOW}If you still have issues, please check the logs with:${NC}"
echo -e "${YELLOW}supervisorctl tail -f apple-subscription${NC}"

# Provide cleanup instruction
echo -e "\n${GREEN}Cleaning up temporary files...${NC}"
rm -f "$TMP_SQL"
echo -e "${GREEN}Done.${NC}"
