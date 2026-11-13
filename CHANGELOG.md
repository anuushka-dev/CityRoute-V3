# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.1] - 2026-11-14

### Security

- `pytest` 8.3.4 → **9.0.3** for the temporary-directory handling advisory.
- `vite` 8.2.2 → **8.3.7**, with `source-map-js` forced to **1.2.2** through an npm override. This clears the vite, launch-editor and source-map-js advisories; `postcss` and `rolldown` moved with them.
- The lockfile was regenerated with `npm install --package-lock-only` and verified with `npm ci` plus a full bundle build before it was committed.
- Open Dependabot alerts on the default branch: **8 → 0** (2 high, 5 moderate, 1 low).

## [3.0.0] - 2026-11-14

First release of CityRoute as a standalone repository: one FastAPI process serving the API and the React SPA, with the road graph, the benchmarks and the deployments included.

### Added

- `app/utils/graphio.py`: graph I/O that works with or without `osmnx`. `osmnx` is imported lazily and every operation has a `networkx` equivalent, so a host policy that blocks the compiled pandas DLLs can no longer stop the service from starting.
- `GET /api`: JSON service index, so the API describes itself even when the SPA owns `/`.
- `app/api/frontend.py`: SPA mount with a build-detection check, a SPA-shell fallback for client-side routes, and a real 404 for a missing asset.
- `render.yaml`: free-plan Render blueprint for `Dockerfile.render-free`, health-checked at `/health/ready`.
- `DEPLOYMENT.md`, `QUICKSTART.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, issue and pull-request templates, Dependabot configuration, and this changelog.
- `docs/ENGINEERING-LOG.md`: the phase-by-phase engineering history, moved out of the README.
- `cityroute-v3.ps1`: one script covering local run, Docker, Compose, setup and setup checks, with free-port probing.

### Changed

- The frontend is plain `.jsx`/`.js`: the `tsc` build step, the `@types/*` dependencies and the `tsconfig*.json` files are gone, and `npm run build` is `vite build` alone.
- `matrix`, `vrp` and `dispatch` responses are unchanged, but repeated requests are now served from Redis when it is reachable and always fail open when it is not.
- `Dockerfile` and `Dockerfile.render-free` are two-stage builds: Node 22 builds the SPA, `python:3.11-slim` serves API and SPA as an unprivileged user with a `/health` healthcheck.
- The Python codebase is formatted and linted by Ruff 0.16.0 across the repository, which the CI job enforces.

### Fixed

- Client-side routes returned 404 instead of the SPA shell: the static handler caught FastAPI's `HTTPException` while `StaticFiles` raises Starlette's, so the fallback never fired.
- The Vite dev proxy rewrote the service index, so the app's own `GET /api` reached the built SPA and returned HTML instead of JSON.
- `src/engineering/EngineeringDashboard.jsx` read `lns_improvement_pct`, which the API never returns; it now reads `lns_vs_greedy_improvement_pct` and labels it "LNS vs greedy".
- Everything that blocked the first Windows run: the port the scripts and Compose published (`WinError 10013` on reserved ranges), `pip` versus `python -m pip` under an Application Control policy, and the blocked-DLL startup crash described above.

[3.0.0]: https://github.com/anuushka-dev/CityRoute-V3/releases/tag/v3.0.0
