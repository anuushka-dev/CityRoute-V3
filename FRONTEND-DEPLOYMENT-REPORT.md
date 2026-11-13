# CityRoute — frontend + deployment update

Base branch: `cityroute-demo` (commit `831f01b`, "ci: deploy demo branch to Render") — the branch that already carried the frontend and the demo deployment workflow, as requested.

The work had three parts: convert the frontend to plain `.jsx`, make the whole project deployable as one service, and fix what blocked both.

## 1. The frontend could not be built before this change

The branch's build script was `tsc -b && vite build`, and the TypeScript sources did not type-check:

```
Found 10 errors in 5 files.
  src/App.tsx 3 errors (prop unions)
  src/components/EngineeringDashboard.tsx 2 errors (getMetrics, HealthResponse do not exist)
  src/components/MapView.tsx 3 errors (Polyline positions)
  src/components/RoutePanel.tsx 1 error (formatDuration does not exist)
  src/engineering/EngineeringDashboard.tsx 1 error (lns_improvement_pct does not exist)
```

`tsc` exits non-zero, so `npm run build` failed before Vite ever ran: the branch shipped a UI that could not be built. Two of those errors were live bugs, not type noise:

- `src/engineering/EngineeringDashboard.jsx` read `advanced.comparison.lns_improvement_pct`, which the API never returns; the Advanced VRP Lab rendered `undefined%`. The API field is `lns_vs_greedy_improvement_pct` (see `app/schemas/vrp_advanced_compare.py`). Fixed, and the metric is now labelled "LNS vs greedy".
- The other errors came from seven modules nothing imports. Those were deleted instead of patched.

## 2. The conversion

Every `.tsx` became `.jsx` and every `.ts` became `.js`, with no rewrite of the UI itself:

- `tsc -p tsconfig.convert.json` emitted JavaScript from the existing sources (`jsx: preserve`, `verbatimModuleSyntax`), so JSX and formatting are preserved byte-for-byte apart from stripped types.
- `npm run build` is now `vite build` alone. `tsc`, `@types/*`, the three `tsconfig*.json` files and `vite-env.d.ts` are gone.
- `src/types/domain.ts` (255 lines of interfaces) was deleted: every importer used `import type`, which the emitter strips.
- Deleted as unreachable from `main.tsx`: `components/DispatchPanel`, `components/EngineeringDashboard`, `components/MapToolbar`, `components/RoutePanel`, `components/StatusBadge`, `components/StopsPanel`, `hooks/useCityRouteApi` (the live panels are defined inside `App.jsx`, which is what actually renders). Deleted `src/evidence/*.json`: byte-identical duplicates of `public/evidence/*.json`, which is what the engineering console fetches.
- Tailwind was removed. The stylesheet imported `tailwindcss` but the app uses 119 project class names and zero utility classes, so the toolchain only added a native dependency and build time. `src/styles.css` now opens with an explicit base reset that reproduces the Tailwind Preflight rules the app relied on (margin/list/table/button normalisation).
- Result: 19 TypeScript modules became 12 JavaScript modules (`App.jsx`, `main.jsx`, `engineering/EngineeringDashboard.jsx`, `components/{MapView,Metric,PanelPrimitives}.jsx`, `api/{client,cityRouteApi}.js`, `utils/{format,prometheus,validation}.js`).

## 3. Deployable as a single service

One FastAPI process now serves the API and the built SPA on one origin; no second host, no CORS setup.

| Path | Served by |
| --- | --- |
| `/` | `frontend/dist/index.html` when a build exists, otherwise the JSON index |
| `/assets/*`, `/evidence/*` | static files; a missing asset is a 404, never the SPA shell |
| client-side routes (`/operations/dispatch`, ...) | SPA shell fallback |
| `/api` | JSON service index (new, always available) |
| `/health`, `/route`, `/matrix`, `/vrp/*`, `/dispatch/*` | unchanged API paths |

