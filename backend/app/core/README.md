# Core Module

Application configuration, security utilities, and constants.

## Current Files

### `config.py`
Application settings using Pydantic Settings. Loads from environment variables and `.env` file.

**Current Settings:**
- `APP_NAME` - Application name
- `DEBUG` - Debug mode flag
- `DATABASE_URL` - PostgreSQL connection string
- `SECRET_KEY` - JWT signing key
- `ALGORITHM` - JWT algorithm (HS256)
- `ACCESS_TOKEN_EXPIRE_MINUTES` - Token expiration time

### `security.py`
Security utilities for authentication and authorization.

**Current Functions:**
- `create_access_token()` - Create JWT access tokens
- `decode_access_token()` - Verify and decode JWT tokens
- `verify_apple_token()` - Verify Apple Sign In identity tokens
- `get_current_user_id()` - FastAPI dependency to get authenticated user

## Current Status ✅

- [x] Environment-based configuration
- [x] JWT token creation & verification
- [x] Apple Sign In token verification (mock for dev)
- [x] Authentication dependency

## Future Additions (per Roadmap)

### `config.py` additions:
- [ ] `APNS_KEY_ID` - Apple Push Notification key
- [ ] `APNS_TEAM_ID` - Apple Team ID
- [ ] `APNS_AUTH_KEY_PATH` - Path to APNs auth key
- [ ] `STORAGE_BUCKET` - Cloud storage bucket for encrypted blobs
- [ ] `ACCESS_REQUEST_EXPIRY_SECONDS` - Access request timeout
- [ ] `VAULT_SESSION_DURATION_MINUTES` - How long vault stays unlocked

### `security.py` additions:
- [ ] `verify_apple_token()` - Full Apple public key verification
- [ ] `generate_ephemeral_keypair()` - For access request encryption
- [ ] `encrypt_key_share()` - Encrypt key share for relay
- [ ] `decrypt_key_share()` - Decrypt received key share

### New Files:
- [ ] `constants.py` - Application constants (vault modes, request states)
- [ ] `exceptions.py` - Custom exception classes
- [ ] `permissions.py` - Permission checking utilities


