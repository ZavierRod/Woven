# Pair Vault staging-readiness verification report

Verification date: 2026-07-17 (America/Los_Angeles)

## Repository and scope

- Original repository (preserved, not edited or deleted during this continuation): `/Users/zavierrodrigues/Desktop/Woven`.
- Relocated repository used for every edit, build, test, container, and Simulator action: `/Users/zavierrodrigues/Developer/Woven`.
- Branch: `main`.
- Remote: `git@github.com:ZavierRod/Woven.git`.
- Starting pushed commit for this continuation: `c49bca9ba13ec51df9d7ce236f46b822c13a689c` (the earlier relocation/MVP commit is `b326348073c0f436e5db3e3b620c9859a697f60a`).
- Previously reported iCloud placeholder: `Woven/Services/BackendDiscoveryService.swift`. The relocated file is readable. A complete tracked-file read found no dataless/unreadable files.
- Baseline from the relocated clone, before the changes in this report: clean iOS build passed; 7 unit and 6 UI executions passed; 100 backend tests passed. Static analysis had previously stopped only when the Mac exhausted disk space.

The final pushed commit is intentionally recorded in the completion response; a commit cannot contain its own hash. The original Desktop repository remains the user’s recovery copy.

## Evidence key

- **Crypto**: `WovenTests/PairVaultTests.swift`, `PairVaultCryptographyTests`.
- **Two-client state**: the production `PairVaultStore` and `PairVaultCryptography` with distinct Alice/Bob secrets and an enforcing deterministic relay in `PairVaultTwoClientStateTests`.
- **HTTP/DB**: actual FastAPI routes, authorization dependencies, SQLAlchemy models, and SQLite/PostgreSQL in `backend/tests/test_pair_v2.py`, `test_production_auth.py`, and `test_staging_boundaries.py`.
- **Live**: Alice on iPhone 17e and Bob on iPhone 17 Pro, both iOS 26.4 Simulators, using the real Debug app and a disposable Python 3.12 FastAPI container.
- **Operations**: PostgreSQL 16 migration upgrade/downgrade/re-upgrade and `alembic check`; hardened container; dependency/static audits; Release Xcode analysis.

## Requirement-verification matrix

### Membership and invitations

| Requirement | Status | Implementation | Automated proof | Integration proof / limitation |
|---|---|---|---|---|
| Exactly two members | Verified | `pair_v2.create_pair_vault`, `accept_invitation`; DB uniqueness | invitation/third-member tests | Live DB contained one vault, two members, two active devices. |
| Invitation single use and cannot be reused | Verified | conditional pending-to-accepted transition; token SHA-256 only | `test_invitation_is_targeted_expiring_and_one_use` | Live one-time code joined Bob; persisted DB contained no raw code. |
| Invitation expires | Verified | server time/status checks in invitation list/accept | `test_expired_invitation_cannot_be_accepted` | Real route tested with controlled expiry; no wall-clock Simulator wait repeated. |
| Inviter cannot accept own invitation | Verified | target account/device authorization | targeted invitation test | Live invitation appeared only on Bob’s UI. |
| Third user cannot join | Verified | target binding and two-member invariant | targeted invitation/third-member assertion | Deterministic HTTP harness receives 403; Debug UI intentionally exposes only Alice/Bob. |
| Membership survives restart | Verified | durable Pair vault/member rows | `test_membership_request_and_encrypted_media_survive_backend_restart` | Historical live restart plus current persisted-container inspection; staging uses PostgreSQL. |
| Revocation invalidates outstanding requests | Verified | membership version bump, vault/member revoke, request cancellation | `test_membership_revocation_invalidates_outstanding_approval`; state test | Deterministic real-route and production-store coverage. |

### Cryptography

