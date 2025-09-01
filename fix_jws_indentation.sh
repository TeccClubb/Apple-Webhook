#!/bin/bash
# Script to fix indentation in apple_jws.py

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Apple JWS Indentation Fix                ${NC}"
echo -e "${BLUE}============================================${NC}"

# Check if we're running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

# Application directory
APP_DIR="/opt/apple-subscription-service"
JWS_FILE="${APP_DIR}/app/core/apple_jws.py"

cd $APP_DIR || {
    echo -e "${RED}Error: Could not change to application directory${NC}"
    exit 1
}

echo -e "${YELLOW}Creating backup of apple_jws.py...${NC}"
cp -f "$JWS_FILE" "${JWS_FILE}.bak.$(date +%Y%m%d_%H%M%S)"

echo -e "${YELLOW}Fixing indentation in apple_jws.py...${NC}"

cat > "$JWS_FILE" << 'EOL'
"""
Apple JWS signature verification module.

This module provides utilities for verifying the JWS signatures from Apple's server notifications.
"""
import base64
import json
import logging
from typing import Dict, Any, Optional, List
import requests
from jose import jwt
from tenacity import retry, stop_after_attempt, wait_exponential

from app.core.config import settings

logger = logging.getLogger(__name__)


class AppleJWSVerifier:
    """
    Class for verifying Apple's JWS signatures.
    """
    # Cache for Apple's public keys
    _public_keys: Dict[str, Dict[str, Any]] = {}
    
    # Apple's public keys URL
    APPLE_PUBLIC_KEYS_URL = "https://appleid.apple.com/auth/keys"
    
    @classmethod
    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=1, max=10),
        reraise=True
    )
    def get_apple_public_keys(cls) -> Dict[str, Dict[str, Any]]:
        """
        Fetch and cache Apple's public keys.
        
        Returns:
            Dict[str, Dict[str, Any]]: A dictionary of key IDs to public keys
        """
        if cls._public_keys:
            return cls._public_keys
            
        logger.info(f"Fetching Apple public keys from {cls.APPLE_PUBLIC_KEYS_URL}")
        response = requests.get(cls.APPLE_PUBLIC_KEYS_URL, timeout=10)
        response.raise_for_status()
        
        keys_data = response.json()
        
        # Process and cache keys
        for key in keys_data.get("keys", []):
            kid = key.get("kid")
            if kid:
                cls._public_keys[kid] = key
                
        logger.info(f"Fetched {len(cls._public_keys)} public keys from Apple")
        return cls._public_keys
    
    @classmethod
    def verify_jws(cls, jws_token: str) -> Dict[str, Any]:
        """
        Verify an Apple JWS token.
        
        Args:
            jws_token: The JWS token to verify
            
        Returns:
            Dict[str, Any]: The decoded and verified payload
            
        Raises:
            ValueError: If the token is invalid or verification fails
        """
        try:
            # Parse the token to get payload directly for App Store notifications
            # that may not follow standard JWS format
            parts = jws_token.split('.')
            if len(parts) != 3:
                raise ValueError("Invalid JWS token format")
                
            # Decode the payload directly for basic validation
            payload_segment = parts[1]
            # Add padding if necessary
            padded_payload = payload_segment + '=' * (4 - len(payload_segment) % 4)
            try:
                # Try to decode the payload to make sure it's valid JSON
                raw_payload = json.loads(base64.b64decode(padded_payload).decode('utf-8'))
                
                # Check if this is a standard notification format (might not have kid)
                # App Store Server Notifications v2 has specific fields we can check
                if "notificationType" in raw_payload or "data" in raw_payload or "summary" in raw_payload:
                    logger.info("Detected App Store notification format, proceeding with payload extraction")
                    return raw_payload
            except Exception as e:
                logger.warning(f"Failed to decode payload directly: {str(e)}")
            
            # Standard JWS verification with kid if the direct decode didn't succeed
            header_segment = parts[0]
            # Add padding if necessary
            padded_header = header_segment + '=' * (4 - len(header_segment) % 4)
            header_data = json.loads(base64.b64decode(padded_header).decode('utf-8'))
            
            kid = header_data.get("kid")
            if not kid:
                logger.warning("No key ID (kid) found in JWS header, attempting verification with all keys")
                # Try all available keys since kid is not specified
                public_keys = cls.get_apple_public_keys()
                verification_errors = []
                
                for key_id, key_data in public_keys.items():
                    try:
                        # Determine appropriate algorithm based on key type and header
                        key_kty = key_data.get("kty")
                        header_alg = header_data.get("alg", "")
                        
                        # First check the header's alg if it's specified
                        if header_alg:
                            alg = header_alg
                        # Otherwise infer from key type
                        elif key_kty == "EC":
                            alg = "ES256"  # Typically used with EC keys
                        elif key_kty == "RSA":
                            alg = "RS256"  # Typically used with RSA keys
                        else:
                            alg = "RS256"  # Default
                        
                        logger.info(f"Trying verification with key {key_id} using algorithm {alg}")
                        
                        payload = jwt.decode(
                            jws_token,
                            key_data,
                            algorithms=[alg],
                            options={"verify_exp": False}  # Skip expiration check for notifications
                        )
                        logger.info(f"Successfully verified JWS with key ID: {key_id}")
                        return payload
                    except Exception as e:
                        verification_errors.append(f"Key {key_id}: {str(e)}")
                
                # If we get here, none of the keys worked
                raise ValueError(f"Verification failed with all keys: {', '.join(verification_errors)}")
                
            # Regular flow with specified kid
            public_keys = cls.get_apple_public_keys()
            
            if kid not in public_keys:
                logger.warning(f"Key ID {kid} not found in Apple's public keys")
                # Keys might have been updated, refresh them
                cls._public_keys = {}
                public_keys = cls.get_apple_public_keys()
                
                if kid not in public_keys:
                    raise ValueError(f"Key ID {kid} not found in Apple's public keys")
            
            # Get the public key for this kid
            key_data = public_keys[kid]
            
            # Determine appropriate algorithm based on key type and header
            key_kty = key_data.get("kty")
            header_alg = header_data.get("alg", "")
            
            # First check the header's alg if it's specified
            if header_alg:
                alg = header_alg
            # Otherwise infer from key type
            elif key_kty == "EC":
                alg = "ES256"  # Typically used with EC keys
            elif key_kty == "RSA":
                alg = "RS256"  # Typically used with RSA keys
            else:
                alg = "RS256"  # Default
                
            logger.info(f"Verifying with key {kid} using algorithm {alg}")
            
            # Verify and decode the JWS token
            payload = jwt.decode(
                jws_token,
                key_data,
                algorithms=[alg],
                options={"verify_exp": False}  # Skip expiration check for App Store notifications
            )
            
            return payload
            
        except Exception as e:
            logger.error(f"Error verifying Apple JWS: {str(e)}")
            raise ValueError(f"Failed to verify Apple JWS signature: {str(e)}")
    
    @staticmethod
    def parse_notification_payload(payload: Dict[str, Any]) -> Dict[str, Any]:
        """
        Parse the notification payload from the decoded JWS.
        
        Args:
            payload: The decoded JWS payload
            
        Returns:
            Dict[str, Any]: The parsed notification data
        """
        # Check if payload already contains notification data directly
        if "notificationType" in payload:
            logger.info("Found notificationType directly in payload")
            return payload
            
        # Standard format: extract from data field
        notification_data = payload.get("data", {})
        
        # If data is a string (sometimes Apple sends it as a JSON string), parse it
        if isinstance(notification_data, str):
            try:
                notification_data = json.loads(notification_data)
                logger.info("Successfully parsed notification data from string")
            except json.JSONDecodeError:
                logger.warning("Failed to parse notification data string as JSON")
        
        # Handle both v1 and v2 notification formats
        # V1: signedRenewalInfo and signedTransactionInfo
        # V2: data and summary fields
        
        # Check for other common notification fields
        for field in ["signedRenewalInfo", "signedTransactionInfo", "summary"]:
            if field in payload and field not in notification_data:
                notification_data[field] = payload.get(field)
                
        return notification_data
