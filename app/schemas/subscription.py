"""
Subscription schemas module.
"""
from datetime import datetime
from typing import Dict, Any, Optional, List
from pydantic import BaseModel, Field
import uuid

from app.models.subscription import SubscriptionStatus, NotificationType
from app.schemas.base import BaseSchema


class SubscriptionBase(BaseModel):
    """Base subscription schema."""
    product_id: str
    status: SubscriptionStatus
    expires_date: Optional[datetime] = None
    purchase_date: datetime
    auto_renew_status: bool = False
    environment: str = "Production"


class SubscriptionCreate(SubscriptionBase):
    """Schema for subscription creation."""
    user_id: uuid.UUID
    original_transaction_id: str


class SubscriptionUpdate(BaseModel):
    """Schema for subscription update."""
    status: Optional[SubscriptionStatus] = None
    expires_date: Optional[datetime] = None
    auto_renew_status: Optional[bool] = None
    raw_data: Optional[Dict[str, Any]] = None


class Subscription(BaseSchema, SubscriptionBase):
    """Schema for subscription response."""
    user_id: uuid.UUID
    original_transaction_id: str
    raw_data: Optional[Dict[str, Any]] = None


class SubscriptionStatus(BaseModel):
    """Schema for subscription status response."""
    user_id: uuid.UUID
    has_active_subscription: bool
    subscriptions: List[Subscription] = []


class NotificationHistoryBase(BaseModel):
    """Base notification history schema."""
    notification_type: NotificationType
    subtype: Optional[str] = None
    notification_uuid: str
    signed_payload: str
    processed: bool = False
    processing_error: Optional[str] = None


class NotificationHistoryCreate(NotificationHistoryBase):
    """Schema for notification history creation."""
    subscription_id: uuid.UUID
    raw_data: Dict[str, Any]


class NotificationHistory(BaseSchema, NotificationHistoryBase):
    """Schema for notification history response."""
    subscription_id: uuid.UUID
    raw_data: Dict[str, Any]


class AppleNotificationPayload(BaseModel):
    """
    Schema for Apple App Store Server Notification payload.
    This represents the root object that Apple sends to the webhook.
    """
    signedPayload: str


class AppleNotificationResponse(BaseModel):
    """
    Schema for response to Apple App Store Server Notification.
    """
    received: bool = True
