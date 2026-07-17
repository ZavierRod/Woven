# Pair Vault independent verification report

> Historical MVP baseline. This report records the 2026-07-16/17 local verification at commit `c49bca9`. Production-readiness hardening after that baseline is documented in `staging-readiness.md` and must not be inferred from this historical report.

Verification date: 2026-07-16/17 (America/Los_Angeles)

## Scope and repository integrity

- Original repository preserved at `/Users/zavierrodrigues/Desktop/Woven`.
- All review, edits, builds, and tests in this report used only `/Users/zavierrodrigues/Developer/Woven`.
- Branch: `main`.
- Remote: `git@github.com:ZavierRod/Woven.git`.
- Baseline commit: `b326348073c0f436e5db3e3b620c9859a697f60a` (`Complete Pair Vault MVP`).
- `BackendDiscoveryService.swift` was the previously reported iCloud placeholder. Its relocated tracked copy is readable and matches Git.
- The relocated repository contained no dataless tracked files. The original Desktop repository was not edited or removed during this review.

## Baseline before hardening

- Clean iOS build: passed on iPhone 17 Pro, iOS 26.4.
- Full iOS tests: passed (7 Swift Testing unit tests and 6 UI test invocations across the configured UI variants).
- Full backend tests: 100 passed with one upstream Starlette `TestClient` deprecation warning.
- Xcode `analyze`: passed after rerunning outside the constrained sandbox. The earlier interruption was disk exhaustion, not a diagnostic failure.

## Evidence key

- **Crypto tests**: `PairVaultCryptographyTests` in `WovenTests/PairVaultTests.swift`.
- **State tests**: `PairVaultTwoClientStateTests` in `WovenTests/PairVaultTests.swift`, using the production `PairVaultStore` and `PairVaultCryptography` with an enforcing in-memory relay.
- **Relay tests**: `backend/tests/test_pair_v2.py`, using the actual FastAPI routes, authorization dependencies, SQLAlchemy models, and durable SQLite where indicated.
- **Live flow**: two booted iOS 26.4 Simulators (Alice on iPhone 17 Pro Max and Bob on iPhone 17 Pro) against the actual `run_pair_dev.py` FastAPI relay and persistent SQLite database.

## Requirement-verification matrix

### Membership and invitations

| Requirement | Status | Implementation | Automated proof | Integration proof and remaining limitation |
|---|---|---|---|---|
| Exactly two members | Verified | `create_pair_vault`, `accept_invitation`, `PairMemberV2` uniqueness constraints | `test_invitation_is_targeted_expiring_and_one_use` | Alice/Bob joined; live Charlie received 403. Development identities are not production identity proofing. |
| Invitation single use / cannot be reused | Verified | `PairInvitationV2.status`; conditional pending-to-accepted update | same relay test | Live replay returned 409 after restart. |
| Invitation expires | Verified | `list_invitations`, `accept_invitation`, `list_pair_vaults` | `test_expired_invitation_cannot_be_accepted` | Live access-request expiry was timed end-to-end; invitation expiry is directly proven at the real route with controlled time. |
| Inviter cannot accept own invitation | Verified | target-account authorization in `accept_invitation` | `test_invitation_is_targeted_expiring_and_one_use` | The live invitation was visible/usable only by Bob. |
| Third user cannot join | Verified | target user/device binding and active membership checks | same relay test | Live `live_charlie` attempt returned 403. |
| Membership survives backend restart | Verified | persistent `PairVaultV2` and `PairMemberV2` | `test_membership_request_and_encrypted_media_survive_backend_restart` | Same live vault was rediscovered by both Simulators after stopping and restarting FastAPI. SQLite is a development persistence target. |
| Revocation invalidates requests | Verified | `revoke_pair_member` increments membership version, revokes vault, clears envelopes, cancels outstanding requests | `test_membership_revocation_invalidates_outstanding_approval`; state test | Live Bob request changed from pending to cancelled and Bob returned to the create-vault state. |

### Cryptography

