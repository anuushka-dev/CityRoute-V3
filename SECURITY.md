# Security Policy

## Supported versions

| Version | Supported |
| --- | --- |
| `main` | Yes, it is the maintained line |
| older tags | No |

## Reporting a vulnerability

Please do not open a public issue for a security problem. Report it privately, either through
GitHub's **Report a vulnerability** button on the Security tab, or by email to
**anuushka27@gmail.com**.

Include what you can:

- the affected endpoint, file or configuration
- the version or commit you tested
- steps to reproduce, and the impact you believe it has
- any proof-of-concept request, log or trace

You can expect an acknowledgement within a few days and an assessment with a fix plan after
the report has been reproduced. Please give me a chance to ship a fix before disclosing the
issue publicly.

## What this service does and does not handle

- **No authentication, no accounts, no personal data.** CityRoute is a routing and
  optimisation API over a public OpenStreetMap road network extract. It stores no user data
  and has no login surface, so there are no sessions or credentials to protect server-side.
- **Coordinates are the only request input** (plus ids you supply). They are validated
  against the loaded graph's bounding box before use.
- **Redis is optional and holds only derived cache entries** — matrix and dispatch results
  keyed by their inputs. Caching fails open, so an unreachable Redis never blocks a request.
- **The shipped graph is public data** extracted from OpenStreetMap (© OpenStreetMap
  contributors, ODbL). Nothing proprietary is embedded in it.

## Secrets

This repository contains **no secrets**. The committed `.env.example` lists variable names
with safe defaults; a local `.env` is git-ignored and never committed. If you deploy this
service, keep `RENDER_DEPLOY_HOOK_URL` and any Redis URL with credentials in your host's
secret store, not in the repository.

Beyond that, the deployment surface is small: one FastAPI process serving the API and the
static SPA, one optional Redis instance, and no outbound calls in a request path.

## Dependency and code scanning

The repository runs CodeQL analysis for Python and JavaScript on every pull request and
weekly, and Dependabot keeps pip, npm and GitHub Actions dependencies current. Reports for
pip, npm and Actions arrive as pull requests that CI then verifies with the full test suite
and a container smoke test.