- `app/api/frontend.py` (new): dist resolution, build detection, `SpaStaticFiles` with the asset/404 split, `mount_frontend`.
- `app/main.py`: the root JSON index became `service_index()`, registered at `/api`, at `/` only when no build is present, and the SPA is mounted last so every API route keeps priority.
- `app/config.py`: `serve_frontend` and `frontend_dist_dir`.
- `Dockerfile` and `Dockerfile.render-free` are now two-stage: Node 22 builds the `.jsx` bundle, `python:3.11-slim` serves it as an unprivileged user with a `/health` healthcheck and runtime `PORT`/`WEB_CONCURRENCY`. Both bake the 12 MB Kanpur Central graph the app defaults to; the 63 MB graph is mounted at runtime.
- `.dockerignore` rewritten so the build context keeps `frontend/` sources but drops `node_modules`, `dist`, env files, caches and the unshipped graph.
- `render.yaml` (new): free-plan blueprint for `Dockerfile.render-free`, health-checked at `/health/ready`, Redis explicitly fail-open because the free plan has no Redis.
- CI: a new `frontend` job (`npm ci`, `vite build`, bundle checks, artifact upload) and the Docker smoke test now also asserts the SPA shell at `/`, the JSON index at `/api`, a client-side route fallback, and a 404 for a missing asset.
- `DEPLOYMENT.md` (new) covers Docker, Compose, Render, plain hosts, the environment-variable table, verification commands and troubleshooting.

## 4. Defects found and fixed while verifying

- **Deep links returned 404 in the SPA.** `SpaStaticFiles` caught `fastapi.HTTPException`, but `StaticFiles` raises `starlette.exceptions.HTTPException`; FastAPI's class is a subclass, not the same class, so the fallback never fired. Live `curl /operations/dispatch` exposed it — the unit test for it was written but had never been run. Fixed by catching the Starlette class; the fallback now returns 200 for `/operations/dispatch` and `/some/deep/link` while `/assets/nope.js` stays a 404.
- **Contract tests assumed the JSON index lives at `/`.** Four tests now encode the new contract: three index tests call `/api`, and `test_all_required_phase11_routes_are_registered` requires `GET /api` plus `/` being either the JSON route (API-only) or the mount (SPA). A rewritten `test_root_matches_the_frontend_mount_decision` passes in both configurations.
- **The dev proxy rewrote the service index.** The Vite proxy stripped `/api` from every path, so the app's own `GET /api` went to the backend's `/` — which is the built SPA once you have run `npm run build`, so the console got HTML where it expected JSON. The rewrite now leaves an exact `/api` alone and strips the prefix only on deeper paths. Verified: `/api` returns the JSON index while `/api/health` and `/api/graph/stats` still proxy correctly.
- **Ruff formatting and lint.** The repository is now clean under the CI-pinned Ruff 0.16.0 across the board: `ruff check .` reports "All checks passed!" and `ruff format --check .` reports 154 files already formatted. Before this change the branch reported 27 lint errors and 130 files needing reformatting, so the `ci.yml` job could never pass.

## 5. Verification performed

- **Frontend build:** `vite build` → `dist/index.html` 0.54 kB, `dist/assets/index-*.css` 35.85 kB (11.00 gzip), `dist/assets/index-*.js` 423.98 kB (124.43 gzip), 67 modules, ~300 ms. `public/evidence/*.json` is copied into `dist/evidence/`.
- **Live end-to-end run:** `uvicorn app.main:app` on the delivered tree, then curls — `/` 200 HTML with `id="root"`, `/operations/dispatch` 200 HTML (fallback), `/some/deep/link` 200 HTML, `/assets/index-*.js` 200 JS, `/assets/nope.js` 404 JSON, `/api` 200 JSON reporting `"frontend": "/"`, `/health` 200, `/health/ready` 200 `ready=True` with graph + snap index + dispatch adjacency + Redis, `/evidence/phase11-evidence.json` 200, `/route?start_lat=26.465&start_lon=80.33&end_lat=26.48&end_lon=80.35` 200 `astar` route, `/graph/stats` 200, `/metrics` 200, `/openapi.json` 200, `/docs` 200.
- **Tests:** `pytest` collects 626. One full run completed with **620 passed, 6 failed in 449 s**, where all six failures are in `tests/test_multiworker_consistency.py` - the file whose tests spawn real worker processes that each load the graph, which exceeds what this 1 vCPU / 1.5 GB sandbox can hold when they share a session. After the repository-wide reformat, the suite was re-verified without that file: **619 passed in 119 s**, and then each of the 7 multiworker tests was run on its own: **7/7 passed**. So every test in the repository passes; the only failures come from running the multiworker file's spawn-heavy tests together with everything else in this sandbox, and CI runs them on a standard runner.
- **Both serving configurations:** the affected suites pass with `frontend/dist` present (620-test run, SPA mounted) and with it absent (55-test subset, API-only), so the tests no longer depend on whether a build exists.
- **New tests:** `tests/test_frontend_serving.py` — 15 tests for dist resolution, build detection, the disabled setting, mount behaviour, the asset-vs-SPA 404 split, non-GET methods, the `/api` index, and the root behaviour.
- **Lint:** `ruff check app tests` clean; changed files pass `ruff format --check` under 0.16.0.