| Requirement | Status | Implementation | Automated proof | Integration proof and remaining limitation |
|---|---|---|---|---|
| Random 256-bit vault key | Verified | `PairVaultCryptography.generateVaultKey` using `SecRandomCopyBytes` | `twoSharesAreRequiredAndReconstructExactly` asserts 32 bytes | Live vault creation and both unlock directions exercised generated material. Statistical RNG validation remains platform/vendor assurance. |
| Two shares reconstruct | Verified | XOR `split` / `combine` | same crypto test | Both live members unlocked the same photo only after approval. |
| One share is insufficient | Verified | random 32-byte local share; complementary partner share | same crypto test asserts neither share equals key and cannot decrypt | Relay database and serialized-relay scans contained neither device share. |
| Incorrect shares fail | Verified | AES-GCM rejects the incorrectly reconstructed key | same crypto test explicitly attempts decryption | No live raw-share manipulation was needed; production crypto path is used by the test. |
| Long-term private keys remain on device | Verified | `PairVaultKeychain.identityPrivateKey`; only public key registration | state tests and backend schema/serialization assertions | Keychain uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; live DB schema/data contained only public keys. A compromised device is out of scope. |
| Fresh requester ephemeral key | Verified | `requestAccess` calls `generateIdentityPrivateKey` for every request and clears it on all terminal/lock paths | state test asserts all request ephemeral public keys are distinct | Multiple live requests in both directions completed. |
| Wrong recipient cannot decrypt | Verified | Curve25519 + HKDF + AES-GCM envelope | `curve25519EnvelopeRoundTripRejectsWrongRecipientSenderAndContext` | Production crypto implementation tested; live flow used designated devices. |
| Ciphertext tampering fails | Verified | AES-GCM media and envelope authentication | `envelopeAndMediaTamperingAreDetectedAndNoncesAreFresh` | Tampered consumed envelope state test remains locked. |
| Authenticated metadata tampering fails | Verified | canonical metadata/media AAD | same crypto test | Relay sees only opaque metadata ciphertext. |
| Cross-vault substitution fails | Verified | vault ID and membership version in canonical AAD/context | crypto tests for envelope and media | Live relay binds every request/media lookup to authorized vault membership. |
| Cross-request substitution fails | Verified | request ID, devices, accounts, ephemeral key and times in `PairAccessContext` | envelope test with a different request ID | Live request contexts were generated and checked in both directions. |
| No plaintext shares/keys serialized | Verified | Pair v2 schemas/models contain encrypted envelopes only | state serialization assertions; `test_relay_stores_invitation_hash_not_raw_token` | Live Pair v2 schema and database string/header scans found no share/key/plaintext media. Legacy non-Pair-v2 tables remain in the development database schema but are not used by Pair v2. |
| Backend cannot reconstruct key | Verified | relay never receives either local share or a vault key; consumed envelope is erased | state serialization and backend persistence tests | Live DB held ciphertext, public keys, identifiers, and a token hash only. This is architectural verification, not a formal cryptographic proof. |

### Access-request state machine

| Requirement | Status | Implementation | Automated proof | Integration proof and remaining limitation |
|---|---|---|---|---|
| Creation and awaiting approval | Verified | `requestAccess`, `create_access_request`, `.creatingRequest`, `.awaitingApproval` | state happy path; `test_pair_access_approval_is_bound_one_time_and_replay_safe` | Observed on both live Simulators. |
| Approval | Verified | authenticated `approve`, conditional pending-to-approved update | state happy path and relay one-time test | Face ID matching response used on disposable Simulators in both directions. |
| Denial | Verified | `deny`, conditional pending-to-denied update | relay terminal-path test | Live denial left Bob locked. Fresh-request UI is now available. |
| Cancellation | Verified | `cancelAccessRequest`, conditional terminal transition clearing envelope | relay terminal-path test | Live cancellation returned Bob to locked request-ready state. |
| Expiration | Verified | two-minute client deadline plus server transition | expiry tests, including no denied/cancelled relabel | Live request was allowed to expire for the real two-minute interval and stayed locked. |
| Consumption | Verified | `consumeApprovedRequest`; conditional approved-to-consumed update erases relay envelope | one-time relay and state tests | Both live directions consumed successfully. |
| Failure | Verified | all consume/crypto errors clear ephemeral key and transition to `.failed` while locked | `tamperedConsumedApprovalFailsClosedWithoutUnlocking` | Modified-envelope failure uses production store/crypto; the actual live relay was separately exercised for success/replay/authorization. |
| Requester/self cannot approve | Verified | approver user ID authorization | relay terminal-path test | Live controls expose approval only to partner. |
| Wrong member cannot approve | Verified | designated approver and active device/membership binding | relay terminal-path test with Charlie | Live Charlie could not join or access the Pair object. |
| Approval only once / replay fails | Verified | conditional updates and envelope erasure on consume | one-time relay test | Live persisted consumed approval replay returned 409. |
| Denied/cancelled/expired cannot unlock | Verified | terminal statuses rejected by consume; requester store remains locked | relay terminal tests | All three were separately exercised live. |
| Membership changes invalidate requests | Verified | membership-version context plus revocation cancellation | revocation tests | Live outstanding request became cancelled on revocation. |

