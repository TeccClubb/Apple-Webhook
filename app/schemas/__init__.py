"""
Schemas package initialization.
"""
from app.schemas.base import BaseSchema
from app.schemas.token import Token, TokenData

# Import subscription first to avoid circular imports
from app.schemas.subscription import (
    Subscription,
    SubscriptionCreate,
    SubscriptionUpdate,
    SubscriptionStatus,
    NotificationHistory,
    NotificationHistoryCreate,
    AppleNotificationPayload,
    AppleNotificationResponse,
)

# Then import user which may reference subscription
from app.schemas.user import User, UserCreate, UserUpdate, UserInDB, UserWithSubscriptions

__all__ = [
    "BaseSchema",
    "User",
    "UserCreate",
    "UserUpdate",
    "UserInDB",
    "UserWithSubscriptions",
    "Token",
    "TokenData",
    "Subscription",
    "SubscriptionCreate",
    "SubscriptionUpdate",
    "SubscriptionStatus",
    "NotificationHistory",
    "NotificationHistoryCreate",
    "AppleNotificationPayload",
    "AppleNotificationResponse",
]
