# Staging deployment record

Status: **The one-iPhone-plus-Simulator MVP path is working: Google and Apple sign-in, Pair Vault creation, one media upload, and decrypted viewing by both users were observed. Formal two-physical-iPhone and broader security acceptance remain pending.**

The deployed backend includes fail-closed Google authentication and the
`google_user_id` migration. Matching Google iOS and Web/server OAuth client IDs
are now configured without a Google client secret. The enabled `/auth/google`
route rejects an invalid token with 401.

## Provider and artifact identity

| Field | Result |
|---|---|
| Provider / plan | Railway / Hobby |
| Project / environment | `Woven Staging` / `staging` |
| API service | `woven-api` |
| PostgreSQL service | `Postgres` |
| Object bucket | `woven-staging-ciphertext` |
| Compute / bucket region | `us-west2` / `sjc` (US West, California) |
| Public HTTPS API hostname | `woven-api-staging.up.railway.app` |
| Backend Git commit | `a75c4d20929d9987e6266e46160730cc0d49f9c9` |
| Alembic revision | `a4b7c9d2e301` (head) |

No credential, secret, token, connection string, private object name, or user data is recorded here.

## Configured application variable names

Railway resolves these names from fixed staging policy values, generated staging-only secrets, or private service/bucket references. Values are intentionally omitted:

`APP_ENV`, `DEBUG`, `PUBLIC_BASE_URL`, `DATABASE_URL`, `SECRET_KEY`, `REFRESH_TOKEN_PEPPER`, `APPLE_CLIENT_ID`, `GOOGLE_CLIENT_ID`, `TRUSTED_HOSTS`, `CORS_ORIGINS`, `PORT`, `STORAGE_BACKEND`, `ENFORCE_DEVICE_SIGNATURES`, `OBJECT_STORAGE_ENDPOINT`, `OBJECT_STORAGE_BUCKET`, `OBJECT_STORAGE_REGION`, `OBJECT_STORAGE_ACCESS_KEY`, `OBJECT_STORAGE_SECRET_KEY`, `OBJECT_STORAGE_ADDRESSING_STYLE`, and `OBJECT_STORAGE_SERVER_SIDE_ENCRYPTION`.

`APPLE_ISSUER` and `APPLE_JWKS_URL` retain the pinned official defaults. The exact non-secret and human-controlled value inventory, source, configuration location, and verification method are recorded in `staging-values.md`.

`GOOGLE_CLIENT_ID` is the non-secret Web/server OAuth client ID and matches the
Staging app's server audience. The official Google issuer and JWKS settings
remain pinned repository defaults.

## Railway controls

- The project contains only the `staging` environment. Railway's empty default `production` environment was removed before services were created.
- API and PostgreSQL each have exactly one `us-west2` replica, capped at 0.25 vCPU and 256 MiB RAM.
- API serverless sleep is enabled. PostgreSQL is not replicated and remains available for readiness checks.
- The API uses a Railway-provided TLS domain on port 8000. No custom domain was purchased.
- PostgreSQL has no TCP proxy, public domain, or custom domain. The API references its private `DATABASE_URL`.
- The bucket is in `sjc`, is private by Railway design, and uses Railway reference variables for credentials.
- The bucket adapter uses virtual-hosted addressing and omits the unsupported S3 server-side-encryption request header. Stored Woven payloads remain application ciphertext.
- Railway does not permit the requested $5 workspace hard limit: its API/CLI requires a hard limit of at least $10 (or $0), and email alerts also start at $5. No higher limit was configured because it would exceed the authorized boundary. Per-service limits and API sleep remain configured.

## Deployment evidence

