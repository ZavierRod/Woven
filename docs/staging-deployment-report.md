# Staging deployment record

Status: **Railway staging backend deployed; Apple registration, signing, and physical-iPhone verification remain pending.**

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
| Backend Git commit | Final pushed deployment commit is recorded in the task completion report and Railway deployment message. |
| Alembic revision | `d7a4c10b8e21` (head) |

No credential, secret, token, connection string, private object name, or user data is recorded here.

## Railway controls

- The project contains only the `staging` environment. Railway's empty default `production` environment was removed before services were created.
- API and PostgreSQL each have exactly one `us-west2` replica, capped at 0.25 vCPU and 256 MiB RAM.
- API serverless sleep is enabled. PostgreSQL is not replicated and remains available for readiness checks.
- The API uses a Railway-provided TLS domain on port 8000. No custom domain was purchased.
- PostgreSQL has no TCP proxy, public domain, or custom domain. The API references its private `DATABASE_URL`.
- The bucket is in `sjc`, is private by Railway design, and uses Railway reference variables for credentials.
- The bucket adapter uses virtual-hosted addressing and omits the unsupported S3 server-side-encryption request header. Stored Woven payloads remain application ciphertext.
- A workspace compute hard limit still requires an authenticated Railway dashboard session. Per-service limits and API sleep are configured, but the dashboard hard limit must be set to the owner's $5 boundary.

## Deployment evidence

| Gate | Result | Sanitized evidence |
|---|---|---|
| Human values configured in secret manager | Passed with Apple limitation | Independent generated application secrets and private service references exist; intended staging Apple audience is configured but not yet registered in Apple Developer. |
| Startup configuration validation | Passed | Railway-resolved variables passed `validate_staging_config.py`; development auth, debug, local DB/storage, wildcard hosts/CORS, and unsigned-device mode remain disabled. |
| Migration upgrade/revision/check | Passed | Railway pre-deploy runs the staging validator, `alembic upgrade head`, an explicit database-head verifier, and `alembic check`; deployment is promoted only after success. |
| Public HTTPS health/readiness/security headers | Passed | `/health` and `/ready` returned 200 through Railway HTTPS; HSTS, no-store, nosniff, and request ID were observed. |
| Remote docs and development auth absent | Passed | Docs/OpenAPI, Pair dev session, and password signup paths returned 404 under valid request schemas. |
| Remote adversarial boundaries | Passed | Untrusted Host rejected by edge/app, 22 MiB streamed body returned 413, invalid bearer returned 401 without echo, unsafe request ID was replaced, wildcard CORS absent, and auth rate limiting returned 429 with `Retry-After`. |
| PostgreSQL private/restart | Passed | Public TCP proxy removed; private endpoint retained; readiness passes after API restart. Backup/restore remains an operator drill. |
| Object store private/opaque/delete | Passed | Woven adapter PUT/GET/DELETE passed with a synthetic ciphertext object; anonymous list/GET were rejected; post-test metadata returned zero objects/bytes. |
| Structured log redaction inspection | Passed | Build, migration, application, and request logs exposed only package names, safe configuration summary fields, routes/statuses, and opaque request IDs; no configured secret values were observed. |
| Apple-authenticated remote matrix | Not tested | Real Apple identity tokens are unavailable until the staging App ID/audience and Sign in with Apple capability are registered. Account creation, refresh rotation/reuse, device enrollment/signing, invitation lifecycle, two-user unlock, media, replay, restart, and revocation therefore remain physical-device acceptance work. Local automated coverage is not substituted for remote evidence. |
| Two physical iPhones | Not tested | Use `two-iphone-staging-results.md`; Apple Developer access and two devices are required. |

## Provider-independent verification

- Backend: 115 tests passed on Python 3.12 with the deployment dependency set; Ruff and Bandit passed; installed-environment `pip-audit` reported no known vulnerabilities.
- The container upgrades pip to a fixed 26.1.2-or-newer release before installing requirements and still runs as the non-root `woven` user.
- Current iOS verification passed with the Railway HTTPS origin and `com.zavier.Woven.staging`: the optimized Staging Simulator artifact built, its display name/bundle ID and Sign in with Apple entitlement were inspected, eight unit/state tests and six UI/launch executions passed with testability enabled only for the test build, and Release analysis passed. This is not Apple signing or physical-device evidence.

## Explicitly deferred

- In Railway: set the workspace Compute Usage hard limit to $5 from an authenticated dashboard session and monitor actual usage. This control is not exposed by the authenticated CLI.
- In Apple Developer: register the unique staging App ID/audience, enable Sign in with Apple, configure the team/profile/certificate, and inject the Railway HTTPS base URL into the Staging archive.
- On physical hardware: install the exact Staging build on two iPhones and complete every item in `two-iphone-staging-results.md`.
- APNs delivery/signing, backup restore drills, recovery, post-revocation content-key rotation, formal security review, incident-response ownership, production infrastructure, and public launch remain out of scope.
