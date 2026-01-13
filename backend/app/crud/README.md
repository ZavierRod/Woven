# CRUD Module

Database operations layer. Pure database queries without business logic.

## Philosophy

- Each file corresponds to one model
- Methods are simple, atomic database operations
- No business logic - that goes in `services/`
- All methods take a `db: Session` as first parameter

## Current Files

### `user.py`
User CRUD operations.

**Current Methods:**
- `get_by_id(db, user_id)` - Get user by ID
- `get_by_email(db, email)` - Get user by email
- `get_by_username(db, username)` - Get user by username
- `get_by_invite_code(db, invite_code)` - Get user by invite code
- `email_exists(db, email)` - Check if email is taken
- `username_exists(db, username)` - Check if username is taken
- `create(db, user_in)` - Create a new user with password hash
- `authenticate(db, identifier, password)` - Verify credentials
- `update_name(db, user, full_name)` - Update user's name

### `vault.py` ✅
Vault and VaultMember CRUD operations.

**VaultCRUD Methods:**
- `get_by_id(db, vault_id)` - Get vault by ID
- `get_user_vaults(db, user_id)` - Get all vaults user owns or is member of
- `create(db, vault_in, owner_id)` - Create new vault
- `update(db, vault, vault_update)` - Update vault settings
- `delete(db, vault)` - Delete vault
- `update_last_accessed(db, vault)` - Update access timestamp
- `get_member_count(db, vault_id)` - Count accepted members
- `get_media_count(db, vault_id)` - Count media items (placeholder)
- `is_owner(db, vault_id, user_id)` - Check ownership
- `is_member(db, vault_id, user_id)` - Check membership
- `can_access(db, vault_id, user_id)` - Check access rights

**VaultMemberCRUD Methods:**
- `get_by_id(db, member_id)` - Get member by ID
- `get_vault_members(db, vault_id)` - Get all vault members
- `get_accepted_members(db, vault_id)` - Get accepted members only
- `add_member(db, vault_id, user_id, role, status)` - Add member
- `accept_membership(db, member)` - Accept pending invite
- `revoke_membership(db, member)` - Revoke membership
- `remove_member(db, member)` - Remove from vault
- `get_pending_invites(db, user_id)` - Get user's pending invites

## Current Status ✅

- [x] User CRUD operations
- [x] Vault CRUD operations
- [x] VaultMember CRUD operations

## Future Additions (per Roadmap)

### `friend.py` (Phase 2 - Pairing)
```python
- create_invite(db, from_user_id, to_invite_code)
- get_pending_invites(db, user_id)
- accept_invite(db, invite_id)
- decline_invite(db, invite_id)
- get_friends(db, user_id)
- remove_friend(db, user_id, friend_id)
```

### `access_request.py` (Phase 3 - Strict Unlock)
```python
- create(db, vault_id, requester_id, ephemeral_public_key)
- get_pending_for_user(db, user_id)  # Requests awaiting their approval
- approve(db, request_id, encrypted_share)
- deny(db, request_id)
- expire_old_requests(db)  # Cleanup job
- get_by_id(db, request_id)
```

### `media.py` (Phase 1 - Media Upload)
```python
- create(db, media_in, vault_id, uploader_id)
- get_by_vault(db, vault_id)
- get_by_id(db, media_id)
- delete(db, media_id)
```

### `audit_log.py` (Phase 5 - Safety)
```python
- create(db, event_type, user_id, vault_id, metadata)
- get_by_vault(db, vault_id, limit)
- get_by_user(db, user_id, limit)
```


