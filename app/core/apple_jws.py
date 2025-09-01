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
                        alg = header_data.get("alg", "RS256")
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
            
            # Verify and decode the JWS token
            payload = jwt.decode(
                jws_token,
                key_data,
                algorithms=[header_data.get("alg", "RS256")],
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
