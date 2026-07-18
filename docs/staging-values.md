# Staging human-controlled values

Configure secrets only in the selected hosting platform’s secret manager or Xcode/Apple signing system. Do not paste populated values into Git, issue trackers, chat, build logs, command history, or `.xcconfig` files committed to this repository.

## Backend and infrastructure

| Name | Obtain from | Secret | Configure in | Verification | Separate local value |
|---|---|---:|---|---|---:|
| Hosting provider/project and region | Infrastructure owner | No | Provider control plane | API workload, private networking, secret injection, one-off jobs, TLS and logs are supported | No |
| Staging DNS hostname / `PUBLIC_BASE_URL` | DNS owner and provider ingress | No | DNS plus backend environment | Publicly trusted HTTPS; `/health` and `/ready`; hostname equals an entry in `TRUSTED_HOSTS` | Yes, `http://127.0.0.1:8000` |
| `DATABASE_URL` | Managed PostgreSQL service | Yes | Provider secret manager | Starts with `postgresql`; migration job and `/ready` pass; DB is not public | Yes, disposable SQLite/PostgreSQL |
| `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` (Compose only) | Database administrator | User/password are secret | Provider secret manager or Compose runtime | Values produce `DATABASE_URL`; never expose port 5432 publicly | Disposable Compose-only values |
| `SECRET_KEY` | Generated directly in secret manager | Yes | Provider secret manager | At least 32 random characters; startup succeeds; never appears in output | Yes, unrelated disposable value |
| `REFRESH_TOKEN_PEPPER` | Generated independently in secret manager | Yes | Provider secret manager | At least 32 random characters and differs from `SECRET_KEY`; refresh rotation passes | Yes, unrelated disposable value |
| `APPLE_CLIENT_ID` | Apple Developer identifier configuration | No | Backend environment | Exact `aud` accepted; wrong audience rejected | Test audience for automated tests |
| `APPLE_ISSUER`, `APPLE_JWKS_URL` | Fixed Apple endpoints | No | Leave repository defaults unchanged | Remote startup rejects anything except Apple's official HTTPS issuer/JWKS endpoint | Same official endpoints |
| `TRUSTED_HOSTS` | Staging DNS decision | No | Backend environment | Exact public API hostname included; add `healthcheck.railway.app` on Railway; wildcard and mismatched host fail | Empty locally |
| `PORT` | Hosting provider | No | Backend environment | `8000` on Railway to match the container listener and healthcheck target | Not required locally |
| `CORS_ORIGINS` | Browser-client owner, if any | No | Backend environment | Empty for native-only staging, otherwise exact HTTPS origins; wildcard fails startup | Empty locally |
| `OBJECT_STORAGE_ENDPOINT` | Private object-storage provider | No | Backend environment | Absolute HTTPS endpoint; storage smoke succeeds | Local filesystem adapter |
| `OBJECT_STORAGE_BUCKET` | Object-storage administrator | Sensitive metadata | Backend environment | Bucket exists, public access is blocked, direct anonymous GET/list fails | Local directory |
| `OBJECT_STORAGE_REGION` | Object-storage provider | No | Backend environment | SDK requests reach the selected region | Empty/provider-specific |
| `OBJECT_STORAGE_ADDRESSING_STYLE` | Object-storage provider | No | Backend environment | `virtual` for current Railway buckets; provider-specific otherwise | `auto` |
| `OBJECT_STORAGE_SERVER_SIDE_ENCRYPTION` | Object-storage provider | No | Backend environment | Leave unset when the provider rejects S3 SSE request headers; set `AES256` for supporting providers | Empty |
| `OBJECT_STORAGE_ACCESS_KEY` | Bucket-scoped service identity | Yes | Provider secret manager | Can get/put/delete only Woven staging objects; cannot change bucket policy | Disposable/local none |
| `OBJECT_STORAGE_SECRET_KEY` | Bucket-scoped service identity | Yes | Provider secret manager | Same least-privilege verification; never logged | Disposable/local none |
| `APP_ENV` | Fixed policy value | No | Backend environment | Exactly `staging` | `local` or `test` |
| `DEBUG` | Fixed policy value | No | Backend environment | Exactly `false`; docs and development auth are absent | `true` for explicit local runner |
| `STORAGE_BACKEND` | Fixed policy value | No | Backend environment | Exactly `object` | `local` |
| `ENFORCE_DEVICE_SIGNATURES` | Fixed policy value | No | Backend environment | Exactly `true`; unsigned/tampered/replayed requests fail | May be `false` for local development |
| `RATE_LIMIT_AUTH_PER_MINUTE` / `RATE_LIMIT_PAIR_PER_MINUTE` | Security/operations owner | No | Backend environment and ingress | Boundary smoke returns 429 without cross-account starvation | Defaults are suitable locally |
| PostgreSQL backup/retention settings | Infrastructure and privacy owners | Sensitive policy | Database provider | Restore drill reaches current Alembic head | No |
| Object-store public-access block, encryption, versioning and lifecycle | Storage/privacy owners | Sensitive policy | Object provider | Anonymous list/get fail; encryption/versioning/lifecycle inspected | No |

`APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_KEY_PATH`, `APNS_BUNDLE_ID`, and an APNs signing key are intentionally not required for this staging milestone. They belong to the APNs milestone after the two-iPhone verification is complete.

## Apple and iOS build

| Xcode/Apple value | Obtain from | Secret | Configure in | Verification | Separate local value |
|---|---|---:|---|---|---:|
| `WOVEN_STAGING_API_BASE_URL` | Deployed staging URL | No | CI/archive command or uncommitted local Xcode user setting | `https`, non-local; built `Info.plist` contains only that URL | Debug uses loopback |
| `WOVEN_STAGING_BUNDLE_IDENTIFIER` | Apple Developer account owner | No | CI/archive command or uncommitted Xcode setting | Unique registered App ID; built bundle identifier matches | Debug currently uses `com.zavier.Woven` |
| `WOVEN_STAGING_DEVELOPMENT_TEAM` | Apple Developer membership | No | CI/archive command or uncommitted Xcode setting | Xcode signing report and installed profile match | Simulator builds can disable signing |
| Sign in with Apple capability | Apple Developer portal | No | Staging App ID and Xcode signing profile | Entitlements contain `com.apple.developer.applesignin`; physical sign-in succeeds | Simulator/unit tests use mocks |
| Staging development/distribution certificate and provisioning profile | Apple Developer/Xcode managed signing | Sensitive credential material | Apple portal, Xcode account, or CI signing vault | Archive/export/install on both registered iPhones | Simulator uses ad-hoc signing |
| iPhone A/B device registration, if using development/ad hoc install | Apple Developer account and physical devices | Device identifier is sensitive | Apple portal/Xcode | Both devices install the exact staging commit | No |

The repository deliberately contains no staging API URL, Apple credential, private key, provisioning profile, database password, or object-storage credential.

## Provider decision: minimum capabilities

No provider is selected in this repository. The human decision needs only choose a platform that supplies:

1. A private container service with secret injection, read-only filesystem support, outbound HTTPS, health checks, redacted logs, and a separate one-off migration job.
2. Private PostgreSQL 16 with encrypted backups and a practical restore workflow.
3. Private S3-compatible object storage with public-access blocking, encryption, lifecycle/versioning, and a bucket-scoped service identity.
4. A publicly trusted HTTPS ingress/custom domain that preserves proxy headers and supports request-size, timeout, and rate boundaries.

These may be one integrated provider or separate services. The material trade-off is operational ownership: an integrated managed platform is simpler, while separately managed cloud services offer finer network/IAM controls. Do not provision paid resources until the owner authorizes the provider, region, and expected cost.
