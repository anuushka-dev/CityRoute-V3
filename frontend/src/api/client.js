// The SPA and the API share one origin in the deployed image, so API_BASE is
// empty there. The Vite dev server proxies /api/* to the backend and strips the
// prefix, so development sets it to /api (see vite.config.js).
export const API_BASE = import.meta.env.VITE_API_PREFIX ?? '';
const JSON_CONTENT_TYPE = 'application/json';
const DEFAULT_ERROR_MESSAGE = 'The CityRoute API request failed.';
export class ApiRequestError extends Error {
    status;
    path;
    detail;
    constructor(status, path, detail) {
        super(extractErrorMessage(detail));
        this.name = 'ApiRequestError';
        this.status = status;
        this.path = path;
        this.detail = detail;
    }
}
function isRecord(value) {
    return typeof value === 'object' && value !== null;
}
function extractErrorMessage(detail) {
    if (typeof detail === 'string' && detail.trim())
        return detail;
    if (!isRecord(detail))
        return DEFAULT_ERROR_MESSAGE;
    for (const key of ['message', 'error', 'detail']) {
        const value = detail[key];
        if (typeof value === 'string' && value.trim())
            return value;
    }
    return DEFAULT_ERROR_MESSAGE;
}
async function parseResponseBody(response) {
    const contentType = response.headers.get('content-type') ?? '';
    if (contentType.includes(JSON_CONTENT_TYPE))
        return response.json();
    return response.text();
}
async function request(path, init) {
    let response;
    try {
        response = await fetch(`${API_BASE}${path}`, {
            ...init,
            headers: {
                Accept: JSON_CONTENT_TYPE,
                ...(init?.body ? { 'Content-Type': JSON_CONTENT_TYPE } : {}),
                ...init?.headers,
            },
        });
    }
    catch (error) {
        throw new ApiRequestError(0, path, error instanceof Error ? error.message : error);
    }
    const body = await parseResponseBody(response);
    if (!response.ok)
        throw new ApiRequestError(response.status, path, body);
    return body;
}
export function get(path) {
    return request(path);
}
export function post(path, payload) {
    return request(path, {
        method: 'POST',
        body: JSON.stringify(payload),
    });
}
