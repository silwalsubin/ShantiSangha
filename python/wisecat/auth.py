from fastapi import Header, HTTPException, status

from .settings import settings


def require_internal_key(authorization: str = Header(default="")) -> None:
    expected = settings.internal_key
    if not expected:
        raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, "WISECAT_INTERNAL_KEY not configured")

    prefix = "Bearer "
    if not authorization.startswith(prefix) or authorization[len(prefix):] != expected:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid bearer token")
