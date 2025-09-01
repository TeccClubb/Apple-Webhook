"""
Custom database types.
"""
import uuid
from sqlalchemy import TypeDecorator, TEXT


class SQLiteUUID(TypeDecorator):
    """
    Platform-independent UUID type.
    Uses TEXT for SQLite, UUID for PostgreSQL.
    """
    impl = TEXT
    cache_ok = True

    def process_bind_param(self, value, dialect):
        """Convert UUID to string when saving to database."""
        if value is None:
            return value
        if isinstance(value, uuid.UUID):
            return str(value)
        return value

    def process_result_value(self, value, dialect):
        """Convert string to UUID when retrieving from database."""
        if value is None:
            return value
        if not isinstance(value, uuid.UUID):
            return uuid.UUID(value)
        return value
