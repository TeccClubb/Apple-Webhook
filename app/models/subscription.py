"""
Subscription models module.
Defines models related to Apple App Store subscriptions.
"""
import enum
from sqlalchemy import Column, String, ForeignKey, Enum, DateTime, JSON, Boolean, Text

from app.db.custom_types import SQLiteUUID
from sqlalchemy.orm import relationship
from datetime import datetime

from app.models.base import BaseModel


class SubscriptionStatus(str, enum.Enum):
    """Subscription status enum."""
    ACTIVE = "ACTIVE"
    EXPIRED = "EXPIRED"
    IN_GRACE_PERIOD = "IN_GRACE_PERIOD"
    IN_BILLING_RETRY = "IN_BILLING_RETRY"
    REVOKED = "REVOKED"
    REFUNDED = "REFUNDED"


class NotificationType(str, enum.Enum):
    """
    Apple App Store server notification types.
    Based on Apple's App Store Server Notifications v2.
    """
    SUBSCRIBED = "SUBSCRIBED"
    DID_CHANGE_RENEWAL_PREF = "DID_CHANGE_RENEWAL_PREF"
    DID_CHANGE_RENEWAL_STATUS = "DID_CHANGE_RENEWAL_STATUS"
    OFFER_REDEEMED = "OFFER_REDEEMED"
    DID_RENEW = "DID_RENEW"
    EXPIRED = "EXPIRED"
    DID_FAIL_TO_RENEW = "DID_FAIL_TO_RENEW"
    GRACE_PERIOD_EXPIRED = "GRACE_PERIOD_EXPIRED"
    PRICE_INCREASE = "PRICE_INCREASE"
    REFUND = "REFUND"
    REFUND_DECLINED = "REFUND_DECLINED"
    CONSUMPTION_REQUEST = "CONSUMPTION_REQUEST"
    RENEWAL_EXTENDED = "RENEWAL_EXTENDED"
    REVOKE = "REVOKE"
    TEST = "TEST"


class Subscription(BaseModel):
    """
    Subscription model for storing subscription information.
    """
    __tablename__ = "subscriptions"
    
    user_id = Column(SQLiteUUID, ForeignKey("users.id"), nullable=False)
    original_transaction_id = Column(String, unique=True, index=True, nullable=False)
    product_id = Column(String, nullable=False)
    status = Column(Enum(SubscriptionStatus), nullable=False)
    expires_date = Column(DateTime)
    purchase_date = Column(DateTime, nullable=False)
    auto_renew_status = Column(Boolean, default=False)
    environment = Column(String, default="Production")
    
    # Store raw JSON data for flexibility
    raw_data = Column(JSON)
    
    # Relationships
    user = relationship("User", back_populates="subscriptions")
    notifications = relationship("NotificationHistory", back_populates="subscription", cascade="all, delete-orphan")
    
    def __repr__(self):
        return f"<Subscription {self.original_transaction_id}>"


class NotificationHistory(BaseModel):
    """
    Model for storing notification history from Apple.
    """
    __tablename__ = "notification_history"
    
    subscription_id = Column(SQLiteUUID, ForeignKey("subscriptions.id"), nullable=False)
    notification_type = Column(Enum(NotificationType), nullable=False)
    subtype = Column(String)
    notification_uuid = Column(String, unique=True, index=True, nullable=False)
    signed_payload = Column(Text, nullable=False)
    processed = Column(Boolean, default=False)
    processing_error = Column(Text)
    
    # Store raw JSON data for flexibility
    raw_data = Column(JSON)
    
    # Relationships
    subscription = relationship("Subscription", back_populates="notifications")
    
    def __repr__(self):
        return f"<NotificationHistory {self.notification_uuid}>"
