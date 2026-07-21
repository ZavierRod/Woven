# Woven two-iPhone staging verification

Allowed result values: **Passed**, **Failed**, **Blocked**, **Not tested**. Mark **Passed** only for behavior directly observed on physical hardware. Keep observations sanitized: never record tokens, invitation codes, private names, filenames, media content, keys, signatures, device identifiers, or Apple credentials.

## Run metadata

| Field | Value |
|---|---|
| Date/time (UTC) | |
| Operator | |
| Staging API hostname | `woven-api-staging.up.railway.app` |
| Backend Git commit/image digest | `207b11f4d7de5cf47d15ac06f3f975197e5774c4` (deployment message; image digest retained in Railway) |
| Alembic revision | `d7a4c10b8e21` |
| iOS staging Git commit/build number | |
| iPhone A model / iOS version | |
| iPhone B model / iOS version | |
| Installation method/profile class | |
| Sanitized log correlation window | |

## Non-hardware preflight (not physical evidence)

As of 2026-07-21, the shared `Woven-Staging` scheme uses Staging for test, launch, profile, analyze, and archive actions. The registered bundle ID, automatic-signing team, Sign in with Apple entitlement, backend Apple audience, and injected Railway HTTPS URL match. Simulator build/launch, generic-device signed build, archive, ten unit/state tests, six UI/launch executions, and Staging/Release analysis passed. The Staging UI exposed no development-account selector. These results do not change any physical checklist result below from **Not tested**.

First hardware action: connect iPhone A by cable, unlock it and trust this Mac, enable Developer Mode if prompted, select iPhone A as the destination for `Woven-Staging`, and install the exact committed build. Record only sanitized device metadata, then install the same commit on iPhone B before checklist item 2.

## Checklist and results

| # | Physical observation | Result | Sanitized observation | Bug reference |
|---:|---|---|---|---|
| 1 | Install the exact Staging build on iPhone A and iPhone B; display name/badge says Staging and no development selector appears. | Not tested | | |
| 2 | Sign in on A and B with distinct Apple-backed staging accounts. | Not tested | | |
| 3 | Enrol one distinct agreement/signing device identity for each account; backend stores public keys only. | Not tested | | |
| 4 | A creates a Pair Vault. | Not tested | | |
| 5 | A invites B; B joins; invitation is single-use and a third account cannot join. | Not tested | | |
| 6 | A imports media; PostgreSQL/object storage contain ciphertext and opaque metadata only. | Not tested | | |
| 7 | Alice requests; Bob authenticates and approves; Alice consumes and views media. | Not tested | | |
| 8 | Bob requests; Alice authenticates and approves; Bob consumes and views the same media. | Not tested | | |
| 9 | Face ID succeeds on each phone; cancelled/failed Face ID stays locked; passcode fallback succeeds. | Not tested | | |
| 10 | Backgrounding immediately locks and clears private presentation. | Not tested | | |
| 11 | App switcher shows only the privacy shield, with no private name/thumbnail/media. | Not tested | | |
| 12 | Force-quit and relaunch require fresh approval and reveal no private content. | Not tested | | |
| 13 | Reboot each device; relaunch remains locked and device-only identity/share behavior is correct. | Not tested | | |
| 14 | Screenshot behavior matches policy and exposes no content while locked/inactive. | Not tested | | |
| 15 | Active screen recording/mirroring causes immediate shield/lock and remains protected. | Not tested | | |
| 16 | Interrupt network separately during request, approval, upload and download; retry remains fail-closed and idempotent. | Not tested | | |
| 17 | Allow a request to expire; consumption/unlock fails. | Not tested | | |
| 18 | Replay invitation, signed request and consumed approval; all are rejected without unlock/state rollback. | Not tested | | |
| 19 | Revoke a device with an outstanding request; access/refresh/signatures/membership/request are invalidated. | Not tested | | |
| 20 | Delete encrypted media; DB row and private object disappear and later retrieval fails. | Not tested | | |
| 21 | Inspect notifications, unified/app logs, widgets, App Intents, Spotlight and external previews; no private content appears. | Not tested | | |

## Storage, database and log inspection

| Inspection | Result | Sanitized observation | Bug reference |
|---|---|---|---|
| PostgreSQL contains no plaintext media, private vault names, original filenames, shares, keys, Apple/access/refresh tokens, authorization headers, device private keys, or raw invitation tokens. | Not tested | | |
| Object bytes have no recognizable source header; key/metadata are opaque; anonymous list/get fail. | Not tested | | |
| Application/ingress logs contain only approved structured fields and no prohibited values. | Not tested | | |
| Backend restart preserves PostgreSQL membership/request/media state and object retrieval. | Not tested | | |

## Completion

| Field | Value |
|---|---|
| Overall result | Not tested |
| Failed/blocked bug references | |
| Retest required | |
| Operator sign-off | |
| Reviewer sign-off | |
