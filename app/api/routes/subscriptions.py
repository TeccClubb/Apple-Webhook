"""
Subscriptions API endpoints.
"""
import logging
from typing import List
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.security import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.subscription import Subscription, SubscriptionStatus
from app.services.subscription_service import SubscriptionService

router = APIRouter()
logger = logging.getLogger(__name__)


@router.get(
    "/subscriptions/status/{user_id}",
    response_model=SubscriptionStatus,
    status_code=status.HTTP_200_OK,
    summary="Get a user's subscription status",
    description="Returns a user's subscription status and active subscriptions"
)
async def get_subscription_status(
    user_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get a user's subscription status.
    
    Args:
        user_id: The user ID to check
        db: Database session
        current_user: The authenticated user
    
    Returns:
        SubscriptionStatus: The user's subscription status
    
    Raises:
        HTTPException: If user is not found or not authorized
    """
    # Check authorization (only allow users to check their own status or superusers)
    if str(current_user.id) != str(user_id) and not current_user.is_superuser:
        logger.warning(f"Unauthorized access attempt to subscription status for user {user_id}")
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to access this user's subscription data"
        )
    
    subscription_service = SubscriptionService(db)
    return await subscription_service.get_user_subscription_status(user_id)


@router.get(
    "/subscriptions/active/{user_id}",
    response_model=List[Subscription],
    status_code=status.HTTP_200_OK,
    summary="Get a user's active subscriptions",
    description="Returns a list of a user's active subscriptions"
)
async def get_active_subscriptions(
    user_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get a user's active subscriptions.
    
    Args:
        user_id: The user ID to check
        db: Database session
        current_user: The authenticated user
    
    Returns:
        List[Subscription]: The user's active subscriptions
    
    Raises:
        HTTPException: If user is not found or not authorized
    """
    # Check authorization (only allow users to check their own subscriptions or superusers)
    if str(current_user.id) != str(user_id) and not current_user.is_superuser:
        logger.warning(f"Unauthorized access attempt to active subscriptions for user {user_id}")
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to access this user's subscription data"
        )
    
    subscription_service = SubscriptionService(db)
    return await subscription_service.get_user_active_subscriptions(user_id)
