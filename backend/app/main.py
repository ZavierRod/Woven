from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import logging

from app.core.config import settings
from app.routers import auth_router, users_router, vaults_router, media_router, friends_router, devices_router, access_requests_router
from app.services.mdns import mdns_service

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title=settings.APP_NAME,
    debug=settings.DEBUG,
)

# CORS middleware for development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(auth_router)
app.include_router(users_router)
app.include_router(vaults_router)
app.include_router(media_router)
app.include_router(friends_router)
app.include_router(devices_router)
app.include_router(access_requests_router)


@app.get("/")
def root():
    """Health check endpoint."""
    return {"message": f"{settings.APP_NAME} is running"}


@app.get("/health")
def health_check():
    """Detailed health check."""
    return {
        "status": "healthy",
        "app": settings.APP_NAME,
        "debug": settings.DEBUG,
    }


@app.on_event("startup")
async def startup_event():
    """Start mDNS service advertisement on startup."""
    if mdns_service.start():
        logger.info("mDNS service started successfully")
    else:
        logger.info("mDNS service not available (continuing without it)")


@app.on_event("shutdown")
async def shutdown_event():
    """Stop mDNS service advertisement on shutdown."""
    mdns_service.stop()
