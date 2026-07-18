# Starlette advisory review

Review date: 2026-07-17. Runtime pair: FastAPI 0.139.2 and Starlette 1.3.1.

## Outcome

The temporary CI exception for `PYSEC-2026-161`, `PYSEC-2026-249`, `PYSEC-2026-248`, `PYSEC-2026-2281`, and `PYSEC-2026-2280` has expired and was removed. PyPI now publishes Starlette 1.3.1 and FastAPI 0.139.2; FastAPI declares `starlette>=0.46.0`, so the fixed pair resolves together. CI must run `pip-audit -r requirements.txt` without ignored IDs.

The older 0.49.3 runtime was exposed through FastAPI's underlying Starlette request/response and multipart handling even where Woven did not directly import the named component. Authentication, request-size/time boundaries, disabled remote documentation, and private storage reduced reachability but were compensating controls only; they never justified retaining a vulnerable dependency after compatible fixes became available.

## Traceability

| Advisory | Fixed in | Woven-relevant path | Prior controls and final resolution |
|---|---|---|---|
| `PYSEC-2026-161` / `CVE-2026-48710` | Starlette 1.0.1 | Malformed `Host` could make `request.url.path` disagree with routing; Woven uses `request.url.path` in device-signature verification | Exact `TRUSTED_HOSTS` and a validating ingress reduced exposure; Starlette 1.3.1 removes it; no exception |
| `PYSEC-2026-249` / `CVE-2026-54283` | Starlette 1.3.1 | URL-encoded form limits were ignored; Woven has FastAPI `Form` fields on the authenticated legacy media upload route | Global byte/time limits reduced resource use; Starlette 1.3.1 removes it; no exception |
| `PYSEC-2026-248` / `CVE-2026-54282` | Starlette 1.3.0 | A malformed non-slash request path could poison reconstructed URL host/path; Woven signature verification reads `request.url.path` | Uvicorn/ingress normalization and route mismatch reduced reachability; Starlette 1.3.1 removes it; no exception |
| `PYSEC-2026-2281` / `CVE-2026-48818` | Starlette 1.1.0 | Windows `StaticFiles` UNC-path SSRF; Woven neither mounts `StaticFiles` nor deploys on Windows | Not reachable in the intended Linux image; Starlette 1.3.1 removes it; no exception |
| `PYSEC-2026-2280` / `CVE-2026-48817` | Starlette 1.1.0 | Nonstandard method dispatch on unconstrained `HTTPEndpoint`; Woven uses FastAPI `APIRoute`, not `HTTPEndpoint` | Not reachable in current route construction; Starlette 1.3.1 removes it; no exception |

Package availability and compatibility were checked against the official [Starlette PyPI release](https://pypi.org/project/starlette/1.3.1/) and [FastAPI 0.139.2 metadata](https://pypi.org/pypi/fastapi/0.139.2/json). Advisory aliases, descriptions, and fixed versions were rechecked with `pip-audit` against the former Starlette 0.49.3 environment; the final requirements audit reports no known vulnerabilities.

## Ongoing rule

Any future audit exception requires a dedicated document naming the advisory, exact affected code path, exploit preconditions, upstream fixed version, owner, expiry date, and compensating controls. It must be removed immediately when a compatible fix is published. A provider deployment may not proceed while the unexcepted audit fails.
