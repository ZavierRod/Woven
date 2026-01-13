# Models Module

SQLAlchemy ORM models representing database tables.

## Current Models

### `user.py` - User Model
Represents an authenticated user.

| Column | Type | Description |
|--------|------|-------------|
| `id` | Integer | Primary key |
| `username` | String | Unique username |
| `email` | String | User's email (unique) |
| `password_hash` | String | Bcrypt hashed password |
| `full_name` | String | User's display name |
| `profile_picture_url` | String | Avatar URL |
| `invite_code` | String | Unique code for friend invites |
| `public_key` | String | User's public key for encryption |
| `created_at` | DateTime | Account creation timestamp |
| `updated_at` | DateTime | Last update timestamp |

### `vault.py` - Vault & VaultMember Models ✅
Encrypted media containers and membership.

**Vault Model:**
| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `name` | String | Vault display name |
| `type` | Enum | "solo" or "pair" |
| `mode` | Enum | "normal" or "strict" |
| `owner_id` | Integer | FK to User |
| `created_at` | DateTime | Creation timestamp |
| `updated_at` | DateTime | Last update timestamp |
| `last_accessed_at` | DateTime | Last access timestamp |

**VaultMember Model:**
| Column | Type | Description |
|--------|------|-------------|
| `id` | Integer | Primary key |
| `vault_id` | UUID | FK to Vault |
| `user_id` | Integer | FK to User |
| `role` | Enum | "owner" or "member" |
| `status` | Enum | "pending", "accepted", "revoked" |
| `key_share` | String | Encrypted key share (for strict mode) |
| `joined_at` | DateTime | When membership was accepted |
| `created_at` | DateTime | Creation timestamp |

## Current Status ✅

- [x] User model
- [x] Vault model
- [x] VaultMember model

## Future Models (per Roadmap)

### `friend.py` - Friend Connection (Phase 2)
Mutual friend relationship.

```python
class Friend(Base):
    id: int
    user_id: int
    friend_id: int
    status: str  # "pending", "accepted", "blocked"
    created_at: datetime
    accepted_at: datetime
```

### `access_request.py` - Access Request (Phase 3)
Push approval requests for strict mode.

```python
class AccessRequest(Base):
    id: UUID
    vault_id: UUID
    requester_id: int
    approver_id: int
    status: str  # "pending", "approved", "denied", "expired"
    ephemeral_public_key: str  # Requester's temp key
    encrypted_share: str  # Approver's encrypted response
    created_at: datetime
    expires_at: datetime
    responded_at: datetime
```

### `vault_media.py` - Encrypted Media (Phase 1)
Encrypted blob reference.

```python
class VaultMedia(Base):
    id: UUID
    vault_id: UUID
    uploaded_by: int
    media_type: str  # "photo" or "video"
    storage_url: str  # Cloud storage URL
    thumbnail_url: str
    file_size: int
    encryption_iv: str  # AES-GCM IV
    created_at: datetime
```

### `audit_log.py` - Audit Trail (Phase 5)
Security event logging.

```python
class AuditLog(Base):
    id: int
    event_type: str  # "vault_opened", "screenshot_detected", etc.
    user_id: int
    vault_id: UUID
    metadata: JSON
    ip_address: str
    device_info: str
    created_at: datetime
```

### `device.py` - User Devices (Future)
Track user's registered devices.

```python
class Device(Base):
    id: UUID
    user_id: int
    device_name: str
    device_type: str  # "iphone", "ipad"
    apns_token: str  # For push notifications
    public_key: str  # Device-specific key
    last_active: datetime
    created_at: datetime
```


