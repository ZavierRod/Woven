# API Routers
from app.routers.auth import router as auth_router
from app.routers.users import router as users_router
from app.routers.vaults import router as vaults_router
from app.routers.media import router as media_router
from app.routers.friends import router as friends_router
from app.routers.devices import router as devices_router
from app.routers.access_requests import router as access_requests_router
from app.routers.pair_v2 import router as pair_v2_router

__all__ = ["auth_router", "users_router",
           "vaults_router", "media_router", "friends_router", "devices_router", "access_requests_router", "pair_v2_router"]
