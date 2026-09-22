# Open Play Book production rollout

This runbook is for Matthew to roll out `https://open.bluespringsbowl.com` safely. Do not paste PINs, device tokens, employee session tokens, enrollment codes, or Supabase service-role keys into source control, Vercel, screenshots, chat, or support messages.

## A. Before deployment

- [ ] Confirm you are working from the intended source folder and review every changed file.
- [ ] Confirm no `.env.local`, `.vercel`, database dump, token, PIN, or enrollment code is staged for commit.
- [ ] Record the current production Vercel deployment so it can be restored quickly.
- [ ] In Supabase, create/confirm a recent project backup before applying any missing migration.
- [ ] Run `npm ci` if dependencies need a clean install.
- [ ] Run `npm test`.
- [ ] Run `npm run lint`.
- [ ] Run `npm run build`.
- [ ] Review migration history in the Supabase Dashboard before running SQL. Do not infer applied migrations merely from files in this repository.
- [ ] Run `supabase/verify-production-readiness.sql` in the BSB Operations SQL Editor. It is read-only. Save the PASS/FAIL output without copying credentials or private row data.

Stop if any verification row is `FAIL`. Determine which migration or permission is missing before continuing.

## B. SQL deployment

The repository migration order is:

1. `202609210001_bsb_identity_foundation.sql`
2. `202609210002_open_play_shared_foundation.sql`
3. `202609210003_open_play_money_validation_fix.sql`
4. `202609210004_open_play_business_night_same_day_fix.sql`
5. `202609210005_device_enrollment.sql`
6. `202609210006_open_play_authoritative_audit.sql`
7. `202609210007_open_play_payment_and_void.sql`
8. `202609210008_open_play_session_milestone_snapshot.sql`

These files are ordered dependencies, not a list to rerun blindly. In the Supabase Dashboard, compare production migration history and database objects with this list and the verification report. Apply only migrations proven missing, in order, using the normal Supabase migration process. If history and actual objects disagree, stop and reconcile them before applying anything.

After applying a missing migration, rerun `supabase/verify-production-readiness.sql`. Continue only when every row is `PASS`. Never run `supabase/bootstrap.sql` in production; initial identity bootstrapping is retired and additional devices use the in-app enrollment flow.

## C. Vercel production environment

Set these for the **Production** environment of the Open Play Book Vercel project:

- [ ] `VITE_OPEN_PLAY_SHARED` = `true`
- [ ] `VITE_SUPABASE_URL` = the BSB Operations Supabase project HTTPS URL
- [ ] `VITE_SUPABASE_ANON_KEY` = the browser-safe Supabase publishable/anon key

Do not add a service-role key or any device/session credential. All `VITE_` values are public in the browser bundle. A terminal receives its own device credential only through OWNER → Devices.

Verify the Vercel project uses this repository root, `npm run build`, and `dist` as the output directory. The production domain must remain `open.bluespringsbowl.com`.

## D. Deploy the application

- [ ] Create a Vercel preview from the exact commit intended for production.
- [ ] Confirm the preview build completed successfully.
- [ ] Check the browser title is **Blue Springs Bowl — Open Play Book**.
- [ ] Confirm the footer and sign-in/setup screens show **Open Play Book v1.0.0** where applicable.
- [ ] Confirm an unprovisioned preview shows device setup, not a local empty board.
- [ ] Promote the verified preview deployment to production using the Vercel Dashboard or the established project workflow. Promotion keeps the tested artifact unchanged.
- [ ] Do not change Supabase settings or data as part of the frontend promotion.

## E. Existing Development PC smoke test

- [ ] Open production on the existing Development PC without clearing browser data.
- [ ] Confirm its device remains authorized and the employee selection screen loads.
- [ ] Sign in and confirm the current authoritative board appears.
- [ ] Confirm `CONNECTED` behavior: no configuration, reconnecting, or offline warning remains.
- [ ] Open Tonight and Last Night and confirm existing data is intact.
- [ ] Make one low-risk, reversible operational change only if business conditions permit, and confirm another signed-in browser sees it.

