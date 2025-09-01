"""
Subscription service module.

Provides services for managing subscription data.
"""
import logging
import uuid
from typing import List, Dict, Any, Optional
from datetime import datetime
from sqlalchemy.orm import Session
from fastapi import HTTPException, status

from app.models.subscription import Subscription as SubscriptionModel
from app.models.subscription import SubscriptionStatus as SubscriptionStatusEnum
from app.models.user import User
from app.schemas.subscription import (
    SubscriptionCreate,
    Subscription,
    SubscriptionStatus,
)

logger = logging.getLogger(__name__)


class SubscriptionService:
    """
    Service for subscription-related operations.
    """
    
    def __init__(self, db: Session):
        """
        Initialize the subscription service.
        
        Args:
            db: Database session
        """
        self.db = db
    
    async def get_user_subscription_status(self, user_id: uuid.UUID) -> SubscriptionStatus:
        """
        Get a user's subscription status.
        
        Args:
            user_id: The user ID to check
        
        Returns:
            SubscriptionStatus: The user's subscription status
        
        Raises:
            HTTPException: If user is not found
        """
        # Check if the user exists
        user = self.db.query(User).filter(User.id == user_id).first()
        if not user:
            logger.warning(f"User not found: {user_id}")
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )
            
        # Get active subscriptions
        active_subscriptions = await self.get_user_active_subscriptions(user_id)
        
        # Determine overall status
        has_active_subscription = len(active_subscriptions) > 0
        
        return SubscriptionStatus(
            user_id=user_id,
            has_active_subscription=has_active_subscription,
            subscriptions=active_subscriptions
        )
    
    async def get_user_active_subscriptions(self, user_id: uuid.UUID) -> List[Subscription]:
        """
        Get a user's active subscriptions.
        
        Args:
            user_id: The user ID to check
        
        Returns:
            List[Subscription]: The user's active subscriptions
        
        Raises:
            HTTPException: If user is not found
        """
        # Check if the user exists
        user = self.db.query(User).filter(User.id == user_id).first()
        if not user:
            logger.warning(f"User not found: {user_id}")
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )
            
        # Query active subscriptions
        active_subscriptions = self.db.query(SubscriptionModel).filter(
            SubscriptionModel.user_id == user_id,
            SubscriptionModel.status == SubscriptionStatusEnum.ACTIVE
        ).all()
        
        # Convert to schema models
        return [Subscription.from_orm(subscription) for subscription in active_subscriptions]
    
    async def get_subscription_by_original_transaction_id(self, original_transaction_id: str) -> Optional[SubscriptionModel]:
        """
        Get a subscription by original transaction ID.
        
        Args:
            original_transaction_id: The original transaction ID
        
        Returns:
            Optional[SubscriptionModel]: The subscription if found, None otherwise
        """
        return self.db.query(SubscriptionModel).filter(
            SubscriptionModel.original_transaction_id == original_transaction_id
        ).first()
    
    async def create_subscription(self, subscription_data: Dict[str, Any]) -> SubscriptionModel:
        """
        Create a new subscription.
        
        Args:
            subscription_data: The subscription data
        
        Returns:
            SubscriptionModel: The created subscription
        
        Raises:
            ValueError: If subscription data is invalid
        """
        try:
            # Check if user exists
            user_id = subscription_data.get("user_id")
            user = self.db.query(User).filter(User.id == user_id).first()
            
            if not user:
                logger.error(f"Cannot create subscription: User not found: {user_id}")
                raise ValueError(f"User not found: {user_id}")
                
            # Create subscription object
            subscription = SubscriptionModel(
                user_id=user_id,
                original_transaction_id=subscription_data.get("original_transaction_id"),
                product_id=subscription_data.get("product_id"),
                status=subscription_data.get("status", SubscriptionStatusEnum.ACTIVE),
                expires_date=subscription_data.get("expires_date"),
                purchase_date=subscription_data.get("purchase_date"),
                auto_renew_status=subscription_data.get("auto_renew_status", False),
                environment=subscription_data.get("environment", "Production"),
                raw_data=subscription_data.get("raw_data")
            )
            
            # Save to database
            self.db.add(subscription)
            self.db.commit()
            self.db.refresh(subscription)
            
            logger.info(f"Created subscription for user {user_id}, product {subscription.product_id}")
            return subscription
            
        except Exception as e:
            self.db.rollback()
            logger.error(f"Error creating subscription: {str(e)}")
            raise ValueError(f"Failed to create subscription: {str(e)}")
    
    async def update_subscription(
        self,
        subscription_id: uuid.UUID,
        subscription_data: Dict[str, Any]
    ) -> SubscriptionModel:
        """
        Update a subscription.
        
        Args:
            subscription_id: The subscription ID
            subscription_data: The data to update
        
        Returns:
            SubscriptionModel: The updated subscription
        
        Raises:
            HTTPException: If subscription is not found
        """
        # Get the subscription
        subscription = self.db.query(SubscriptionModel).filter(
            SubscriptionModel.id == subscription_id
        ).first()
        
        if not subscription:
            logger.warning(f"Subscription not found: {subscription_id}")
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Subscription not found"
            )
        
        try:
            # Update fields
            for key, value in subscription_data.items():
                if hasattr(subscription, key) and value is not None:
                    setattr(subscription, key, value)
            
            # Save changes
            self.db.commit()
            self.db.refresh(subscription)
            
            logger.info(f"Updated subscription {subscription_id}")
            return subscription
            
        except Exception as e:
            self.db.rollback()
            logger.error(f"Error updating subscription {subscription_id}: {str(e)}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to update subscription: {str(e)}"
            )
