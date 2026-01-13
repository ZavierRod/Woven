# Schemas Module

Pydantic models for request validation and response serialization.

## Naming Convention

- `*Create` - For POST request bodies
- `*Update` - For PATCH request bodies
- `*Response` - For API responses
- `*InDB` - Internal representation with all fields

## Current Schemas

### `auth.py`
- `SignUpRequest` - Email/password registration
- `LoginRequest` - Email/username + password login
- `AuthResponse` - Token + user info response
- `Token` - JWT token response

### `user.py`
- `UserBase` - Shared user fields
- `UserCreate` - Create user request
- `UserResponse` - User API response

### `vault.py` ✅
- `VaultCreate` - Create vault request (name, type, mode)
- `VaultUpdate` - Update vault request (name, mode)
- `VaultResponse` - Vault list item response
- `VaultDetailResponse` - Vault with members response
- `VaultMemberResponse` - Member info in vault
- `VaultInviteRequest` - Invite by code request
- `VaultInviteResponse` - Invite confirmation response

## Current Status ✅

- [x] Auth schemas (email/password)
- [x] User schemas
- [x] Vault schemas
- [x] VaultMember schemas

## Future Schemas (per Roadmap)

### `friend.py` (Phase 2)
```python
class FriendInviteCreate(BaseModel):
    invite_code: str

class FriendInviteResponse(BaseModel):
    id: int
    from_user: UserResponse
    status: str
    created_at: datetime

class FriendResponse(BaseModel):
    id: int
    user: UserResponse
    since: datetime
```

### `access_request.py` (Phase 3)
```python
class AccessRequestCreate(BaseModel):
    vault_id: UUID
    ephemeral_public_key: str

class AccessRequestResponse(BaseModel):
    id: UUID
    vault: VaultResponse
    requester: UserResponse
    status: str
    created_at: datetime
    expires_at: datetime

class AccessApproval(BaseModel):
    encrypted_share: str
```

### `media.py` (Phase 1)
```python
class MediaUploadRequest(BaseModel):
    vault_id: UUID
    filename: str
    content_type: str
    file_size: int

class MediaUploadResponse(BaseModel):
    upload_url: str
    media_id: UUID

class MediaCreate(BaseModel):
    vault_id: UUID
    media_type: Literal["photo", "video"]
    storage_key: str
    thumbnail_key: Optional[str]
    encryption_iv: str

class MediaResponse(BaseModel):
    id: UUID
    media_type: str
    thumbnail_url: Optional[str]
    uploaded_by: UserResponse
    created_at: datetime
```

### `notification.py` (Phase 3)
```python
class DeviceRegister(BaseModel):
    apns_token: str
    device_name: str
    device_type: str

class NotificationSettings(BaseModel):
    enabled: bool = True
    quiet_hours_start: Optional[time] = None
    quiet_hours_end: Optional[time] = None
    access_requests: bool = True
    vault_activity: bool = True
```


