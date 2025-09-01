"""
Authentication API endpoints.
"""
import logging
from datetime import timedelta
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import verify_password, create_access_token
from app.db.session import get_db
from app.schemas.token import Token
from app.models.user import User

router = APIRouter()
logger = logging.getLogger(__name__)


@router.post(
    "/subscriptions/auth",
    response_model=Token,
    status_code=status.HTTP_200_OK,
    summary="Get access token for authentication"
)
async def login_for_access_token(
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: Session = Depends(get_db)
):
    """
    Create an access token for API authentication.
    
    Args:
        form_data: The OAuth2 password request form
        db: Database session
    
    Returns:
        Token: The access token
    
    Raises:
        HTTPException: If authentication fails
    """
    # Find the user by email
    user = db.query(User).filter(User.email == form_data.username).first()
    
    # Check if the user exists and the password is correct
    if not user or not verify_password(form_data.password, user.hashed_password):
        logger.warning(f"Failed login attempt for user: {form_data.username}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    # Check if the user is active
    if not user.is_active:
        logger.warning(f"Login attempt for inactive user: {form_data.username}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Inactive user",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    # Create the access token
    access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": str(user.id)},
        expires_delta=access_token_expires
    )
    
    logger.info(f"Successful login for user: {form_data.username}")
    return Token(
        access_token=access_token,
        token_type="bearer"
    )
