bool trustedBankEntry(Uri uri) =>
    uri.scheme == 'https' &&
    uri.userInfo.isEmpty &&
    (uri.port == 443 &&
            ['vtbkz.rbsuat.com', 'payment.vtb.kz'].contains(uri.host) &&
            uri.path.startsWith('/payment/') ||
        uri.port == 443 &&
            uri.host == 'joba.com.kz' &&
            uri.path == '/api/v1/public/billing/bcc/form' &&
            RegExp(r'^[0-9a-f-]{36}$')
                .hasMatch(uri.queryParameters['payment_id'] ?? '') &&
            RegExp(r'^[a-f0-9]{64}$')
                .hasMatch(uri.queryParameters['token'] ?? '') ||
        uri.host == 'test3ds.bcc.kz' &&
            uri.port == 5445 &&
            uri.path == '/cgi-bin/cgi_link' ||
        uri.host == '3dsecure.bcc.kz' &&
            uri.port == 443 &&
            uri.path == '/webview');

bool bankReturn(Uri uri, String paymentId) =>
    uri.scheme == 'https' &&
    uri.port == 443 &&
    uri.userInfo.isEmpty &&
    uri.host == 'joba.com.kz' &&
    ['/api/v1/public/billing/vtb/return', '/api/v1/public/billing/bcc/return']
        .contains(uri.path) &&
    uri.queryParameters['payment_id'] == paymentId;

bool bankNavigationAllowed(Uri uri) =>
    uri.toString() == 'about:blank' ||
    uri.scheme == 'https' && uri.userInfo.isEmpty && uri.host.isNotEmpty;
