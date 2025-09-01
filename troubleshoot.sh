#!/bin/bash
# Apple Subscription Service Troubleshooting Script
# For Ubuntu/Debian-based systems
# Usage: bash troubleshoot.sh

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

DEPLOY_PATH="/opt/apple-subscription-service"
APP_USER="appuser"
LOG_PATH="$DEPLOY_PATH/logs"

# Detect OS type for proper command usage
if [[ "$OSTYPE" == "darwin"* ]]; then
    IS_MAC=true
    echo -e "${YELLOW}Detected macOS environment${NC}"
else
    IS_MAC=false
    echo -e "${YELLOW}Detected Linux environment${NC}"
fi

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Apple Subscription Service Troubleshooting ${NC}"
echo -e "${BLUE}============================================${NC}"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

# 1. Check service status
echo -e "\n${GREEN}Checking service status...${NC}"
if $IS_MAC; then
    echo -e "${CYAN}Note: Supervisor might not be running on macOS${NC}"
    # Check if running locally with launchd on macOS
    launchctl list | grep apple-subscription || echo -e "${YELLOW}Service not found in launchd${NC}"
else
    supervisorctl status apple-subscription || {
        echo -e "${RED}Supervisor may not be running. Attempting to start...${NC}"
        systemctl start supervisor
        sleep 2
        supervisorctl status apple-subscription
    }
fi

# 2. Check log files
echo -e "\n${GREEN}Checking log files...${NC}"
if [ -f "$LOG_PATH/gunicorn-error.log" ]; then
    echo -e "${YELLOW}Last 20 lines of error log:${NC}"
    tail -n 20 "$LOG_PATH/gunicorn-error.log"
    
    # Check for common error patterns
    echo -e "\n${CYAN}Analyzing logs for common error patterns...${NC}"
    grep -i "error\|exception\|failed\|traceback" "$LOG_PATH/gunicorn-error.log" | tail -n 10
else
    echo -e "${RED}Error log not found at $LOG_PATH/gunicorn-error.log${NC}"
    echo -e "${YELLOW}Creating log directory and files...${NC}"
    mkdir -p "$LOG_PATH"
    touch "$LOG_PATH/gunicorn-error.log"
    touch "$LOG_PATH/gunicorn.log"
    
    if $IS_MAC; then
        chown -R $(whoami) "$LOG_PATH"
    else
        chown -R "$APP_USER":"$APP_USER" "$LOG_PATH"
    fi
    chmod -R 755 "$LOG_PATH"
fi

# 2.1 Check system journal for relevant errors
echo -e "\n${GREEN}Checking system journal for service errors...${NC}"
if ! $IS_MAC; then
    journalctl -u supervisor --no-pager | grep -i "apple-subscription\|error" | tail -n 10
    journalctl -u nginx --no-pager | grep -i "error\|failed" | tail -n 10
else
    echo -e "${CYAN}Skipping journal check on macOS${NC}"
fi

# 3. Check permissions
echo -e "\n${GREEN}Checking file permissions...${NC}"
ls -la "$DEPLOY_PATH" | head -n 10

# Check critical directories
echo -e "\n${YELLOW}Checking critical directories...${NC}"
for dir in "app" "keys" "venv"; do
    if [ -d "$DEPLOY_PATH/$dir" ]; then
        echo -e "${CYAN}$dir directory exists with permissions:${NC}"
        ls -ld "$DEPLOY_PATH/$dir"
    else
        echo -e "${RED}$dir directory is missing!${NC}"
    fi
done

# 4. Check Python environment
echo -e "\n${GREEN}Checking Python environment...${NC}"
if [ -f "$DEPLOY_PATH/venv/bin/activate" ]; then
    source "$DEPLOY_PATH/venv/bin/activate" || {
        echo -e "${RED}Failed to activate virtual environment${NC}"
        echo -e "${YELLOW}Attempting to recreate virtual environment...${NC}"
        cd "$DEPLOY_PATH"
        rm -rf venv
        python3 -m venv venv
        source venv/bin/activate
        pip install -r requirements.txt
    }
    echo -e "${YELLOW}Python version:${NC}"
    python3 --version

    echo -e "\n${YELLOW}Installed packages:${NC}"
    pip list | grep -E "fastapi|uvicorn|gunicorn|psycopg2"
    
    # Check for missing dependencies
    echo -e "\n${YELLOW}Checking for missing dependencies...${NC}"
    for pkg in "fastapi" "uvicorn" "gunicorn" "psycopg2-binary"; do
        if ! pip list | grep -q "$pkg"; then
            echo -e "${RED}Missing package: $pkg. Installing...${NC}"
            pip install "$pkg"
        fi
    done