### Media protection

| Requirement | Status | Implementation | Automated proof | Integration proof and remaining limitation |
|---|---|---|---|---|
| Encrypt before upload | Verified | `importPhoto` seals blob and private metadata before `uploadMedia` | state plaintext-absence assertion; crypto image-header test | Alice imported a real JPEG; DB blob began with non-JPEG ciphertext bytes. |
| No backend plaintext media | Verified | `PairMediaV2` accepts encrypted blob/metadata only | persistence/plaintext test | Live DB `strings`/SQL inspection found no JPEG/Exif/JFIF or vault name/token markers. |
| No persisted plaintext thumbnails | Verified | `PairDecryptedMedia` exists only in memory; locked state clears it | state lock/relaunch assertions | Background privacy shield and relaunch snapshots exposed no thumbnail. No Pair thumbnail persistence or cache path exists. |
| Stored blob has no original header | Verified | AES-GCM combined ciphertext | crypto test starts plaintext with JPEG header and asserts absence | Live decoded blob did not begin `ff d8`. |
| Media survives app/backend restart | Verified | durable encrypted `PairMediaV2`; device-only shares persist in Keychain | backend restart and state relaunch tests | Live encrypted record survived relay restart and the vault remained discoverable/locked after app relaunch. SQLite remains development-only. |
| Locked/relaunched views expose nothing private | Verified | `lock` clears key/media; `PairVaultPrivacyShield`; locked copy uses no private name | state tests | Live accessibility snapshots after Home/relaunch showed only generic locked text and no photo/name/key. |
| Delete removes backend blob | Verified | authorized `delete_pair_media` | relay media test and state test | Live DELETE returned 204 and DB count became zero. |
| No widgets/App Intents/Spotlight/log/notification/external previews | Verified | Pair feature has no external-surface registration and logs no Pair content | repository-wide negative surface/log scan plus state plaintext scan | Fourteen live runtime/OSLog files had no token, name, authorization, envelope, key/share, or media markers. Negative verification cannot replace a full device forensic review. |

### Lifecycle behavior

| Requirement | Status | Implementation | Automated proof | Integration proof and remaining limitation |
|---|---|---|---|---|
| Locks on background | Verified | `PairVaultRootView` scene-phase handler calls `lock` and overlays privacy shield | state `lock` clearing assertions | Live Home action immediately produced “Woven content hidden while inactive” and no private accessibility content. |
| Locks on timeout | Verified | `startLockTimeout`, production duration 300 seconds | state test injects a two-second timeout and verifies locked/empty state through the same production path | Production duration was not idled for five minutes in UI; only the duration value differs in the deterministic test. |
| Locks on logout | Verified | `logout` calls `lock` then clears session | state test logs Bob out while unlocked, asserts empty/signed-out, signs in to locked state | Live development account switches also returned locked. |
| Locks after relaunch | Verified | no vault key/decrypted media persistence | state relaunch test | Both live app relaunches required Pair sign-in and returned locked. |
| Screen-capture response | Partially verified | `UITraitSceneCaptureState` monitor locks and privacy shield remains while active | lock/clearing path is directly tested | Static integration is present, but an active screen-recording transition while unlocked was not reliably automatable on these disposable iOS 26.4 Simulators. Validate again on physical hardware before release. |
| Key and decrypted media leave feature state on lock | Verified | `lock` nils `vaultKey` and request ephemeral key and removes `decryptedMedia` | state lock, timeout, logout, tamper, and revocation assertions | Live inactive/relaunched accessibility inspection showed no private presentation. Swift/Data zeroization is not guaranteed by the language runtime. |