| Requirement | Status | Implementation | Automated proof | Integration proof / limitation |
|---|---|---|---|---|
| Random 256-bit vault key | Verified | `PairVaultCryptography.generateVaultKey` / Security RNG | `twoSharesAreRequiredAndReconstructExactly` | Live vault creation used the production code path; RNG assurance ultimately relies on Apple. |
| Two shares reconstruct | Verified | 2-of-2 XOR `split`/`combine` | crypto test | Both directional deterministic unlocks reconstruct the same vault. |
| Either share alone reveals no usable key | Verified | independent random share and complementary share | share test asserts neither equals key and wrong reconstruction cannot decrypt | Backend serialization/DB contains neither local share. |
| Incorrect shares fail | Verified | AES-GCM authentication after reconstruction | explicit wrong-share decryption assertion | Production CryptoKit implementation is used. |
| Long-term private keys never leave device | Verified | device-only Keychain; registration sends public agreement/signing keys | state serialization and backend schema checks | Live DB contained only public keys; compromised-device memory is out of scope. |
| Fresh requester ephemeral key | Verified | generated per `requestAccess`, cleared on terminal/lock paths | distinct ephemeral-key assertion | Current live run created requests in both directions. |
| Wrong recipient fails | Verified | Curve25519/HKDF/AES-GCM envelope | wrong-recipient crypto test | Bound production crypto path tested. |
| Ciphertext tampering fails | Verified | AES-GCM tag | envelope/media tamper test | Tampered consumed envelope remains locked in state test. |
| Authenticated metadata tampering fails | Verified | canonical AAD | metadata tamper test | Backend sees opaque ciphertext only. |
| Cross-vault substitution fails | Verified | vault/member version in AAD and authorization | crypto and HTTP authorization tests | Actual routes scope every lookup to active membership. |
| Cross-request substitution fails | Verified | request ID/accounts/devices/ephemeral key/times in context | different-request envelope assertion | Actual request records are server-authorized and one-time. |
| Backend never serializes plaintext shares/keys | Verified | Pair schemas have public keys, ciphertext, hashes only | serialization/persistence assertions | Disposable DB marker scan returned `marker_matches: []`. |
| Backend cannot reconstruct vault key | Verified | neither device share nor vault key is sent; consumed envelope erased | state storage scan and HTTP/DB tests | Architectural result; formal protocol review remains required. |

### Access-request state machine

| Requirement | Status | Implementation | Automated proof | Integration proof / limitation |
|---|---|---|---|---|
| Creation / awaiting approval | Verified | `requestAccess`, `create_access_request` | two-client state and route tests | Observed on both live Simulators. |
| Approval | Verified | local authentication then bound envelope; conditional DB transition | state and one-time route tests | Both live UIs reached the iOS device-auth sheet. The Mac locked before the Simulator biometric menu could be triggered; success is directly proven by production-store tests and the prior live baseline. |
| Denial | Verified | conditional pending-to-denied transition | terminal-path route/state tests | Deny control observed live; earlier real live denial stayed locked. |
| Cancellation | Verified | requester-only transition and envelope clear | terminal-path tests | Live Alice cancellation UI/state observed in this verification series. |
| Expiration | Verified | server-enforced expiry | expiry and terminal-relabel tests | Direct actual-route proof; wall-clock wait covered in prior live baseline. |
| Consumption | Verified | approved-to-consumed conditional update, envelope erase | one-time route and state tests | Both directional production-store flows consume; live manual approval was blocked at OS auth as noted. |
| Failure | Verified | crypto/consume errors clear ephemeral/key state and fail closed | tampered consumed-envelope state test | Failure remains locked. |
| Requester cannot self-approve | Verified | server derives account from access token | terminal-path route test | UI offers approval only to partner. |
| Wrong member cannot approve | Verified | designated member/device binding | wrong-approver route test | Third account cannot join or access Pair objects. |
| Approval only once / replay fails | Verified | conditional state transitions and replay uniqueness | one-time/replay route test | Real route returns conflict. |
| Denied, cancelled, expired cannot unlock | Verified | terminal status rejected by consume | direct assertions for all three | Production store remains locked. |
| Membership changes invalidate requests | Verified | membership-version binding and revoke cascade | revocation tests | Request cancellation verified at actual route/DB layer. |

### Media protection