else
    echo -e "${RED}Virtual environment not found. Creating a new one...${NC}"
    cd "$DEPLOY_PATH"
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
fi

# 5. Check .env file
echo -e "\n${GREEN}Checking environment configuration...${NC}"
if [ -f "$DEPLOY_PATH/.env" ]; then
    echo -e "${YELLOW}Found .env file. Checking required variables:${NC}"
    # Check for required environment variables without showing sensitive data
    for var in "DATABASE_URL" "APNS_KEY_ID" "APNS_TEAM_ID" "SECRET_KEY"; do
        if grep -q "^$var=" "$DEPLOY_PATH/.env"; then
            echo -e "${CYAN}✓ $var is set${NC}"
        else
            echo -e "${RED}✗ $var is missing${NC}"
        fi
    done
else
    echo -e "${RED}.env file not found. Creating from example...${NC}"
    if [ -f "$DEPLOY_PATH/example.env" ]; then
        cp "$DEPLOY_PATH/example.env" "$DEPLOY_PATH/.env"
        echo -e "${YELLOW}Created .env file from example. Please update with actual values${NC}"
    else
        echo -e "${RED}No example.env file found to create .env from${NC}"
    fi
fi

# 6. Test database connection
echo -e "\n${GREEN}Testing database connection...${NC}"
cd "$DEPLOY_PATH"
cat > test_db.py << 'EOL'
try:
    from app.db.session import engine
    from sqlalchemy import text
    
    conn = engine.connect()
    result = conn.execute(text("SELECT 1"))
    print(f"Database connection successful: {result.scalar()}")
    conn.close()
except Exception as e:
    print(f"Database connection error: {str(e)}")
EOL

python3 test_db.py || {
    echo -e "${RED}Database connection test failed${NC}"
    echo -e "${YELLOW}Checking database settings in .env file...${NC}"
    
    if grep -q "DATABASE_URL=" "$DEPLOY_PATH/.env"; then
        DB_URL=$(grep "DATABASE_URL=" "$DEPLOY_PATH/.env" | cut -d'=' -f2-)
        echo -e "Database URL format: ${CYAN}${DB_URL}${NC}"
        
        # Test if DB is SQLite
        if [[ "$DB_URL" == sqlite* ]]; then
            echo -e "${YELLOW}Using SQLite database${NC}"
            DB_FILE=$(echo "$DB_URL" | sed -e 's/sqlite:\/\///g')
            if [ -f "$DB_FILE" ]; then
                echo -e "${CYAN}Database file exists at: $DB_FILE${NC}"
                echo -e "${YELLOW}Testing SQLite database integrity...${NC}"
                if $IS_MAC; then
                    if command -v sqlite3 > /dev/null; then
                        sqlite3 "$DB_FILE" "PRAGMA integrity_check;"
                    else
                        echo -e "${RED}sqlite3 not found. Install with: brew install sqlite${NC}"
                    fi
                else
                    sqlite3 "$DB_FILE" "PRAGMA integrity_check;" || echo -e "${RED}SQLite database may be corrupted${NC}"
                fi
            else
                echo -e "${RED}SQLite database file does not exist: $DB_FILE${NC}"
            fi
        # Test if DB is PostgreSQL
        elif [[ "$DB_URL" == postgresql* ]]; then
            echo -e "${YELLOW}Using PostgreSQL database${NC}"
            if ! $IS_MAC; then
                echo -e "${YELLOW}Checking if PostgreSQL is running...${NC}"
                systemctl status postgresql || {
                    echo -e "${RED}PostgreSQL is not running. Starting...${NC}"
                    systemctl start postgresql
                }
            else
                echo -e "${YELLOW}Checking if PostgreSQL is running on macOS...${NC}"
                pg_isready || echo -e "${RED}PostgreSQL is not running. Start with: brew services start postgresql${NC}"
            fi
        fi
    else
        echo -e "${RED}DATABASE_URL not found in .env file${NC}"
    fi
}