### Bidirectional behavior

| Requirement | Status | Implementation | Automated proof | Integration proof and remaining limitation |
|---|---|---|---|---|
| Alice requests, Bob approves | Verified | common request/approve/consume path | state test explicitly executes direction one | Live Alice unlocked and displayed the imported JPEG after Bob approval. |
| Bob requests, Alice approves | Verified | same path with inverted bound account/device context | state test explicitly executes inverse direction | Live Bob unlocked and displayed the same JPEG after Alice approval. |

## Live adversarial results

- Wrong invitation code: rejected and did not join.
- Denial, cancellation, and real two-minute expiration: each remained locked.
- Invitation replay: HTTP 409.
- Consumed approval replay after relay restart: HTTP 409.
- Third user invitation acceptance: HTTP 403.
- Modified approval envelope: production store/crypto test transitioned to failed and remained locked.
- Revocation during a live pending Bob request: vault became `revoked/v2`, request became `cancelled`, and Bob returned to no-vault state.
- Oversized Pair bodies: declared-length and chunked-transfer requests both return HTTP 413.

## Issues found and fixes

1. Production configuration defaulted to debug mode and a committed JWT secret. Defaults now fail closed (`DEBUG=false`, no secret), non-debug startup requires a secret of at least 32 characters, and the local runner/tests inject explicit disposable values.
2. Approval, denial, cancellation, consumption, and invitation acceptance depended on `SELECT ... FOR UPDATE`, which SQLite ignores. One-time transitions now use conditional SQL updates and conflicts fail closed.
3. Expired requests could be relabelled denied/cancelled. Those endpoints now persist `expired` and return conflict.
4. A tampered consumed approval left the client UI in `.approved`. The store now clears ephemeral material and transitions to `.failed` without unlocking.
5. Denied/expired/failed UI had no path to create the promised fresh request. A locked-only “Request Fresh Approval” action was added.
6. Pair request size enforcement trusted `Content-Length`. The ASGI middleware now counts actual chunks and enforces a 21 MiB total cap.
7. Existing adversarial tests did not directly prove incorrect-share media failure, JPEG header opacity, cross-vault/media membership substitution, fresh request keys, modified consumed-envelope fail-closed state, or the real timeout path. Focused assertions/tests were added.

## Remaining development-only limitations

- `/pair-v2/dev/session/{alice|bob}`, polling, permissive CORS, SQLite, and mDNS are development facilities. The dev-session route is unavailable when `DEBUG=false`, but production authentication, origin policy, rate limiting, operational monitoring, and a production database deployment still require deployment-specific configuration.
- The relay observes account/device/vault identifiers, membership, object sizes, request timing, and access patterns. It does not provide traffic-analysis resistance.
- Polling is bounded by one task per signed-in store and is cancelled at logout, but it is not a production push/stream transport.
- Keychain protection is device-only and unlocked-device scoped; device compromise and memory inspection while unlocked are outside this MVP threat boundary.
- Swift and CryptoKit do not promise deterministic memory zeroization of copied `Data` buffers.
- Screen-capture transition behavior needs physical-device validation.
- This review is implementation verification, not an independent formal cryptographic proof, penetration test, or production infrastructure assessment. External professional cryptographic and application-security review remains required before handling high-value private media.

## Final verification

- Post-fix clean iOS build: passed without warnings in 9.0 seconds.
- Full iOS result: passed on iPhone 17 Pro / iOS 26.4, with 11 logical tests, 14 device/configuration executions, zero failures, and zero skips. The executions comprise 8 Swift unit/state tests and 6 UI test/launch invocations.
- Full backend result: 103 passed in 37.97 seconds, with only the upstream Starlette `TestClient` deprecation warning.
- Xcode static analysis: `** ANALYZE SUCCEEDED **` with no product diagnostics.
- Runtime/OSLog sensitive-marker scan: zero matches across 14 Pair live-run logs.
- Final repository scan: no dataless or unreadable files, databases, credentials, key files, virtual environments, build products, screenshots, result bundles, or uploaded-media artifacts in the working tree.
- The exact final pushed commit hash is recorded in the completion response because a Git commit cannot embed its own hash.
