# CityRoute - quick start

Everything below runs on Windows, and the same project runs unchanged on Linux and
macOS. `cityroute-v3.ps1` is the single file that covers all of it: it checks Python
3.11, Node and Docker, installs whatever is missing, picks free ports, then starts
either the local demo or the container.

The 12.7 MB Kanpur Central graph is included (data/graphs/kanpur_central.graphml), so
nothing downloads on first run. Redis is optional: without it the service reports
`degraded` and skips caching, but every endpoint still answers.

## One file for everything (Windows)

```powershell
powershell -ExecutionPolicy Bypass -File ./cityroute-v3.ps1
```

The menu: 1 run locally, 2 run in Docker, 3 Docker Compose, 4 set up only,
5 check my setup. Skip it with `-Mode local` or `-Mode docker`, and force ports with
`-ApiPort 8010 -WebPort 5173 -DockerPort 8000`.

## Local setup (Windows)

Needs Python 3.11 (`winget install --id Python.Python.3.11 -e`) and Node 22.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
./setup.ps1                 # one time: .venv, backend deps, .env, frontend deps
./run-local.ps1             # every time: API on 8010, demo on 5173
```

Then open http://localhost:5173. The two ports printed by the script are the ones it
actually used: it skips ports Windows reserves, so the numbers can differ from the
defaults (see WinError 10013 below).

## Docker setup (Windows)

Needs Docker Desktop running (WSL2 backend).

```powershell
./run-docker.ps1              # builds Dockerfile.render-free and runs it on 8000
./run-docker.ps1 -Port 9080   # pick the host port yourself
./run-docker.ps1 -Compose     # API + Redis + Prometheus via docker-compose.yml
```

Open http://localhost:8000. The image builds the .jsx bundle with Node inside the
build, so it needs nothing installed on the host beyond Docker. `-Compose` publishes
the API on 8010 and Prometheus on 9090, and reads `.env`.

The equivalent manual commands:

```bash
docker build -f Dockerfile.render-free -t cityroute:local .
docker run --rm -p 8000:8000 cityroute:local
```
## WinError 10013: ports Windows reserves

Hyper-V, WSL2 and Docker Desktop reserve TCP ranges, and binding one of them fails with
`[WinError 10013] An attempt was made to access a socket in a way forbidden by its access
permissions`. `run-local.ps1`, `run-docker.ps1` and `cityroute-v3.ps1` probe candidate
ports and use a free one, so this stops happening. To see what is reserved:

```powershell
netsh interface ipv4 show excludedportrange protocol=tcp
```

To free a specific port, reserve it outside the dynamic ranges (admin shell):

```powershell
net stop winnat
netsh int ipv4 add excludedportrange protocol=tcp startport=8001 numberofports=1
net start winnat
```

## Application Control: blocked DLLs from pip wheels

Some managed machines run an Application Control or Smart App Control policy that
blocks executables and DLLs it does not recognise, including files inside pip wheels.
There are two symptoms, and neither one is fatal:

| Symptom | What is happening | What to do |
| --- | --- | --- |
| `pip install ...` reports "has blocked this file" | The policy blocks `pip.exe` | Call `python -m pip install -r requirements.txt` instead; every script in this project already does |
| `ImportError: DLL load failed while importing hashtable: An Application Control policy has blocked this file.` | pandas compiled extensions, pulled in by osmnx, are blocked | Nothing. The service detects it, logs one warning and loads the graph with networkx instead. `/graph/stats` reports `"graph_loader": "networkx"` |

osmnx is only needed to download a graph for a new area. Routing, snapping, the
distance matrix, VRP and dispatch work without it. The Docker path avoids the policy
entirely, because the container runs Linux.

## Check that it is running

```bash
curl http://localhost:8010/health          # service heartbeat
curl http://localhost:8010/health/ready    # 200 once graph, snap index and adjacency are loaded
curl http://localhost:8010/graph/stats     # nodes, edges, load time and the graph loader in use
curl http://localhost:8010/api             # JSON service index ("frontend": "/" when the SPA is mounted)
curl "http://localhost:8010/route?start_lat=26.465&start_lon=80.33&end_lat=26.48&end_lon=80.35"
curl -X POST http://localhost:8010/matrix -H "Content-Type: application/json" -d "{\"locations\":[{\"id\":\"a\",\"lat\":26.45,\"lon\":80.33},{\"id\":\"b\",\"lat\":26.48,\"lon\":80.35}]}"
```

Interactive API docs: the `/docs` URL printed by the run script, or http://localhost:8000/docs in Docker.

## Manual setup (macOS, Linux, or Windows without the scripts)

Backend, from the repository root:

```bash
python -m venv .venv
source .venv/bin/activate        # Windows PowerShell: .venv/Scripts/Activate.ps1
python -m pip install -r requirements.txt
cp .env.example .env             # Windows: copy .env.example .env
python -m uvicorn app.main:app --reload --port 8010
```

Frontend, in a second terminal (set VITE_API_ORIGIN when the API is not on 8010):

```bash
cd frontend
npm install
npm run dev -- --port 5173
```

One process, like production:

```bash
cd frontend && npm ci && npm run build && cd ..
python -m uvicorn app.main:app --port 8010
```

With a build present the app owns /, client-side routes work, and the JSON service index
answers /api. Without a build, / is the JSON index and the process is API-only.

## Optional: Redis

```bash
docker run -d --name cityroute-redis -p 6379:6379 redis:7-alpine
```

Defaults point at redis://localhost:6379/0. With Redis up, readiness reports ready and
repeated matrix and dispatch requests hit the cache. Without it everything still works
and readiness reports `degraded`.

## If something looks wrong

| Symptom | Cause | Fix |
| --- | --- | --- |
| WinError 10013 when starting the API | The port is in a range Windows reserves | Use cityroute-v3.ps1 or run-local.ps1, which pick a free port |
| "has blocked this file" during install | The policy blocks pip.exe | Use `python -m pip install -r requirements.txt` |
| `DLL load failed while importing hashtable` at startup | Application Control blocks pandas/osmnx | Nothing to fix: the graph loads through networkx; check `"graph_loader"` in /graph/stats |
| Docker is not answering | Docker Desktop is not running | Start it, wait for "Engine running", retry |
| / shows JSON instead of the app | No frontend build in the tree or image | npm run build in frontend/, or use run-docker.ps1 |
| 503 from /health/ready | Graph, snap index or adjacency not loaded | Read the startup log lines for app.main |
| The map is blank | Blocked tile requests or a browser without WebGL | Check the browser console; the API panels still work |

Full detail: DEPLOYMENT.md (deployment) and frontend/README.md (frontend).