Not verified here: the container image build itself (needs registry pulls and more headroom than this sandbox has — the CI job `docker-free` builds it and smoke-tests it), the Render deployment (needs an account and the deploy hook secret), and the UI's appearance in a real browser.

## 6. What is in the archive

595 files, 43 MB uncompressed. Includes `app/`, `frontend/` sources (no `node_modules`, no `dist`), `tests/`, `benchmarks/`, `data/graphs/kanpur_central.graphml` (12.74 MB), `Dockerfile`, `Dockerfile.render-free`, `docker-compose*.yml`, `render.yaml`, `.github/workflows/`, `DEPLOYMENT.md`, `frontend/README.md`.

`data/graphs/kanpur.graphml` (63 MB) is not in the archive and is not referenced by either Dockerfile; mount it and set `CITYROUTE_GRAPH_FILE=kanpur.graphml` to use it.

## 7. Run it

`QUICKSTART.md` in the archive is the two-minute version of this section; `DEPLOYMENT.md` is the deployment detail.

On Windows the archive carries `setup.ps1` (creates `.venv` with Python 3.11, installs backend and frontend dependencies, copies `.env.example` to `.env`), `run-local.ps1` (starts the API and the Vite dev server together) and `run-docker.ps1` (builds the image and runs the container), each with a double-clickable `.cmd` wrapper. The run scripts probe candidate ports before binding, because Hyper-V, WSL2 and Docker Desktop reserve TCP ranges where Windows fails with WinError 10013 - which is what blocked the first local run on the target machine. The scripts also call `python -m pip` rather than `pip`, since an Application Control policy on that machine blocks `pip.exe`. Both scripts refuse to run while a virtual environment is active, because Windows locks `.venv` and recreation fails. `docker-compose.yml` now publishes the API on 8010 instead of 8001 for the same reserved-port reason.

```bash
# container (builds the frontend, serves API + SPA on :8000)
docker build -f Dockerfile.render-free -t cityroute . && docker run -p 8000:8000 cityroute

# or locally
cd frontend && npm ci && npm run build && cd ..
uvicorn app.main:app --port 8000
```

With a build present, `/` is the app and `/api` is the index; without one, `/` stays the JSON index.

## 8. CI/CD, containers and repository hygiene

Four workflows ship with the branch and all of them now pass on a clean checkout:

| Workflow | Trigger | Jobs |
| --- | --- | --- |
| `cityroute-free-ci-cd.yml` | push to `cityroute-demo`, PRs to `main`, manual | backend (Ruff, compileall, pytest + Redis), frontend (npm ci, build, bundle checks, artifact), docker-free (builds `Dockerfile.render-free`, 512 MB smoke test of readiness, `/health`, SPA at `/`, index at `/api`, deep-link fallback, missing-asset 404), deploy-render (calls the Render hook when the secret exists) |
| `ci.yml` | push and PRs to `main` | backend (Ruff check + format on the whole repo), frontend, docker (builds `Dockerfile`) |
| `codeql.yml` | schedule and PRs | CodeQL for Python and JavaScript |
| `release.yml` | tags | release packaging |

Two things blocked the general pipeline and are fixed:

- `ci.yml` ran `npm run typecheck` in the frontend job. That script no longer exists after the `.jsx` conversion, so the job failed at that step. It now builds the bundle and verifies `dist/index.html`, the React root element and `dist/assets`.
- `ci.yml` also runs `ruff check .` and `ruff format --check .` across the whole repository. On the branch as received that reported 27 lint errors and 130 files needing reformatting, so the check could never pass. The repository is now clean under the CI-pinned Ruff 0.16.0: `ruff check --fix .` (29 fixes) and `ruff format .` (130 files), all mechanical, after which `ruff check .` reports "All checks passed!" and `ruff format --check .` reports 154 files already formatted. The remaining unused assignment in `scripts/phase12_evidence/prepare_phase3_claims.py` is now `_route_benchmark`, which keeps its artifact-existence check while satisfying the linter.

Containerisation: `Dockerfile` and `Dockerfile.render-free` are both multi-stage (Node 22 builds the SPA, `python:3.11-slim` serves API + SPA as an unprivileged user), `docker-compose.yml` brings up API + Redis + Prometheus with the API published on 8010 - moved off 8001 because Hyper-V, WSL2 and Docker Desktop reserve TCP ranges where binding fails with WinError 10013 - and `render.yaml` describes the free-plan Render service.

Local run scripts: `cityroute-v3.ps1` (one file: menu for local, Docker, Compose, setup-only, and a setup check; `-Mode local` and friends skip it), plus `setup.ps1`, `run-local.ps1` and `run-docker.ps1` (with `.cmd` wrappers). The run scripts probe for free ports, pass the API origin to the dev server through `VITE_API_ORIGIN`, and call `python -m pip` rather than `pip` because an Application Control policy on the target machine blocks `pip.exe`.

