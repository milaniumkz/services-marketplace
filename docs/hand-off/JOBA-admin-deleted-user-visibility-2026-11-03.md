# Deleted account visibility in admin

Published API source: `d03e821968d4038ad9e91173e679fb8c7ff5e8e3`.
Deployment: https://github.com/milaniumkz/services-marketplace/actions/runs/41621138227 (success).

Admin GET requests now read records through `admin_visible_records`, scoped by AsyncLocalStorage. The view excludes deleted users and follows ownership and record references to remove their related document checks, portfolio, services, orders, chat records, subscriptions and other dependent records from directories, search, details and dashboard aggregates. Filtering happens before pagination and aggregate counts. Blocked accounts remain visible. UUID identity prevents a newly registered account reusing a deleted phone from inheriting its visibility state.

The view materializes reference edges once per query and traverses them using a recursive equality join with UNION deduplication. A first implementation using a recursive disjunctive join was too slow on production reads and was replaced immediately. A 24,000-record isolated benchmark returned the expected 11,901 visible verification records in 281 ms.

Base records remain available to existing private retention/cleanup jobs, and writes continue to use base tables. Read context does not leak to concurrent ordinary requests. This changes operational admin visibility, not retention policy or other participants' stored data.

Validation: `npm run verify` passed all 200 tests; the focused deleted-account integration test passed against the final migration. Production read-only verification checked users, document checks, portfolio, services, orders, support, cases, related user profiles and dashboard availability. Native free mobile access remained enabled. Existing web assets were preserved; no APK/AAB build was made.
