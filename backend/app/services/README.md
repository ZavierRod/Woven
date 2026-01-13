# Services Module

Business logic layer. Complex operations that span multiple models or involve external services.

## Philosophy

- Services contain business logic, not CRUD operations
- Each service focuses on one domain
- Services can call CRUD operations and other services
- External API integrations live here

## Current Status

Currently empty - business logic is simple enough to live in routers.

## Future Services (per Roadmap)

### `apple_auth.py` - Apple Sign In (Enhancement)
Full Apple token verification with public keys.

```python
class AppleAuthService:
    async def fetch_apple_public_keys() -> dict
    async def verify_identity_token(token: str) -> AppleUserInfo
    async def refresh_public_keys()  # Cache Apple's rotating keys
```

### `vault_service.py` - Vault Operations (Phase 1)
Vault creation, key management, and access control.

```python
class VaultService:
    def create_solo_vault(db, user_id, name) -> Vault
    def create_pair_vault(db, owner_id, partner_id, name) -> Vault
    def can_access_vault(db, user_id, vault_id) -> bool
    def generate_vault_key() -> bytes  # Random AES key
    def split_key_shares(vault_key) -> tuple[bytes, bytes]  # XOR split
    def reconstruct_key(share_a, share_b) -> bytes
```

### `friend_service.py` - Friend Management (Phase 2)
Friend invite flow and relationship management.

```python
class FriendService:
    def send_invite(db, from_user_id, to_invite_code) -> FriendInvite
    def accept_invite(db, invite_id, user_id) -> Friend
    def are_friends(db, user_a_id, user_b_id) -> bool
    def get_mutual_vaults(db, user_a_id, user_b_id) -> List[Vault]
```

### `access_service.py` - Access Request Flow (Phase 3)
Push approval workflow for strict mode vaults.

```python
class AccessService:
    async def request_access(db, vault_id, requester_id, ephemeral_key) -> AccessRequest
    async def approve_access(db, request_id, approver_id, encrypted_share) -> AccessRequest
    async def deny_access(db, request_id, approver_id) -> AccessRequest
    def is_request_valid(request: AccessRequest) -> bool
    def cleanup_expired_requests(db)  # Background job
```

### `push_service.py` - Push Notifications (Phase 3)
APNs integration for access requests and alerts.

```python
class PushService:
    async def send_access_request_notification(user_id, vault_name, requester_name)
    async def send_access_approved_notification(user_id, vault_name)
    async def send_screenshot_alert(user_id, vault_name, detected_by)
    async def send_vault_invite_notification(user_id, vault_name, inviter_name)
```

### `storage_service.py` - Cloud Storage (Phase 1)
Encrypted blob storage (S3/GCS).

```python
class StorageService:
    async def generate_upload_url(media_id, content_type) -> str
    async def generate_download_url(storage_key) -> str
    async def delete_blob(storage_key)
    def get_storage_key(vault_id, media_id) -> str
```

### `encryption_service.py` - Cryptography Helpers (Phase 1)
Encryption utilities (most encryption happens on-device, but server needs some helpers).

```python
class EncryptionService:
    def generate_ephemeral_keypair() -> tuple[str, str]  # public, private
    def encrypt_for_public_key(data: bytes, public_key: str) -> str
    def decrypt_with_private_key(data: str, private_key: str) -> bytes
```

### `audit_service.py` - Security Logging (Phase 5)
Security event tracking and anomaly detection.

```python
class AuditService:
    def log_event(db, event_type, user_id, vault_id, metadata)
    def get_vault_activity(db, vault_id, since) -> List[AuditLog]
    def detect_suspicious_activity(db, user_id) -> List[Alert]
    def get_security_summary(db, vault_id) -> SecurityReport
```

### `screenshot_service.py` - Screenshot Response (Phase 4)
Handle screenshot/recording detection events from iOS.

```python
class ScreenshotService:
    async def handle_screenshot_detected(db, user_id, vault_id)
    async def handle_recording_detected(db, user_id, vault_id)
    def should_require_reapproval(db, vault_id) -> bool
```


