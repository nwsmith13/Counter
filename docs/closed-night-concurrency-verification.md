# Closed-night concurrency verification

Run this acceptance check only in a disposable Supabase project populated with
non-production test identities and sessions. Do not use a real business night.

The automated repository tests verify migration shape, lifecycle restrictions,
UI read-only routing, and error classification. They do not execute concurrent
PostgreSQL connections. A true database acceptance check must use two sessions:

1. Apply migrations through `202609220004_closed_night_immutability.sql` to the
   disposable project and run `verify-production-readiness.sql`.
2. Create an open test night and suitable ACTIVE, AWAITING_CLOSE, COMPLETED, and
   VOIDED sessions through the normal RPCs.
3. In connection A, begin a transaction and acquire the target business-night
   row `FOR UPDATE`. In connection B, invoke each session mutation. Confirm it
   waits. Close and commit in A; confirm B returns SQLSTATE `BSB03` and no row or
   activity event changes.
4. Reverse the order: hold a session/assignment mutation before commit, invoke
   Close Night in B, and confirm Close Night waits. Commit the mutation; confirm
   Close Night then observes the committed state and either closes or reports
   the correct unresolved-session blocker.
5. Repeat for Edit, Add Lane, Move Lane, Release Lane, Start Billing Now, End,
   Payment Complete, Reopen, Void, and Reinstate.
6. After close, directly attempt inserts, updates, and deletes on
   `open_play_sessions` and `open_play_lane_assignments`. Confirm `BSB03` and no
   changes. Confirm a VOIDED session cannot be reopened or reinstated.
7. Fetch Last Night before and after every rejected operation and compare the
   session, assignment, activity, and closeout payloads byte-for-byte.

Also confirm organization-level lane conditions, settings, leagues, employees,
and devices remain editable according to their existing roles; they are
intentionally outside the historical-night barrier.
