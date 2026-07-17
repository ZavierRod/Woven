from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import logging
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.config import settings
from app.routers import auth_router, users_router, vaults_router, media_router, friends_router, devices_router, access_requests_router, pair_v2_router
from app.services.mdns import mdns_service

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title=settings.APP_NAME,
    debug=settings.DEBUG,
)

MAX_PAIR_REQUEST_BYTES = 21 * 1024 * 1024


class PairRequestSizeLimitMiddleware:
    """Bound Pair request bodies even when clients use chunked transfer."""

    def __init__(self, app: ASGIApp, max_bytes: int):
        self.app = app
        self.max_bytes = max_bytes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or not scope.get("path", "").startswith("/pair-v2/"):
            await self.app(scope, receive, send)
            return

        headers = {key.lower(): value for key, value in scope.get("headers", [])}
        content_length = headers.get(b"content-length")
        if content_length is not None:
            try:
                declared_length = int(content_length)
            except ValueError:
                await JSONResponse(status_code=400, content={"detail": "Invalid Content-Length header"})(
                    scope, receive, send
                )
                return
            if declared_length < 0:
                await JSONResponse(status_code=400, content={"detail": "Invalid Content-Length header"})(
                    scope, receive, send
                )
                return
            if declared_length > self.max_bytes:
                await JSONResponse(status_code=413, content={"detail": "Pair request exceeds the size limit"})(
                    scope, receive, send
                )
                return

        messages: list[Message] = []
        received_bytes = 0
        while True:
            message = await receive()
            messages.append(message)
            if message["type"] == "http.disconnect":
                return
            if message["type"] != "http.request":
                continue
            received_bytes += len(message.get("body", b""))
            if received_bytes > self.max_bytes:
                await JSONResponse(status_code=413, content={"detail": "Pair request exceeds the size limit"})(
                    scope, receive, send
                )
                return
            if not message.get("more_body", False):
                break

        async def replay_receive() -> Message:
            if messages:
                return messages.pop(0)
            return {"type": "http.request", "body": b"", "more_body": False}

        await self.app(scope, replay_receive, send)


app.add_middleware(PairRequestSizeLimitMiddleware, max_bytes=MAX_PAIR_REQUEST_BYTES)

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
app.include_router(pair_v2_router)


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
