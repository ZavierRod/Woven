# Woven roadmap and implementation status

Status date: 2026-07-17.

## Implemented

- On-device AES-GCM media and metadata encryption for Solo and Pair vault paths.
- Pair v2 two-member membership, targeted expiring one-time invitations, XOR 2-of-2 shares, Curve25519 envelopes, approval/denial/cancellation/expiry/consumption, revocation, encrypted media, and lifecycle locks.
- Sign in with Apple client nonce flow and backend signature/JWKS, issuer, audience, expiry, and nonce validation.
- Short access JWTs, hashed rotating refresh credentials, reuse-family revocation, logout, and device-bound refresh revocation.
- One active Pair device per account, separate agreement/signing keys, device list/revoke, and canonical Ed25519 signed sensitive requests with freshness and replay rejection.
- Explicit local/test/staging/production configuration; PostgreSQL and private object storage required remotely.
- Container, migrations, health/readiness, request limits/timeouts, request IDs, restrictive hosts/CORS, rate limiting, security headers, structured logging, and CI gates.

## Required before a public launch

- Deploy and exercise an actual staging hostname, PostgreSQL service, private object bucket, TLS ingress, secret manager, monitoring, and automated encrypted backups.
- Complete the physical two-iPhone checklist in `docs/staging-readiness.md`, including real Apple accounts, reinstall/relaunch, revocation, clock-skew, network interruption, and screen-capture behavior.
- Configure production Apple identifiers and validate App Store entitlements/provisioning.
- Select and implement APNs delivery. Polling remains the explicit current transport and APNs is not claimed complete.
- Add retained security audit events, operational alert thresholds, abuse escalation, key rotation after membership change, and an explicit account/device recovery policy.
- Obtain independent application-security and cryptographic review and perform a penetration test against the deployed staging service.

## Product decisions still open

- Device-loss recovery versus maximum-privacy no-recovery.
- Post-revocation rekeying and treatment of previously downloaded ciphertext.
- Notification quiet hours and abuse controls.
- Retention/deletion policy and user-facing account deletion.
- Whether Normal mode should cache approval for a bounded interval; Pair v2 currently follows strict two-party unlock semantics.
