# Deploying CityRoute

One container serves the API and the built single-page app on the same origin. There is no separate frontend host, no CORS configuration, and no second service to keep in sync.

```
 browser ──► container : PORT
               │
               ├─ /              → SPA shell (frontend/dist/index.html)
               ├─ /assets/*      → hashed JS/CSS bundles (404 when missing)
               ├─ /evidence/*    → archived evidence JSON bundled by the SPA
               └─ /api, /health, /route, /matrix, /vrp/*, /dispatch/* → FastAPI
```

`/api` is the JSON service index. `/` is the SPA whenever `frontend/dist/index.html` exists; without a build the same process stays API-only and answers `/` with that JSON index.

## 1. Docker (recommended)

```bash
# 12 MB Kanpur Central graph, single worker, ~512 MB friendly
docker build -f Dockerfile.render-free -t cityroute:demo .
docker run --rm -p 8000:8000 cityroute:demo

# general image (same runtime, no free-tier pinning)
docker build -f Dockerfile -t cityroute:full .
docker run --rm -p 8000:8000 cityroute:full

# either image can serve the large 63 MB Kanpur graph from a mount:
docker run --rm -p 8000:8000 -v "$PWD/data:/app/data" \
  -e CITYROUTE_GRAPH_FILE=kanpur.graphml cityroute:full
```

Both images are multi-stage: Node 22 builds the `.jsx` frontend, then a `python:3.11-slim` runtime serves it with Uvicorn. The container runs as an unprivileged user and answers `GET /health` for the platform health check. `PORT` (default 8000) and `WEB_CONCURRENCY` (default 1) are read at runtime; each worker loads its own copy of the graph.

Verify a running container:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8000/health/ready   # 200 when ready
curl -s http://localhost:8000/api | head -c 120                              # JSON service index
curl -s http://localhost:8000/ | grep -c 'id="root"'                        # 1 → SPA shell
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8000/assets/nope.js # 404, not HTML
```

## 2. Docker Compose (API + Redis + Prometheus)

```bash
cp .env.example .env       # compose reads env_file: .env
mkdir -p data/graphs       # place kanpur.graphml or kanpur_central.graphml here
docker compose up --build  # API on :8001, Prometheus on :9090
```

Compose mounts `./data` into the container, so graphs are read from the host instead of being baked into the image. Redis is a service in the compose file; the API finds it at `redis://redis:6379/0`.

## 3. Render (Blueprint)

`render.yaml` describes a single free-plan web service that builds `Dockerfile.render-free` and health-checks `/health/ready`. Point Render at this repository, choose New → Blueprint, and apply. The free plan has no Redis instance: cache operations stay fail-open, so routing, matrix, VRP, and dispatch keep working while the dispatch road-matrix cache reports itself unavailable.

On a paid plan, add the Redis instance commented at the bottom of `render.yaml` and set `CITYROUTE_REDIS_URL` to its internal key-value URL.

## 4. Plain host / VM

```bash
python -m venv .venv && . .venv/bin/activate
pip install -r requirements-prod.txt          # or requirements.txt for tests

cd frontend && npm ci && npm run build && cd ..

PORT=8000 WEB_CONCURRENCY=1 uvicorn app.main:app --host 0.0.0.0 --port $PORT
```

Run Uvicorn from the repository root so `frontend/dist` and `data/graphs` resolve. Behind Nginx or Caddy, proxy everything to Uvicorn: the SPA and the API share one origin by design.

## Environment variables

Every setting is prefixed with `CITYROUTE_`, read case-insensitively, and documented in `app/config.py`. The ones that matter for a deployment:

| Variable | Default | Purpose |
| --- | --- | --- |
| `CITYROUTE_ENVIRONMENT` | `local` | Label reported in logs |
| `CITYROUTE_GRAPH_FILE` | `kanpur_central.graphml` | Graph inside `CITYROUTE_GRAPH_DIR` |
| `CITYROUTE_GRAPH_DIR` | `data/graphs` | Where the GraphML extract lives |
| `CITYROUTE_CITY_NAME` | `Kanpur Central, Uttar Pradesh, India` | Display name for the graph |
| `CITYROUTE_SERVE_FRONTEND` | `true` | Serve `frontend/dist` at `/` when present |
| `CITYROUTE_FRONTEND_DIST_DIR` | `frontend/dist` | SPA build location |
| `CITYROUTE_METRICS_ENABLED` | `true` | Expose `GET /metrics` |
| `CITYROUTE_REDIS_URL` | `redis://localhost:6379/0` | Cache for road-matrix results |
| `CITYROUTE_REDIS_FAIL_OPEN` | `true` | Keep serving when Redis is down |
| `CITYROUTE_READINESS_REQUIRE_REDIS` | `false` | Make Redis a readiness requirement |
| `WEB_CONCURRENCY` | `1` | Uvicorn workers (each loads the graph) |
| `PORT` | `8000` | Listen port |

## Verification after deploying

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://HOST/health/live        # 200, process alive
curl -s -o /dev/null -w '%{http_code}\n' https://HOST/health/ready       # 200 ready, 503 not ready
curl -s https://HOST/api | python -m json.tool | head -20                 # "frontend": "/"
curl -s -o /dev/null -w '%{http_code}\n' 'https://HOST/route?start_lat=26.465&start_lon=80.33&end_lat=26.48&end_lon=80.35'
```

A `frontend` value of `/` in the service index means the SPA is mounted; `null` means the process is running API-only.

## CI

`.github/workflows/cityroute-free-ci-cd.yml` has three jobs:

- `backend` - Ruff, `compileall`, and the full pytest suite against a Redis service container.
- `frontend` - `npm ci`, `npm run build`, and build-output checks on Node 22.
- `docker-free` - builds `Dockerfile.render-free`, then runs a 512 MB container and smoke-tests readiness, `/health`, the SPA shell at `/`, the JSON index at `/api`, a client-side route fallback, and a missing asset.

The `deploy-render` job runs on pushes to the demo branch and calls the Render deploy hook when `RENDER_DEPLOY_HOOK_URL` is set.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `/` returns JSON, not the app | No SPA build in the image | Build with `Dockerfile` / `Dockerfile.render-free`, or run `npm run build` in `frontend/` |
| `/health/ready` stays 503 | Graph, snap index, or adjacency failed to load | Check the container logs for the graph load line |
| Deep links 404 in the browser | Traffic bypassed the app (static host serving `dist` directly) | Proxy all paths to the app; it owns the SPA fallback |
| Dispatch results always uncached | Redis unreachable and fail-open | Set `CITYROUTE_REDIS_URL` to a reachable instance |
| Container restarts under load | Worker count times graph memory exceeds the plan limit | Keep `WEB_CONCURRENCY=1` on 512 MB plans |
| Startup aborts with `DLL load failed while importing hashtable: An Application Control policy has blocked this file.` | The host policy blocks the compiled pandas extensions that osmnx pulls in | Nothing: the service logs a warning and loads the graph with networkx. Confirm with `graph_loader` in `/graph/stats`; the container paths are unaffected because they are Linux |

## osmnx is optional

`app/utils/graphio.py` imports osmnx lazily and falls back to networkx for every graph
operation. Only `graph_from_bbox` and `graph_from_place` - downloading a graph for a new
area - truly require osmnx; without it they raise `GraphDownloadUnavailable` with a
message rather than an import traceback. Loading the shipped GraphML, snapping,
routing, the matrix, VRP and dispatch all work with networkx alone, which is pure Python
and needs about half the memory of osmnx' pandas-based loader. `/graph/stats` reports
which loader ran as `graph_loader`.
