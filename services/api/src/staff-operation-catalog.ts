// Explicit reviewable API operation catalogue. No wildcards may be assigned.
export const staffOperations=[
  {id:'POST /admin/users/{id}/block',method:'POST',path:'/admin/users/{id}/block',block:'users',label:'Блокировать аккаунт'},
  {id:'POST /admin/users/{id}/unblock',method:'POST',path:'/admin/users/{id}/unblock',block:'users',label:'Разблокировать аккаунт'},
  {id:'POST /admin/users/{id}/delete',method:'POST',path:'/admin/users/{id}/delete',block:'users',label:'Удалять аккаунт'},

  {id:'GET /admin/subscription-plans',method:'GET',path:'/admin/subscription-plans',block:'price-versions',label:'Просмотр цен Стандарта и Премиума'},
  {id:'POST /admin/subscription-plans',method:'POST',path:'/admin/subscription-plans',block:'price-versions',label:'Изменять цены Стандарта и Премиума'},
  {
    "id": "GET /admin/category-tree",
    "method": "GET",
    "path": "/admin/category-tree",
    "block": "category-tree"
  },
  {
    "id": "GET /admin/categories/{id}",
    "method": "GET",
    "path": "/admin/categories/{id}",
    "block": "categories"
  },
  {
    "id": "PATCH /admin/categories/{id}",
    "method": "PATCH",
    "path": "/admin/categories/{id}",
    "block": "categories"
  },
  {
    "id": "GET /admin/referral-campaigns/{id}",
    "method": "GET",
    "path": "/admin/referral-campaigns/{id}",
    "block": "referral-campaigns"
  },
  {
    "id": "PATCH /admin/referral-campaigns/{id}",
    "method": "PATCH",
    "path": "/admin/referral-campaigns/{id}",
    "block": "referral-campaigns"
  },
  {
    "id": "GET /admin/ranking-configs/{id}",
    "method": "GET",
    "path": "/admin/ranking-configs/{id}",
    "block": "ranking-configs"
  },
  {
    "id": "PATCH /admin/ranking-configs/{id}",
    "method": "PATCH",
    "path": "/admin/ranking-configs/{id}",
    "block": "ranking-configs"
  },
  {
    "id": "GET /admin/placement-policies/{id}",
    "method": "GET",
    "path": "/admin/placement-policies/{id}",
    "block": "placement-policies"
  },
  {
    "id": "PATCH /admin/placement-policies/{id}",
    "method": "PATCH",
    "path": "/admin/placement-policies/{id}",
    "block": "placement-policies"
  },
  {
    "id": "GET /admin/analytics",
    "method": "GET",
    "path": "/admin/analytics",
    "block": "analytics"
  },
  {
    "id": "POST /admin/boost-grants/preview",
    "method": "POST",
    "path": "/admin/boost-grants/preview",
    "block": "boost-grants"
  },
  {
    "id": "GET /admin/country-capabilities",
    "method": "GET",
    "path": "/admin/country-capabilities",
    "block": "country-capabilities"
  },
  {
    "id": "GET /admin/search",
    "method": "GET",
    "path": "/admin/search",
    "block": "search"
  },
  {
    "id": "POST /admin/jobs/{id}/retry",
    "method": "POST",
    "path": "/admin/jobs/{id}/retry",
    "block": "jobs"
  },
  {
    "id": "GET /admin/security-events",
    "method": "GET",
    "path": "/admin/security-events",
    "block": "security-events"
  },
  {
    "id": "GET /admin/jobs",
    "method": "GET",
    "path": "/admin/jobs",
    "block": "jobs"
  },
  {
    "id": "GET /admin/jobs/{id}",
    "method": "GET",
    "path": "/admin/jobs/{id}",
    "block": "jobs"
  },
  {
    "id": "GET /admin/cases/{id}",
    "method": "GET",
    "path": "/admin/cases/{id}",
    "block": "cases"
  },
  {
    "id": "GET /admin/cases/{id}/messages",
    "method": "GET",
    "path": "/admin/cases/{id}/messages",
    "block": "cases"
  },
  {
    "id": "POST /admin/cases/{id}/messages",
    "method": "POST",
    "path": "/admin/cases/{id}/messages",
    "block": "cases"
  },
  {
    "id": "GET /admin/monetization-summary",
    "method": "GET",
    "path": "/admin/monetization-summary",
    "block": "monetization-summary"
  },
  {
    "id": "GET /admin/contractors",
    "method": "GET",
    "path": "/admin/contractors",
    "block": "contractors"
  },
  {
    "id": "GET /admin/legal/documents",
    "method": "GET",
    "path": "/admin/legal/documents",
    "block": "legal"
  },
  {
    "id": "POST /admin/legal/documents",
    "method": "POST",
    "path": "/admin/legal/documents",
    "block": "legal"
  },
  {
    "id": "GET /admin/orders/{id}",
    "method": "GET",
    "path": "/admin/orders/{id}",
    "block": "orders"
  },
  {
    "id": "GET /admin/portfolio/{id}",
    "method": "GET",
    "path": "/admin/portfolio/{id}",
    "block": "portfolio"
  },
  {
    "id": "GET /admin/contractors/{id}",
    "method": "GET",
    "path": "/admin/contractors/{id}",
    "block": "contractors"
  },
  {
    "id": "GET /admin/support-threads/{id}",
    "method": "GET",
    "path": "/admin/support-threads/{id}",
    "block": "support-threads"
  },
  {
    "id": "GET /admin/recovery-threads/{id}",
    "method": "GET",
    "path": "/admin/recovery-threads/{id}",
    "block": "recovery-threads"
  },
  {
    "id": "GET /admin/verifications/{id}",
    "method": "GET",
    "path": "/admin/verifications/{id}",
    "block": "verifications"
  },
  {
    "id": "GET /admin/privacy-requests/{id}",
    "method": "GET",
    "path": "/admin/privacy-requests/{id}",
    "block": "privacy-requests"
  },
  {
    "id": "GET /admin/dashboard",
    "method": "GET",
    "path": "/admin/dashboard",
    "block": "dashboard"
  },
  {
    "id": "GET /admin/users",
    "method": "GET",
    "path": "/admin/users",
    "block": "users"
  },
  {
    "id": "GET /admin/users/{id}",
    "method": "GET",
    "path": "/admin/users/{id}",
    "block": "users"
  },
  {
    "id": "GET /admin/users/{id}/security-events",
    "method": "GET",
    "path": "/admin/users/{id}/security-events",
    "block": "users"
  },
  {
    "id": "GET /admin/orders",
    "method": "GET",
    "path": "/admin/orders",
    "block": "orders"
  },
  {
    "id": "GET /admin/support-threads",
    "method": "GET",
    "path": "/admin/support-threads",
    "block": "support-threads"
  },
  {
    "id": "GET /admin/recovery-threads",
    "method": "GET",
    "path": "/admin/recovery-threads",
    "block": "recovery-threads"
  },
  {
    "id": "GET /admin/cases",
    "method": "GET",
    "path": "/admin/cases",
    "block": "cases"
  },
  {
    "id": "GET /admin/audit",
    "method": "GET",
    "path": "/admin/audit",
    "block": "audit"
  },
  {
    "id": "GET /admin/blacklist",
    "method": "GET",
    "path": "/admin/blacklist",
    "block": "blacklist"
  },
  {
    "id": "GET /admin/portfolio",
    "method": "GET",
    "path": "/admin/portfolio",
    "block": "portfolio"
  },
  {
    "id": "GET /admin/verifications",
    "method": "GET",
    "path": "/admin/verifications",
    "block": "verifications"
  },
  {
    "id": "GET /admin/privacy-requests",
    "method": "GET",
    "path": "/admin/privacy-requests",
    "block": "privacy-requests"
  },
  {
    "id": "GET /admin/runtime-settings",
    "method": "GET",
    "path": "/admin/runtime-settings",
    "block": "runtime-settings"
  },
  {
    "id": "POST /admin/runtime-settings",
    "method": "POST",
    "path": "/admin/runtime-settings",
    "block": "runtime-settings"
  },
  {
    "id": "GET /admin/boost-reports",
    "method": "GET",
    "path": "/admin/boost-reports",
    "block": "boost-reports"
  },
  {
    "id": "POST /admin/legal/documents/{id}/publish",
    "method": "POST",
    "path": "/admin/legal/documents/{id}/publish",
    "block": "legal"
  },
  {
    "id": "POST /admin/users/{id}/blacklist",
    "method": "POST",
    "path": "/admin/users/{id}/blacklist",
    "block": "users"
  },
  {
    "id": "POST /admin/blacklist/{id}/decision",
    "method": "POST",
    "path": "/admin/blacklist/{id}/decision",
    "block": "blacklist"
  },
  {
    "id": "POST /admin/verifications/{id}/decision",
    "method": "POST",
    "path": "/admin/verifications/{id}/decision",
    "block": "verifications"
  },
  {
    "id": "POST /admin/auto-holds/{id}/decision",
    "method": "POST",
    "path": "/admin/auto-holds/{id}/decision",
    "block": "auto-holds"
  },
  {
    "id": "POST /admin/cases/{id}/resolve",
    "method": "POST",
    "path": "/admin/cases/{id}/resolve",
    "block": "cases"
  },
  {
    "id": "POST /admin/cases/{id}/appeal-decision",
    "method": "POST",
    "path": "/admin/cases/{id}/appeal-decision",
    "block": "cases"
  },
  {
    "id": "POST /admin/entitlement-grants",
    "method": "POST",
    "path": "/admin/entitlement-grants",
    "block": "entitlement-grants"
  },
  {
    "id": "POST /admin/entitlement-grants/{id}/approve",
    "method": "POST",
    "path": "/admin/entitlement-grants/{id}/approve",
    "block": "entitlement-grants"
  },
  {
    "id": "POST /admin/brand-icons",
    "method": "POST",
    "path": "/admin/brand-icons",
    "block": "brand-icons"
  },
  {
    "id": "GET /admin/brand-icons",
    "method": "GET",
    "path": "/admin/brand-icons",
    "block": "brand-icons"
  },
  {
    "id": "POST /admin/brand-icons/{id}/approve",
    "method": "POST",
    "path": "/admin/brand-icons/{id}/approve",
    "block": "brand-icons"
  },
  {
    "id": "POST /admin/brand-icons/{id}/generate",
    "method": "POST",
    "path": "/admin/brand-icons/{id}/generate",
    "block": "brand-icons"
  },
  {
    "id": "POST /admin/boost-grants",
    "method": "POST",
    "path": "/admin/boost-grants",
    "block": "boost-grants"
  },
  {
    "id": "POST /admin/portfolio/{id}/decision",
    "method": "POST",
    "path": "/admin/portfolio/{id}/decision",
    "block": "portfolio"
  },
  {
    "id": "POST /admin/contractors/{id}/decision",
    "method": "POST",
    "path": "/admin/contractors/{id}/decision",
    "block": "contractors"
  },
  {
    "id": "POST /admin/recovery-threads/{id}/assign",
    "method": "POST",
    "path": "/admin/recovery-threads/{id}/assign",
    "block": "recovery-threads"
  },
  {
    "id": "GET /admin/support-threads/{id}/messages",
    "method": "GET",
    "path": "/admin/support-threads/{id}/messages",
    "block": "support-threads"
  },
  {
    "id": "POST /admin/support-threads/{id}/messages",
    "method": "POST",
    "path": "/admin/support-threads/{id}/messages",
    "block": "support-threads"
  },
  {
    "id": "GET /admin/recovery-threads/{id}/messages",
    "method": "GET",
    "path": "/admin/recovery-threads/{id}/messages",
    "block": "recovery-threads"
  },
  {
    "id": "POST /admin/recovery-threads/{id}/messages",
    "method": "POST",
    "path": "/admin/recovery-threads/{id}/messages",
    "block": "recovery-threads"
  },
  {
    "id": "POST /admin/support-threads/{id}/commands",
    "method": "POST",
    "path": "/admin/support-threads/{id}/commands",
    "block": "support-threads"
  },
  {
    "id": "GET /admin/support-threads/{id}/internal-notes",
    "method": "GET",
    "path": "/admin/support-threads/{id}/internal-notes",
    "block": "support-threads"
  },
  {
    "id": "POST /admin/support-threads/{id}/internal-notes",
    "method": "POST",
    "path": "/admin/support-threads/{id}/internal-notes",
    "block": "support-threads"
  },
  {
    "id": "GET /admin/categories",
    "method": "GET",
    "path": "/admin/categories",
    "block": "categories"
  },
  {
    "id": "POST /admin/categories",
    "method": "POST",
    "path": "/admin/categories",
    "block": "categories"
  },
  {
    "id": "POST /admin/categories/{id}/validate",
    "method": "POST",
    "path": "/admin/categories/{id}/validate",
    "block": "categories"
  },
  {
    "id": "POST /admin/categories/{id}/preview",
    "method": "POST",
    "path": "/admin/categories/{id}/preview",
    "block": "categories"
  },
  {
    "id": "POST /admin/categories/{id}/publish",
    "method": "POST",
    "path": "/admin/categories/{id}/publish",
    "block": "categories"
  },
  {
    "id": "POST /admin/categories/{id}/stop",
    "method": "POST",
    "path": "/admin/categories/{id}/stop",
    "block": "categories"
  },
  {
    "id": "POST /admin/categories/{id}/cancel",
    "method": "POST",
    "path": "/admin/categories/{id}/cancel",
    "block": "categories"
  },
  {
    "id": "POST /admin/categories/{id}/rollback",
    "method": "POST",
    "path": "/admin/categories/{id}/rollback",
    "block": "categories"
  },
  {
    "id": "GET /admin/price-versions",
    "method": "GET",
    "path": "/admin/price-versions",
    "block": "price-versions"
  },
  {
    "id": "POST /admin/price-versions",
    "method": "POST",
    "path": "/admin/price-versions",
    "block": "price-versions"
  },
  {
    "id": "POST /admin/price-versions/{id}/validate",
    "method": "POST",
    "path": "/admin/price-versions/{id}/validate",
    "block": "price-versions"
  },
  {
    "id": "POST /admin/price-versions/{id}/preview",
    "method": "POST",
    "path": "/admin/price-versions/{id}/preview",
    "block": "price-versions"
  },
  {
    "id": "POST /admin/price-versions/{id}/publish",
    "method": "POST",
    "path": "/admin/price-versions/{id}/publish",
    "block": "price-versions"
  },
  {
    "id": "POST /admin/price-versions/{id}/stop",
    "method": "POST",
    "path": "/admin/price-versions/{id}/stop",
    "block": "price-versions"
  },
  {
    "id": "POST /admin/price-versions/{id}/cancel",
    "method": "POST",
    "path": "/admin/price-versions/{id}/cancel",
    "block": "price-versions"
  },
  {
    "id": "POST /admin/price-versions/{id}/rollback",
    "method": "POST",
    "path": "/admin/price-versions/{id}/rollback",
    "block": "price-versions"
  },
  {
    "id": "GET /admin/monetization-configs",
    "method": "GET",
    "path": "/admin/monetization-configs",
    "block": "monetization-configs"
  },
  {
    "id": "POST /admin/monetization-configs",
    "method": "POST",
    "path": "/admin/monetization-configs",
    "block": "monetization-configs"
  },
  {
    "id": "POST /admin/monetization-configs/{id}/validate",
    "method": "POST",
    "path": "/admin/monetization-configs/{id}/validate",
    "block": "monetization-configs"
  },
  {
    "id": "POST /admin/monetization-configs/{id}/preview",
    "method": "POST",
    "path": "/admin/monetization-configs/{id}/preview",
    "block": "monetization-configs"
  },
  {
    "id": "POST /admin/monetization-configs/{id}/publish",
    "method": "POST",
    "path": "/admin/monetization-configs/{id}/publish",
    "block": "monetization-configs"
  },
  {
    "id": "POST /admin/monetization-configs/{id}/stop",
    "method": "POST",
    "path": "/admin/monetization-configs/{id}/stop",
    "block": "monetization-configs"
  },
  {
    "id": "POST /admin/monetization-configs/{id}/cancel",
    "method": "POST",
    "path": "/admin/monetization-configs/{id}/cancel",
    "block": "monetization-configs"
  },
  {
    "id": "POST /admin/monetization-configs/{id}/rollback",
    "method": "POST",
    "path": "/admin/monetization-configs/{id}/rollback",
    "block": "monetization-configs"
  },
  {
    "id": "GET /admin/push-campaigns",
    "method": "GET",
    "path": "/admin/push-campaigns",
    "block": "push-campaigns"
  },
  {
    "id": "POST /admin/push-campaigns",
    "method": "POST",
    "path": "/admin/push-campaigns",
    "block": "push-campaigns"
  },
  {
    "id": "POST /admin/push-campaigns/{id}/validate",
    "method": "POST",
    "path": "/admin/push-campaigns/{id}/validate",
    "block": "push-campaigns"
  },
  {
    "id": "POST /admin/push-campaigns/{id}/preview",
    "method": "POST",
    "path": "/admin/push-campaigns/{id}/preview",
    "block": "push-campaigns"
  },
  {
    "id": "POST /admin/push-campaigns/{id}/publish",
    "method": "POST",
    "path": "/admin/push-campaigns/{id}/publish",
    "block": "push-campaigns"
  },
  {
    "id": "POST /admin/push-campaigns/{id}/stop",
    "method": "POST",
    "path": "/admin/push-campaigns/{id}/stop",
    "block": "push-campaigns"
  },
  {
    "id": "POST /admin/push-campaigns/{id}/cancel",
    "method": "POST",
    "path": "/admin/push-campaigns/{id}/cancel",
    "block": "push-campaigns"
  },
  {
    "id": "POST /admin/push-campaigns/{id}/rollback",
    "method": "POST",
    "path": "/admin/push-campaigns/{id}/rollback",
    "block": "push-campaigns"
  },
  {
    "id": "GET /admin/referral-campaigns",
    "method": "GET",
    "path": "/admin/referral-campaigns",
    "block": "referral-campaigns"
  },
  {
    "id": "POST /admin/referral-campaigns",
    "method": "POST",
    "path": "/admin/referral-campaigns",
    "block": "referral-campaigns"
  },
  {
    "id": "POST /admin/referral-campaigns/{id}/validate",
    "method": "POST",
    "path": "/admin/referral-campaigns/{id}/validate",
    "block": "referral-campaigns"
  },
  {
    "id": "POST /admin/referral-campaigns/{id}/preview",
    "method": "POST",
    "path": "/admin/referral-campaigns/{id}/preview",
    "block": "referral-campaigns"
  },
  {
    "id": "POST /admin/referral-campaigns/{id}/publish",
    "method": "POST",
    "path": "/admin/referral-campaigns/{id}/publish",
    "block": "referral-campaigns"
  },
  {
    "id": "POST /admin/referral-campaigns/{id}/stop",
    "method": "POST",
    "path": "/admin/referral-campaigns/{id}/stop",
    "block": "referral-campaigns"
  },
  {
    "id": "POST /admin/referral-campaigns/{id}/cancel",
    "method": "POST",
    "path": "/admin/referral-campaigns/{id}/cancel",
    "block": "referral-campaigns"
  },
  {
    "id": "POST /admin/referral-campaigns/{id}/rollback",
    "method": "POST",
    "path": "/admin/referral-campaigns/{id}/rollback",
    "block": "referral-campaigns"
  },
  {
    "id": "GET /admin/moderation-dictionaries",
    "method": "GET",
    "path": "/admin/moderation-dictionaries",
    "block": "moderation-dictionaries"
  },
  {
    "id": "POST /admin/moderation-dictionaries",
    "method": "POST",
    "path": "/admin/moderation-dictionaries",
    "block": "moderation-dictionaries"
  },
  {
    "id": "POST /admin/moderation-dictionaries/{id}/validate",
    "method": "POST",
    "path": "/admin/moderation-dictionaries/{id}/validate",
    "block": "moderation-dictionaries"
  },
  {
    "id": "POST /admin/moderation-dictionaries/{id}/preview",
    "method": "POST",
    "path": "/admin/moderation-dictionaries/{id}/preview",
    "block": "moderation-dictionaries"
  },
  {
    "id": "POST /admin/moderation-dictionaries/{id}/publish",
    "method": "POST",
    "path": "/admin/moderation-dictionaries/{id}/publish",
    "block": "moderation-dictionaries"
  },
  {
    "id": "POST /admin/moderation-dictionaries/{id}/stop",
    "method": "POST",
    "path": "/admin/moderation-dictionaries/{id}/stop",
    "block": "moderation-dictionaries"
  },
  {
    "id": "POST /admin/moderation-dictionaries/{id}/cancel",
    "method": "POST",
    "path": "/admin/moderation-dictionaries/{id}/cancel",
    "block": "moderation-dictionaries"
  },
  {
    "id": "POST /admin/moderation-dictionaries/{id}/rollback",
    "method": "POST",
    "path": "/admin/moderation-dictionaries/{id}/rollback",
    "block": "moderation-dictionaries"
  },
  {
    "id": "GET /admin/ranking-configs",
    "method": "GET",
    "path": "/admin/ranking-configs",
    "block": "ranking-configs"
  },
  {
    "id": "POST /admin/ranking-configs",
    "method": "POST",
    "path": "/admin/ranking-configs",
    "block": "ranking-configs"
  },
  {
    "id": "POST /admin/ranking-configs/{id}/validate",
    "method": "POST",
    "path": "/admin/ranking-configs/{id}/validate",
    "block": "ranking-configs"
  },
  {
    "id": "POST /admin/ranking-configs/{id}/preview",
    "method": "POST",
    "path": "/admin/ranking-configs/{id}/preview",
    "block": "ranking-configs"
  },
  {
    "id": "POST /admin/ranking-configs/{id}/publish",
    "method": "POST",
    "path": "/admin/ranking-configs/{id}/publish",
    "block": "ranking-configs"
  },
  {
    "id": "POST /admin/ranking-configs/{id}/stop",
    "method": "POST",
    "path": "/admin/ranking-configs/{id}/stop",
    "block": "ranking-configs"
  },
  {
    "id": "POST /admin/ranking-configs/{id}/cancel",
    "method": "POST",
    "path": "/admin/ranking-configs/{id}/cancel",
    "block": "ranking-configs"
  },
  {
    "id": "POST /admin/ranking-configs/{id}/rollback",
    "method": "POST",
    "path": "/admin/ranking-configs/{id}/rollback",
    "block": "ranking-configs"
  },
  {
    "id": "GET /admin/promotions",
    "method": "GET",
    "path": "/admin/promotions",
    "block": "promotions"
  },
  {
    "id": "POST /admin/promotions",
    "method": "POST",
    "path": "/admin/promotions",
    "block": "promotions"
  },
  {
    "id": "POST /admin/promotions/{id}/validate",
    "method": "POST",
    "path": "/admin/promotions/{id}/validate",
    "block": "promotions"
  },
  {
    "id": "POST /admin/promotions/{id}/preview",
    "method": "POST",
    "path": "/admin/promotions/{id}/preview",
    "block": "promotions"
  },
  {
    "id": "POST /admin/promotions/{id}/publish",
    "method": "POST",
    "path": "/admin/promotions/{id}/publish",
    "block": "promotions"
  },
  {
    "id": "POST /admin/promotions/{id}/stop",
    "method": "POST",
    "path": "/admin/promotions/{id}/stop",
    "block": "promotions"
  },
  {
    "id": "POST /admin/promotions/{id}/cancel",
    "method": "POST",
    "path": "/admin/promotions/{id}/cancel",
    "block": "promotions"
  },
  {
    "id": "POST /admin/promotions/{id}/rollback",
    "method": "POST",
    "path": "/admin/promotions/{id}/rollback",
    "block": "promotions"
  },
  {
    "id": "GET /admin/placement-policies",
    "method": "GET",
    "path": "/admin/placement-policies",
    "block": "placement-policies"
  },
  {
    "id": "POST /admin/placement-policies",
    "method": "POST",
    "path": "/admin/placement-policies",
    "block": "placement-policies"
  },
  {
    "id": "POST /admin/placement-policies/{id}/validate",
    "method": "POST",
    "path": "/admin/placement-policies/{id}/validate",
    "block": "placement-policies"
  },
  {
    "id": "POST /admin/placement-policies/{id}/preview",
    "method": "POST",
    "path": "/admin/placement-policies/{id}/preview",
    "block": "placement-policies"
  },
  {
    "id": "POST /admin/placement-policies/{id}/publish",
    "method": "POST",
    "path": "/admin/placement-policies/{id}/publish",
    "block": "placement-policies"
  },
  {
    "id": "POST /admin/placement-policies/{id}/stop",
    "method": "POST",
    "path": "/admin/placement-policies/{id}/stop",
    "block": "placement-policies"
  },
  {
    "id": "POST /admin/placement-policies/{id}/cancel",
    "method": "POST",
    "path": "/admin/placement-policies/{id}/cancel",
    "block": "placement-policies"
  },
  {
    "id": "POST /admin/placement-policies/{id}/rollback",
    "method": "POST",
    "path": "/admin/placement-policies/{id}/rollback",
    "block": "placement-policies"
  },
  {
    "id": "GET /admin/verification-policies",
    "method": "GET",
    "path": "/admin/verification-policies",
    "block": "verification-policies"
  },
  {
    "id": "POST /admin/verification-policies",
    "method": "POST",
    "path": "/admin/verification-policies",
    "block": "verification-policies"
  },
  {
    "id": "POST /admin/verification-policies/{id}/validate",
    "method": "POST",
    "path": "/admin/verification-policies/{id}/validate",
    "block": "verification-policies"
  },
  {
    "id": "POST /admin/verification-policies/{id}/preview",
    "method": "POST",
    "path": "/admin/verification-policies/{id}/preview",
    "block": "verification-policies"
  },
  {
    "id": "POST /admin/verification-policies/{id}/publish",
    "method": "POST",
    "path": "/admin/verification-policies/{id}/publish",
    "block": "verification-policies"
  },
  {
    "id": "POST /admin/verification-policies/{id}/stop",
    "method": "POST",
    "path": "/admin/verification-policies/{id}/stop",
    "block": "verification-policies"
  },
  {
    "id": "POST /admin/verification-policies/{id}/cancel",
    "method": "POST",
    "path": "/admin/verification-policies/{id}/cancel",
    "block": "verification-policies"
  },
  {
    "id": "POST /admin/verification-policies/{id}/rollback",
    "method": "POST",
    "path": "/admin/verification-policies/{id}/rollback",
    "block": "verification-policies"
  },
  {
    "id": "GET /admin/retention-policies",
    "method": "GET",
    "path": "/admin/retention-policies",
    "block": "retention-policies"
  },
  {
    "id": "POST /admin/retention-policies",
    "method": "POST",
    "path": "/admin/retention-policies",
    "block": "retention-policies"
  },
  {
    "id": "POST /admin/retention-policies/{id}/validate",
    "method": "POST",
    "path": "/admin/retention-policies/{id}/validate",
    "block": "retention-policies"
  },
  {
    "id": "POST /admin/retention-policies/{id}/preview",
    "method": "POST",
    "path": "/admin/retention-policies/{id}/preview",
    "block": "retention-policies"
  },
  {
    "id": "POST /admin/retention-policies/{id}/publish",
    "method": "POST",
    "path": "/admin/retention-policies/{id}/publish",
    "block": "retention-policies"
  },
  {
    "id": "POST /admin/retention-policies/{id}/stop",
    "method": "POST",
    "path": "/admin/retention-policies/{id}/stop",
    "block": "retention-policies"
  },
  {
    "id": "POST /admin/retention-policies/{id}/cancel",
    "method": "POST",
    "path": "/admin/retention-policies/{id}/cancel",
    "block": "retention-policies"
  },
  {
    "id": "POST /admin/retention-policies/{id}/rollback",
    "method": "POST",
    "path": "/admin/retention-policies/{id}/rollback",
    "block": "retention-policies"
  },
  {
    "id": "GET /admin/country-controls",
    "method": "GET",
    "path": "/admin/country-controls",
    "block": "country-controls"
  },
  {
    "id": "POST /admin/country-controls",
    "method": "POST",
    "path": "/admin/country-controls",
    "block": "country-controls"
  },
  {
    "id": "POST /admin/country-controls/{id}/validate",
    "method": "POST",
    "path": "/admin/country-controls/{id}/validate",
    "block": "country-controls"
  },
  {
    "id": "POST /admin/country-controls/{id}/preview",
    "method": "POST",
    "path": "/admin/country-controls/{id}/preview",
    "block": "country-controls"
  },
  {
    "id": "POST /admin/country-controls/{id}/publish",
    "method": "POST",
    "path": "/admin/country-controls/{id}/publish",
    "block": "country-controls"
  },
  {
    "id": "POST /admin/country-controls/{id}/stop",
    "method": "POST",
    "path": "/admin/country-controls/{id}/stop",
    "block": "country-controls"
  },
  {
    "id": "POST /admin/country-controls/{id}/cancel",
    "method": "POST",
    "path": "/admin/country-controls/{id}/cancel",
    "block": "country-controls"
  },
  {
    "id": "POST /admin/country-controls/{id}/rollback",
    "method": "POST",
    "path": "/admin/country-controls/{id}/rollback",
    "block": "country-controls"
  },
  {
    "id": "GET /admin/legal-holds",
    "method": "GET",
    "path": "/admin/legal-holds",
    "block": "legal-holds"
  },
  {
    "id": "POST /admin/legal-holds",
    "method": "POST",
    "path": "/admin/legal-holds",
    "block": "legal-holds"
  },
  {
    "id": "GET /admin/languages",
    "method": "GET",
    "path": "/admin/languages",
    "block": "languages"
  },
  {
    "id": "GET /admin/revenue",
    "method": "GET",
    "path": "/admin/revenue",
    "block": "revenue"
  },
  {
    "id": "GET /admin/blacklist/{id}",
    "method": "GET",
    "path": "/admin/blacklist/{id}",
    "block": "blacklist"
  },
  {
    "id": "GET /admin/bulk/{id}",
    "method": "GET",
    "path": "/admin/bulk/{id}",
    "block": "bulk"
  },
  {
    "id": "GET /admin/refund-requests",
    "method": "GET",
    "path": "/admin/refund-requests",
    "block": "refund-requests"
  },
  {
    "id": "GET /admin/refund-requests/{id}",
    "method": "GET",
    "path": "/admin/refund-requests/{id}",
    "block": "refund-requests"
  },
  {
    "id": "POST /admin/refund-requests/{id}/approve",
    "method": "POST",
    "path": "/admin/refund-requests/{id}/approve",
    "block": "refund-requests"
  },
  {
    "id": "POST /admin/refund-requests/{id}/reject",
    "method": "POST",
    "path": "/admin/refund-requests/{id}/reject",
    "block": "refund-requests"
  },
  {
    "id": "POST /admin/refund-requests/{id}/submit",
    "method": "POST",
    "path": "/admin/refund-requests/{id}/submit",
    "block": "refund-requests"
  },
  {
    "id": "POST /admin/refund-requests/{id}/reconcile",
    "method": "POST",
    "path": "/admin/refund-requests/{id}/reconcile",
    "block": "refund-requests"
  },
  {
    "id": "GET /admin/payment-transactions",
    "method": "GET",
    "path": "/admin/payment-transactions",
    "block": "payment-transactions"
  },
  {
    "id": "GET /admin/monetization-configs/{id}",
    "method": "GET",
    "path": "/admin/monetization-configs/{id}",
    "block": "monetization-configs"
  },
  {
    "id": "PATCH /admin/monetization-configs/{id}",
    "method": "PATCH",
    "path": "/admin/monetization-configs/{id}",
    "block": "monetization-configs"
  },
  {
    "id": "GET /admin/moderation-dictionaries/{id}",
    "method": "GET",
    "path": "/admin/moderation-dictionaries/{id}",
    "block": "moderation-dictionaries"
  },
  {
    "id": "PATCH /admin/moderation-dictionaries/{id}",
    "method": "PATCH",
    "path": "/admin/moderation-dictionaries/{id}",
    "block": "moderation-dictionaries"
  },
  {
    "id": "POST /admin/legal-holds/{id}/release",
    "method": "POST",
    "path": "/admin/legal-holds/{id}/release",
    "block": "legal-holds"
  },
  {
    "id": "POST /admin/moderation-dictionaries/{id}/dry-run",
    "method": "POST",
    "path": "/admin/moderation-dictionaries/{id}/dry-run",
    "block": "moderation-dictionaries"
  },
  {
    "id": "POST /admin/security-events/{id}/disclose",
    "method": "POST",
    "path": "/admin/security-events/{id}/disclose",
    "block": "security-events"
  },
  {
    "id": "POST /admin/bulk/preview",
    "method": "POST",
    "path": "/admin/bulk/preview",
    "block": "bulk"
  },
  {
    "id": "POST /admin/bulk/{id}/execute",
    "method": "POST",
    "path": "/admin/bulk/{id}/execute",
    "block": "bulk"
  },
  {
    "id": "GET /admin/push-test-accounts",
    "method": "GET",
    "path": "/admin/push-test-accounts",
    "block": "push-test-accounts"
  },
  {
    "id": "POST /admin/users/{id}/push-test-access",
    "method": "POST",
    "path": "/admin/users/{id}/push-test-access",
    "block": "users"
  },
  {
    "id": "GET /admin/push-campaigns/{id}",
    "method": "GET",
    "path": "/admin/push-campaigns/{id}",
    "block": "push-campaigns"
  },
  {
    "id": "PATCH /admin/push-campaigns/{id}",
    "method": "PATCH",
    "path": "/admin/push-campaigns/{id}",
    "block": "push-campaigns"
  },
  {
    "id": "POST /admin/push-campaigns/{id}/test",
    "method": "POST",
    "path": "/admin/push-campaigns/{id}/test",
    "block": "push-campaigns"
  },
  {
    "id": "POST /admin/push-campaigns/{id}/schedule",
    "method": "POST",
    "path": "/admin/push-campaigns/{id}/schedule",
    "block": "push-campaigns"
  },
  {
    "id": "POST /admin/account-restriction-jobs/preview",
    "method": "POST",
    "path": "/admin/account-restriction-jobs/preview",
    "block": "account-restriction-jobs"
  },
  {
    "id": "GET /admin/account-restriction-jobs/{id}",
    "method": "GET",
    "path": "/admin/account-restriction-jobs/{id}",
    "block": "account-restriction-jobs"
  },
  {
    "id": "POST /admin/account-restriction-jobs/{id}/execute",
    "method": "POST",
    "path": "/admin/account-restriction-jobs/{id}/execute",
    "block": "account-restriction-jobs"
  },
  {
    "id": "POST /admin/account-restriction-jobs/{id}/cancel",
    "method": "POST",
    "path": "/admin/account-restriction-jobs/{id}/cancel",
    "block": "account-restriction-jobs"
  },
  {
    "id": "GET /admin/brand-icons/{id}",
    "method": "GET",
    "path": "/admin/brand-icons/{id}",
    "block": "brand-icons"
  },
  {
    "id": "GET /admin/brand-icons/{id}/source",
    "method": "GET",
    "path": "/admin/brand-icons/{id}/source",
    "block": "brand-icons"
  },
  {
    "id": "GET /admin/brand-icons/{id}/preview",
    "method": "GET",
    "path": "/admin/brand-icons/{id}/preview",
    "block": "brand-icons"
  },
  {
    "id": "GET /admin/brand-icons/{id}/bundle",
    "method": "GET",
    "path": "/admin/brand-icons/{id}/bundle",
    "block": "brand-icons"
  },
  {
    "id": "GET /admin/users/{id}/orders",
    "method": "GET",
    "path": "/admin/users/{id}/orders",
    "block": "users"
  },
  {
    "id": "GET /admin/users/{id}/cases",
    "method": "GET",
    "path": "/admin/users/{id}/cases",
    "block": "users"
  },
  {
    "id": "GET /admin/users/{id}/support-threads",
    "method": "GET",
    "path": "/admin/users/{id}/support-threads",
    "block": "users"
  },
  {
    "id": "GET /admin/users/{id}/decisions",
    "method": "GET",
    "path": "/admin/users/{id}/decisions",
    "block": "users"
  }
] as const;
