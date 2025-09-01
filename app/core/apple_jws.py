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
            # Parse the token header to get the key ID (kid)
            header_segment = jws_token.split('.')[0]
            # Add padding if necessary
            padded = header_segment + '=' * (4 - len(header_segment) % 4)
            header_data = json.loads(base64.b64decode(padded).decode('utf-8'))
            
            kid = header_data.get("kid")
            if not kid:
                raise ValueError("No key ID (kid) found in JWS header")
                
            # Get Apple's public keys
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
                options={"verify_exp": True}
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
        # Extract and decode the notification payload if it exists
        notification_data = payload.get("data", {})
        
        # Parse any additional fields needed here
        
        return notification_data
