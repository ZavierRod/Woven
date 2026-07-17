# Staging deployment and physical-device runbook

This is the operator checklist for a real staging environment. It does not select or create a hosting provider. Commands are examples; adapt service names to the chosen platform without weakening the boundaries below.

## Required services and trust boundaries

1. A dedicated staging DNS name with valid publicly trusted TLS, such as `api.staging.example.com`.
2. A private PostgreSQL 16 database reachable only by the API workload and administrators.
3. A private S3-compatible bucket with public access blocked, encryption at rest enabled, and credentials scoped to that one bucket.
4. A secret manager for database credentials, JWT secret, refresh pepper, object credentials, and any future APNs key. Do not store populated `.env` files in Git or container images.
5. Central log collection and alerts. Logs may contain request ID, route template, status, duration, account/device opaque IDs, and rate-limit events. They must not contain Authorization headers, Apple tokens, refresh tokens, signatures, nonces, request bodies, invitation tokens, encrypted envelopes, filenames, or decrypted content.

The object store is never public. Clients upload and download through authenticated API routes. Object keys are random opaque identifiers and reveal no account, vault, media ID, or filename.

## Apple configuration

1. In the Apple Developer portal, enable Sign in with Apple for the staging app identifier used by the installed build.
2. Set `APPLE_CLIENT_ID` to the exact identity-token audience. For the native app this is normally its bundle identifier; confirm the value from Apple rather than guessing.
3. Ensure the Xcode target has the Sign in with Apple entitlement and a matching provisioning profile.
4. The client generates a random raw nonce, sends its SHA-256 value to Apple, and sends the raw nonce only to Woven. The backend verifies Apple’s RS256 signature via the configured JWKS URL and requires issuer, audience, subject, issued-at, expiry, and matching nonce.
5. Never log the Apple credential or raw nonce. Apple name/email may be returned only on first authorization; Woven must continue to work when later credentials omit them.

## Environment and first deployment

Create deployment secrets from `backend/.env.staging.example`. Generate independent values of at least 32 random characters for `SECRET_KEY` and `REFRESH_TOKEN_PEPPER`. Set a PostgreSQL DSN, HTTPS public URL, exact trusted host, restricted CORS origins if a browser client exists, Apple audience, object endpoint/bucket/region/credentials, and `ENFORCE_DEVICE_SIGNATURES=true`.

Validate before rollout:

```bash
docker compose --env-file .env.staging config
docker compose --env-file .env.staging build
docker compose --env-file .env.staging run --rm api alembic upgrade head
docker compose --env-file .env.staging up -d
curl --fail https://api.staging.example.com/health
curl --fail https://api.staging.example.com/ready
```

Do not publish port 8000 directly. Terminate TLS at a maintained ingress/load balancer, forward only to the private API network, preserve `X-Forwarded-Proto`, cap request sizes there as well, and set idle/request timeouts no larger than the application boundary.

## Migration and rollback policy

- Back up PostgreSQL before every schema rollout.
- Run `alembic upgrade head` as a one-off release job before shifting traffic. Do not let many API replicas race migrations.
- Verify `alembic current` equals head and `GET /ready` succeeds before traffic.
- Prefer forward fixes. Use `alembic downgrade -1` only after confirming the migration’s downgrade is data-safe for the deployed rows.
- The security migration requires existing local Pair devices to re-enrol; copied legacy agreement bytes are migration scaffolding, not a valid signing identity. Staging should begin empty or explicitly revoke/re-enrol migrated devices before enabling traffic.
- Roll back the application image independently only when it is compatible with the current schema.

## Backup and restore drill

Use the provider’s encrypted automated backups plus a separately retained logical backup. Example:

```bash
pg_dump --format=custom --no-owner --dbname "$DATABASE_URL" --file woven-staging.dump
createdb woven_restore_drill
pg_restore --clean --if-exists --no-owner --dbname woven_restore_drill woven-staging.dump
```

Run `alembic current` and a read-only integrity check against the restored database, then destroy the drill database. Test restoration at least quarterly and before a production launch. Backups contain ciphertext and sensitive relationship metadata; restrict and audit access and define retention/deletion periods.

