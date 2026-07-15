# Pair Vault v2 threat model and protocol

Status: development protocol for the two-member Pair Vault MVP. This document
describes the protocol implemented by the `PairVault` iOS feature and the
`/pair-v2` FastAPI relay. It does not apply to the preserved legacy Pair/Strict
Mode code.

## Security goal

A Pair Vault has exactly two active members and one active iOS device per
member in this MVP. Neither device's locally held share is a usable content key.
An unlock requires a fresh request from one member and an authenticated approval
from the other. Media, content keys, key shares, and decrypted thumbnails never
enter backend plaintext storage.

The protocol provides confidentiality and integrity against loss of backend
records and against replay, swapping, or modification of previously stored
encrypted objects. Stored backend data and either one share remain insufficient
to reconstruct the vault key. A fully active malicious backend can deny service,
suppress state, substitute device-directory keys, or fabricate an unsigned
access prompt. Client-side context checks prevent silent mutation of a request
that the requester actually created, but they cannot prove to the approver that
the relay did not originate a different prompt. Production deployment must add
authenticated device-key verification and end-to-end request signatures before
claiming active-server man-in-the-middle resistance.

## Protected assets

- Pair Vault content-encryption key (`vaultKey`, 32 random bytes).
- Member key shares (`shareA` and `shareB`).
- Device Curve25519 key-agreement private keys.
- Plaintext photos and decrypted metadata/thumbnails.
- Short-lived requester ephemeral private keys.
- Approval decisions and request-state integrity.

## Trust boundaries

Trusted for this MVP:

- Security framework random generation (`SecRandomCopyBytes`) plus CryptoKit
  SHA-256, HKDF, Curve25519 key agreement, and AES-GCM.
- The iOS process while the vault is unlocked.
- Device-only Keychain storage and the device passcode/LocalAuthentication
  boundary on an uncompromised device.
- The approving human's explicit choice after LocalAuthentication.

Untrusted or only partially trusted:

- The FastAPI service, database, blob directory, network, polling transport,
  APNs payload transport, logs, backups, and administrators.
- Invitation and access-request delivery order.
- Encrypted blobs and envelopes returned by the backend.
- Screenshots, screen recording, external cameras, and a compromised iOS
  process. Privacy covers reduce accidental exposure; they are not a
  cryptographic boundary.

The backend remains trusted for availability, account authorization, exact
two-member admission, single-use invitation state, and atomic request-state
transitions. Clients authenticate all cryptographic context and fail closed if
the backend violates it.

## Expected attacker capabilities

The attacker may copy the database and blob storage, read observable metadata,
modify/reorder/replay encrypted values, call endpoints using their own account,
steal one unlocked member device, or control the backend. The baseline MVP does
not claim resistance to kernel compromise, malicious accessibility software,
an attacker who extracts an already reconstructed `vaultKey` from process
memory, or compromise of both member devices.

## Identities

Account, vault-member, and device identities are separate records. Each device
has a stable identifier derived from the SHA-256 fingerprint of its Curve25519
key-agreement public key. The 32-byte private key is generated on device, stored with
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, and never uploaded. Only the
raw public key is registered. The development relay enforces one active device
per account; production multi-device enrollment requires a separate protocol.

## 2-of-2 key construction

The creator generates independent uniformly random 32-byte values `vaultKey`
and `shareA`, then computes:

```text
shareB = vaultKey XOR shareA
vaultKey = shareA XOR shareB
```

For every candidate `vaultKey` and a fixed observed `shareA`, exactly one
equally likely `shareB` produces that key. Because `shareA` is uniform and
independent, either individual share has a uniform distribution independent of
`vaultKey` and reveals no information about it. This is a standard 2-of-2
one-time-pad construction; it is not a novel cipher. Reusing a share across
different vault keys is forbidden.

The creator stores only `shareA` locally. `shareB` is sealed to the invited
device's long-term Curve25519 public key and relayed as an invitation envelope.
The invited device opens and stores `shareB` locally after accepting. The
backend stores ciphertext only.

## Envelope construction

All protocol contexts use canonical, versioned bytes. The typed Codable models
are encoded as sorted-key JSON with slash escaping disabled; context is never
assembled from an unordered dictionary or ad-hoc string concatenation.

For a key-share envelope:

1. The sender uses its device-only Curve25519 identity. Invitation recipients
   and approval requesters verify the embedded sender public key against the
   expected member/device directory record.
2. Curve25519 key agreement uses the recipient public key.
3. HKDF-SHA256 derives a 32-byte AES key using a protocol-specific constant
   salt and the full canonical context as `sharedInfo`.
4. AES-GCM seals the 32-byte share while authenticating the same context.
5. The envelope contains only protocol version, sender public key, and the
   AES-GCM combined nonce/ciphertext/authentication-tag bytes.

Invitation-share context binds protocol purpose, vault ID, invitation ID,
inviter account/device, invitee account/device, and version. Approval context
binds purpose, vault ID, request ID, requester/approver account and device IDs,
the exact requester ephemeral public key, creation/expiration timestamps,
membership version, and protocol version.

