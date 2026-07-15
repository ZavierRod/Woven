# Pair Vault v2 development runbook

Pair Vault v2 is an isolated development protocol. It does not use the legacy
Pair endpoints, legacy full-vault-key storage, APNs payload path, or Sign in
with Apple placeholder verifier.

## Start the persistent local relay

From `backend/`, create a virtual environment and install
`requirements.txt`, then run:

```bash
python run_pair_dev.py
```

This creates `backend/woven-pair-dev.db`, creates all SQLAlchemy tables, and
serves FastAPI on `http://127.0.0.1:8000`. The SQLite file is development data
and must not be committed. PostgreSQL remains available through
`docker compose up -d`, `alembic upgrade head`, and the existing Uvicorn
command.

## Run the two-Simulator flow

1. Boot two disposable iPhone Simulators and launch Woven in both.
2. Open the Pair tab. Continue as Bob on one Simulator, then as Alice on the
   other. This registers one Curve25519 public device identity per account.
3. Alice creates a Pair vault and transfers the displayed one-time code to Bob
   out of band. The relay stores only the SHA-256 hash of that code.
4. Bob opens the pending invitation, enters the code, and accepts. Bob's share
   is decrypted locally and stored with the ThisDeviceOnly Keychain class.
5. Alice requests access. Bob opens the incoming request and approves with
   Face ID/device authentication. The development transport polls every two
   seconds; no APNs credentials are required.
6. Alice consumes the one-time envelope, reconstructs the key in memory, and
   imports a photo through PhotosPicker. Lock Alice; Bob requests access and
   Alice authenticates to approve, proving the inverse direction. Lock Bob,
   terminate and relaunch Alice, request a fresh approval from Bob, verify the
   same encrypted photo persisted, then delete it.

The default client URL is `http://127.0.0.1:8000`, which reaches the Mac host
from iOS Simulator. Physical devices require an HTTPS-reachable development
host and are outside this runbook.

## Automated verification

```bash
cd backend
pytest -q
```

Run the Woven scheme's `WovenTests` target on an iPhone Simulator for Solo
regressions, adversarial Pair cryptography tests, and the deterministic
two-client state harness.

## Development-only behavior

- `POST /pair-v2/dev/session/alice` and `/bob` issue JWTs only when `DEBUG` is
  enabled. They are deterministic test identities, not production auth.
- Polling replaces APNs for invitations and access requests.
- The relay stores Base64-encoded encrypted blobs in the development database.
- One active device is enforced per account. Multi-device enrollment and key
  recovery are deferred.
- The complete security analysis and production gaps are in
  `docs/pair-vault-threat-model.md`.
