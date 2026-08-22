# GitHub Copilot instructions

## Project

- This is a small German-language, multi-tenant web application for writing
  and consolidating fire-service incident reports.
- Keep the implementation minimal. Prefer Node.js built-ins and browser APIs;
  do not add dependencies when the platform already provides the feature.
- Runtime: Node.js 22.5 or newer.
- Backend: `server.js` using `node:http` and `node:sqlite`.
- Frontend: dependency-free HTML, CSS, and JavaScript in
  `public/index.html`.
- Data is stored in SQLite at `data/app.db`; tests use an in-memory database.

## Domain and authorization

- An organization (`organization`) is a tenant and contains multiple units.
- `wehrleitung` can access all incidents and reports in its organization and
  writes the consolidated report.
- `einheitsleitung` can access and edit draft reports for its own unit and
  release them to the organization leadership.
- `fuehrungskraft` can write reports and only access reports authored by that
  user.
- Every database query involving tenant data must be scoped by
  `organization_id`. Unit-bound users must additionally be restricted to
  their own `unit_id`.
- Released reports are immutable.

## DIVERA 24/7

- DIVERA integration is configured per unit with an access key.
- Treat DIVERA as strictly read-only. External DIVERA requests must use HTTP
  `GET` and may only retrieve alarms and vehicle information.
- Never call DIVERA endpoints that create, update, acknowledge, close, or
  delete data.
- Importing a DIVERA alarm writes only to the application's local SQLite
  database; it must never write back to DIVERA.
- Never log, return, or commit DIVERA access keys.

## Development

- Run tests with `npm test`.
- GitHub Actions runs the same command from
  `.github/workflows/test.yml`.
- Add one focused `node:test` check for non-trivial behavior, especially
  authorization, tenant isolation, and external API boundaries.
- Preserve the existing JSON error format and validate input at API
  boundaries.
