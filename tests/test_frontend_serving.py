# tests/test_frontend_serving.py

from __future__ import annotations

from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.frontend import (
    SpaStaticFiles,
    frontend_available,
    mount_frontend,
    resolve_frontend_dist_dir,
)
from app.config import Settings
from app.main import app

INDEX_HTML = '<!doctype html><html><body><div id="root"></div></body></html>'
APP_JS = "console.log('cityroute');"


def _build_frontend_dist(tmp_path: Path) -> Path:
    dist_dir = tmp_path / "dist"
    assets_dir = dist_dir / "assets"

    assets_dir.mkdir(parents=True)

    (dist_dir / "index.html").write_text(INDEX_HTML, encoding="utf-8")
    (assets_dir / "index-abc123.js").write_text(APP_JS, encoding="utf-8")

    return dist_dir


def _settings(**overrides) -> Settings:
    return Settings(**overrides)


def test_resolve_frontend_dist_dir_uses_absolute_path(tmp_path: Path):
    resolved = resolve_frontend_dist_dir(dist_dir=tmp_path)

    assert resolved == tmp_path


def test_resolve_frontend_dist_dir_resolves_relative_to_cwd():
    resolved = resolve_frontend_dist_dir(config=_settings(frontend_dist_dir=Path("frontend/dist")))

    assert resolved == Path.cwd() / "frontend" / "dist"


def test_frontend_available_is_false_without_a_build(tmp_path: Path):
    assert frontend_available(dist_dir=tmp_path) is False


def test_frontend_available_is_true_with_a_build(tmp_path: Path):
    dist_dir = _build_frontend_dist(tmp_path)

    assert frontend_available(dist_dir=dist_dir) is True


def test_frontend_available_respects_disabled_setting(tmp_path: Path):
    dist_dir = _build_frontend_dist(tmp_path)

    assert (
        frontend_available(
            dist_dir=dist_dir,
            config=_settings(serve_frontend=False),
        )
        is False
    )


def test_mount_frontend_returns_false_without_a_build(tmp_path: Path):
    mounted = mount_frontend(FastAPI(), dist_dir=tmp_path)

    assert mounted is False


def test_mount_frontend_returns_false_when_disabled(tmp_path: Path):
    dist_dir = _build_frontend_dist(tmp_path)

    mounted = mount_frontend(
        FastAPI(),
        dist_dir=dist_dir,
        config=_settings(serve_frontend=False),
    )

    assert mounted is False


def test_mounted_frontend_serves_spa_and_static_assets(tmp_path: Path):
    dist_dir = _build_frontend_dist(tmp_path)
    frontend_app = FastAPI()

    frontend_app.add_api_route("/health", lambda: {"status": "ok"})

    assert mount_frontend(frontend_app, dist_dir=dist_dir) is True

    with TestClient(frontend_app) as client:
        index_response = client.get("/")
        asset_response = client.get("/assets/index-abc123.js")
        missing_asset_response = client.get("/assets/missing.js")
        client_route_response = client.get("/operations/dispatch")
        health_response = client.get("/health")

    assert index_response.status_code == 200
    assert '<div id="root">' in index_response.text

    assert asset_response.status_code == 200
    assert asset_response.text == APP_JS

    # A missing bundle must 404 instead of returning HTML to the browser.
    assert missing_asset_response.status_code == 404

    # Unknown client-side routes fall back to the SPA shell.
    assert client_route_response.status_code == 200
    assert '<div id="root">' in client_route_response.text

    # API routes registered before the mount keep priority.
    assert health_response.status_code == 200
    assert health_response.json() == {"status": "ok"}


def test_spa_static_files_rejects_non_read_methods(tmp_path: Path):
    dist_dir = _build_frontend_dist(tmp_path)
    frontend_app = FastAPI()

    mount_frontend(frontend_app, dist_dir=dist_dir)

    with TestClient(frontend_app) as client:
        response = client.post("/")

    assert response.status_code == 405


def test_service_index_is_available_at_api():
    with TestClient(app) as client:
        response = client.get("/api")

    assert response.status_code == 200

    payload = response.json()

    assert payload["status"] == "ok"
    assert payload["index"] == "/api"
    assert payload["route"] == "/route"
    assert payload["dispatch_compare"] == "/dispatch/compare"


def test_root_matches_the_frontend_mount_decision():
    with TestClient(app) as client:
        response = client.get("/")

    assert response.status_code == 200

    if app.state.frontend_mounted:
        assert response.headers["content-type"].startswith("text/html")
        assert '<div id="root">' in response.text
    else:
        # API-only deployments keep the JSON service index at "/".
        assert response.headers["content-type"].startswith("application/json")
        assert response.json()["status"] == "ok"
        assert response.json()["frontend"] is None


def test_spa_static_files_class_is_used_by_the_mount(tmp_path: Path):
    dist_dir = _build_frontend_dist(tmp_path)
    frontend_app = FastAPI()

    mount_frontend(frontend_app, dist_dir=dist_dir)

    mounted_apps = [
        route.app for route in frontend_app.routes if getattr(route, "name", None) == "frontend"
    ]

    assert len(mounted_apps) == 1
    assert isinstance(mounted_apps[0], SpaStaticFiles)


def test_frontend_index_name_is_stable():
    from app.api.frontend import INDEX_FILE_NAME

    assert INDEX_FILE_NAME == "index.html"


@pytest.mark.parametrize("asset_path", ["assets/app.js", "evidence/report.json"])
def test_static_asset_prefixes_do_not_fall_back(asset_path: str, tmp_path: Path):
    dist_dir = _build_frontend_dist(tmp_path)
    frontend_app = FastAPI()

    mount_frontend(frontend_app, dist_dir=dist_dir)

    with TestClient(frontend_app) as client:
        response = client.get(f"/{asset_path}")

    assert response.status_code == 404