| Gate | Result | Sanitized evidence |
|---|---|---|
| Human values configured in secret manager | Passed | Independent generated application secrets and private service references exist; Apple audiences match `com.zavier.Woven.staging`, and the Railway Google audience matches the Staging app's server client ID. |
| Startup configuration validation | Passed | Railway-resolved variables passed `validate_staging_config.py`; development auth, debug, local DB/storage, wildcard hosts/CORS, and unsigned-device mode remain disabled. |
| Migration upgrade/revision/check | Passed | Railway pre-deploy runs the staging validator, `alembic upgrade head`, an explicit database-head verifier, and `alembic check`; deployment is promoted only after success. |
| Public HTTPS health/readiness/security headers | Passed | `/health` and `/ready` returned 200 through Railway HTTPS; HSTS, no-store, nosniff, and request ID were observed. |
| Remote docs and development auth absent | Passed | Docs/OpenAPI, Pair dev session, and password signup paths returned 404 under valid request schemas. |
| Remote adversarial boundaries | Passed | Untrusted Host rejected by edge/app, 22 MiB streamed body returned 413, invalid bearer returned 401 without echo, unsafe request ID was replaced, wildcard CORS absent, and auth rate limiting returned 429 with `Retry-After`. |
| Signed Pair partner lookup | Passed | The deployed minimal-response route is active and rejects unsigned requests with 401. Focused tests cover case-normalized success, unknown codes, and self-pair rejection. No Pair Vault creation request reached the backend during the original client decoding failure. |
| Interim one-iPhone-plus-Simulator Pair flow | Passed (limited scope) | The operator observed distinct Google/Simulator and Apple/physical-iPhone users create a Pair Vault, add one picture, and view it from both clients. This is MVP functional evidence, not two-device hardware, biometric, replay, revocation, capture, reboot, or storage-inspection evidence. |
| PostgreSQL private/restart | Passed | Public TCP proxy removed; private endpoint retained; readiness passes after API restart. Backup/restore remains an operator drill. |
| Object store private/opaque/delete | Passed | Woven adapter PUT/GET/DELETE passed with a synthetic ciphertext object; anonymous list/GET were rejected; post-test metadata returned zero objects/bytes. |
| Structured log redaction inspection | Passed | Build, migration, application, and request logs exposed only package names, safe configuration summary fields, routes/statuses, and opaque request IDs; no configured secret values were observed. |
| Apple-authenticated remote matrix | Not tested | The App ID, entitlement, provisioning configuration, and backend audience are ready, but real Apple identity tokens require a physical signed-in device. Account creation, refresh rotation/reuse, device enrollment/signing, invitation lifecycle, two-user unlock, media, replay, restart, and revocation remain physical-device acceptance work. Local automated coverage is not substituted for remote evidence. |
| Two physical iPhones | Not tested | Use `two-iphone-staging-results.md`; Apple Developer access and two devices are required. |

## Provider-independent verification

- Backend: 121 tests passed on Python 3.12 with the deployment dependency set; Ruff and Bandit passed; installed-environment `pip-audit` reported no known vulnerabilities.
- The container upgrades pip to a fixed 26.1.2-or-newer release before installing requirements and still runs as the non-root `woven` user.
- Current iOS verification passed with the Railway HTTPS origin and `com.zavier.Woven.staging`: the `Woven-Staging` scheme resolves every action to Staging; its compiled plist contains the matching Google iOS client, server audience, and reversed callback scheme; and the generic-Simulator build, generic-device build, and Xcode archive succeeded. Automatic Apple Development signing still contains the registered bundle/application identifier and `com.apple.developer.applesignin = Default` entitlement. Interactive Google UI and account exchange remain unclaimed until the Simulator is launched.
- Ten Staging unit/state tests and six UI/launch executions passed (thirteen logical tests in Xcode's result summary). The tests include fail-closed unreadable Apple credentials and proof that Staging never permits deterministic development accounts. Both Staging and Release static analysis passed. Development login types, UI, and callable API methods are compiled only when the explicit Debug-only `WOVEN_DEVELOPMENT_AUTH` condition is present; normal Staging settings do not define it.
- The signed archive uses a development provisioning profile (`get-task-allow = true`), which is appropriate for the requested device-development validation. Distribution/App Store export was not requested or claimed. No physical-device, Face ID, passcode, privacy-capture, reboot, or two-phone result is inferred from these checks.

## Explicitly deferred

- In Railway: no action is required unless the owner chooses a different cost policy. Railway rejected the authorized $5 hard ceiling because its minimum is $10; changing that boundary requires explicit new authorization. Monitor actual usage and stop the staging services before $5 if necessary.
- In Google Cloud: OAuth branding and both client IDs are configured. Google sign-in was observed on the Simulator. Keep the intended Gmail address as an OAuth test user while the consent screen is in testing. No Google client secret is used or committed.
- In Apple Developer/Xcode: no remaining non-hardware configuration issue was found. Interactive account or provisioning approval may still appear when a physical device is first selected.
- On physical hardware: the interim Pair creation/upload/view flow passed with one iPhone and the iPhone 17e Simulator. A second physical iPhone is still required for the formal hardware checklist, including two-device biometric, capture, reboot, network interruption, replay, expiry, and revocation behavior.
- APNs delivery/signing, backup restore drills, recovery, post-revocation content-key rotation, formal security review, incident-response ownership, production infrastructure, and public launch remain out of scope.

## Recommended APNs milestone after physical verification

After every two-iPhone checklist item has a recorded result, add APNs as a separate fail-closed milestone: create a least-privilege Apple APNs signing key; store the `.p8` material only in the deployment secret manager; configure `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_KEY_PATH`, and `APNS_BUNDLE_ID`; register and rotate device tokens; send only opaque wake-up/event-type payloads with no account, vault, request, filename, media, token, key, share, or invitation data; and verify foreground/background delivery, token replacement, revoked-device rejection, logging redaction, retry/idempotency, and polling fallback on both physical iPhones. Do not begin this milestone before the current polling-based physical workflow passes.