## F. First Front Counter Tablet enrollment

- [ ] On an existing authorized OWNER terminal, sign in as OWNER.
- [ ] Open **Devices**, enter a friendly unique name such as `Front Counter Tablet`, and choose **Authorize New Device**.
- [ ] Keep the one-time code private. It expires after 15 minutes and can be redeemed once.
- [ ] On the new tablet, open `https://open.bluespringsbowl.com`.
- [ ] Confirm **SET UP THIS DEVICE** appears.
- [ ] Enter the one-time code on the tablet.
- [ ] Confirm the app advances to **WHO'S WORKING?**. The device token must not be displayed.
- [ ] Choose an employee and sign in with that employee's PIN.
- [ ] Confirm the authoritative current board loads before any mutation control is usable.
- [ ] Do not use DevTools or manually copy a localStorage device token.

The Development PC remains a separate authorized device and is not altered by enrolling the tablet. Deactivated credentials cannot reactivate themselves; a different authorized OWNER terminal must issue a new enrollment code.

## G. Two-terminal synchronization test

- [ ] Keep the Development PC and Front Counter Tablet signed in side by side.
- [ ] Start a clearly identified test Open Bowling session on an available lane.
- [ ] Within the normal polling interval, confirm the other terminal shows the same session.
- [ ] Add or move a lane and confirm the other terminal receives the authoritative result.
- [ ] Release the added/moved lane and verify both terminals agree.
- [ ] Confirm grace, minimum, elapsed time, bowler count, and shoe count remain correct.
- [ ] Do not perform the same mutation simultaneously from both terminals.

## H. Offline/recovery smoke test

- [ ] Disconnect only the Front Counter Tablet from the network.
- [ ] Confirm the last board remains readable and timers continue visually.
- [ ] Confirm **Reconnecting…** appears first, followed by **OFFLINE — VIEW ONLY** after repeated failures.
- [ ] Attempt one safe mutation and confirm it is rejected with a connection explanation and does not alter the board.
- [ ] Make a test change on the connected Development PC.
- [ ] Restore tablet connectivity.
- [ ] Confirm the tablet fetches and displays the server's authoritative change before mutations become available.
- [ ] Confirm the rejected offline action was not replayed.

## I. End-of-night reporting smoke test

- [ ] End the test session and complete its payment workflow.
- [ ] Confirm Tonight shows the correct employee attribution and amount.
- [ ] As a manager/owner, void the test session using category **Training/Test** and a meaningful note identifying rollout testing.
- [ ] Confirm the test session is excluded from nightly totals but remains visible in void history.
- [ ] Test Reinstate only if intentionally validating it; if reinstated, void the test session again as **Training/Test** before acceptance ends.
- [ ] Confirm Last Night still opens and existing reports remain readable.
- [ ] Do not close a real open night solely for rollout testing.

## J. If something fails

- [ ] Stop making operational changes from the affected terminal.
- [ ] Preserve the displayed error and note the time, employee, device name, and action—never credentials.
- [ ] Check whether the other terminal has authoritative current state.
- [ ] Check the production Vercel deployment status and environment variable names.
- [ ] Run the read-only production verification SQL if a database mismatch is suspected.
- [ ] Use the matching recovery procedure below. Do not clear browser storage as a generic troubleshooting step.

## Rollback and recovery

### 1. Bad frontend deployment

Use Vercel's rollback/instant rollback to restore the last known-good production deployment. Confirm the production alias points to that deployment, then smoke-test the Development PC. A frontend rollback does not roll back database migrations.

### 2. Failed migration before app deployment

Do not deploy the new frontend. Record the SQL error and current migration state. If the migration was transactional and rolled back, diagnose it in a non-production environment. If it partially changed production, stop and use the Supabase backup plus a reviewed forward repair; do not improvise destructive rollback SQL.

