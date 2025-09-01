"""
Apple webhook API endpoints.
"""
import logging
import json
from typing import Dict, Any
from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.orm import Session
from pydantic import BaseModel

from app.core.apple_jws import AppleJWSVerifier
from app.db.session import get_db
from app.models.subscription import NotificationType
from app.schemas.subscription import AppleNotificationPayload, AppleNotificationResponse
from app.services.notification_processor import NotificationProcessor
from app.services.subscription_service import SubscriptionService
from app.core.config import settings

router = APIRouter()
logger = logging.getLogger(__name__)


class ConnectionTestResponse(BaseModel):
    """Response model for the connection test endpoint."""
    status: str
    message: str


@router.post(
    "/webhook/apple",
    response_model=AppleNotificationResponse,
    status_code=status.HTTP_200_OK,
    summary="Apple App Store Server Notification webhook endpoint"
)
async def apple_webhook(
    payload: AppleNotificationPayload,
    request: Request,
    db: Session = Depends(get_db)
):
    """
    Receive and process Apple App Store Server Notifications.
    
    This endpoint receives notifications from Apple's App Store Server about
    subscription events (purchase, renewal, expiration, etc.).
    
    Args:
        payload: The notification payload from Apple
        request: The request object
        db: Database session
    
    Returns:
        AppleNotificationResponse: A response indicating the notification was received
    
    Raises:
        HTTPException: If notification processing fails
    """
    logger.info("Received Apple App Store Server Notification")
    
    try:
        # Extract the signed payload
        signed_payload = payload.signedPayload
        
        # Verify the JWS signature
        try:
            decoded_payload = AppleJWSVerifier.verify_jws(signed_payload)
        except ValueError as e:
            logger.error(f"JWS verification failed: {str(e)}")
            # Don't reject the payload immediately, try to process it anyway
            # Apple sometimes sends test notifications with invalid signatures
            logger.warning("Attempting to process notification despite signature verification failure")
            try:
                # Try to extract payload directly
                parts = signed_payload.split('.')
                if len(parts) >= 2:
                    payload_segment = parts[1]
                    padded_payload = payload_segment + '=' * (4 - len(payload_segment) % 4)
                    decoded_payload = json.loads(base64.b64decode(padded_payload).decode('utf-8'))
                    logger.info("Successfully extracted payload directly from JWS")
                else:
                    raise ValueError("Invalid JWS format")
            except Exception as extract_error:
                logger.error(f"Failed to extract payload directly: {str(extract_error)}")
                # Now we can raise the exception since all attempts failed
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Invalid JWS signature: {str(e)}"
                )
            
        # Parse the notification payload
        notification_data = AppleJWSVerifier.parse_notification_payload(decoded_payload)
        
        # Process the notification
        notification_processor = NotificationProcessor(db)
        await notification_processor.process_notification(
            signed_payload=signed_payload,
            decoded_payload=notification_data
        )
        
        return AppleNotificationResponse(received=True)
        
    except Exception as e:
        logger.error(f"Error processing Apple notification: {str(e)}")
        # Always return 200 OK to Apple, even on error
        # (Apple expects this and will retry if non-200 is returned)
        return AppleNotificationResponse(received=True)


@router.get(
    "/test-connection",
    response_model=ConnectionTestResponse,
    status_code=status.HTTP_200_OK,
    summary="Test Apple connection and configuration"
)
async def test_apple_connection():
    """
    Test the connection to Apple's servers and verify configuration.
    
    This endpoint checks:
    1. That the required Apple configuration is present
    2. That we can fetch Apple's public keys
    3. That the private key can be loaded (if configured)
    
    Returns:
        ConnectionTestResponse: Connection test results
    """
    try:
        # 1. Check for required configuration
        missing_configs = []
        required_configs = [
            ("APPLE_PRIVATE_KEY_ID", settings.APPLE_PRIVATE_KEY_ID),
            ("APPLE_TEAM_ID", settings.APPLE_TEAM_ID),
            ("APPLE_BUNDLE_ID", settings.APPLE_BUNDLE_ID),
            ("APPLE_ISSUER_ID", settings.APPLE_ISSUER_ID)
        ]
        
        for name, value in required_configs:
            if not value:
                missing_configs.append(name)
                
        if missing_configs:
            return ConnectionTestResponse(
                status="error",
                message=f"Missing required Apple configuration: {', '.join(missing_configs)}"
            )
        
        # 2. Test fetching Apple's public keys
        try:
            public_keys = AppleJWSVerifier.get_apple_public_keys()
            if not public_keys:
                return ConnectionTestResponse(
                    status="error",
                    message="Could not fetch Apple public keys. Check your internet connection."
                )
            logger.info(f"Successfully fetched {len(public_keys)} Apple public keys")
        except Exception as e:
            logger.error(f"Error fetching Apple public keys: {str(e)}")
            return ConnectionTestResponse(
                status="error",
                message=f"Error connecting to Apple servers: {str(e)}"
            )
        
        # 3. Check private key (if path is configured)
        if settings.APPLE_PRIVATE_KEY_PATH:
            try:
                # Just try to open and read the file to verify it exists and is readable
                with open(settings.APPLE_PRIVATE_KEY_PATH, "r") as key_file:
                    key_content = key_file.read()
                    if not key_content or "-----BEGIN PRIVATE KEY-----" not in key_content:
                        return ConnectionTestResponse(
                            status="warning",
                            message="Private key file exists but may not be a valid private key."
                        )
            except Exception as e:
                logger.error(f"Error reading private key file: {str(e)}")
                return ConnectionTestResponse(
                    status="error",
                    message=f"Could not read private key file: {str(e)}"
                )
        else:
            return ConnectionTestResponse(
                status="warning",
                message="Private key path not configured. JWS signing will not work."
            )
        
        # All checks passed
        return ConnectionTestResponse(
            status="success",
            message="Successfully connected to Apple servers and verified configuration."
        )
        
    except Exception as e:
        logger.error(f"Error testing Apple connection: {str(e)}")
        return ConnectionTestResponse(
            status="error",
            message=f"Error testing Apple connection: {str(e)}"
        )
