"""Woven API application with fail-closed staging/production boundaries."""

from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import re
import time
import uuid
from collections import defaultdict, deque
from typing import Deque, Dict

from fastapi import FastAPI
from fastapi.exception_handlers import request_validation_exception_handler
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text as sql_text
from starlette.middleware.trustedhost import TrustedHostMiddleware
from starlette.requests import Request
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.config import settings
from app.db.session import SessionLocal
from app.routers import (
    access_requests_router,
    auth_router,
    devices_router,
    friends_router,
    media_router,
    pair_v2_router,
    users_router,
    vaults_router,
)
from app.services.mdns import mdns_service


class JSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        event = {
            "timestamp": int(time.time()),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        for field in ("request_id", "method", "route", "status", "duration_ms"):
            value = getattr(record, field, None)
            if value is not None:
                event[field] = value
        return json.dumps(event, separators=(",", ":"))


handler = logging.StreamHandler()
handler.setFormatter(JSONFormatter())
logging.basicConfig(level=logging.INFO, handlers=[handler], force=True)
logger = logging.getLogger(__name__)

app = FastAPI(
    title=settings.APP_NAME,
    debug=settings.DEBUG,
    docs_url=None if settings.is_remote else "/docs",
    redoc_url=None if settings.is_remote else "/redoc",
    openapi_url=None if settings.is_remote else "/openapi.json",
)


@app.exception_handler(RequestValidationError)
async def safe_validation_error(request: Request, error: RequestValidationError):
    if settings.is_remote:
        return JSONResponse(status_code=422, content={"detail": "Invalid request"})
    return await request_validation_exception_handler(request, error)


class RequestBoundaryMiddleware:
    """Apply body, timeout, request-ID, security-header, and rate boundaries."""

    _safe_request_id = re.compile(r"^[A-Za-z0-9._-]{1,64}$")

    def __init__(self, app: ASGIApp):
        self.application = app
        self._requests: Dict[str, Deque[float]] = defaultdict(deque)

    def _rate_limit(self, scope: Scope) -> int:
        path = scope.get("path", "")
        if path.startswith("/auth/"):
            return settings.RATE_LIMIT_AUTH_PER_MINUTE
        if path.startswith("/pair-v2/"):
            return settings.RATE_LIMIT_PAIR_PER_MINUTE
        return 0

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.application(scope, receive, send)
            return

        headers = {key.lower(): value for key, value in scope.get("headers", [])}
        started_at = time.monotonic()
        response_status = 500
        supplied_request_id = headers.get(b"x-request-id", b"").decode("ascii", errors="ignore")
        request_id = supplied_request_id if self._safe_request_id.fullmatch(supplied_request_id) else str(uuid.uuid4())

        def log_boundary(status: int) -> None:
            logger.info(
                "request_boundary",
                extra={
                    "request_id": request_id,
                    "method": scope.get("method", "UNKNOWN"),
                    "route": "boundary",
                    "status": status,
                    "duration_ms": round((time.monotonic() - started_at) * 1000, 2),
                },
            )

