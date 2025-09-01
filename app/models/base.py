"""
Base model for all models.
"""
import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import Column, DateTime
from sqlalchemy.dialects.postgresql import UUID

from app.db.session import Base
from app.db.custom_types import SQLiteUUID


class BaseModel(Base):
    """
    Base class for all models.
    Provides common fields and functionality.
    """
    __abstract__ = True
    
    id = Column(SQLiteUUID, primary_key=True, default=uuid.uuid4)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
