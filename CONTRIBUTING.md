# Contributing to CityRoute

Thanks for taking a look. This document covers the local setup, the gates your change has to pass, and the conventions used in this repository.

## Setting up

```bash
python -m venv .venv
source .venv/bin/activate          # Windows PowerShell: .venv/Scripts/Activate.ps1
python -m pip install -r requirements.txt
cp .env.example .env                # Windows: copy .env.example .env
```

```bash
cd frontend && npm install && cd ..   # only needed to work on the UI
```

On Windows, `cityroute-v3.ps1` does all of the above (`-Mode setup` skips the menu) and picks free ports automatically.

## Running the app

```bash
python -m uvicorn app.main:app --reload --port 8010      # API
cd frontend && npm run dev -- --port 5173                # demo UI, proxies /api to the API
```

The graph is already in `data/graphs/`, so no download is needed. Redis is optional; without it the service reports `degraded` and skips caching.

## Before you open a pull request

Run the same gates CI runs:

```bash
python -m ruff check .
python -m ruff format --check .
python -m compileall -q app
python -m pytest
```

`python -m pytest` collects 626 tests. If you are changing the graph loader, the routing algorithms or the matrix service, also run the consistency suite on its own so the worker processes get the memory they need:

```bash
python -m pytest tests/test_multiworker_consistency.py
```

For UI changes, build the bundle as well, and keep the tests written in JavaScript, not TypeScript:

```bash
cd frontend && npm run build
```

## Style

- **Python**: formatted and linted by Ruff (the version pinned in CI). Type annotations on public functions, no unused imports, docstrings on modules and non-obvious functions. Keep algorithm code in `app/core/` free of FastAPI imports so it stays unit-testable.
- **JavaScript/JSX**: plain `.jsx`/`.js` files, two-space indent, named exports where possible, no TypeScript syntax. The build is `vite build` alone.
- **Markdown and PowerShell**: forward slashes in command examples so they work in PowerShell, cmd and POSIX shells alike.

## Commits and branches

Conventional Commits, imperative mood, subject under ~72 characters:

```
feat(matrix): return road distances for 200 locations
fix(graphio): coerce GraphML edge lengths to float
perf(routing): skip the snap index rebuild when the graph is unchanged
docs(readme): document the free-tier deployment
test(vrp): assert 2-opt never increases tour length
chore(ci): cache npm and pip downloads
```

Branch names describe the change: `feat/route-compare`, `fix/readiness-redis`, `docs/quickstart-ports`.

## Adding an endpoint

1. Implement the algorithm in `app/core/` with unit tests that do not need the HTTP layer.
2. Expose it through a router in `app/api/` and a service in `app/services/`.
3. Define Pydantic request/response models in `app/schemas/`.
4. Add contract tests (status codes, validation failures, cache behaviour) and, if it is user-facing, a panel in the frontend.
5. Update `README.md`'s endpoint table and `CHANGELOG.md`.

## Reporting bugs and requesting features

Use the issue templates. For anything security-related, follow [SECURITY.md](SECURITY.md) instead of opening a public issue.

## License

By contributing you agree that your contribution is licensed under the [MIT License](LICENSE).
