#!/bin/bash
# Script to diagnose and fix service startup issues

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Service Startup Diagnostic Tool          ${NC}"
echo -e "${BLUE}============================================${NC}"

# Server connection details
SERVER_USER="root"
SERVER_HOST="ubuntu-4gb-nbg1-2"
REMOTE_PATH="/opt/apple-subscription-service"

echo -e "${YELLOW}Connecting to server to diagnose service issues...${NC}"

# Connect to the server and run diagnostic commands
ssh ${SERVER_USER}@${SERVER_HOST} << EOF
    cd ${REMOTE_PATH}
    
    echo -e "${YELLOW}Checking supervisor configuration...${NC}"
    echo -e "======================= SUPERVISOR CONFIG =======================\n"
    cat /etc/supervisor/conf.d/apple-subscription.conf
    echo -e "\n=============================================================="
    
    echo -e "\n${YELLOW}Checking service logs...${NC}"
    echo -e "========================= ERROR LOGS ===========================\n"
    tail -n 20 logs/gunicorn-error.log
    echo -e "\n=============================================================="
    
    echo -e "\n${YELLOW}Checking supervisor logs...${NC}"
    echo -e "======================= SUPERVISOR LOGS =======================\n"
    tail -n 20 /var/log/supervisor/supervisord.log
    echo -e "\n=============================================================="
    
    echo -e "\n${YELLOW}Checking if Python virtual environment exists...${NC}"
    if [ -d "venv" ] && [ -f "venv/bin/python" ]; then
        echo -e "${GREEN}Virtual environment exists${NC}"
    else
        echo -e "${RED}Virtual environment is missing or incomplete${NC}"
    fi
    
    echo -e "\n${YELLOW}Checking if main application file exists...${NC}"
    if [ -f "main.py" ]; then
        echo -e "${GREEN}Main application file exists${NC}"
    else
        echo -e "${RED}main.py is missing${NC}"
        ls -la
    fi
    
    echo -e "\n${YELLOW}Checking Python dependencies...${NC}"
    source venv/bin/activate
    echo -e "Python version: \$(python --version)"
    
    echo -e "\n${YELLOW}Testing application imports...${NC}"
    python3 -c "
try:
    import sys
    sys.path.insert(0, '${REMOTE_PATH}')
    from app.core.apple_jws import AppleJWSVerifier
    print('✓ Successfully imported AppleJWSVerifier')
except Exception as e:
    print(f'✗ Error importing: {str(e)}')
"
    
    echo -e "\n${YELLOW}Checking file structure in app module...${NC}"
    ls -la app/
    ls -la app/core/
    ls -la app/api/routes/
EOF

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Service Repair Tool                      ${NC}"
echo -e "${BLUE}============================================${NC}"

echo -e "${YELLOW}Would you like to attempt to fix the service? (y/n)${NC}"
read -p "Enter choice: " fix_choice

if [[ "$fix_choice" == "y" ]]; then
    echo -e "${YELLOW}Connecting to server to attempt service repair...${NC}"
    
    ssh ${SERVER_USER}@${SERVER_HOST} << EOF
        cd ${REMOTE_PATH}
        
        echo -e "${YELLOW}Recreating Python virtual environment...${NC}"
        if [ -d "venv" ]; then
            echo -e "Backing up old virtual environment..."
            mv venv venv.bak
        fi
        
        echo -e "Creating new virtual environment..."
        python3 -m venv venv
        source venv/bin/activate
        
        echo -e "Upgrading pip..."
        pip install --upgrade pip
        
        echo -e "Installing requirements..."
        pip install -r requirements.txt
        
        echo -e "Installing additional required packages..."
        pip install gunicorn uvicorn
        
        echo -e "${YELLOW}Fixing permissions...${NC}"
        chown -R www-data:www-data ${REMOTE_PATH}
        chmod -R 750 ${REMOTE_PATH}
        chmod -R 770 ${REMOTE_PATH}/logs
        
        echo -e "${YELLOW}Restarting supervisor...${NC}"
        supervisorctl reread
        supervisorctl update
        supervisorctl restart apple-subscription
        sleep 5
        
        echo -e "${YELLOW}Checking service status...${NC}"
        supervisorctl status apple-subscription
EOF
else
    echo -e "${YELLOW}Skipping repair attempt.${NC}"
fi

echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}Diagnostics completed. Please review the output above for issues.${NC}"
echo -e "${BLUE}============================================${NC}"
