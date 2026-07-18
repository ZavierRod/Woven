"""Non-secret smoke checks for an already deployed Woven staging API."""

from __future__ import annotations

import argparse
from urllib.parse import urlparse

import httpx


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("base_url", help="Public staging API URL; never include credentials")
    args = parser.parse_args()
    parsed = urlparse(args.base_url)
    require(parsed.scheme == "https", "staging URL must use HTTPS")
    require(parsed.hostname not in {"localhost", "127.0.0.1", "::1"}, "staging URL cannot be local")

    with httpx.Client(base_url=args.base_url.rstrip("/"), timeout=20, follow_redirects=False, http2=True) as client:
        health = client.get("/health")
        require(health.status_code == 200 and health.json() == {"status": "ok"}, "health check failed")
        require(health.headers.get("strict-transport-security", "").startswith("max-age="), "HSTS missing")
        require(health.headers.get("cache-control") == "no-store", "no-store missing")
        require(health.headers.get("x-content-type-options") == "nosniff", "nosniff missing")
        require(bool(health.headers.get("x-request-id")), "request ID missing")

        ready = client.get("/ready")
        require(ready.status_code == 200 and ready.json() == {"status": "ready"}, "readiness check failed")

        for path in ("/docs", "/redoc", "/openapi.json"):
            require(client.get(path).status_code == 404, f"remote documentation exposed at {path}")

        dev_session = client.post("/pair-v2/dev/session/alice")
        require(dev_session.status_code == 404, "development Pair authentication is enabled")
        password_signup = client.post(
            "/auth/signup",
            json={"username": "boundary", "email": "boundary@example.com", "password": "not-a-real-secret"},
        )
        require(password_signup.status_code == 404, "development password authentication is enabled")

        marker = "staging-validation-marker-must-not-echo"
        malformed = client.post("/auth/apple", json={"identity_token": {"marker": marker}})
        require(malformed.status_code == 422, "malformed authentication request did not fail safely")
        require(marker not in malformed.text, "validation response echoed request content")

    print("staging boundary smoke passed")


if __name__ == "__main__":
    main()
