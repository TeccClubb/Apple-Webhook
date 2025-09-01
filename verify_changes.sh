#!/bin/bash

# Verification script for the Apple JWS and notification handler changes
# Checks if the code changes have been applied correctly

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Apple Notification Handler Verification   ${NC}"
echo -e "${BLUE}============================================${NC}"

# Define key code changes to check for
APPLE_JWS_CHANGES=(
  "key_kty = key_data.get(\"kty\")"
  "if key_kty == \"EC\":"
  "alg = \"ES256\""
  "Detected App Store notification format"
)

WEBHOOK_CHANGES=(
  "import base64"
  "Try to extract payload directly"
)

NOTIFICATION_PROCESSOR_CHANGES=(
  "import base64"
  "direct_renewal_info = json.loads"
  "direct_transaction_info = json.loads"
)

# Check a file for specific changes
check_file() {
  local file=$1
  local changes=("${@:2}")
  local missing=0
  
  if [ ! -f "$file" ]; then
    echo -e "${RED}❌ File not found: $file${NC}"
    return 1
  fi
  
  echo -e "${YELLOW}Checking $file...${NC}"
  
  for change in "${changes[@]}"; do
    if grep -q "$change" "$file"; then
      echo -e "  ${GREEN}✅ Found: $change${NC}"
    else
      echo -e "  ${RED}❌ Missing: $change${NC}"
      missing=$((missing + 1))
    fi
  done
  
  if [ $missing -eq 0 ]; then
    echo -e "${GREEN}All expected changes found in $file${NC}"
    return 0
  else
    echo -e "${RED}Missing $missing expected changes in $file${NC}"
    return 1
  fi
}

# Check if we're in the expected directory structure
if [ ! -d "app/core" ] || [ ! -d "app/services" ]; then
  echo -e "${RED}Error: Not in the correct directory. Please run this script from the project root.${NC}"
  exit 1
fi

# Check files for expected changes
check_file "app/core/apple_jws.py" "${APPLE_JWS_CHANGES[@]}"
APPLE_JWS_OK=$?

check_file "app/api/routes/apple_webhook.py" "${WEBHOOK_CHANGES[@]}"
WEBHOOK_OK=$?

check_file "app/services/notification_processor.py" "${NOTIFICATION_PROCESSOR_CHANGES[@]}"
PROCESSOR_OK=$?

# Summary
echo -e "\n${BLUE}============================================${NC}"
echo -e "${BLUE}  Verification Summary                      ${NC}"
echo -e "${BLUE}============================================${NC}"

if [ $APPLE_JWS_OK -eq 0 ] && [ $WEBHOOK_OK -eq 0 ] && [ $PROCESSOR_OK -eq 0 ]; then
  echo -e "${GREEN}✅ All changes have been successfully implemented!${NC}"
  echo -e "${GREEN}You can deploy the changes with ./restart_service.sh${NC}"
else
  echo -e "${RED}❌ Some changes are missing. Please review the output above.${NC}"
fi

echo -e "\n${BLUE}============================================${NC}"
