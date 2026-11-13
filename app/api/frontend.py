# app/api/frontend.py

from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.responses import Response

from app.config import Settings, settings
from app.utils.logger import get_logger

logger = get_logger(__name__)

INDEX_FILE_NAME = "index.html"

# Assets that must never fall back to the SPA shell, because a browser asking
# for a missing bundle should get a 404 instead of HTML.
STATIC_ASSET_PREFIXES = ("assets/", "evidence/", "static/")


def resolve_frontend_dist_dir(
    *,
    dist_dir: str | Path | None = None,
    config: Settings | None = None,
) -> Path:
    """Return the directory that holds the built SPA.

    Relative paths are resolved against the process working directory, which is
    the repository root for local runs and /app inside the deployment image.
    """

    if dist_dir is not None:
        configured = Path(dist_dir)
    else:
        configured = Path((config or settings).frontend_dist_dir)

    if configured.is_absolute():
        return configured

    return Path.cwd() / configured


def frontend_available(
    *,
    dist_dir: str | Path | None = None,
    config: Settings | None = None,
) -> bool:
    """Return True when a built SPA should be served by this process."""

    effective_config = config or settings

    if not effective_config.serve_frontend:
        return False

    resolved_dist_dir = resolve_frontend_dist_dir(
        dist_dir=dist_dir,
        config=effective_config,
    )

    return (resolved_dist_dir / INDEX_FILE_NAME).is_file()


class SpaStaticFiles(StaticFiles):
    """StaticFiles that serves index.html for client-side routes.

    A single-page app has client-side paths that do not exist on disk, so any
    miss that is not a static asset request must return the SPA shell instead of
    404 so the app can boot and route on the client.
    """

    async def get_response(
        self,
        path: str,
        scope,
    ) -> Response:
        try:
            return await super().get_response(path, scope)
        except StarletteHTTPException as exc:
            if exc.status_code != 404 or path.startswith(STATIC_ASSET_PREFIXES):
                raise

            return await super().get_response(INDEX_FILE_NAME, scope)


def mount_frontend(
    app: FastAPI,
    *,
    dist_dir: str | Path | None = None,
    config: Settings | None = None,
) -> bool:
    """Serve the built SPA at `/` when a build is present.

    Returns True when the SPA was mounted. When no build is present the JSON
    service index keeps answering `/`, which is what the test suite and API-only
    deployments expect.
    """

    effective_config = config or settings

    if not frontend_available(dist_dir=dist_dir, config=effective_config):
        logger.info(
            "No built frontend found; serving the JSON index at / | dist_dir=%s",
            resolve_frontend_dist_dir(
                dist_dir=dist_dir,
                config=effective_config,
            ),
        )
        return False

    resolved_dist_dir = resolve_frontend_dist_dir(
        dist_dir=dist_dir,
        config=effective_config,
    )

    app.mount(
        "/",
        SpaStaticFiles(directory=str(resolved_dist_dir), html=True),
        name="frontend",
    )

    logger.info(
        "Frontend mounted at / | dist_dir=%s",
        resolved_dist_dir,
    )

    return True


__all__ = [
    "INDEX_FILE_NAME",
    "SpaStaticFiles",
    "frontend_available",
    "mount_frontend",
    "resolve_frontend_dist_dir",
]
