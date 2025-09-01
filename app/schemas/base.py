"""
Base schema module.
"""
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field
import uuid


class BaseSchema(BaseModel):
    """Base schema with common fields."""
    id: uuid.UUID = Field(...)
    created_at: datetime
    updated_at: datetime

    class Config:
        """Pydantic config."""
        orm_mode = True
