"""
User schemas module.
"""
from typing import Optional, List, Any
from pydantic import BaseModel, EmailStr, Field

from app.schemas.base import BaseSchema


class UserBase(BaseModel):
    """Base user schema."""
    email: Optional[EmailStr] = None
    full_name: Optional[str] = None
    is_active: Optional[bool] = True


class UserCreate(UserBase):
    """Schema for user creation."""
    email: EmailStr
    password: str = Field(..., min_length=8)


class UserUpdate(UserBase):
    """Schema for user update."""
    password: Optional[str] = Field(None, min_length=8)


class UserInDB(UserBase):
    """Schema for user in database."""
    hashed_password: str


class User(BaseSchema, UserBase):
    """Schema for user response."""
    pass


class UserWithSubscriptions(User):
    """Schema for user with subscriptions."""
    subscriptions: List[Any] = []
