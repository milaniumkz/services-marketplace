# Login locations and VTB tenge settlement

## Security journal

New security events retain the request IP plus an approximate city/region/country snapshot from a local DB-IP City Lite 2026-11 database. No individual IP lookup is sent to an external service. IPv4, mapped IPv4 and IPv6 are supported; private, reserved, malformed and unknown IPs return an explicit unavailable state. Street address and precise coordinates are not inferred or stored. Version/source, lookup timestamp and approximate precision are retained. Backfilled/legacy lookups are explicitly marked historical/current-database estimates, not proof of a past physical location.

Registration, login, staff login and refresh now have distinct auth_action labels; failed password attempts for known nondeleted accounts survive transaction rollback. Bounded, control-character-stripped User-Agent is captured from the HTTP request. Raw IP/session identifiers remain out of normal summaries. Existing regional security permissions, MFA and audited raw-IP disclosure remain unchanged. Admin user overview, user security history and global security log show the location; source/accuracy/VPN caveats and DB-IP CC BY 4.0 attribution links are visible. Own privacy exports include own security events without session secrets. Existing retention minimization removes location with IP/device data; unrelated records remain unchanged. Privacy service text describes the same security purpose without introducing forced GPS prompts or perpetual retention.

Database download is hash-pinned (compressed and uncompressed), build-time only, ignored by Git/Docker context and installed in the API image. `maxmind` is only the MIT reader; the data is DB-IP Lite CC BY 4.0, not the restricted MaxMind GeoLite distribution. Update the monthly snapshot URL and both hashes during normal database maintenance. Runtime lookup failure cannot turn a city guess into an exact location or prevent authentication.

## VTB

Read-only production diagnostics showed VTB sandbox with default KZ/KZT only and enabled internal RU simulation; BCC was production KZ/KZT. The owner then explicitly requested RUB display in the app with KZT on the VTB bank page. Private bank files, environments, global controls and existing subscriptions are preserved.

Default VTB invoice regions are KZ/RU/BY (explicit country restrictions are respected); accepted bank currencies remain the actual configured currencies. A KZT VTB terminal can accept RUB/BYN invoices by server conversion. BCC is unchanged. Public bank readiness now reports invoice currencies separately. Registering the VTB provider for RU suppresses internal simulated offers and blocks previously cached simulated purchases through the existing provider-ready guard.

For RUB/BYN VTB quotes and promotion reservations, an official National Bank of Kazakhstan rate is retrieved over fixed HTTPS with timeout, strict date/units/decimal checks and bounded content validation. Rates are cached for six hours; stale/unavailable rates fail closed rather than fabricating a conversion. Monetary conversion uses BigInt and rounds once to the nearest tiyn. The bank settlement is frozen in the server quote/reservation. The app's plan/invoice remains RUB/BYN; checkout displays the frozen KZT bank amount, official rate/date and issuer-conversion caveat. Existing installed clients can open the returned VTB form without an APK change; the additional explanatory UI is in web and next native release sources. No APK is built.

Bank orders, independent amount/currency verification, paid cash journal, and refunds use the exact KZT amount actually sent to the bank (398). Subscription price/credit calculations retain the original invoice currency. The immutable payment journal is written correctly on creation, never rewritten afterward. Promotion verification uses the bank payment state machine and validates the referenced reservation, preventing duplicate/restored grants. Free fully discounted quotes do not need a rate or bank registration.

VTB remains BANK SANDBOX, not live. Real capture requires the owner's bank-issued production parameters; this change does not invent those credentials or switch environments.

## Newly executed checks

- API build and focused `login-location`, `vtb-fx`, existing VTB/BCC/refund/privacy/export/retention/public-service checks.
- Admin browser location journal, masked IP and audited disclosure.
- Flutter checkout shows the original RUB price plus the frozen KZT amount/rate; existing payment/checkout flows; analyzer.
- Real VTB sandbox: isolated in-memory RU fixture, RUB 100.00 invoice, official rate 5.59 KZT/RUB on 2026-11-27, bank registered KZT 559.00, returned an HTTPS bank form with HTTP 200. No card entered, capture, refund, production database or customer notification. Callbacks disabled only for that isolated probe. This is an unpaid bank-form check, NOT a completed bank payment/refund.
- Earlier direct RUB/BYN registration probes with overlong diagnostic order numbers returned error 1; they do not establish currency support and are not used as evidence for currency routing.

Commands and sanitized outcomes are retained under the private nov27-network-location delivery folder. Standard deployment preserves all bank files and payment controls and creates the existing backup/rollback artifacts.
