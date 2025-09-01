"""
Application settings and configuration module.
Loads environment variables and provides application configuration.
"""
import os
import logging
from typing import List, Optional, Dict, Any
from pydantic import Field, validator
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """
    Application settings class.
    Loads settings from environment variables and provides default values.
    """
    # Project settings
    PROJECT_NAME: str = "Apple Subscription Service"
    API_V1_PREFIX: str = "/api/v1"
    DEBUG: bool = Field(default=False)
    
    # Server settings
    HOST: str = Field(default="0.0.0.0")
    PORT: int = Field(default=8000)
    ALLOWED_ORIGINS: List[str] = Field(default_factory=lambda: ["*"])
    
    # Security
    SECRET_KEY: str = Field(...)
    ACCESS_TOKEN_EXPIRE_MINUTES: int = Field(default=60 * 24)  # 1 day
    ALGORITHM: str = Field(default="HS256")

    # Database
    DATABASE_URL: str = Field(...)
    
    # Apple specific
    APPLE_BUNDLE_ID: str = Field(...)
    APPLE_ISSUER_ID: Optional[str] = None
    APPLE_PRIVATE_KEY_ID: Optional[str] = None
    APPLE_PRIVATE_KEY_PATH: Optional[str] = None
    APPLE_TEAM_ID: Optional[str] = None
    APPLE_ENVIRONMENT: str = Field(default="Production")  # Production or Sandbox
    
    # Logging
    LOG_LEVEL: str = Field(default="INFO")
    
    @validator("LOG_LEVEL")
    def validate_log_level(cls, v):
        """Validate log level."""
        allowed_levels = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
        if v.upper() not in allowed_levels:
            return "INFO"
        return v.upper()
    
    class Config:
        """Pydantic config."""
        env_file = ".env"
        case_sensitive = True
        env_file_encoding = "utf-8"


# Initialize settings
settings = Settings()  # type: ignore

# Configure logging
logging.basicConfig(
    level=settings.LOG_LEVEL,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
