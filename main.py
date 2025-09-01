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


@app.get("/api/v1/test-connection", tags=["diagnostics"])
async def test_apple_connection():
    """Test connection to Apple servers and check configuration."""
    from app.services.apple_service import AppleService
    from app.core.config import settings
    import pkg_resources
    import sys
    import os
    
    diagnostics = {
        "status": "ok",
        "details": {},
        "environment": {},
        "dependencies": {}
    }
    
    # Check environment variables
    apple_env_vars = {
        "APPLE_TEAM_ID": settings.APPLE_TEAM_ID,
        "APPLE_BUNDLE_ID": settings.APPLE_BUNDLE_ID,
        "APPLE_ENVIRONMENT": settings.APPLE_ENVIRONMENT,
        "APPLE_PRIVATE_KEY_ID": settings.APPLE_PRIVATE_KEY_ID,
        "APPLE_ISSUER_ID": settings.APPLE_ISSUER_ID,
    }
    
    diagnostics["environment"] = {
        "python_version": sys.version,
        "apple_config_set": all(apple_env_vars.values()),
        "database_url_set": bool(settings.DATABASE_URL),
        "debug_mode": settings.DEBUG,
    }
    
    # Check for key file
    key_path = settings.APPLE_PRIVATE_KEY_PATH
    key_exists = os.path.isfile(key_path) if key_path else False
    diagnostics["details"]["key_file"] = {
        "path": key_path,
        "exists": key_exists
    }
    
    # Check critical dependencies
    critical_packages = ["fastapi", "uvicorn", "sqlalchemy", "psycopg2", "pyjwt", "cryptography"]
    diagnostics["dependencies"] = {}
    
    for package in critical_packages:
        try:
            version = pkg_resources.get_distribution(package).version
            diagnostics["dependencies"][package] = {
                "installed": True,
                "version": version
            }
        except pkg_resources.DistributionNotFound:
            diagnostics["dependencies"][package] = {
                "installed": False,
                "version": None
            }
            diagnostics["status"] = "warning"
    
    # Test database connection
    try:
        from app.db.session import engine
        from sqlalchemy import text
        
        with engine.connect() as conn:
            result = conn.execute(text("SELECT 1"))
            database_ok = result.scalar() == 1
            
        diagnostics["details"]["database"] = {
            "connected": database_ok,
            "type": settings.DATABASE_URL.split("://")[0] if settings.DATABASE_URL else "unknown"
        }
    except Exception as e:
        diagnostics["details"]["database"] = {
            "connected": False,
            "error": str(e)
        }
        diagnostics["status"] = "warning"
    
    # Test Apple connection if everything else is OK
    if key_exists and diagnostics["status"] == "ok":
        try:
            apple_service = AppleService()
            token = apple_service.generate_token()
            
            diagnostics["details"]["apple_api"] = {
                "token_generated": bool(token),
                "environment": settings.APPLE_ENVIRONMENT
            }
        except Exception as e:
            diagnostics["details"]["apple_api"] = {
                "token_generated": False,
                "error": str(e)
            }
            diagnostics["status"] = "warning"
    
    return diagnostics


if __name__ == "__main__":
    import uvicorn
    
    uvicorn.run(
        "main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.DEBUG,
        log_level=settings.LOG_LEVEL.lower(),
    )
