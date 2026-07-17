# Woven

Woven is an iOS encrypted vault prototype. The current Pair Vault v2 path encrypts media and private metadata on-device, keeps device and vault secrets in device-only Keychain items, splits Pair vault keys across two members, and treats the FastAPI service as an authenticated ciphertext relay.

## Current status

- Solo Vault and Pair Vault iOS surfaces build on iOS 26.
- Pair Vault v2 supports two members, targeted one-time invitations, two-party unlock approval, encrypted media, revocation, and lifecycle locking.
- Remote account authentication uses Sign in with Apple plus short access tokens and rotating refresh credentials.
- Pair API requests are bound to account, enrolled device, route, vault, body, timestamp, request ID, and nonce with Ed25519 signatures.
- Local/test, staging, and production configuration are explicit and fail closed. Deterministic Alice/Bob accounts exist only for local/test use.
- Staging uses PostgreSQL and private object storage; SQLite and filesystem storage are local/test facilities.

APNs delivery is deliberately deferred. Local development and the current staging validation workflow use polling. This is not represented as complete production notification delivery.

## Start locally

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python run_pair_dev.py
```

Open `Woven.xcodeproj`, select the `Woven` scheme, and run a Debug build. Debug is configured for `local` and `http://127.0.0.1:8000`. Release has no default API host and presents an actionable configuration error until a non-local HTTPS URL is supplied.

## Documentation

- [Local two-Simulator workflow](docs/pair-vault-development.md)
- [Staging deployment and physical-device runbook](docs/staging-readiness.md)
- [Pair Vault threat model](docs/pair-vault-threat-model.md)
- [Independent MVP verification baseline](docs/pair-vault-verification.md)
- [Current roadmap](roadmap.md)

The original repository copy at `/Users/zavierrodrigues/Desktop/Woven` is archival. Active work is performed only in `/Users/zavierrodrigues/Developer/Woven`.
