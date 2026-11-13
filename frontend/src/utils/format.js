export function formatDistance(meters) {
    if (meters === null || meters === undefined || !Number.isFinite(meters))
        return '—';
    if (Math.abs(meters) >= 1000)
        return `${(meters / 1000).toFixed(2)} km`;
    return `${meters.toFixed(0)} m`;
}
export function formatMilliseconds(value) {
    if (value === null || value === undefined || !Number.isFinite(value))
        return '—';
    return `${value.toFixed(value < 10 ? 2 : 0)} ms`;
}
export function formatSeconds(value) {
    if (value === null || value === undefined || !Number.isFinite(value))
        return '—';
    if (value < 60)
        return `${value.toFixed(0)} s`;
    const minutes = Math.floor(value / 60);
    const seconds = Math.round(value % 60);
    return `${minutes}m ${seconds}s`;
}
export function formatNumber(value, digits = 0) {
    if (value === null || value === undefined || !Number.isFinite(value))
        return '—';
    return new Intl.NumberFormat('en-IN', { maximumFractionDigits: digits }).format(value);
}
export function formatPct(value, digits = 1) {
    if (value === null || value === undefined || !Number.isFinite(value))
        return '—';
    return `${value.toFixed(digits)}%`;
}
export function formatBytesMb(value) {
    if (value === null || value === undefined || !Number.isFinite(value))
        return '—';
    return `${value.toFixed(1)} MB`;
}
export function formatBool(value) {
    if (value === null || value === undefined)
        return '—';
    return value ? 'true' : 'false';
}
