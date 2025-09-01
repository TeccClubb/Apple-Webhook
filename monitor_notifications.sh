#!/bin/bash
# Apple Notification Monitor
# This script monitors logs for Apple notifications and checks the database

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Apple Notification Monitor               ${NC}"
echo -e "${BLUE}============================================${NC}"

# Get database connection details from .env file
DEPLOY_PATH="/opt/apple-subscription-service"
ENV_FILE="${DEPLOY_PATH}/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}Error: .env file not found at $ENV_FILE${NC}"
    exit 1
fi

# Extract database connection info from .env
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
fi

# Function to check webhook status
check_webhook_status() {
    echo -e "\n${YELLOW}Checking webhook configuration...${NC}"
    WEBHOOK_URL="https://apple.safeprovpn.com/api/v1/webhook/apple"
    
    # Test the webhook endpoint
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$WEBHOOK_URL")
    
    if [ "$RESPONSE" == "404" ] || [ "$RESPONSE" == "405" ]; then
        echo -e "${GREEN}✅ Webhook URL is properly configured (endpoint exists)${NC}"
    elif [ "$RESPONSE" == "200" ]; then
        echo -e "${GREEN}✅ Webhook URL is properly configured and accepting requests${NC}"
    else
        echo -e "${RED}❌ Webhook URL returned unexpected status code: $RESPONSE${NC}"
    fi
}

# Function to check database records
check_database_records() {
    echo -e "\n${YELLOW}Checking database records...${NC}"
    
    # Count subscriptions
    SUBSCRIPTION_COUNT=$(sudo -u postgres psql -t -c "SELECT COUNT(*) FROM subscriptions;" "$DB_NAME" 2>/dev/null || echo "Error")
    
    if [[ "$SUBSCRIPTION_COUNT" == "Error" ]]; then
        SUBSCRIPTION_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -t -c "SELECT COUNT(*) FROM subscriptions;" "$DB_NAME" 2>/dev/null || echo "Error")
    fi
    
    # Count notifications
    NOTIFICATION_COUNT=$(sudo -u postgres psql -t -c "SELECT COUNT(*) FROM notification_history;" "$DB_NAME" 2>/dev/null || echo "Error")
    
    if [[ "$NOTIFICATION_COUNT" == "Error" ]]; then
        NOTIFICATION_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -t -c "SELECT COUNT(*) FROM notification_history;" "$DB_NAME" 2>/dev/null || echo "Error")
    fi
    
    if [[ "$SUBSCRIPTION_COUNT" != "Error" ]]; then
        echo -e "${GREEN}Found ${SUBSCRIPTION_COUNT} subscription records${NC}"
    else
        echo -e "${RED}❌ Could not retrieve subscription count${NC}"
    fi
    
    if [[ "$NOTIFICATION_COUNT" != "Error" ]]; then
        echo -e "${GREEN}Found ${NOTIFICATION_COUNT} notification history records${NC}"
    else
        echo -e "${RED}❌ Could not retrieve notification count${NC}"
    fi
    
    # Show recent subscriptions if any exist
    if [[ "$SUBSCRIPTION_COUNT" != "Error" && "$SUBSCRIPTION_COUNT" -gt 0 ]]; then
        echo -e "\n${YELLOW}Recent subscriptions:${NC}"
        sudo -u postgres psql -c "SELECT id, user_id, original_transaction_id, product_id, status, purchase_date, expires_date FROM subscriptions ORDER BY purchase_date DESC LIMIT 3;" "$DB_NAME" 2>/dev/null || \
        PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -c "SELECT id, user_id, original_transaction_id, product_id, status, purchase_date, expires_date FROM subscriptions ORDER BY purchase_date DESC LIMIT 3;" "$DB_NAME"
    fi
    
    # Show recent notifications if any exist
    if [[ "$NOTIFICATION_COUNT" != "Error" && "$NOTIFICATION_COUNT" -gt 0 ]]; then
        echo -e "\n${YELLOW}Recent notifications:${NC}"
        sudo -u postgres psql -c "SELECT id, subscription_id, notification_type, processed, created_at FROM notification_history ORDER BY created_at DESC LIMIT 3;" "$DB_NAME" 2>/dev/null || \
        PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -c "SELECT id, subscription_id, notification_type, processed, created_at FROM notification_history ORDER BY created_at DESC LIMIT 3;" "$DB_NAME"
    fi
}

# Function to monitor logs
monitor_logs() {
    echo -e "\n${YELLOW}Starting log monitor for webhook activity...${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop monitoring${NC}\n"
    
    # Monitor logs with grep for relevant webhook activity
    supervisorctl tail -f apple-subscription | grep -E 'webhook|notification|subscription|apple'
}

# Main menu
while true; do
    echo -e "\n${BLUE}============================================${NC}"
    echo -e "${GREEN}Apple Notification Monitor - Main Menu${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo -e "1. Check webhook configuration"
    echo -e "2. View database records"
    echo -e "3. Monitor logs for notifications in real-time"
    echo -e "4. Perform complete notification check"
    echo -e "5. Exit"
    echo -e "${BLUE}============================================${NC}"
    
    read -p "Select an option (1-5): " option
    
    case $option in
        1) check_webhook_status ;;
        2) check_database_records ;;
        3) monitor_logs ;;
        4)
            check_webhook_status
            check_database_records
            monitor_logs
            ;;
        5) 
            echo -e "${GREEN}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please select 1-5.${NC}"
            ;;
    esac
done
