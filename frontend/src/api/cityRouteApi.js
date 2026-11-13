import { API_BASE, get, post } from './client';
// The JSON service index answers / in local development (the dev proxy strips
// the /api prefix from every request) and /api in the deployed image, where the
// SPA owns / and the API keeps its own paths on the same origin.
const ROOT_PATH = API_BASE ? '' : '/api';
const HEALTH_PATH = '/health';
const LIVE_PATH = '/health/live';
const READY_PATH = '/health/ready';
const GRAPH_STATS_PATH = '/graph/stats';
const GRAPH_VALIDATE_PATH = '/graph/validate';
const GRAPH_SNAP_PATH = '/graph/snap';
const ROUTE_PATH = '/route';
const ROUTE_COMPARE_PATH = '/route/compare';
const MATRIX_PATH = '/matrix';
const VRP_GREEDY_PATH = '/vrp/greedy';
const VRP_COMPARE_PATH = '/vrp/compare';
const VRP_ADVANCED_COMPARE_PATH = '/vrp/compare/advanced';
const DISPATCH_COMPARE_PATH = '/dispatch/compare';
const METRICS_PATH = '/metrics';
export function getRoot() { return get(ROOT_PATH); }
export function getHealth() { return get(HEALTH_PATH); }
export function getLiveness() { return get(LIVE_PATH); }
export function getReadiness() { return get(READY_PATH); }
export function getGraphStats() { return get(GRAPH_STATS_PATH); }
function buildCoordinateQuery(coordinate, prefix) {
    return `${prefix}_lat=${encodeURIComponent(coordinate.lat)}&${prefix}_lon=${encodeURIComponent(coordinate.lon)}`;
}
function buildRouteQuery(start, end) {
    return [buildCoordinateQuery(start, 'start'), buildCoordinateQuery(end, 'end')].join('&');
}
export function validateGraphCoordinate(coordinate) {
    return get(`${GRAPH_VALIDATE_PATH}?lat=${coordinate.lat}&lon=${coordinate.lon}`);
}
export function snapGraphCoordinate(coordinate) {
    return get(`${GRAPH_SNAP_PATH}?lat=${coordinate.lat}&lon=${coordinate.lon}`);
}
export function getRoute(start, end) {
    return get(`${ROUTE_PATH}?${buildRouteQuery(start, end)}`);
}
export function compareRoute(start, end) {
    return get(`${ROUTE_COMPARE_PATH}?${buildRouteQuery(start, end)}`);
}
export function createMatrix(request) {
    return post(MATRIX_PATH, request);
}
export function optimizeStops(request) {
    return post(VRP_GREEDY_PATH, request);
}
export function compareStops(request) {
    return post(VRP_COMPARE_PATH, request);
}
export function compareAdvancedStops(request) {
    return post(VRP_ADVANCED_COMPARE_PATH, request);
}
export function compareDispatch(request) {
    return post(DISPATCH_COMPARE_PATH, request);
}
export async function getMetricsText() {
    const response = await fetch(`${API_BASE}${METRICS_PATH}`, {
        headers: { Accept: 'text/plain' },
    });
    const body = await response.text();
    if (!response.ok)
        throw new Error(`Metrics request failed with HTTP ${response.status}.`);
    return body;
}
