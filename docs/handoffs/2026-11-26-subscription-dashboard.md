# Subscription acquisition dashboard

Read-only extension of GET /admin/dashboard and the admin home page. Counts for the selected 7/30/90-day UTC period and all time, split by the selected countries (ALL = KZ/KG/RU/BY), refresh every five seconds with the existing dashboard refresh. No mobile build or API consumer changes required.

Paid acquisitions are deduplicated provider+transaction events from the server payment journal, purchase/renewal, production, positive cash, active evidence, fulfilled subscription source. Pending, sandbox, test, free, boost-only, unresolved, revoked/refunded subscriptions are excluded. Renewals and Top-100 subscription purchases count as acquisitions, not unique people or revenue; currency amounts are not summed.

Rewarded acquisitions count actual non-test subscription periods issued by rewarded_ads/yandex_web_ads. Incomplete ad sessions/individual watched videos are not acquisitions. Referral/admin/free gifts are excluded. Expired periods remain in historical acquisition totals; revoked/refunded periods are excluded. A scheduled paid/rewarded renewal counts on issuance. Historical active-subscription metric now excludes explicit test/sandbox rows too.

Tests: isolated subscription-dashboard, operations-overview, admin-country-overview; admin browser dashboard controls/period selection. No live charge/refund/config mutation or customer notification is performed. Deployment preserves bank settings and payment/reward controls.

## Separate Top-100 acquisition breakdown

The existing overall API totals are preserved for compatibility. `breakdown.subscriptions` and `breakdown.top100` each contain period/all_time/by_country with the same schema. Classification follows subscription periodPlan: price_snapshot.plan, then plan, then standard. Only plan=top100 counts as a separately purchased add-on; Premium remains a base subscription and does not create a second counted acquisition. The admin now displays two distinct groups, each with rewarded/paid counters and its country table. Both refresh together. Isolated tests verify snapshot precedence, paid event deduplication, historical Top-100, sandbox exclusion, country scope, Premium classification and reconciliation to the original total. Browser checks assert both groups and period selection.

## Visible period controls

The 7/30/90-day selector is repeated immediately above the subscription and Top-100 groups, with the exact UTC start/end dates. Metric captions explicitly name the selected number of days. Both selectors share the existing dashboard period/query; the main selector now precedes the owner's tall server-resource panel. The local selector sits outside refreshed metric HTML so polling does not replace an open selector; the date range refreshes with the data. Isolated browser test at 390px verifies the control fits the phone viewport, changes to 90 days, synchronizes the main selector, updates captions and switches back to 30 days. Admin production build passes.