Object storage needs versioning or provider snapshots and lifecycle rules consistent with database retention. A database restore without corresponding ciphertext objects is incomplete; document a common recovery point.

## Build a staging iOS artifact

Create a staging build configuration or injected Release setting with:

- `WOVEN_ENVIRONMENT=staging`
- `WOVEN_API_BASE_URL=https://api.staging.example.com`
- the staging bundle identifier/provisioning profile with Sign in with Apple

Release code rejects local/test environments, HTTP, localhost, unresolved build variables, and empty URLs. Do not add ATS exceptions for the staging host. Local-network/Bonjour declarations are for Debug development and should be removed from a distribution-specific plist if the product no longer needs them.

## Two-iPhone verification

Use two physical iPhones with different real Apple IDs and Face ID/passcodes enabled. Record app build, iOS versions, backend commit/image, migration head, and UTC time. Do not record identity tokens, invite tokens, keys, signatures, or media plaintext.

1. Install cleanly on both phones. Confirm each sees Sign in with Apple, never Alice/Bob controls.
2. Sign in as User A and User B. Confirm two backend users and exactly one active Pair device per account; database rows contain only public agreement/signing keys and hashed refresh secrets.
3. On B, note the displayed invite code. On A, create a Pair vault using that code. Transfer the one-time invitation code out of band and accept on B.
4. Attempt self-acceptance, wrong code, replay, expiry, and a third account. Each must fail without changing membership.
5. Import a recognizable photo on A. Inspect PostgreSQL and the private bucket: the object key is opaque, the bytes do not begin with the source header, and neither filename, vault name, token, thumbnail, key, nor share is present.
6. Lock both apps. Have A request access and B deny; repeat and cancel; repeat and allow expiry. A must remain locked each time.
7. Have A request and B approve after local authentication. A may decrypt only after consuming the bound one-time envelope. Replay consumption must fail. Repeat in the opposite direction.
8. Background, lock, relaunch, and reboot each phone. Confirm private name/media/thumbnail is absent while locked and approval is again required.
9. Start screen recording/mirroring while unlocked. Confirm immediate cover and lock. Take a screenshot and confirm the documented current response; APNs notification is deferred and must not be claimed.
10. Interrupt network during create, accept, approve, consume, upload, and delete. Confirm retry/error states do not unlock, duplicate membership, reuse identifiers, or leave plaintext caches.
11. Set one phone’s clock outside the allowed skew. Signed sensitive requests must fail; restore automatic time and verify a fresh request succeeds.
12. Revoke B’s device from B (or the authorized account device-management surface). Its refresh family and access generation must be invalidated, outstanding requests cancelled, Pair membership/vault revoked, and subsequent signed calls rejected.
13. Delete an encrypted media object and verify both the database record and bucket object disappear. Review logs by request ID and confirm no prohibited values were emitted.

## Exit criteria

Staging is ready for wider internal testing only when CI is green, migrations and restore have been exercised, HTTPS/headers/rate limits are observed at the public edge, object storage is private, Apple login and refresh rotation work on two physical phones, signed-device adversarial cases fail closed, and the full two-user workflow above has recorded evidence. APNs, recovery, post-revocation key rotation, formal security review, and production operational ownership remain explicit blockers for a public launch.

## Dependency-audit exception

As of 2026-07-17, `pip-audit` reports five 2026 Starlette advisories whose stated fixes are Starlette 1.0.1–1.3.1, while the newest package published to the configured index is 0.49.3 and the newest FastAPI line is 0.128.8. CI ignores only `PYSEC-2026-161`, `PYSEC-2026-249`, `PYSEC-2026-248`, `PYSEC-2026-2281`, and `PYSEC-2026-2280`; every other advisory remains blocking. Recheck this exception on every dependency update and remove it as soon as a compatible fixed release exists. Compensating boundaries are authenticated native clients, strict request-size/time limits, no remote documentation/static-file surface, and a maintained TLS ingress, but these do not constitute a vendor fix.
