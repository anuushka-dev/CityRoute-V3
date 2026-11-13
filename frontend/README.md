# CityRoute Frontend

The CityRoute UI is plain JavaScript with JSX (`.jsx`) built by Vite and React 19. There is no TypeScript build step in this app.

The UI is split into two views:

- **Product**: the map-first routing, delivery optimization, and dispatch workflows backed by the FastAPI endpoints.
- **Engineering**: live runtime/graph/readiness/metrics telemetry plus archived Phase 11 evidence and source-archive inventory.

## Requirements

- Node.js 22 or newer (24 is used in the container images)

## Local development

Two processes: the API on port 8001 and the Vite dev server on port 5173.

```bash
# terminal 1 - backend
python -m uvicorn app.main:app --reload --port 8001

# terminal 2 - frontend
cd frontend
npm install
npm run dev            # http://localhost:5173
```

The dev server proxies `/api/*` to `http://127.0.0.1:8001` and strips the prefix, so the browser code and the deployed image call the same backend paths. Override the target with `VITE_API_ORIGIN` if the backend runs elsewhere.

## Production build

```bash
npm ci
npm run build          # writes frontend/dist
```

`npm run build` runs `vite build` only: no type checker and no Tailwind. The bundle is written to `frontend/dist` and is served by the FastAPI process itself in deployment, at `/`:

- `GET /` - single-page app shell
- `GET /assets/*` - hashed bundles (a missing asset is a 404, not the shell)
- `GET /api` - JSON service index
- `GET /health`, `/health/ready`, `/route`, `/matrix`, ... - the API, unchanged

The build uses same-origin API paths by default. To build the SPA against a separately hosted API, pass the prefix as a build arg, for example `docker build --build-arg VITE_API_PREFIX=/api` when a gateway owns `/api`.

## Module map

```
index.html              Vite entry that loads src/main.jsx
vite.config.js          dev proxy, API prefix, build output
src/main.jsx            mounts App into #root
src/App.jsx             product workspace: header, route/deliveries/dispatch panels, matrix view
src/engineering/EngineeringDashboard.jsx
                        engineering console: live telemetry probes and archived evidence
src/components/MapView.jsx        Leaflet map, geometry and marker rendering
src/components/Metric.jsx         metric tile
src/components/PanelPrimitives.jsx  CodeTag, PanelSection, StatusPill
src/api/client.js       fetch wrapper, ApiRequestError, API base
src/api/cityRouteApi.js one call per backend endpoint
src/utils/format.js     number/distance/duration formatting
src/utils/prometheus.js minimal Prometheus text parsing for the console
src/utils/validation.js city bounds and coordinate guard
src/styles.css          the entire stylesheet (no Tailwind)
public/evidence/*.json  archived evidence fetched by the engineering console
```

## Notes

- Styling lives in `src/styles.css` and uses project class names only; the file starts with an explicit base reset that replaces the Tailwind Preflight layer the stylesheet used to import.
- The engineering console fetches `/evidence/*.json` from `public/`, which Vite copies into `dist/`. Archived evidence is labelled as archived; it is never presented as live telemetry.
- `frontend/dist` is a build artifact and is not committed.
