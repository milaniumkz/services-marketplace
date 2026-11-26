# Subscription acquisition dashboard

Read-only extension of GET /admin/dashboard and the admin home page. Counts for the selected 7/30/90-day UTC period and all time, split by the selected countries (ALL = KZ/KG/RU/BY), refresh every five seconds with the existing dashboard refresh. No mobile build or API consumer changes required.

Paid acquisitions are deduplicated provider+transaction events from the server payment journal, purchase/renewal, production, positive cash, active evidence, fulfilled subscription source. Pending, sandbox, test, free, boost-only, unresolved, revoked/refunded subscriptions are excluded. Renewals and Top-100 subscription purchases count as acquisitions, not unique people or revenue; currency amounts are not summed.

Rewarded acquisitions count actual non-test subscription periods issued by rewarded_ads/yandex_web_ads. Incomplete ad sessions/individual watched videos are not acquisitions. Referral/admin/free gifts are excluded. Expired periods remain in historical acquisition totals; revoked/refunded periods are excluded. A scheduled paid/rewarded renewal counts on issuance. Historical active-subscription metric now excludes explicit test/sandbox rows too.

Tests: isolated subscription-dashboard, operations-overview, admin-country-overview; admin browser dashboard controls/period selection. No live charge/refund/config mutation or customer notification is performed. Deployment preserves bank settings and payment/reward controls.