Consequences:

- Wrong-recipient key agreement cannot derive the AES key.
- Modified ciphertext or tag fails AES-GCM authentication.
- Modified context fails authentication.
- Cross-vault, cross-request, or cross-recipient substitution fails.
- Cryptography does not by itself stop replay; the backend's atomic
  single-consumption state machine provides replay protection.

Media and private metadata use separate AES-GCM seals under `vaultKey` with
distinct random nonces and purpose-specific authenticated context. The backend
receives UUID routing identifiers, uploader identity, byte counts, timestamps,
and ciphertext. It does not receive original filenames, MIME-derived previews,
plaintext metadata, plaintext thumbnails, or plaintext media.

## Invitation state

The creator targets one account and its one active device, uploads only the
encrypted invited share, and receives a random invitation ID/code. The backend
state is `pending`, `accepted`, `expired`, or `cancelled`. Acceptance requires
the targeted account and device, a non-expired pending invitation, a vault with
one active creator member, and no previous consumption. The inviter cannot
accept, and no third active member can be added. Acceptance is atomic; later
uses of the same invitation fail.

## Access-request state

The backend state machine is:

```text
pending -> approved -> consumed
pending -> denied
pending -> cancelled
pending -> expired
pending|approved -> cancelled (membership change)
```

The iOS presentation state additionally distinguishes none, creating request,
awaiting approval, approved, denied, expired, cancelled, consumed, and failed.

The requester creates a UUID request ID and a fresh Curve25519 ephemeral key
pair held only in memory. Creation binds both members/devices, timestamps, the
ephemeral public key, and current membership version. Only the other member may
approve. The approver first passes LocalAuthentication, reads only their local
share, and seals it to the requester ephemeral public key. Consumption is an
atomic backend transition; a second consume attempt fails. The requester opens
the envelope, XORs both shares in memory, and decrypts media.

Lock, app backgrounding, timeout, logout, request cancellation, or membership
change clears the reconstructed key, decrypted media, and pending ephemeral
private key from application state. Swift value semantics do not guarantee
perfect memory zeroization; this is a documented platform limitation.

The Pair root view also watches the scene-capture trait. An active capture or
inactive scene immediately locks Pair state and places an opaque privacy cover
over the UI. This reduces accidental exposure in app-switcher snapshots and
screen recordings; it is not a guarantee against every capture mechanism.

## Compromise outcomes

One member device compromised:

- The attacker can obtain that member's share and anything decrypted during a
  compromised unlocked session.
- That share alone cannot reconstruct `vaultKey` or decrypt stored media.
- The attacker may create requests as that member, but still needs an approval
  envelope from the other member.
- Remote revocation prevents new relay operations but cannot erase extracted
  bytes or revoke a key already reconstructed before compromise.

Backend/database/blob compromise:

- Stored data contains public keys, routing metadata, invitation/request state,
  encrypted share envelopes, encrypted metadata, and encrypted media.
- It contains neither local share, device private key, nor `vaultKey`, so stored
  records alone cannot reconstruct the key.
- Modification of an existing envelope or its bound context is detected by
  authenticated encryption, while replay is rejected by state transitions.
  Deletion and denial of service remain possible.
- A fully active backend can substitute directory public keys or fabricate an
  access request that appears to come from the other account. Human approval
  remains required, but the request itself is not end-to-end signed in this
  MVP. Production requires verified device keys and signed access requests, not
  merely TLS.

Lost device:

- `ThisDeviceOnly` keys and shares do not migrate or restore from backup.
- The MVP has no recovery or replacement-device flow. The vault becomes
  unavailable unless a future recovery/rekey protocol was configured before
  loss.

## Observable backend metadata

The service can observe account IDs, device IDs and public keys, vault and media
UUIDs, membership, invitation/request status, timestamps, IP/network metadata,
encrypted object sizes, uploader identity, polling frequency, and access timing.
It cannot observe plaintext names stored in encrypted metadata, image content,
thumbnails, shares, or content keys in the Pair v2 path.

## Development-only behavior

- Deterministic Alice/Bob development accounts and tokens are exposed only when
  backend `DEBUG` is enabled and are labeled in the UI.
- A polling notification adapter replaces APNs for local verification. It is
  not production push delivery.
- One active device per account is enforced.
- Local HTTP and Base64 ciphertext stored in a local SQLite database are
  development transports. Production requires TLS, hardened authentication,
  rate limits, audited storage controls, APNs credentials, and
  migration/operations work.
- Simulator LocalAuthentication and privacy/capture behavior do not reproduce a
  physical device's complete hardware-backed threat model.

## Production work not claimed by this MVP

- Authenticated device-key verification, end-to-end access-request signatures,
  multi-device enrollment, key rotation, recovery, replacement-device
  enrollment, and forward-secure revocation.
- Production Sign in with Apple verification and account-deletion workflows.
- APNs delivery, server-side rate limiting/abuse controls, audit retention, and
  operational key management.
- Guaranteed screenshot prevention, external-camera prevention, or guaranteed
  zeroization of Swift/OS memory copies.
