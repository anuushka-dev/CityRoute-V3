# app/utils/graphio.py
"""Graph file I/O that works with or without osmnx.

osmnx is only needed to download a graph or to write GraphML with osmnx' own
conventions. Importing it pulls in geopandas and pandas, and on Windows the
compiled DLLs inside those wheels can be blocked by an Application Control or
Smart App Control policy, which makes the import fail with::

    ImportError: DLL load failed while importing hashtable:
    An Application Control policy has blocked this file.

That failure happens at import time, so a module-level "import osmnx" takes the
whole service down before it serves a single request. osmnx is therefore
imported lazily here and every operation has a networkx equivalent: networkx is
pure Python and cannot be blocked this way, so the service starts and routes
with or without osmnx available.
"""

from __future__ import annotations

from collections.abc import Iterable
from importlib import import_module
from math import asin, cos, radians, sin, sqrt
from pathlib import Path
from typing import Any

import networkx as nx

from app.utils.logger import get_logger

logger = get_logger(__name__)

EARTH_RADIUS_M = 6_371_000.0

# Attributes the routers do arithmetic on. The GraphML reader of networkx keeps
# the type declared in the file, but that declaration is not always honoured by
# other writers, so the fallback load coerces these to float.
_NUMERIC_NODE_ATTRIBUTES = ("x", "y", "lat", "lon")
_NUMERIC_EDGE_ATTRIBUTES = ("length", "speed_kph", "travel_time", "weight", "minute")

# osmnx stores these as booleans; GraphML writes them as the strings "True" /
# "False", which networkx keeps as text.
_BOOLEAN_EDGE_ATTRIBUTES = ("oneway", "reversed", "bridge", "tunnel")

_osmnx_module: Any | None = None
_osmnx_import_error: Exception | None = None
_osmnx_checked = False


class GraphDownloadUnavailable(RuntimeError):
    """Raised when a download is requested but osmnx cannot be imported."""


def osmnx() -> Any | None:
    """Return the osmnx module, or None when it is not importable here."""
    global _osmnx_module, _osmnx_import_error, _osmnx_checked

    if not _osmnx_checked:
        _osmnx_checked = True
        try:
            _osmnx_module = import_module("osmnx")
        except Exception as exc:  # noqa: BLE001 - ImportError or a blocked-DLL OSError
            _osmnx_module = None
            _osmnx_import_error = exc
            logger.warning(
                (
                    "osmnx is not importable (%s: %s); graph I/O falls back to networkx. "
                    "Routing, snapping and every API endpoint are unaffected."
                ),
                type(exc).__name__,
                exc,
            )

    return _osmnx_module


def osmnx_import_error() -> Exception | None:
    """Return the exception that stopped osmnx from importing, if any."""
    osmnx()
    return _osmnx_import_error


def graph_backend() -> str:
    """Name the loader in use: "osmnx" or "networkx"."""
    return "osmnx" if osmnx() is not None else "networkx"


def load_graphml(path: str | Path) -> Any:
    """Load a GraphML file with osmnx when available, otherwise with networkx."""
    path = Path(path)
    module = osmnx()

    if module is not None:
        return module.load_graphml(path)

    logger.warning("Loading GraphML with the networkx fallback: %s", path)

    # osmnx always returns a MultiDiGraph; the fallback asks networkx for the
    # same shape so that edge keys and parallel edges behave identically.
    graph = nx.read_graphml(path, node_type=int, force_multigraph=True)

    graph = _coerce_numeric_attributes(
        graph,
        node_attributes=_NUMERIC_NODE_ATTRIBUTES,
        edge_attributes=_NUMERIC_EDGE_ATTRIBUTES,
    )

    return _coerce_boolean_attributes(graph, edge_attributes=_BOOLEAN_EDGE_ATTRIBUTES)


