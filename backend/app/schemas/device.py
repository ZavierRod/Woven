from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class DeviceTokenBase(BaseModel):
    token: str
    device_id: str
    apns_environment: Optional[str] = "sandbox"
    platform: Optional[str] = "ios"

class DeviceRegisterRequest(BaseModel):
    token: str
    device_id: str
    apns_environment: Optional[str] = "sandbox"
    platform: Optional[str] = "ios"

class DeviceTokenResponse(DeviceRegisterRequest):
    id: int
    user_id: int
    created_at: datetime
    last_seen_at: datetime

    class Config:
        from_attributes = True
