# CityRoute production image: builds the .jsx frontend, then serves it from the
# same FastAPI process that serves the API. One image, one port, one origin.

# ---------------------------------------------------------------------------
# Stage 1 - build the frontend bundle
# ---------------------------------------------------------------------------
FROM node:22-alpine AS frontend-build

WORKDIR /frontend

# VITE_API_PREFIX is empty for the single-service deployment: the SPA calls the
# API on its own origin. Set it to /api to target a separately hosted backend.
ARG VITE_API_PREFIX=""
ENV VITE_API_PREFIX=${VITE_API_PREFIX}

COPY frontend/package.json frontend/package-lock.json ./

RUN npm ci --no-audit --no-fund

COPY frontend/ ./

RUN npm run build

# ---------------------------------------------------------------------------
# Stage 2 - Python API runtime that also serves the built SPA
# ---------------------------------------------------------------------------
FROM python:3.15-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1

# Default graph for the deployment image (12 MB Kanpur Central OSM extract).
# Point CITYROUTE_GRAPH_FILE at kanpur.graphml after mounting the full extract.
ENV CITYROUTE_GRAPH_FILE=kanpur_central.graphml

WORKDIR /app

COPY requirements-prod.txt .

RUN python -m pip install --upgrade pip \
    && pip install --no-cache-dir -r requirements-prod.txt

# CityRoute application
COPY app ./app

# Routing graph used by CityRoute (12 MB Kanpur Central OSM extract)
COPY data/graphs/kanpur_central.graphml ./data/graphs/kanpur_central.graphml

# Built single-page app served at /
COPY --from=frontend-build /frontend/dist ./frontend/dist

# Run as an unprivileged user instead of root
RUN useradd --create-home --uid 10001 appuser \
    && chown -R appuser:appuser /app

USER appuser

EXPOSE 8000

# The platform supplies PORT at runtime (Render, Railway, Fly, Replit, ...).
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD python -c "import os,urllib.request,sys; \
url='http://127.0.0.1:%s/health' % os.environ.get('PORT','8000'); \
sys.exit(0 if urllib.request.urlopen(url, timeout=4).status == 200 else 1)" || exit 1

# Each worker loads its own copy of the graph. One worker fits a 512 MB free tier.
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --workers ${WEB_CONCURRENCY:-1}"]
