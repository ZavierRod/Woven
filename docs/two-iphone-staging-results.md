# Woven two-iPhone staging verification

Allowed result values: **Passed**, **Failed**, **Blocked**, **Not tested**. Mark **Passed** only for behavior directly observed on physical hardware. Keep observations sanitized: never record tokens, invitation codes, private names, filenames, media content, keys, signatures, device identifiers, or Apple credentials.

## Run metadata

| Field | Value |
|---|---|
| Date/time (UTC) | |
| Operator | |
| Staging API hostname | `woven-api-staging.up.railway.app` |
| Backend Git commit/image digest | `a75c4d20929d9987e6266e46160730cc0d49f9c9` (deployed source; image digest retained in Railway) |
| Alembic revision | `a4b7c9d2e301` |
| iOS staging Git commit/build number | `a75c4d20929d9987e6266e46160730cc0d49f9c9` / 1 (Pair lookup fix; exact build installation pending) |
| iPhone A model / iOS version | |
| iPhone B model / iOS version | |
| Installation method/profile class | |
| Sanitized log correlation window | |

## Non-hardware preflight (not physical evidence)

As of 2026-08-03, the shared `Woven-Staging` scheme uses Staging for test, launch, profile, analyze, and archive actions. The registered bundle ID, automatic-signing team, Sign in with Apple entitlement, backend Apple audience, injected Railway HTTPS URL, Google iOS client, server audience, and reversed callback scheme match. The configured generic-Simulator build, generic-device signed build, and archive passed. Earlier ten unit/state tests, six UI/launch executions, and Staging/Release analysis also passed. The Staging UI exposes no development-account selector. These results do not change any physical checklist result below from **Not tested**.

The operator reported that an earlier Staging build ran on iPhone A and completed
Sign in with Apple, and that Google sign-in succeeded on the Simulator. Pair Vault
creation then failed before its POST because the client used a legacy account
lookup response shape. Commit `a75c4d20929d9987e6266e46160730cc0d49f9c9`
adds a minimal signed lookup endpoint and switches the client to it; 121 backend
tests, the Staging Simulator build, the Railway migration gate, live health and
readiness, and remote smoke/adversarial checks passed. The build commit, device
metadata, and remaining hardware behaviors were not recorded, so the formal rows
below remain **Not tested**. Install the exact fixed build on iPhone A and the
Simulator before repeating the interim flow.

## One-iPhone plus Simulator interim test

This is useful functional evidence but does **not** replace the two-physical-iPhone
hardware acceptance results below. With Google OAuth configured and the matching
backend revision deployed, use Sign in with Apple on the
physical iPhone and Sign in with Google on the Simulator. Confirm they receive
different Woven user IDs, then exercise Pair Vault creation, invitation, join,
upload, request, approval, consume, and replay rejection in both directions.
Record Face ID/passcode, reboot, capture, recording, and physical-device results
only for the real iPhone; leave the second-device hardware rows Not tested.

### Interim result — 2026-08-03

| Observation | Result | Sanitized evidence |
|---|---|---|
| Simulator user signs in with Google and physical-iPhone user signs in with Apple | Passed | Operator observed both staging sessions. |
| Partner invite lookup and Pair Vault creation | Passed | Operator created the Pair Vault after installing the lookup fix. |
| Add one picture to the Pair Vault | Passed | One media item was added successfully. |
| Both users decrypt and view the picture | Passed | Operator observed the same item from the Simulator and physical iPhone. |
| Remaining request/approval, replay, expiry, revocation, network, biometric, capture, recording, reboot, and second-physical-device checks | Not tested | No result inferred from the MVP path. |

The operator also reported that the current flow is clunky and the UI needs a
substantial usability and visual-design pass. This does not invalidate the MVP
functional result, but it should be addressed before broader testing or launch.

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