        def boundary_headers(additional: dict[str, str] | None = None) -> dict[str, str]:
            values = {
                "X-Request-ID": request_id,
                "X-Content-Type-Options": "nosniff",
                "X-Frame-Options": "DENY",
                "Referrer-Policy": "no-referrer",
                "Cache-Control": "no-store",
            }
            if settings.is_remote:
                values["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
            if additional:
                values.update(additional)
            return values

        limit = self._rate_limit(scope)
        if limit:
            client = scope.get("client") or ("unknown", 0)
            authorization = headers.get(b"authorization")
            # Isolate authenticated native clients that share a carrier NAT
            # or reverse proxy. The credential is only hashed into this
            # process-local bucket key and is never logged or persisted.
            principal = (
                hashlib.sha256(authorization).hexdigest()
                if authorization
                else str(client[0])
            )
            route_family = scope.get("path", "").split("/", 2)[1:2]
            key = f"{principal}:{route_family}"
            now = time.monotonic()
            bucket = self._requests[key]
            while bucket and bucket[0] <= now - 60:
                bucket.popleft()
            if len(bucket) >= limit:
                log_boundary(429)
                await JSONResponse(
                    status_code=429,
                    content={"detail": "Rate limit exceeded"},
                    headers=boundary_headers({"Retry-After": "60"}),
                )(scope, receive, send)
                return
            bucket.append(now)

        content_length = headers.get(b"content-length")
        if content_length is not None:
            try:
                declared_length = int(content_length)
            except ValueError:
                declared_length = -1
            if declared_length < 0:
                log_boundary(400)
                await JSONResponse(
                    status_code=400,
                    content={"detail": "Invalid Content-Length header"},
                    headers=boundary_headers(),
                )(scope, receive, send)
                return
            if declared_length > settings.MAX_REQUEST_BYTES:
                log_boundary(413)
                await JSONResponse(
                    status_code=413,
                    content={"detail": "Request exceeds the size limit"},
                    headers=boundary_headers(),
                )(scope, receive, send)
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
            if received_bytes > settings.MAX_REQUEST_BYTES:
                log_boundary(413)
                await JSONResponse(
                    status_code=413,
                    content={"detail": "Request exceeds the size limit"},
                    headers=boundary_headers(),
                )(scope, receive, send)
                return
            if not message.get("more_body", False):
                break

        response_complete = asyncio.Event()

        async def replay_receive() -> Message:
            if messages:
                return messages.pop(0)
            # StreamingResponse listens for disconnect after consuming the
            # request. Block here until its send path completes instead of
            # producing an infinite stream of empty request frames.
            await response_complete.wait()
            return {"type": "http.disconnect"}

        async def secured_send(message: Message) -> None:
            nonlocal response_status
            if message["type"] == "http.response.start":
                response_status = int(message["status"])
                response_headers = list(message.get("headers", []))
                response_headers.extend(
                    [
                        (b"x-request-id", request_id.encode("ascii")),
                        (b"x-content-type-options", b"nosniff"),
                        (b"x-frame-options", b"DENY"),
                        (b"referrer-policy", b"no-referrer"),
                        (b"cache-control", b"no-store"),
                    ]
                )
                if settings.is_remote:
                    response_headers.append((b"strict-transport-security", b"max-age=31536000; includeSubDomains"))
                message["headers"] = response_headers
            await send(message)
            if message["type"] == "http.response.body" and not message.get("more_body", False):
                response_complete.set()
                route = scope.get("route")
                logger.info(
                    "request_completed",
                    extra={
                        "request_id": request_id,
                        "method": scope.get("method", "UNKNOWN"),
                        "route": getattr(route, "path", "unmatched"),
                        "status": response_status,
                        "duration_ms": round((time.monotonic() - started_at) * 1000, 2),
                    },
                )

        try:
            await asyncio.wait_for(
                self.application(scope, replay_receive, secured_send),
                timeout=settings.REQUEST_TIMEOUT_SECONDS,
            )
        except asyncio.TimeoutError:
            log_boundary(504)
            await JSONResponse(
                status_code=504,
                content={"detail": "Request timed out"},
                headers=boundary_headers(),
            )(scope, replay_receive, send)


app.add_middleware(RequestBoundaryMiddleware)
if settings.is_remote:
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=settings.trusted_hosts)
if settings.cors_origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=[
            "Authorization",
            "Content-Type",
            "X-Request-ID",
            "X-Woven-Protocol",
            "X-Woven-Device-ID",
            "X-Woven-Request-ID",
            "X-Woven-Timestamp-MS",
            "X-Woven-Nonce",
            "X-Woven-Signature",
        ],
    )

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
    return {"status": "ok"}


@app.get("/health")
def health_check():
    return {"status": "ok"}


@app.get("/ready")
def readiness_check():
    try:
        with SessionLocal() as db:
            db.execute(sql_text("SELECT 1"))
    except Exception:
        return JSONResponse(status_code=503, content={"status": "unavailable"})
    return {"status": "ready"}


@app.on_event("startup")
async def startup_event():
    logger.info("configuration=%s", settings.safe_summary())
    if settings.is_local and mdns_service.start():
        logger.info("mDNS service started")


@app.on_event("shutdown")
async def shutdown_event():
    if settings.is_local:
        mdns_service.stop()
