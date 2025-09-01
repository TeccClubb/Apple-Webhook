"""
Apple notification processor module.

Processes Apple App Store Server Notifications and updates subscription data.
"""
import logging
import uuid
import json
import base64
from typing import Dict, Any, Optional
from datetime import datetime
from sqlalchemy.orm import Session

from app.core.apple_jws import AppleJWSVerifier
from app.models.subscription import (
    Subscription,
    NotificationHistory,
    SubscriptionStatus as SubscriptionStatusEnum,
    NotificationType
)
from app.models.user import User
from app.services.subscription_service import SubscriptionService

logger = logging.getLogger(__name__)


class NotificationProcessor:
    """
    Service for processing Apple App Store Server Notifications.
    """
    
    def __init__(self, db: Session):
        """
        Initialize the notification processor.
        
        Args:
            db: Database session
        """
        self.db = db
        self.subscription_service = SubscriptionService(db)
    
    async def process_notification(
        self,
        signed_payload: str,
        decoded_payload: Dict[str, Any]
    ) -> None:
        """
        Process an Apple App Store Server Notification.
        
        Args:
            signed_payload: The raw signed JWS payload
            decoded_payload: The decoded payload
            
        Returns:
            None
        """
        try:
            # Extract notification data
            notification_type = self._get_notification_type(decoded_payload)
            notification_uuid = decoded_payload.get("notificationUUID")
            subtype = decoded_payload.get("subtype")
            
            if not notification_uuid:
                logger.error("Missing notificationUUID in payload")
                return
                
            # Check for duplicate notifications
            existing_notification = self.db.query(NotificationHistory).filter(
                NotificationHistory.notification_uuid == notification_uuid
            ).first()
            
            if existing_notification:
                logger.info(f"Duplicate notification received: {notification_uuid}")
                return
                
            # Get or create subscription
            subscription = await self._get_or_create_subscription(decoded_payload)
            
            if not subscription:
                logger.error("Failed to get or create subscription for notification")
                return
                
            # Record notification history
            notification = NotificationHistory(
                subscription_id=subscription.id,
                notification_type=notification_type,
                subtype=subtype,
                notification_uuid=notification_uuid,
                signed_payload=signed_payload,
                raw_data=decoded_payload,
                processed=True
            )
            
            self.db.add(notification)
            
            # Update subscription based on notification type
            await self._update_subscription_status(subscription, notification_type, decoded_payload)
            
            # Commit changes
            self.db.commit()
            logger.info(f"Processed {notification_type} notification: {notification_uuid}")
            
        except Exception as e:
            self.db.rollback()
            logger.error(f"Error processing notification: {str(e)}")
    
    async def _get_or_create_subscription(
        self,
        payload: Dict[str, Any]
    ) -> Optional[Subscription]:
        """
        Get or create a subscription from notification payload.
        
        Args:
            payload: The notification payload
            
        Returns:
            Optional[Subscription]: The subscription, or None if it couldn't be created
        """
        try:
            # Extract transaction data
            transaction_info = self._extract_transaction_info(payload)
            
            if not transaction_info:
                logger.error("No transaction info found in notification payload")
                return None
                
            original_transaction_id = transaction_info.get("originalTransactionId")
            
            if not original_transaction_id:
                logger.error("No originalTransactionId found in transaction info")
                return None
                
            # Try to find existing subscription
            subscription = await self.subscription_service.get_subscription_by_original_transaction_id(
                original_transaction_id
            )
            
            if subscription:
                return subscription
                
            # Subscription doesn't exist yet, create it
            # We need to find or create a user for this subscription
            # In a real app, you'd have a way to map Apple's transaction data to your users
            # For this example, we'll use a demo user or create one if needed
            
            # Try to find a demo user or create one
            user = self.db.query(User).first()
            if not user:
                # Create a demo user if none exists
                # In a real app, you'd have proper user management
                from app.core.security import get_password_hash
                user = User(
                    email="demo@example.com",
                    hashed_password=get_password_hash("demopassword"),
                    full_name="Demo User"
                )
                self.db.add(user)
                self.db.commit()
                self.db.refresh(user)
                logger.info("Created demo user for subscription")
            
            # Create subscription data
            product_id = transaction_info.get("productId", "unknown_product")
            purchase_date_ms = transaction_info.get("purchaseDate")
            expires_date_ms = transaction_info.get("expiresDate")
            
            purchase_date = datetime.utcfromtimestamp(purchase_date_ms / 1000) if purchase_date_ms else datetime.utcnow()
            expires_date = datetime.utcfromtimestamp(expires_date_ms / 1000) if expires_date_ms else None
            
            auto_renew_status = self._extract_auto_renew_status(payload)
            environment = payload.get("environment", "Production")
            
            subscription_data = {
                "user_id": user.id,
                "original_transaction_id": original_transaction_id,
                "product_id": product_id,
                "status": SubscriptionStatusEnum.ACTIVE,  # Default to active, will be updated based on notification
                "purchase_date": purchase_date,
                "expires_date": expires_date,
                "auto_renew_status": auto_renew_status,
                "environment": environment,
                "raw_data": transaction_info
            }
            
            # Create the subscription
            return await self.subscription_service.create_subscription(subscription_data)
            
        except Exception as e:
            logger.error(f"Error getting or creating subscription: {str(e)}")
            return None
    
    async def _update_subscription_status(
        self,
        subscription: Subscription,
        notification_type: NotificationType,
        payload: Dict[str, Any]
    ) -> None:
        """
        Update subscription status based on notification type.
        
        Args:
            subscription: The subscription to update
            notification_type: The notification type
            payload: The notification payload
            
        Returns:
            None
        """
        subscription_data = {}
        
        # Update status based on notification type
        if notification_type == NotificationType.SUBSCRIBED:
            subscription_data["status"] = SubscriptionStatusEnum.ACTIVE
            
        elif notification_type == NotificationType.DID_RENEW:
            subscription_data["status"] = SubscriptionStatusEnum.ACTIVE
            
            # Update expiration date from payload
            expires_date_ms = self._extract_expires_date(payload)
            if expires_date_ms:
                subscription_data["expires_date"] = datetime.utcfromtimestamp(expires_date_ms / 1000)
            
        elif notification_type == NotificationType.DID_FAIL_TO_RENEW:
            # If auto-renew failed, but still in grace period
            if payload.get("subtype") == "GRACE_PERIOD":
                subscription_data["status"] = SubscriptionStatusEnum.IN_GRACE_PERIOD
            else:
                subscription_data["status"] = SubscriptionStatusEnum.IN_BILLING_RETRY
            
        elif notification_type == NotificationType.EXPIRED:
            subscription_data["status"] = SubscriptionStatusEnum.EXPIRED
            
        elif notification_type == NotificationType.GRACE_PERIOD_EXPIRED:
            subscription_data["status"] = SubscriptionStatusEnum.EXPIRED
            
        elif notification_type == NotificationType.REFUND:
            subscription_data["status"] = SubscriptionStatusEnum.REFUNDED
            
        elif notification_type == NotificationType.REVOKE:
            subscription_data["status"] = SubscriptionStatusEnum.REVOKED
            
        # Update auto-renew status from payload
        auto_renew_status = self._extract_auto_renew_status(payload)
        if auto_renew_status is not None:
            subscription_data["auto_renew_status"] = auto_renew_status
            
        # Update the subscription if we have changes
        if subscription_data:
            await self.subscription_service.update_subscription(
                subscription.id,
                subscription_data
            )
    
    def _get_notification_type(self, payload: Dict[str, Any]) -> NotificationType:
        """
        Extract notification type from payload.
        
        Args:
            payload: The notification payload
            
        Returns:
            NotificationType: The notification type
        """
        type_str = payload.get("notificationType")
        
        try:
            return NotificationType(type_str) if type_str else NotificationType.TEST
        except ValueError:
            logger.warning(f"Unknown notification type: {type_str}, defaulting to TEST")
            return NotificationType.TEST
    
    def _extract_transaction_info(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        """
        Extract transaction info from payload.
        
        Args:
            payload: The notification payload
            
        Returns:
            Dict[str, Any]: The transaction info
        """
        # Try different paths for transaction info
        if "data" in payload and isinstance(payload["data"], dict):
            # Check signedRenewalInfo
            if "signedRenewalInfo" in payload["data"]:
                try:
                    renewal_info = AppleJWSVerifier.verify_jws(payload["data"]["signedRenewalInfo"])
                    if renewal_info and isinstance(renewal_info, dict):
                        return renewal_info
                except Exception as e:
                    logger.warning(f"Error decoding signedRenewalInfo: {str(e)}")
                    # Try extracting the payload directly
                    try:
                        parts = payload["data"]["signedRenewalInfo"].split('.')
                        if len(parts) == 3:  # Valid JWS format
                            payload_segment = parts[1]
                            # Add padding if necessary
                            padded_payload = payload_segment + '=' * (4 - len(payload_segment) % 4)
                            direct_renewal_info = json.loads(base64.b64decode(padded_payload).decode('utf-8'))
                            logger.info("Successfully extracted renewal info by direct decoding")
                            if direct_renewal_info and isinstance(direct_renewal_info, dict):
                                return direct_renewal_info
                    except Exception as e2:
                        logger.warning(f"Failed to extract renewal info directly: {str(e2)}")
            
            # Check signedTransactionInfo
            if "signedTransactionInfo" in payload["data"]:
                try:
                    transaction_info = AppleJWSVerifier.verify_jws(payload["data"]["signedTransactionInfo"])
                    if transaction_info and isinstance(transaction_info, dict):
                        return transaction_info
                except Exception as e:
                    logger.warning(f"Error decoding signedTransactionInfo: {str(e)}")
                    # Try extracting the payload directly
                    try:
                        parts = payload["data"]["signedTransactionInfo"].split('.')
                        if len(parts) == 3:  # Valid JWS format
                            payload_segment = parts[1]
                            # Add padding if necessary
                            padded_payload = payload_segment + '=' * (4 - len(payload_segment) % 4)
                            direct_transaction_info = json.loads(base64.b64decode(padded_payload).decode('utf-8'))
                            logger.info("Successfully extracted transaction info by direct decoding")
                            if direct_transaction_info and isinstance(direct_transaction_info, dict):
                                return direct_transaction_info
                    except Exception as e2:
                        logger.warning(f"Failed to extract transaction info directly: {str(e2)}")
        
        # Fallback to the raw payload if we couldn't extract transaction info
        return payload
    
    def _extract_expires_date(self, payload: Dict[str, Any]) -> Optional[int]:
        """
        Extract expires date from payload.
        
        Args:
            payload: The notification payload
            
        Returns:
            Optional[int]: The expires date in milliseconds since epoch
        """
        transaction_info = self._extract_transaction_info(payload)
        return transaction_info.get("expiresDate")
    
    def _extract_auto_renew_status(self, payload: Dict[str, Any]) -> bool:
        """
        Extract auto renew status from payload.
        
        Args:
            payload: The notification payload
            
        Returns:
            bool: The auto renew status
        """
        transaction_info = self._extract_transaction_info(payload)
        return bool(transaction_info.get("autoRenewStatus", False))
