# Routers Module

API endpoint handlers organized by resource.

## Current Routers

### `auth.py` - Authentication
Prefix: `/auth`

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/signup` | Register with email/password |
| POST | `/login` | Login with email/username + password |

### `users.py` - User Management
Prefix: `/users`

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/me` | Get current user's profile |
| GET | `/{invite_code}` | Find user by invite code |

### `vaults.py` - Vault Management ✅
Prefix: `/vaults`

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/` | Create a new vault |
| GET | `/` | List user's vaults |
| GET | `/{id}` | Get vault details |
| PATCH | `/{id}` | Update vault (name, mode) |
| DELETE | `/{id}` | Delete vault (owner only) |
| POST | `/{id}/invite` | Invite user to pair vault |
| GET | `/invites/pending` | Get pending invitations |
| POST | `/{id}/accept` | Accept vault invitation |
| POST | `/{id}/decline` | Decline vault invitation |
| DELETE | `/{id}/leave` | Leave vault (non-owner) |

## Current Status ✅

- [x] Email/password authentication
- [x] User profile endpoints
- [x] Full vault CRUD
- [x] Vault membership management

## Future Routers (per Roadmap)

### `friends.py` - Friend System (Phase 2)
Prefix: `/friends`

```
GET    /              List friends
POST   /invite        Send friend invite
GET    /invites       List pending invites
POST   /invites/{id}/accept   Accept invite
POST   /invites/{id}/decline  Decline invite
DELETE /{id}          Remove friend
```

### `access.py` - Access Requests (Phase 3)
Prefix: `/access`

```
POST   /request       Create access request (request unlock)
GET    /pending       List pending requests for approval
POST   /{id}/approve  Approve access request
POST   /{id}/deny     Deny access request
```

### `media.py` - Media Upload/Download (Phase 1)
Prefix: `/media`

```
POST   /upload-url    Get signed upload URL
POST   /              Register uploaded media
GET    /{id}          Get media details
GET    /{id}/download Get signed download URL
DELETE /{id}          Delete media
```

### `notifications.py` - Push Notifications (Phase 3)
Prefix: `/notifications`

```
POST   /register      Register device APNs token
DELETE /unregister    Unregister device
GET    /settings      Get notification preferences
PATCH  /settings      Update preferences (quiet hours, etc.)
```

### `audit.py` - Audit Logs (Phase 5)
Prefix: `/audit`

```
GET    /vault/{id}    Get vault activity log
POST   /report        Report suspicious activity
```


