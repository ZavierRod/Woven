# Woven FastAPI service

The service authenticates accounts and enrolled devices, enforces Pair membership and access-request transitions, and stores only ciphertext plus operational metadata. It must never receive a vault key, key share, decrypted media, plaintext thumbnail, Apple identity token in logs, or raw refresh credential in storage.

## Environments

| `APP_ENV` | Database | media storage | account entry | device signatures | discovery/docs |
|---|---|---|---|---|---|
| `local` | SQLite or PostgreSQL | local filesystem | password + deterministic Pair accounts | optional | mDNS and API docs enabled |
| `test` | SQLite | isolated local adapter | test password accounts | test-selectable | no mDNS |
| `staging` | PostgreSQL required | private S3-compatible object store required | Sign in with Apple | required | no mDNS or API docs |
| `production` | PostgreSQL required | private S3-compatible object store required | Sign in with Apple | required | no mDNS or API docs |

Remote startup rejects debug mode, HTTP/public localhost URLs, SQLite, local media storage, missing Apple audience, missing trusted hosts, wildcard CORS, weak secrets, or disabled device signatures.

## Local development

```bash
cp .env.example .env
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
alembic upgrade head
uvicorn app.main:app --reload
```

For the disposable Pair relay with deterministic accounts, use `python run_pair_dev.py`. Do not expose that process to an untrusted network.

## Verification

```bash
pytest -q
ruff check app tests
bandit -q -r app -x tests
pip-audit -r requirements.txt
alembic check
```

CI also upgrades, downgrades, and re-upgrades the migration head against PostgreSQL, scans Git history for secrets, analyzes the Release iOS target, and runs all iOS tests.

## Operations

- `GET /health` is a minimal liveness response.
- `GET /ready` checks database connectivity without disclosing configuration.
- Responses carry request IDs, no-store policy, clickjacking/content-sniffing protections, and HSTS remotely.
- Logs are structured and contain operational summaries only. Credentials and request bodies are not logged.
- HTTPS terminates at the deployment ingress; the API container trusts forwarded headers only inside that controlled network.

See [the staging runbook](../docs/staging-readiness.md) for secrets, Apple configuration, migrations, backups, rollback, DNS/TLS, object storage, and physical iPhone validation.
