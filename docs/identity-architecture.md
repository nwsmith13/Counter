# Blue Springs Bowl shared identity foundation

## Boundary

Identity is a separate application layer. Open Play's reducer, pricing, lanes, sessions, reports, Night lifecycle, and `bsb-counter:v1` localStorage payload are unchanged. Future modules consume `useActiveEmployee()` and attach `employee.id` as `performed_by_user_id` when their shared-data mutations are introduced.

## Data and security

- `organizations` provides the reusable tenant/location boundary.
- `employees` contains public identity fields plus a bcrypt verifier in `pin_hash`. The verifier is never returned by an RPC.
- `authorized_devices` represents “is this a house terminal?” separately from employee PIN authentication.
- `employee_terminal_sessions` stores only SHA-256 hashes of opaque 256-bit session tokens. Sessions expire after 12 hours and are revoked when an employee is deactivated.
- All tables have RLS enabled with no direct browser table grants. The anon client can execute only the narrow identity, enrollment, and Open Play `SECURITY DEFINER` RPCs granted by the ordered migrations. Each function fixes its `search_path`, checks a device or employee session where required, and scopes rows to one organization.
- PINs are four digits and hashed with PostgreSQL `pgcrypto` bcrypt (`crypt`/`gen_salt('bf',10)`). Verification happens inside PostgreSQL. Invalid attempts receive a uniform error and a small delay. Production hardening should add gateway rate limiting and a failed-attempt audit table before broader rollout.

## Device authorization

Each terminal receives a random device token once during OWNER-managed enrollment; the database stores only its SHA-256 hash. The browser stores the credential as `bsb-identity:device:v1`. Device credentials are never build-time environment values and are not provisioned through DevTools. Revoke a lost terminal through OWNER → Devices; a deactivated device must be re-enrolled from a different authorized OWNER terminal.

## Terminal session and offline behavior

After a valid PIN, the browser caches the public employee identity, opaque token, and 12-hour expiry in `bsb-identity:session:v1`. Refresh/PWA navigation therefore retains identity. In shared mode, a temporary outage preserves only the last confirmed read-only board; authoritative mutations remain disabled while offline. Fresh login, employee switching, and employee management require Supabase. Lock and Switch User clear the cached employee session immediately.

## Deployment

Follow `docs/production-rollout.md`. Production requires explicit shared mode, the project URL, and a browser-safe publishable/anon key. Apply only migrations proven missing, verify with the read-only production readiness SQL, and provision every additional terminal through OWNER → Devices.
