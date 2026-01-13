# Woven MVP v1 Roadmap

## The Promise
**"Secure storage + consented access + audit + rapid lock"** (not "uncopyable")

Woven protects against:
- Server/database breaches (server never has plaintext).
- Casual snooping (camera roll, shared albums, chat apps).
- One partner secretly opening the vault (if strict mode is enabled).

Woven cannot fully prevent copying:
- Screenshots are detected *after* the fact.
- Screen recording/mirroring is detected *live* (content hidden).
- External cameras cannot be stopped.

## Roles and Objects
- **User**: Account + Device(s).
- **Friend**: Mutual connection (invite/accept).
- **Vault**: Solo or Pair, contains encrypted media.
- **Access Request**: A short-lived "approve unlock" session.

## Cryptography Model
### Encryption
- Media encrypted on-device using **AES-GCM (CryptoKit)**.
- Server stores only encrypted blobs + non-sensitive metadata.

### Keys
- **Solo Vault**: One random `vaultKey` stored in iOS Keychain (optionally wrapped by passcode).
- **Pair Vault** (Strict Mode):
    - Create random `vaultKey`.
    - Split into two shares: `shareA` = `vaultKey` XOR `shareB`.
    - Store `shareA` in User A's Keychain, `shareB` in User B's Keychain.
    - **Result**: Neither share alone can decrypt anything. Approval is cryptographically enforced.

## MVP Feature Set
### 1. Auth + Device Security
- **Sign in with Apple**: Simplifies trust.
- **Local Auth**: Require Face ID / Passcode to open app.
- **App Switcher**: Blur content.

### 2. Friends + Pairing
- **Invite Flow**: User A invites -> User B accepts.
- **Pair Vault Creation**: User B must explicitly accept joining.

### 3. Vault Modes
- **Normal Mode (Default)**:
    - Open with local device auth.
    - Co-approval required only for: New device, after X hours (e.g., 24h), after screenshot detected, or failed unlock attempts.
- **Strict Mode**:
    - Every open requires approval from the other person (Push -> Approve).

### 4. Access Request Flow (Push Approval)
1. User A taps "Open Vault" -> Server creates `AccessRequest` (with ephemeral public key).
2. Server sends APNs push to User B.
3. User B authenticates -> Taps Approve.
4. User B's device encrypts its key share to requester's ephemeral key -> Sends to Server.
5. User A receives share, reconstructs `vaultKey`, decrypts, and starts short session (5-10 mins).

### 5. Uploading Media (View-Only, No Downloads)
- Upload only while vault is unlocked.
- Encrypt on-device with `vaultKey`.
- Upload encrypted blob.
- **View-only in app**: Media can only be viewed in-app, cannot be saved/downloaded to device.
- Temporary signed URLs for viewing (short expiration).
- No "Save to Photos" or export functionality.

### 6. Screenshot / Recording Response
- **Screen Recording/Mirroring**: If `UIScreen.isCaptured`, immediately cover content with blur/lock screen.
- **Screenshot**: On `userDidTakeScreenshotNotification`:
    1. Lock the vault.
    2. Notify the other person.
    3. Require re-approval for next unlock.
- **Note**: Do NOT auto-delete vault.

## Open Decisions (Security/Policy)
- **Device Loss**:
    - *Option A*: Max privacy (no recovery).
    - *Option B*: Recovery key (offline storage).
- **Revocation / Breakup**:
    - Immediate "Revoke access".
    - "Rotate keys" so future uploads can't be decrypted by revoked device.
- **Abuse Controls**:
    - Rate-limit access requests.
    - Quiet hours / mute requests.

## Backend Responsibilities (FastAPI)
- Accounts + Friend Invites.
- Vault Membership (2-person limit).
- AccessRequests State Machine (pending/approved/denied/expired).
- Push Notifications (APNs).
- Encrypted Blob Storage + Signed URLs.
- Audit Log.

## App Store Safety
- Market as "private encrypted shared vault".
- Avoid explicit positioning to comply with guidelines regarding "apps that may include pornography".

## Build Order

### ✅ Phase 0: Foundation (Complete)
- [x] FastAPI backend setup with PostgreSQL
- [x] Email/password authentication (signup + login)
- [x] JWT token-based authorization
- [x] User model with invite codes

### ✅ Phase 1: Solo Vault (Core Complete)
- [x] Vault model (solo/pair types, normal/strict modes)
- [x] Create, list, get, update, delete vaults
- [x] Vault membership system
- [x] iOS app: VaultView with create/delete functionality
- [ ] Media upload + view-only display (in progress)
- [ ] On-device encryption with AES-GCM

### ✅ Phase 2: Pairing (Complete)
- [x] Vault invitations via invite code
- [x] Accept/decline invitations
- [x] Leave vault functionality
- [x] Pair vault max 2 members enforcement
- [x] Dedicated Friends system (mutual connections)
- [x] Push notifications for invites

### 🔲 Phase 3: Strict Unlock (NEXT)
- [ ] Access requests + push approvals
- [ ] 2-of-2 key share relay
- [ ] APNs integration (Completed in Phase 2, ready for implementation here)

### 🔲 Phase 4: Capture Handling
- [ ] Recording detection cover (UIScreen.isCaptured)
- [ ] Screenshot detection lock/notify

### 🔲 Phase 5: Safety
- [ ] Key rotation
- [ ] Revoke access
- [ ] Audit logging