| Requirement | Status | Implementation | Automated proof | Integration proof / limitation |
|---|---|---|---|---|
| Encrypt before upload | Verified | `PairVaultStore.importPhoto` seals media/metadata before API call | plaintext-absence and JPEG-header assertions | Production store path tested; current live run did not inject a new photo into the clean Simulator library. |
| Backend never stores plaintext media | Verified | Pair route accepts ciphertext; opaque private object storage | persistence/plaintext tests | DB marker scan found no vault name, invite code, JFIF, or Exif. |
| No persisted plaintext thumbnails | Verified | decrypted image exists only in feature memory | lock/relaunch state assertions | Locked live UI explicitly exposed no name/thumbnail/media. |
| Stored blob lacks original headers | Verified | AES-GCM combined ciphertext | JPEG-header opacity assertion | Actual storage abstraction tested; private S3 service requires staging drill. |
| Media survives app/backend restart | Verified | durable storage key + Pair media row; Keychain share | restart persistence test | Local persistence proven; object-store backup/restore is an operator drill. |
| Locked/relaunched views expose no private data | Verified | `lock`, generic locked view, privacy shield | state lifecycle assertions | Bob’s live post-accept screen was generic and locked. |
| Delete removes encrypted blob | Verified | storage delete plus row delete | encrypted-media deletion tests | Local storage implementation tested; provider delete semantics need staging observation. |
| No Pair widgets/App Intents/Spotlight/log/notification/preview leakage | Verified | Pair is absent from external registrations; structured logs omit bodies/headers | repository negative scans and state serialization | Live backend logs contained routes/status/IDs only; negative evidence is not device forensics. |

### Lifecycle and directionality

| Requirement | Status | Implementation | Automated proof | Integration proof / limitation |
|---|---|---|---|---|
| Lock on background | Verified | scene-phase handler and privacy shield | state lock clearing | Simulator relaunch returned to generic locked state. |
| Lock on timeout | Verified | cancellable five-minute timer | injected two-second production-path test | Duration is shortened only through dependency injection in test. |
| Lock on logout | Verified | `logout` locks then clears session | logout state assertions | Live account sign-out returned to selector. |
| Lock after relaunch | Verified | no reconstructed key/media persistence | relaunch state test | Live Bob accepted, relaunched, and remained locked. |
| Screen-capture response | Partially verified | capture-state monitor locks and shields | shared lock/clear path | iOS 26.4 Simulator transition was not reliable; physical-device screen recording and screenshot behavior remain in the runbook. |
| Decrypted media/key leave feature state | Verified | `lock` nils key/ephemeral material and clears media | lock/timeout/logout/tamper/revoke assertions | Swift `Data` does not promise deterministic memory zeroization. |
| Alice requests, Bob approves | Verified | common bound request path | explicit first direction in two-client test | Live Alice request appeared on Bob; OS approval success relies on direct automated/prior-live evidence. |
| Bob requests, Alice approves | Verified | same path with inverse accounts/devices | explicit inverse direction in two-client test | Live Bob request appeared on Alice; clean Simulator lacked an enrolled passcode. |

## Adversarial and operational evidence

- Actual-route tests cover invitation replay/expiry/self/third user, self/wrong approval, denial, cancellation, request expiry, approval replay, revocation, IDOR checks, declared and streamed oversize bodies, path traversal, and backend restart.
- Signed device requests bind protocol, method, path, request/account/device/vault IDs, timestamp, nonce, and body hash. Tests reject body/header tampering, replay, stale time, and cross-account tokens.
- Apple identity tests reject wrong nonce/audience/expiry/signature. Refresh rotation tests detect reuse, revoke the family, and invalidate issued access tokens.
- Remote configuration fails closed unless it has HTTPS, PostgreSQL, Apple audience, strict hosts/CORS, private object storage credentials, strong independent secrets, and enforced device signatures.
- PostgreSQL 16 migrations passed clean upgrade, security-migration downgrade/re-upgrade, and `alembic check` with no pending operations.
- Live two-user DB inspection: two users, two active devices, one vault, two members, two requests; no raw invitation token, private vault name, JFIF, or Exif marker.
- The live run found and fixed credential-blind IP rate buckets. Alice and Bob behind the same Simulator/Docker NAT had exhausted one another’s Pair budget. Authenticated buckets now use only an in-memory SHA-256 of the credential, and a regression test proves distinct credentials are isolated. The fixed live run created and accepted the vault without 429 responses.