def save_graphml(graph: Any, path: str | Path) -> bool:
    """Write a GraphML file. Returns False when the networkx fallback wrote it."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)

    module = osmnx()

    if module is not None:
        module.save_graphml(graph, path)
        return True

    logger.warning("Writing GraphML with the networkx fallback: %s", path)
    nx.write_graphml(graph, path)
    return False


def graph_from_bbox(
    bbox: tuple[float, float, float, float],
    *,
    network_type: str = "drive",
    simplify: bool = True,
) -> Any:
    """Download a graph for a (west, south, east, north) bounding box."""
    module = _require_osmnx("download a bounding-box graph")
    return module.graph_from_bbox(bbox, network_type=network_type, simplify=simplify)


def graph_from_place(
    place: str,
    *,
    network_type: str = "drive",
    simplify: bool = True,
) -> Any:
    """Download a graph for a place name."""
    module = _require_osmnx("download a graph for a place")
    return module.graph_from_place(place, network_type=network_type, simplify=simplify)


def nearest_node(graph: Any, *, lat: float, lon: float) -> int:
    """Return the node of the graph closest to (lat, lon).

    osmnx uses a haversine BallTree; the fallback scans the node coordinates
    with the same distance function, so both return the same node.
    """
    module = osmnx()

    if module is not None:
        return int(module.distance.nearest_nodes(graph, X=lon, Y=lat))

    return _nearest_node_by_distance(graph, lat=lat, lon=lon)


def haversine_m(lat_a: float, lon_a: float, lat_b: float, lon_b: float) -> float:
    """Great-circle distance between two coordinates, in metres."""
    lat_a_r, lon_a_r = radians(lat_a), radians(lon_a)
    lat_b_r, lon_b_r = radians(lat_b), radians(lon_b)

    delta_lat = lat_b_r - lat_a_r
    delta_lon = lon_b_r - lon_a_r

    value = sin(delta_lat / 2) ** 2 + cos(lat_a_r) * cos(lat_b_r) * sin(delta_lon / 2) ** 2

    return 2 * EARTH_RADIUS_M * asin(sqrt(value))


def _require_osmnx(action: str) -> Any:
    module = osmnx()

    if module is None:
        error = osmnx_import_error()
        raise GraphDownloadUnavailable(
            f"osmnx is not importable ({type(error).__name__}: {error}), so this process "
            f"cannot {action}. Put a GraphML file at the configured graph path "
            "(CITYROUTE_GRAPH_FILE) and restart."
        )

    return module


def _nearest_node_by_distance(graph: Any, *, lat: float, lon: float) -> int:
    best_node: int | None = None
    best_distance = float("inf")

    for node, data in graph.nodes(data=True):
        node_lat = data.get("y")
        node_lon = data.get("x")

        if node_lat is None or node_lon is None:
            continue

        distance = haversine_m(lat, lon, float(node_lat), float(node_lon))

        if distance < best_distance:
            best_node = int(node)
            best_distance = distance

    if best_node is None:
        raise ValueError("Graph contains no nodes with x/y coordinates.")

    return best_node


def _coerce_numeric_attributes(
    graph: Any,
    *,
    node_attributes: Iterable[str],
    edge_attributes: Iterable[str],
) -> Any:
    for _node, data in graph.nodes(data=True):
        _coerce(data, node_attributes)

    for _source, _target, data in graph.edges(data=True):
        _coerce(data, edge_attributes)

    return graph


def _coerce_boolean_attributes(graph: Any, *, edge_attributes: Iterable[str]) -> Any:
    for _source, _target, data in graph.edges(data=True):
        for key in edge_attributes:
            if key in data:
                data[key] = _to_bool(data[key])

    return graph


def _to_bool(value: Any) -> Any:
    if isinstance(value, bool):
        return value

    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered in {"true", "1"}:
            return True
        if lowered in {"false", "0"}:
            return False

    return value


def _coerce(data: dict[str, Any], keys: Iterable[str]) -> None:
    for key in keys:
        if key in data:
            data[key] = _to_float(data[key])


def _to_float(value: Any) -> Any:
    if isinstance(value, bool) or isinstance(value, float):
        return value

    if isinstance(value, (int, str)):
        try:
            return float(value)
        except (TypeError, ValueError):
            return value

    return value