### 3. App deployed but a migration is missing

The app should fail closed or report an RPC/configuration error. Roll back the frontend to the prior deployment first. Verify migration history, apply only the proven missing migration in order, rerun the readiness verifier, then redeploy/promote the tested frontend.

### 4. Supabase temporarily unavailable

Leave terminals open on the cached read-only board. Do not record lane moves, payments, starts, or ends in the app until authoritative connectivity returns. The app does not queue or replay changes. After recovery, confirm the server board refreshes before resuming work.

### 5. Front Counter Tablet lost or replaced

From another authorized OWNER terminal, deactivate the lost device. This also revokes its sessions. Enroll the replacement as a new device with a new friendly name and one-time code. Do not reuse or transfer the old browser storage.

### 6. Device accidentally deactivated

A deactivated device cannot recover itself. On a different authorized OWNER terminal, create a new enrollment code and re-enroll the device. Its old credential remains inactive.

### 7. Employee PIN forgotten

An OWNER opens Employees, edits the employee, and assigns a new four-digit PIN. Do not recover, display, or share the old PIN. Confirm the employee can sign in, then lock the OWNER session.

### 8. Owner session expired

Return through **WHO'S WORKING?** and sign in again with the OWNER PIN. Session expiration is an identity event, not an offline event. If the device is unauthorized, use a different OWNER terminal to re-enroll it.

### 9. Production environment variable misconfigured

Correct the three production variables in Vercel, then create a new preview/build because Vite embeds them at build time. Validate the preview and promote it. Never substitute a service-role key. A configuration failure must remain fail-closed rather than switching to local mode.

### 10. Shared state looks wrong on one terminal

Compare with a second connected terminal and wait for an authoritative refresh. Reload the affected app if needed. Check its connection and identity messages. Do not clear storage casually: clearing site data removes `bsb-identity:device:v1` and requires OWNER re-enrollment. If state is wrong on every terminal, stop mutations and investigate Supabase/server state rather than editing local storage.

## First-terminal acceptance checklist

- [ ] Load `https://open.bluespringsbowl.com`.
- [ ] Confirm **SET UP THIS DEVICE**.
- [ ] Authorize `Front Counter Tablet` from an existing OWNER terminal.
- [ ] Redeem the one-time code on the tablet.
- [ ] Confirm **WHO'S WORKING?**.
- [ ] Sign in with an appropriate employee PIN.
- [ ] Confirm current night and shared state match the Development PC.
- [ ] Start a clearly named test Open Bowling session.
- [ ] Confirm the second terminal sees it.
- [ ] Move/add/release a lane and confirm both terminals agree.
- [ ] Verify grace period, minimum charge, and elapsed timing.
- [ ] End the session and complete **Payment Complete**.
- [ ] Verify Tonight activity and employee/device attribution.
- [ ] Void the test session as **Training/Test** with a meaningful rollout note.
- [ ] Confirm it disappears from nightly totals.
- [ ] Reinstate only if intentionally testing Reinstate; void it again afterward.
- [ ] Verify cached offline view-only behavior.
- [ ] Reconnect and confirm authoritative catch-up before writes resume.
- [ ] Close and relaunch the browser/app; confirm device authorization persists.
- [ ] If using the installed experience, install/open the PWA and confirm standalone operation.
- [ ] Confirm the test session finishes in **VOIDED / Training/Test** so reporting is not contaminated.

## PWA notes

The manifest and icons use root-relative production paths and identify the app as **Blue Springs Bowl — Open Play Book**. There is currently no application service worker, so no custom worker can trap a tablet on an obsolete JavaScript build. Vercel's hashed assets allow new deployments to load new bundles on refresh/relaunch. Browser storage retains the authorized-device credential in standalone mode; it is not part of an offline mutation mechanism.