## Security hardening delivered

1. Added explicit local/test/staging/production configuration and remote fail-closed validation.
2. Added Sign in with Apple RS256/JWKS/nonce validation, short access tokens, hashed rotating refresh credentials, family reuse detection, logout, and authentication-generation revocation.
3. Added one-active-Pair-device enrollment with separate agreement/signing keys, list/revoke endpoints, and revocation cascades.
4. Added Ed25519 application-layer request signatures and replay tables for sensitive Pair calls.
5. Replaced DB blobs for new Pair media with an opaque local/object-storage abstraction; blocked traversal and public URLs.
6. Added request-size/time/rate boundaries, security headers, trusted hosts, restrictive CORS, minimal health/readiness, remote docs disablement, safe structured logs, and local-only mDNS.
7. Added PostgreSQL-ready UUID models/migration, non-root read-only-compatible container, staging Compose reference, separate single-writer migration step, CI, dependency updates/audits, and Dependabot.
8. Added Release fail-closed iOS configuration, Apple sign-in/refresh UI, device-only Keychain accessibility, per-request Ed25519 signatures, production partner lookup, and removed production development-account selection.
9. Fixed a Release-only compile failure by excluding Debug preview fixtures from Release analysis.
10. Fixed authenticated rate-limit cross-talk for users sharing an IP/NAT.

## Focused tests added

- Swift: explicit single-share/incorrect-share failure, wrong recipient/sender, cross-vault and cross-request binding, ciphertext/metadata tampering, nonce freshness, JPEG-header opacity, both directional approvals, denial/cancellation/expiry/replay/revocation behavior, relaunch/logout/timeout locking, encrypted deletion, and tampered-consume fail-closed state.
- Backend: invitation expiry/reuse/targeting, signed-request tamper/replay/cross-account rejection, device list/revoke, approval terminal states and replay, restart persistence, storage opacity/traversal, staging fail-closed configuration, Apple token verification, refresh-family reuse, security headers, and per-credential rate-limit isolation.
- The backend suite grew from the 100-test baseline to 112 tests. The final Swift suite contains eight logical unit/state tests plus six configured UI/launch executions.

## Final verification results

- Backend: **112 passed** in 40.36 seconds on Python 3.12 in the hardened container.
- PostgreSQL migration verification: upgrade/downgrade/re-upgrade and `alembic check` passed.
- Python static/dependency results: Ruff passed; Bandit passed with the OAuth `bearer` scheme false positive explicitly scoped as `B105`; `pip-audit` found no unexcepted vulnerability and reported seven records ignored under the five documented Starlette advisory IDs.
- iOS unit tests: **8 passed**, zero failures, in the final post-fix run.
- iOS UI tests: **6 executions passed**, zero failures, in 144.62 seconds in the final post-fix run.
- Xcode Release analysis: exit 0 after the preview-boundary fix, with no product diagnostic.

## Remaining development-only and external-review items

- A deployed staging environment was not provisioned because no hosting, DNS/TLS, Apple entitlement/profile, real Apple IDs, PostgreSQL service, private object bucket, secret manager, or APNs credential was supplied. `staging-readiness.md` is the exact two-iPhone/operator runbook.
- Physical-device Apple sign-in, Face ID/passcode, screenshot/screen-recording, background/reboot, clock-skew, network interruption, private object-store inspection, ingress headers/rates, and backup/restore must be recorded in staging.
- APNs, account/device recovery, replacement-device policy, post-revocation content-key rotation, operational alerting/ownership, privacy/retention policy, and production traffic-analysis decisions remain product/deployment work.
- Follow-up on 2026-07-17: compatible FastAPI 0.139.2 and Starlette 1.3.1 releases became available, so all five Starlette audit exceptions were removed. The historical audit result above describes the prior milestone only; current CI has no ignored vulnerability IDs.
- Professional cryptographic protocol review, mobile application-security review, penetration testing, privacy review, and production infrastructure review remain required before public or high-value use.
