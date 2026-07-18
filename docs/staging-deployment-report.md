# Staging deployment record

Status: **Blocked — hosting provider, region, DNS, and credentials have not been selected or authorized.** No paid resource was provisioned and no claim of deployed verification is made.

## Provider-independent verification

Completed locally on 2026-07-17 before handoff:

- Final container build passed as non-root with a read-only-runtime design and packaged staging validator.
- Backend: 114 tests passed; Ruff passed; Bandit passed; `pip-audit` reported no known vulnerabilities with no ignored IDs.
- PostgreSQL 16: upgrade to head, downgrade one revision, re-upgrade, `alembic check`, and `alembic current` all passed at `d7a4c10b8e21`.
- iOS: the Release-equivalent `Woven-Staging` Simulator build passed, and its expanded plist contained the injected HTTPS URL, staging environment, distinct bundle/display name, and no local-network or ATS exception keys.
- iOS regression: eight unit/state tests and six UI/launch executions passed on the iPhone 17 Pro Simulator.

These results validate the deployable artifacts and local boundaries only. They are not evidence for public TLS, provider networking, managed PostgreSQL, private object storage, Apple signing, or physical-device behavior.

## Provider and artifact identity

| Field | Result |
|---|---|
| Provider / project / region | Pending human decision |
| Public HTTPS API hostname | Pending human decision |
| Private PostgreSQL service | Pending human decision |
| Private object bucket | Pending human decision |
| Backend Git commit / image digest | Pending deployment |
| Alembic revision | Pending deployment |
| iOS Staging commit / build number | Pending archive |

## Deployment evidence

| Gate | Result | Sanitized evidence |
|---|---|---|
| Human values configured in secret manager | Blocked | Provider not selected |
| Startup configuration validation | Not tested | |
| Migration upgrade/current/check | Not tested | |
| Public HTTPS health/readiness/security headers | Not tested | |
| Remote docs and development auth absent | Not tested | |
| PostgreSQL private/restart/backup restore | Not tested | |
| Object store private/encrypted/opaque/delete | Not tested | |
| Structured log redaction inspection | Not tested | |
| Two physical iPhones | Not tested | Use `two-iphone-staging-results.md` |

## Explicitly deferred

APNs delivery and signing credentials remain a separate milestone. Production deployment, recovery, post-revocation content-key rotation, formal security review, incident response ownership, and public launch remain out of scope for this staging verification.
