#!/bin/bash
# Quick fix for service startup issues
# Run this script directly on the server

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Service Quick Fix                        ${NC}"
echo -e "${BLUE}============================================${NC}"

# Check if we're running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

# Application directory
APP_DIR="/opt/apple-subscription-service"

cd $APP_DIR || {
    echo -e "${RED}Error: Could not change to application directory${NC}"
    exit 1
}

echo -e "${YELLOW}1. Checking python file indentation in apple_jws.py...${NC}"
# Fix indentation issue in apple_jws.py file
if grep -q "# Determine appropriate algorithm based on key type and header" app/core/apple_jws.py; then
    echo -e "${YELLOW}Found algorithm determination code, fixing indentation...${NC}"
    
    # Create a temporary file for editing
    TEMP_FILE=$(mktemp)
    
    # Fix the indentation in the file
    awk '
        /for key_id, key_data in public_keys.items():/ {
            print $0
            in_block = 1
            next
        }
        /# Determine appropriate algorithm based on key type and header/ {
            if (in_block) {
                # Print with proper indentation
                print "                    # Determine appropriate algorithm based on key type and header"
                print "                    key_kty = key_data.get(\"kty\")"
                print "                    header_alg = header_data.get(\"alg\", \"\")"
                print ""
                print "                    # First check the header'\''s alg if it'\''s specified"
                print "                    if header_alg:"
                print "                        alg = header_alg"
                print "                    # Otherwise infer from key type"
                print "                    elif key_kty == \"EC\":"
                print "                        alg = \"ES256\"  # Typically used with EC keys"
                print "                    elif key_kty == \"RSA\":"
                print "                        alg = \"RS256\"  # Typically used with RSA keys"
                print "                    else:"
                print "                        alg = \"RS256\"  # Default"
                
                # Skip the badly indented block
                skip_lines = 13
                next
            } else {
                print $0
                next
            }
        }
        /logger.info\(f"Trying verification with key {key_id} using algorithm {alg}"\)/ {
            # Reset the block flag since we've reached the end of the problematic area
            in_block = 0
            print $0
            next
        }
        # Print all other lines as is
        { print $0 }
    ' app/core/apple_jws.py > $TEMP_FILE
    
    # Backup the original file
    cp app/core/apple_jws.py app/core/apple_jws.py.backup
    
    # Replace with the fixed file
    cp $TEMP_FILE app/core/apple_jws.py
    rm $TEMP_FILE
    
    echo -e "${GREEN}Fixed indentation in apple_jws.py${NC}"
else
    echo -e "${GREEN}No indentation issues detected in apple_jws.py${NC}"
fi

echo -e "${YELLOW}2. Reinstalling Python virtual environment...${NC}"

# Backup and recreate virtual environment
if [ -d "venv" ]; then
    echo -e "Backing up old virtual environment..."
    mv venv venv.bak_$(date +%Y%m%d_%H%M%S)
fi

echo -e "Creating new virtual environment..."
python3 -m venv venv
source venv/bin/activate

echo -e "Upgrading pip..."
pip install --upgrade pip

echo -e "Installing requirements..."
if [ -f "requirements.txt" ]; then
    pip install -r requirements.txt
else
    echo -e "${YELLOW}requirements.txt not found, installing core packages...${NC}"
    pip install fastapi uvicorn sqlalchemy psycopg2-binary python-jose[cryptography] python-multipart pydantic email-validator requests tenacity gunicorn
fi

echo -e "${YELLOW}3. Checking supervisor configuration...${NC}"

# Check if supervisor config exists
if [ ! -f "/etc/supervisor/conf.d/apple-subscription.conf" ]; then
    echo -e "${RED}Supervisor configuration is missing. Creating it...${NC}"
    
    cat > "/etc/supervisor/conf.d/apple-subscription.conf" << EOL
[program:apple-subscription]
directory=/opt/apple-subscription-service
command=/opt/apple-subscription-service/venv/bin/gunicorn -w 4 -k uvicorn.workers.UvicornWorker -b 127.0.0.1:8000 app.main:app --log-level debug --timeout 120
user=root
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
stdout_logfile=/opt/apple-subscription-service/logs/gunicorn.log
stderr_logfile=/opt/apple-subscription-service/logs/gunicorn-error.log
startretries=10
startsecs=10
environment=PYTHONPATH="/opt/apple-subscription-service",PATH="/opt/apple-subscription-service/venv/bin:%(ENV_PATH)s"
EOL
    echo -e "${GREEN}Created supervisor configuration${NC}"
else
    echo -e "${GREEN}Supervisor configuration exists${NC}"
fi

echo -e "${YELLOW}4. Checking logs directory...${NC}"
mkdir -p logs
chmod -R 775 logs

echo -e "${YELLOW}5. Restarting supervisor...${NC}"
supervisorctl reread
supervisorctl update
supervisorctl restart apple-subscription
sleep 5

echo -e "${YELLOW}6. Checking service status...${NC}"
supervisorctl status apple-subscription

echo -e "${YELLOW}7. Checking logs for errors...${NC}"
if [ -f "logs/gunicorn-error.log" ]; then
    tail -n 20 logs/gunicorn-error.log
else
    echo -e "${RED}Log file not found${NC}"
fi

echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}Service repair completed.${NC}"
echo -e "${YELLOW}If the service is still not running, check the logs for specific error messages.${NC}"
echo -e "${BLUE}============================================${NC}"
