"""IBKR Web API OAuth 1.0a client.

Two-stage auth dance:
  1. **Live Session Token (LST) handshake** — RSA-SHA256-signed POST to
     `/v1/api/oauth/live_session_token` with a Diffie-Hellman challenge.
     IBKR returns the LST encrypted under the consumer's prime; we
     derive the shared secret locally. LSTs are valid ~24h. We cache
     the LST in module memory so warm Lambda invocations reuse it.
  2. **Per-request signing** — every business call is signed
     OAuth-1.0a-style with HMAC-SHA256, using the LST as the signing
     secret. Much cheaper than RSA per-request.

Credentials live in AWS Secrets Manager under the secret id
`WISECAT_IBKR_SECRET_ID` (default `shantisangha/ibkr_oauth`) as a JSON
blob with these fields:

    {
      "consumer_key": "...",
      "access_token": "...",
      "access_token_secret": "...",     # only used for the LST handshake
      "signing_private_key_pem": "-----BEGIN RSA PRIVATE KEY-----...",
      "encryption_private_key_pem": "-----BEGIN RSA PRIVATE KEY-----...",
      "dh_prime_hex": "..."
    }

Setup is one-time (~30 min) via IBKR's Client Portal → Settings → API
→ Web API. The user generates the keypair, registers it with IBKR,
exchanges for an access token, and pastes the bundle into Secrets
Manager. After that, this client signs every request automatically.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import logging
import os
import secrets
import time
from dataclasses import dataclass
from urllib.parse import quote

import httpx

# `cryptography` is imported lazily inside the signing helpers so that
# importing this module never breaks the Lambda when the new dep hasn't
# been redeployed yet — existing wisecat actions (score / history /
# quote / etc.) continue to work even if the IBKR layer is unbuilt.

logger = logging.getLogger(__name__)


class IbkrUnauthorized(RuntimeError):
    """Raised when IBKR rejects a request (401 / 403). The .NET caller
    detects the string `ibkr_unauthorized` in the FunctionError body and
    flips IbkrAccount.Status to NeedsReauth."""

    def __init__(self, message: str):
        super().__init__(f"ibkr_unauthorized: {message}")


class IbkrUnavailable(RuntimeError):
    """Network / 5xx / misconfiguration. Distinct from Unauthorized so
    the .NET side knows to keep the existing status (transient)."""


# ---------- credential resolution ------------------------------------------


@dataclass(frozen=True)
class IbkrCreds:
    consumer_key: str
    access_token: str
    access_token_secret: str
    signing_private_key_pem: str
    encryption_private_key_pem: str
    dh_prime_hex: str


_cached_creds: IbkrCreds | None = None


def _get_creds() -> IbkrCreds:
    global _cached_creds
    if _cached_creds is not None:
        return _cached_creds

    secret_id = os.environ.get("WISECAT_IBKR_SECRET_ID", "shantisangha/ibkr_oauth")
    try:
        import boto3
        sm = boto3.client("secretsmanager")
        resp = sm.get_secret_value(SecretId=secret_id)
        blob = json.loads(resp["SecretString"])
    except Exception as e:
        raise IbkrUnavailable(f"unable to resolve IBKR OAuth credentials: {e}") from e

    required = (
        "consumer_key", "access_token", "access_token_secret",
        "signing_private_key_pem", "encryption_private_key_pem", "dh_prime_hex",
    )
    for k in required:
        if not blob.get(k):
            raise IbkrUnavailable(f"IBKR creds secret missing field '{k}'")

    _cached_creds = IbkrCreds(
        consumer_key=blob["consumer_key"],
        access_token=blob["access_token"],
        access_token_secret=blob["access_token_secret"],
        signing_private_key_pem=blob["signing_private_key_pem"],
        encryption_private_key_pem=blob["encryption_private_key_pem"],
        dh_prime_hex=blob["dh_prime_hex"],
    )
    return _cached_creds


# ---------- HTTP plumbing --------------------------------------------------


_BASE_URL = "https://api.ibkr.com"
_API_PREFIX = "/v1/api"
_http_client: httpx.Client | None = None


def _http() -> httpx.Client:
    global _http_client
    if _http_client is None:
        _http_client = httpx.Client(base_url=_BASE_URL, timeout=15.0)
    return _http_client


# ---------- Live Session Token handshake -----------------------------------


_cached_lst: bytes | None = None
_cached_lst_expires_at: float = 0.0


def _percent_encode(s: str) -> str:
    """RFC 3986 percent-encode for OAuth signature base strings."""
    return quote(str(s), safe="")


def _oauth_param_string(params: dict[str, str]) -> str:
    return "&".join(
        f"{_percent_encode(k)}={_percent_encode(v)}"
        for k, v in sorted(params.items())
    )


def _build_signature_base(method: str, url: str, oauth_params: dict[str, str]) -> str:
    """OAuth 1.0a signature base string = METHOD & URL & PARAMS, each
    percent-encoded then joined with '&'. URL is the absolute URL
    without query string."""
    return "&".join((
        method.upper(),
        _percent_encode(url),
        _percent_encode(_oauth_param_string(oauth_params)),
    ))


def _rsa_sha256_sign(private_key_pem: str, message: bytes) -> str:
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import padding
    key = serialization.load_pem_private_key(private_key_pem.encode("ascii"), password=None)
    sig = key.sign(message, padding.PKCS1v15(), hashes.SHA256())
    return base64.b64encode(sig).decode("ascii")


def _compute_live_session_token() -> bytes:
    """RSA-signed handshake. Returns the raw LST bytes (typically 20 bytes
    of HMAC key material). Cached on success."""
    global _cached_lst, _cached_lst_expires_at

    creds = _get_creds()
    # IBKR's DH prime is a 2048-bit safe prime they provide during onboarding;
    # generator is fixed at 2.
    dh_prime = int(creds.dh_prime_hex, 16)
    dh_generator = 2
    # Local secret a (random 256-bit) and public value A = g^a mod p.
    a_int = int.from_bytes(secrets.token_bytes(32), "big")
    big_a = pow(dh_generator, a_int, dh_prime)
    big_a_hex = format(big_a, "x")

    # OAuth params for the LST request. Signature_method is RSA-SHA256.
    nonce = secrets.token_hex(16)
    timestamp = str(int(time.time()))
    oauth_params = {
        "oauth_consumer_key": creds.consumer_key,
        "oauth_nonce": nonce,
        "oauth_signature_method": "RSA-SHA256",
        "oauth_timestamp": timestamp,
        "oauth_token": creds.access_token,
        "diffie_hellman_challenge": big_a_hex,
    }

    # Pre-compute the prepend: HMAC-SHA1 (yes, SHA1 here per IBKR's spec
    # for the handshake step) of the access token secret using the
    # encryption private key. The result is prepended to the signature
    # base string. NOTE: this is an IBKR-specific quirk of their OAuth
    # implementation — without the prepend, the server returns 401.
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import padding
    encryption_key = serialization.load_pem_private_key(
        creds.encryption_private_key_pem.encode("ascii"), password=None)
    decrypted_secret = encryption_key.decrypt(
        base64.b64decode(creds.access_token_secret),
        padding.PKCS1v15())
    prepend = decrypted_secret.hex()

    base_string = _build_signature_base(
        "POST",
        f"{_BASE_URL}{_API_PREFIX}/oauth/live_session_token",
        oauth_params)
    to_sign = (prepend + base_string).encode("ascii")
    signature = _rsa_sha256_sign(creds.signing_private_key_pem, to_sign)
    oauth_params["oauth_signature"] = signature

    headers = {
        "Authorization": "OAuth " + ", ".join(
            f'{k}="{_percent_encode(v)}"'
            for k, v in oauth_params.items()
            if k != "diffie_hellman_challenge"
        ),
        "Content-Type": "application/x-www-form-urlencoded",
        "User-Agent": "shantisangha-wisecat/1.0",
    }

    try:
        resp = _http().post(
            f"{_API_PREFIX}/oauth/live_session_token",
            data={"diffie_hellman_challenge": big_a_hex},
            headers=headers,
        )
    except httpx.HTTPError as e:
        raise IbkrUnavailable(f"LST handshake transport error: {e}") from e

    if resp.status_code in (401, 403):
        raise IbkrUnauthorized(
            f"LST handshake rejected (status={resp.status_code}, body={resp.text[:200]})")
    if resp.status_code >= 400:
        raise IbkrUnavailable(
            f"LST handshake failed (status={resp.status_code}, body={resp.text[:200]})")

    body = resp.json()
    b_hex = body.get("diffie_hellman_response")
    encrypted_lst_b64 = body.get("live_session_token_signature")
    expiration_ms = body.get("live_session_token_expiration", 0)
    if not b_hex or not encrypted_lst_b64:
        raise IbkrUnavailable(f"LST handshake response missing fields: {body}")

    # Compute K = B^a mod p, then LST = HMAC-SHA1(K, access_token_secret).
    # IBKR specifies that K is encoded as an unsigned big-endian byte string
    # with a leading 0x00 byte if the high bit is set (preserves sign).
    big_b = int(b_hex, 16)
    k = pow(big_b, a_int, dh_prime)
    k_bytes = k.to_bytes((k.bit_length() + 7) // 8, "big")
    if k_bytes[0] & 0x80:
        k_bytes = b"\x00" + k_bytes
    lst = hmac.new(k_bytes, decrypted_secret, hashlib.sha1).digest()

    _cached_lst = lst
    # LST is good for ~24h; refresh proactively at 22h.
    _cached_lst_expires_at = (
        expiration_ms / 1000.0 if expiration_ms > 0 else time.time() + 22 * 3600
    )
    logger.info("IBKR LST acquired (expires at %s)", _cached_lst_expires_at)
    return lst


def _get_lst(force_refresh: bool = False) -> bytes:
    global _cached_lst, _cached_lst_expires_at
    if force_refresh:
        _cached_lst = None
    if _cached_lst is not None and time.time() < _cached_lst_expires_at - 300:
        return _cached_lst
    return _compute_live_session_token()


# ---------- Per-request signing --------------------------------------------


def _sign_and_send(method: str, path: str, params: dict[str, str] | None = None,
                   body: dict | None = None, _retried: bool = False) -> dict:
    """Sign the request with HMAC-SHA256 using the LST and send. On 401,
    refresh the LST once and retry."""
    creds = _get_creds()
    lst = _get_lst()

    nonce = secrets.token_hex(16)
    timestamp = str(int(time.time()))
    oauth_params = {
        "oauth_consumer_key": creds.consumer_key,
        "oauth_nonce": nonce,
        "oauth_signature_method": "HMAC-SHA256",
        "oauth_timestamp": timestamp,
        "oauth_token": creds.access_token,
    }

    # For HMAC signing, the param-set fed into the base string includes
    # any query params on the URL (but not the request body).
    sig_params = dict(oauth_params)
    if params:
        sig_params.update(params)

    base_string = _build_signature_base(method, f"{_BASE_URL}{path}", sig_params)
    signing_key = base64.b64encode(lst).decode("ascii")
    signature = base64.b64encode(
        hmac.new(signing_key.encode("ascii"), base_string.encode("ascii"),
                 hashlib.sha256).digest()
    ).decode("ascii")
    oauth_params["oauth_signature"] = signature

    auth_header = "OAuth " + ", ".join(
        f'{k}="{_percent_encode(v)}"' for k, v in oauth_params.items())
    headers = {
        "Authorization": auth_header,
        "Accept": "application/json",
        "User-Agent": "shantisangha-wisecat/1.0",
    }
    if body is not None:
        headers["Content-Type"] = "application/json"

    try:
        resp = _http().request(
            method, path,
            params=params,
            json=body,
            headers=headers,
        )
    except httpx.HTTPError as e:
        raise IbkrUnavailable(f"IBKR transport error on {method} {path}: {e}") from e

    if resp.status_code in (401, 403):
        if not _retried:
            logger.info("IBKR returned %d; refreshing LST and retrying", resp.status_code)
            _get_lst(force_refresh=True)
            return _sign_and_send(method, path, params, body, _retried=True)
        raise IbkrUnauthorized(f"{method} {path} (body={resp.text[:200]})")
    if resp.status_code >= 400:
        raise IbkrUnavailable(
            f"IBKR {method} {path} returned {resp.status_code} (body={resp.text[:200]})")

    if not resp.content:
        return {}
    try:
        return resp.json()
    except ValueError:
        return {"_raw": resp.text}


# ---------- Public API (called by lambda_handler) --------------------------


def get_auth_status() -> dict:
    body = _sign_and_send("GET", f"{_API_PREFIX}/iserver/auth/status")
    return {
        "authenticated": bool(body.get("authenticated", False)),
        "connected": bool(body.get("connected", False)),
        "competing": bool(body.get("competing", False)),
    }


def get_accounts() -> dict:
    # /portfolio/accounts must be hit once per session before any per-account
    # endpoint. Safe to call repeatedly; IBKR caches server-side.
    raw = _sign_and_send("GET", f"{_API_PREFIX}/portfolio/accounts")
    rows = raw if isinstance(raw, list) else raw.get("accounts") or []
    accounts = []
    for r in rows:
        acct_id = r.get("accountId") or r.get("id")
        if not acct_id:
            continue
        accounts.append({
            "accountId": acct_id,
            "currency": r.get("currency"),
        })
    return {"accounts": accounts}


def get_positions(account_id: str) -> dict:
    # IBKR paginates positions; we read page 0 only for v1 (<100 holdings).
    path = f"{_API_PREFIX}/portfolio/{account_id}/positions/0"
    raw = _sign_and_send("GET", path)
    rows = raw if isinstance(raw, list) else raw.get("positions") or []
    positions = []
    for r in rows:
        positions.append({
            "conid": int(r.get("conid", 0)),
            "ticker": r.get("ticker"),
            "contractDesc": r.get("contractDesc"),
            "position": float(r.get("position", 0) or 0),
            "avgCost": float(r.get("avgCost", 0) or 0),
            "currency": r.get("currency"),
            "assetClass": r.get("assetClass"),
        })
    return {"positions": positions}


def get_ledger(account_id: str) -> dict:
    """Ledger returns a dict keyed by currency code (and a 'BASE' summary
    row). We surface each currency row separately so the .NET caller can
    filter to its base currency."""
    path = f"{_API_PREFIX}/portfolio/{account_id}/ledger"
    raw = _sign_and_send("GET", path)
    if not isinstance(raw, dict):
        return {"entries": []}
    entries = []
    for k, v in raw.items():
        if not isinstance(v, dict):
            continue
        if k.upper() == "BASE":
            continue  # skip summary row
        entries.append({
            "currency": v.get("currency") or k,
            "cashBalance": float(v.get("cashbalance", 0) or 0),
        })
    return {"entries": entries}


def resolve_contract(conid: int) -> dict:
    path = f"{_API_PREFIX}/iserver/contract/{conid}/info"
    raw = _sign_and_send("GET", path)
    return {
        "ticker": raw.get("ticker"),
        "symbol": raw.get("symbol"),
        "companyName": raw.get("company_name") or raw.get("companyName"),
    }