rm -f test_db.py

# 7. Check Apple keys and certificates
echo -e "\n${GREEN}Checking Apple keys and certificates...${NC}"
KEY_DIR="$DEPLOY_PATH/keys"
if [ -d "$KEY_DIR" ]; then
    echo -e "${YELLOW}Keys directory exists. Checking for .p8 files...${NC}"
    P8_COUNT=$(ls "$KEY_DIR"/*.p8 2>/dev/null | wc -l)
    if [ "$P8_COUNT" -gt 0 ]; then
        echo -e "${CYAN}Found $P8_COUNT .p8 key file(s)${NC}"
        ls -l "$KEY_DIR"/*.p8
    else
        echo -e "${RED}No .p8 key files found. These are required for Apple Push Notifications${NC}"
    fi
else
    echo -e "${RED}Keys directory not found. Creating...${NC}"
    mkdir -p "$KEY_DIR"
    if $IS_MAC; then
        chown $(whoami) "$KEY_DIR"
    else
        chown "$APP_USER":"$APP_USER" "$KEY_DIR"
    fi
    chmod 750 "$KEY_DIR"
    echo -e "${YELLOW}Keys directory created at $KEY_DIR. Please add your Apple .p8 key files here${NC}"
fi

# 8. Check app structure
echo -e "\n${GREEN}Checking application structure...${NC}"
for dir in "app/api" "app/models" "app/services"; do
    if [ -d "$DEPLOY_PATH/$dir" ]; then
        echo -e "${CYAN}✓ $dir exists${NC}"
    else
        echo -e "${RED}✗ $dir is missing!${NC}"
    fi
done

if [ -f "$DEPLOY_PATH/main.py" ]; then
    echo -e "${CYAN}✓ main.py exists${NC}"
else
    echo -e "${RED}✗ main.py is missing!${NC}"
fi

# 9. Test direct app startup
echo -e "\n${GREEN}Testing direct application startup...${NC}"
cd "$DEPLOY_PATH"
echo -e "${YELLOW}Checking syntax of main.py...${NC}"
python3 -m py_compile main.py && echo -e "${CYAN}Syntax check passed${NC}" || echo -e "${RED}Syntax error in main.py${NC}"

echo -e "\n${YELLOW}Testing application imports...${NC}"
python3 -c "
import sys
sys.path.insert(0, '${DEPLOY_PATH}')
try:
    from main import app
    print('Successfully imported app from main.py')
except Exception as e:
    print(f'Error importing app: {str(e)}')
"

echo -e "\n${YELLOW}Running application directly with uvicorn (will timeout after 7 seconds)...${NC}"
timeout 7 python3 -m uvicorn main:app --host 127.0.0.1 --port 8080 --no-access-log &
PID=$!
sleep 5
if kill -0 $PID 2>/dev/null; then
    echo -e "${GREEN}Application started successfully${NC}"
    kill $PID
else
    echo -e "${RED}Application failed to start${NC}"
fi

# 10. Fix common issues
echo -e "\n${GREEN}Fixing common issues...${NC}"

# Fix directory permissions
echo -e "${YELLOW}Resetting file permissions...${NC}"
if $IS_MAC; then
    echo -e "${CYAN}Setting ownership to current user on macOS${NC}"
    chown -R $(whoami) "$DEPLOY_PATH"
else
    chown -R "$APP_USER":"$APP_USER" "$DEPLOY_PATH"
fi
chmod -R 750 "$DEPLOY_PATH"

# Ensure log directory exists and is writable
echo -e "${YELLOW}Setting up log directory...${NC}"
mkdir -p "$LOG_PATH"
if $IS_MAC; then
    chown -R $(whoami) "$LOG_PATH"
else
    chown -R "$APP_USER":"$APP_USER" "$LOG_PATH"
fi
chmod -R 755 "$LOG_PATH"

# Create database tables if they don't exist
echo -e "${YELLOW}Ensuring database tables are created...${NC}"
cd "$DEPLOY_PATH"
source venv/bin/activate
python3 -c "
try:
    from app.db.session import create_tables
    create_tables()
    print('Database tables created or verified successfully')
except Exception as e:
    print(f'Error creating database tables: {str(e)}')
"

# 11. Check and fix supervisor configuration
echo -e "\n${GREEN}Checking supervisor configuration...${NC}"
if ! $IS_MAC; then
    SUPERVISOR_CONF="/etc/supervisor/conf.d/apple-subscription.conf"
    if [ -f "$SUPERVISOR_CONF" ]; then
        echo -e "${YELLOW}Supervisor config exists. Ensuring it's correctly configured...${NC}"
        cat > "$SUPERVISOR_CONF" << EOL
[program:apple-subscription]
directory=${DEPLOY_PATH}
command=${DEPLOY_PATH}/venv/bin/gunicorn -w 2 -k uvicorn.workers.UvicornWorker main:app --bind 127.0.0.1:8000 --log-level debug --timeout 120
user=${APP_USER}
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
stdout_logfile=${LOG_PATH}/gunicorn.log
stderr_logfile=${LOG_PATH}/gunicorn-error.log
redirect_stderr=true
startretries=10
startsecs=10
environment=PYTHONPATH="${DEPLOY_PATH}",PATH="${DEPLOY_PATH}/venv/bin:%(ENV_PATH)s",PYTHONUNBUFFERED="1"
EOL
        echo -e "${CYAN}Supervisor config updated${NC}"
    else
        echo -e "${RED}Supervisor config not found. Creating...${NC}"
        cat > "$SUPERVISOR_CONF" << EOL
[program:apple-subscription]
directory=${DEPLOY_PATH}
command=${DEPLOY_PATH}/venv/bin/gunicorn -w 2 -k uvicorn.workers.UvicornWorker main:app --bind 127.0.0.1:8000 --log-level debug --timeout 120
user=${APP_USER}
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
stdout_logfile=${LOG_PATH}/gunicorn.log
stderr_logfile=${LOG_PATH}/gunicorn-error.log
redirect_stderr=true
startretries=10
startsecs=10
environment=PYTHONPATH="${DEPLOY_PATH}",PATH="${DEPLOY_PATH}/venv/bin:%(ENV_PATH)s",PYTHONUNBUFFERED="1"
EOL
        echo -e "${CYAN}Supervisor config created${NC}"
    fi
    
    # Restart services
    echo -e "\n${GREEN}Restarting services...${NC}"
    supervisorctl reread
    supervisorctl update
    supervisorctl restart apple-subscription
    sleep 5
    
    systemctl is-active nginx >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        systemctl restart nginx
    else
        echo -e "${RED}Nginx is not active. Skipping restart.${NC}"
    fi
else
    echo -e "${CYAN}Skipping supervisor setup on macOS.${NC}"
    echo -e "${YELLOW}For macOS, consider using launchd or running the app directly:${NC}"
    echo -e "cd $DEPLOY_PATH && source venv/bin/activate && uvicorn main:app --reload"
fi

# 12. Check if service is running and test endpoints
echo -e "\n${GREEN}Checking if service is running now...${NC}"
if ! $IS_MAC; then
    supervisorctl status apple-subscription
    
    # Test local endpoints
    echo -e "\n${YELLOW}Testing local API endpoints...${NC}"
    echo -e "${CYAN}Health endpoint:${NC}"
    curl -s http://localhost:8000/health || echo -e "${RED}Health endpoint not available${NC}"
    
    echo -e "\n${CYAN}API test connection:${NC}"
    curl -s http://localhost:8000/api/v1/test-connection || echo -e "${RED}Test connection endpoint not available${NC}"
    
    # Check ports
    echo -e "\n${YELLOW}Checking port usage...${NC}"
    netstat -tulpn | grep -E "8000|8080" || echo -e "${RED}No service detected on standard ports${NC}"
else
    echo -e "${CYAN}Testing local endpoints on macOS...${NC}"
    # Try various ports in case the app is running on a non-standard port
    for port in 8000 8080 5000; do
        echo -e "${YELLOW}Trying port $port...${NC}"
        curl -s "http://localhost:$port/health" && {
            echo -e "${GREEN}Service found running on port $port!${NC}"
            break
        } || echo -e "${RED}No service on port $port${NC}"
    done
fi

# 13. Create a log summary
echo -e "\n${GREEN}Creating troubleshooting summary...${NC}"
SUMMARY_FILE="$DEPLOY_PATH/troubleshoot_summary.log"
{
    echo "===========================================" 
    echo " Apple Subscription Service Troubleshooting" 
    echo " $(date)" 
    echo "===========================================" 
    echo
    echo "System: $(uname -a)"
    
    echo
    echo "Python version: $(python3 --version 2>&1)"
    
    echo
    echo "Service status:"
    if ! $IS_MAC; then
        supervisorctl status apple-subscription 2>&1
    else
        echo "Running on macOS - supervisor not used"
    fi
    
    echo
    echo "Database connection:"
    cd "$DEPLOY_PATH" && source venv/bin/activate && python3 -c "
try:
    from app.db.session import engine
    from sqlalchemy import text
    conn = engine.connect()
    result = conn.execute(text('SELECT 1'))
    print(f'Connected: {result.scalar() == 1}')
    conn.close()
except Exception as e:
    print(f'Failed: {str(e)}')
" 2>&1
    
    echo
    echo "File permissions:"
    ls -la "$DEPLOY_PATH" | head -n 5
    
    echo
    echo "Last 5 errors from log:"
    if [ -f "$LOG_PATH/gunicorn-error.log" ]; then
        grep -i "error\|exception" "$LOG_PATH/gunicorn-error.log" | tail -n 5
    else
        echo "No error log found"
    fi
} > "$SUMMARY_FILE"

echo -e "${CYAN}Summary saved to: $SUMMARY_FILE${NC}"

echo -e "\n${BLUE}============================================${NC}"
echo -e "${GREEN}Troubleshooting completed!${NC}"
echo -e "${BLUE}============================================${NC}"
echo -e "Next steps:"

if $IS_MAC; then
    echo -e "\n${YELLOW}For macOS development environment:${NC}"
    echo -e "1. Run the app locally: ${BLUE}cd $DEPLOY_PATH && source venv/bin/activate && uvicorn main:app --reload${NC}"
    echo -e "2. Test the API: ${BLUE}curl http://localhost:8000/health${NC}"
    echo -e "3. Test connection: ${BLUE}curl http://localhost:8000/api/v1/test-connection${NC}"
    echo -e "4. Check the logs in: ${BLUE}$LOG_PATH/gunicorn-error.log${NC}"
else
    echo -e "\n${YELLOW}For production environment:${NC}"
    echo -e "1. Test the API: ${BLUE}curl https://apple.safeprovpn.com/health${NC}"
    echo -e "2. Check connection: ${BLUE}curl https://apple.safeprovpn.com/api/v1/test-connection${NC}"
    echo -e "3. Check supervisor logs: ${BLUE}supervisorctl tail -f apple-subscription${NC}"
    echo -e "4. Check system logs: ${BLUE}journalctl -u supervisor${NC}"
    echo -e "5. Check NGINX logs: ${BLUE}tail -f /var/log/nginx/error.log${NC}"
fi

# Display common troubleshooting tips
echo -e "\n${YELLOW}Common troubleshooting tips:${NC}"
echo -e "1. Database issues: Check connection string in .env file"
echo -e "2. Permission issues: Ensure $APP_USER has access to all files"
echo -e "3. Apple certificate problems: Verify .p8 files in keys directory"
echo -e "4. Port conflicts: Make sure no other service is using ports 8000/8080"
echo -e "5. Missing dependencies: Check requirements.txt and reinstall if needed"

echo -e "\n${BLUE}============================================${NC}"
