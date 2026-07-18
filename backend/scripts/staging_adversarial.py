"""No-credential adversarial checks for a deployed Woven staging API."""

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

    marker = "woven-adversarial-marker-must-not-echo"
    with httpx.Client(
        base_url=args.base_url.rstrip("/"),
        timeout=20,
        follow_redirects=False,
        http2=True,
    ) as client:
        untrusted_host = client.get("/health", headers={"Host": "untrusted.invalid"})
        require(untrusted_host.status_code in {400, 404}, "untrusted Host header was accepted")

        with httpx.Client(
            base_url=args.base_url.rstrip("/"),
            timeout=55,
            follow_redirects=False,
            http2=False,
        ) as upload_client:
            oversized = upload_client.post(
                "/health",
                content=(b"x" * (1024 * 1024) for _ in range(22)),
            )
        require(oversized.status_code == 413, "oversized declared body was not rejected")
        require(marker not in oversized.text, "oversized response disclosed marker")

        invalid_bearer = client.get(
            "/pair-v2/vaults",
            headers={"Authorization": f"Bearer {marker}"},
        )
        require(invalid_bearer.status_code == 401, "invalid bearer credential was accepted")
        require(marker not in invalid_bearer.text, "authentication response echoed credential")

        unsafe_request_id = "x" * 65
        sanitized = client.get("/health", headers={"X-Request-ID": unsafe_request_id})
        require(sanitized.status_code == 200, "request-ID boundary probe failed")
        require(sanitized.headers.get("x-request-id") != unsafe_request_id, "unsafe request ID was reflected")
        require(sanitized.headers.get("access-control-allow-origin") != "*", "wildcard CORS is enabled")

        rate_limited = False
        for _ in range(15):
            response = client.post("/auth/apple", json={"identity_token": {"marker": marker}})
            require(marker not in response.text, "malformed authentication response echoed request content")
            if response.status_code == 429:
                rate_limited = True
                require(response.headers.get("retry-after") == "60", "rate-limit retry boundary missing")
                break
            require(response.status_code == 422, "malformed authentication request did not fail safely")
        require(rate_limited, "authentication rate limit was not observed")

    print("staging adversarial checks passed")


if __name__ == "__main__":
    main()