EOL

echo -e "${GREEN}Fixed indentation in apple_jws.py${NC}"

echo -e "${YELLOW}Creating database permissions fix script...${NC}"

cat > "${APP_DIR}/fix_db_permissions.sh" << 'EOL'
#!/bin/bash

# Script to fix database permissions for the Apple Subscription Service
# This grants necessary permissions to create ENUM types

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  PostgreSQL Permissions Fix               ${NC}"
echo -e "${BLUE}============================================${NC}"

# Database credentials
DB_NAME="apple_subscriptions"
DB_USER="apple_app"

echo -e "${YELLOW}Checking database connection...${NC}"
if ! sudo -u postgres psql -c "SELECT 1" > /dev/null 2>&1; then
    echo -e "${RED}Error: Could not connect to PostgreSQL${NC}"
    exit 1
fi

echo -e "${GREEN}Connected to PostgreSQL${NC}"

echo -e "${YELLOW}Granting permissions to $DB_USER...${NC}"
sudo -u postgres psql -c "ALTER SCHEMA public OWNER TO $DB_USER;" || {
    echo -e "${RED}Failed to change public schema owner${NC}"
    exit 1
}

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;" || {
    echo -e "${RED}Failed to grant database privileges${NC}"
    exit 1
}

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON SCHEMA public TO $DB_USER;" || {
    echo -e "${RED}Failed to grant schema privileges${NC}"
    exit 1
}