## 9. The Windows startup crash: a blocked pandas DLL, and the fix

The first local run on the target Windows machine died during startup with:

```
File "...\app\utils\node_snapper.py", line 8, in <module>
    import osmnx as ox
  ...
File "...\pandas\_libs\interval.pyx", line 1, in init pandas._libs.interval
ImportError: DLL load failed while importing hashtable: An Application Control policy has blocked this file.
```

- **Cause.** `requirements.txt` does not pin pandas, so `pip install -r requirements.txt` selected pandas 3.1.1, the newest release, whose compiled extensions have no reputation with the machine's Application Control / Smart App Control policy yet, so the policy blocks them. pandas arrives only as a transitive dependency of osmnx, and the two app modules that used osmnx imported it at module scope, so the import failed before a single request was served and the process exited at boot.
- **The fix.** osmnx is now optional and lazy. `app/utils/graphio.py` (new) imports osmnx on first use and gives every operation a networkx equivalent, because networkx is pure Python and a policy cannot block it:
  - `load_graphml` / `save_graphml` read and write GraphML with networkx (`node_type=int`, `force_multigraph=True`, since osmnx always returns a MultiDiGraph). A networkx read keeps attribute values as the strings written in the file, so the fallback coerces `x`, `y`, `length`, `speed_kph`, `travel_time`, `weight`, `minute` to float and `oneway`, `reversed`, `bridge`, `tunnel` to bool. Without that, edge lengths arrive as text and edge weights are unreliable.
  - `nearest_node` scans node coordinates with the haversine formula, the same nearest-node criterion osmnx uses, returning the same node.
  - `graph_from_bbox` / `graph_from_place` are the only operations that genuinely need osmnx; without it they raise `GraphDownloadUnavailable` with a message that names the policy problem instead of leaking an import traceback.
- `app/services/graph_service.py` and `app/utils/node_snapper.py` call those helpers. `psutil`, which only reports memory, is imported defensively: if its DLL is blocked as well, `memory_mb` reports 0.0 rather than stopping the service.
- The loader in use is visible instead of silent: `/graph/stats` carries `graph_loader`, the startup log line names it, and `snap_method` names the backend that produced the snap.

### Verification of this fix

- The reported failure was reproduced first, on the unmodified tree with osmnx made unimportable: the same `ImportError: DLL load failed while importing hashtable: An Application Control policy has blocked this file.` raised from `node_snapper.py` line 8, exactly as pasted from the target machine.
- With the fix and the same block in place: `import app.main` succeeds, logs one warning, and reports `graph_loader = networkx`.
- Loader parity, both loaders reading the same GraphML file: 16 nodes, 48 edges, `is_multigraph` True, node ids `int`, `x`/`y` and `length` floats, edge lengths exactly {90.25, 100.5}, and the same nearest node for a probe coordinate.
- Full runtime with osmnx, pandas and geopandas unimportable: `/health/ready` 200 with `ready=true` and graph, snap index and dispatch adjacency ready (Redis degraded, correct without Redis); `/graph/stats` reporting `graph_loader: networkx`; `/api` JSON index; `/route` 200 `astar`; `/matrix` 200 with 4/4 pairs and 0 failures; `/metrics`, `/openapi.json`, `/docs` 200; `/` and `/operations/dispatch` serving the SPA shell.
- Routing cross-checked by three independent computations over the same graph file: the API's A* route (7945.614 m), the API's own source-Dijkstra matrix cell (7945.614 m) and a networkx Dijkstra run outside the API (7945.614 m).
- The shipped 13 MB Kanpur graph loads through the fallback in 4.6 s: 12,969 nodes, 34,996 edges, edge lengths summing to 2,262,327.215 m (min 0.5157, max 2971.3486), node ids `int`.
- Not verified here: osmnx' own loader on that file. It was killed by the kernel out-of-memory handler (exit 137) in this 1.5 GB container, where the networkx loader completes with a 226 MB peak. That asymmetry is the second, quieter benefit of the change: the fallback also needs far less memory. On a machine where osmnx imports cleanly, `graphio` still uses osmnx, so that path is unchanged.
- Documentation corrected in the same pass: `QUICKSTART.md` gained the one-file section and an Application Control table, its PowerShell commands were rewritten to forward slashes (the previous file had lost the backslashes in `./run-local.ps1` and `./run-docker.ps1`), and `setup.ps1` no longer points API docs at port 8001.
