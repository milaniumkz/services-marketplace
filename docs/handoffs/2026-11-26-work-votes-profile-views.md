# Work-based reactions and profile views

PUT /listing-votes/{orders|services}/{id} requires a completed order in the same country whose customer and executor are exactly the voter and target owner, in either direction. Chat, pending/cancelled work and subscription alone do not qualify. Rejection: HTTP 403 COMPLETED_WORK_REQUIRED. Votes remain one editable +/-1 per voter/card; DELETE allows withdrawal without subscription or current eligibility. Votes do not delete accounts or profiles. Ranking excludes historical votes lacking this relationship, inactive/deleted users, self and staff votes. Top responses include can_vote so clients disable unavailable controls.

Authenticated GET /contractors/{id} records one unique registered visitor per profile, all time. Catalog loads, self, staff, rejected/blocked visits and repeat opens do not increment. No IP or device fingerprint is stored. Presentation and owner's /me/overview contractor metadata expose aggregate profile_views. Private visit rows belong to the visitor, are included only in their own data export and removed when either account is erased. Profile editing versions are unaffected. Counts start at deployment; historical views are not fabricated.

Mobile/web UI shows an eye and count on the provider's profile. Native sources are updated; no APK is built. Older clients immediately get server-side voting enforcement; the new counter and disabled-button UI require the next native release.

Validation:
- npm run build --workspace @marketplace/api
- node --test services/api/test/work-votes-and-profile-views.test.cjs services/api/test/top-listings.test.cjs services/api/test/immediate-account-deletion.test.cjs
- npm run mobile:analyze
- env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy bash scripts/flutter-mobile.sh test --no-pub --reporter expanded test/top_listings_test.dart test/profile_views_test.dart test/contractor_profile_test.dart

Isolated API checks cover pending, cancelled, other-country and unrelated work; valid/reversed counterparties; repeat/change/withdraw vote; old stranger votes; blocked/self/staff/repeated views; owner counter; export privacy and erasure. No real users, payments or production votes are used in tests. Deployment preserves bank configuration and existing payment switches.