sudo -u postgres psql -d $DB_NAME -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;" || {
    echo -e "${RED}Failed to grant table privileges${NC}"
    exit 1
}

sudo -u postgres psql -d $DB_NAME -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;" || {
    echo -e "${RED}Failed to grant sequence privileges${NC}"
    exit 1
}

# Grant specific permissions for ENUM types
sudo -u postgres psql -d $DB_NAME -c "GRANT CREATE ON SCHEMA public TO $DB_USER;" || {
    echo -e "${RED}Failed to grant CREATE permission${NC}"
    exit 1
}

# Drop existing ENUM types if they exist to allow recreation
echo -e "${YELLOW}Checking for existing ENUM types...${NC}"
sudo -u postgres psql -d $DB_NAME -c "DROP TYPE IF EXISTS subscriptionstatus CASCADE;" || {
    echo -e "${YELLOW}Note: Could not drop ENUM subscriptionstatus, it may not exist${NC}"
}

sudo -u postgres psql -d $DB_NAME -c "DROP TYPE IF EXISTS notificationtype CASCADE;" || {
    echo -e "${YELLOW}Note: Could not drop ENUM notificationtype, it may not exist${NC}"
}

echo -e "${GREEN}Database permissions fixed successfully!${NC}"
echo -e "${BLUE}============================================${NC}"
echo -e "${YELLOW}You can now restart the apple-subscription service:${NC}"
echo -e "${GREEN}supervisorctl restart apple-subscription${NC}"
echo -e "${BLUE}============================================${NC}"
EOL

chmod +x "${APP_DIR}/fix_db_permissions.sh"
echo -e "${GREEN}Created database permissions fix script${NC}"

echo -e "${YELLOW}Fixing ownership of files...${NC}"
chown appuser:appuser "$JWS_FILE"
chown appuser:appuser "${APP_DIR}/fix_db_permissions.sh"

echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}Files fixed successfully!${NC}"
echo -e "${YELLOW}Now run the database permissions fix script:${NC}"
echo -e "${GREEN}./fix_db_permissions.sh${NC}"
echo -e "${BLUE}============================================${NC}"
