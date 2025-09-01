"""
Main FastAPI application entrypoint.
"""
import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.api.routes.apple_webhook import router as apple_webhook_router
from app.api.routes.subscriptions import router as subscriptions_router
from app.api.routes.auth import router as auth_router
from app.core.config import settings
from app.db.session import create_tables

# Configure logging
logging.basicConfig(
    level=settings.LOG_LEVEL,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title=settings.PROJECT_NAME,
    description="Apple App Store Server Notifications Service API",
    version="1.0.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc",
)

# Set up CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(apple_webhook_router, prefix="/api/v1", tags=["webhook"])
app.include_router(subscriptions_router, prefix="/api/v1", tags=["subscriptions"])
app.include_router(auth_router, prefix="/api/v1", tags=["auth"])


@app.on_event("startup")
async def startup_event():
    """Initialize application on startup."""
    logger.info("Starting Apple Subscription Service...")
    create_tables()


@app.get("/health", tags=["health"])
async def health_check():
    """Health check endpoint."""
    return {"status": "ok"}


if __name__ == "__main__":
    import uvicorn
    
    uvicorn.run(
        "main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.DEBUG,
        log_level=settings.LOG_LEVEL.lower(),
    )
