import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:services_marketplace/screens/bank_form.dart';
import 'package:services_marketplace/screens/bank_payment.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:http/testing.dart';
import 'widget_test.dart' show MemoryVault, ok;

class TestDelegate extends PlatformNavigationDelegate {
  TestDelegate(super.params) : super.implementation();
  NavigationRequestCallback? navigate;
  @override
  Future<void> setOnNavigationRequest(NavigationRequestCallback value) async {
    navigate = value;
  }

  @override
  Future<void> setOnProgress(ProgressCallback value) async {
    value(100);
  }

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback value) async {}
}

class TestController extends PlatformWebViewController {
  TestController(super.params) : super.implementation();
  LoadRequestParams? loaded;
  JavaScriptMode? mode;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode value) async {
    mode = value;
  }

  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
      PlatformNavigationDelegate handler) async {}
  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    loaded = params;
  }
}

class TestView extends PlatformWebViewWidget {
  TestView(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const Text('Bank-owned web content');
}

class TestPlatform extends WebViewPlatform {
  late TestController controller;
  late TestDelegate delegate;
  @override
  PlatformWebViewController createPlatformWebViewController(
          PlatformWebViewControllerCreationParams params) =>
      controller = TestController(params);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
          PlatformNavigationDelegateCreationParams params) =>
      delegate = TestDelegate(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
          PlatformWebViewWidgetCreationParams params) =>
      TestView(params);
}

void main() {
  test(
      'bank entry and return are scoped while issuer HTTPS 3DS navigation stays supported',
      () {
    expect(
        trustedBankEntry(Uri.parse(
            'https://vtbkz.rbsuat.com/payment/merchants/ecom/payment.html?mdOrder=test')),
        true);
    for (final s in [
      'http://vtbkz.rbsuat.com/payment/',
      'https://vtbkz.rbsuat.com.evil.example/payment/',
      'https://user:password@vtbkz.rbsuat.com/payment/',
      'https://payment.vtb.kz:8443/payment/',
      'https://payment.vtb.kz/not-payment/'
    ]) expect(trustedBankEntry(Uri.parse(s)), false);
    expect(
        bankReturn(
            Uri.parse(
                'https://joba.com.kz/api/v1/public/billing/vtb/return?payment_id=own'),
            'own'),
        true);
    expect(
        bankReturn(
            Uri.parse(
                'https://joba.com.kz/api/v1/public/billing/vtb/return?payment_id=other'),
            'own'),
        false);
    expect(
        bankReturn(
            Uri.parse(
                'https://joba.com.kz.evil.example/api/v1/public/billing/vtb/return?payment_id=own'),
            'own'),
        false);
    expect(
        bankNavigationAllowed(
            Uri.parse('https://issuer.example:8443/3ds/challenge')),
        true);
    for (final s in [
      'http://issuer.example/3ds',
      'javascript:alert(1)',
      'file:///data/session',
      'data:text/html,test',
      'https://user:password@issuer.example/3ds'
    ]) expect(bankNavigationAllowed(Uri.parse(s)), false);
  });
  testWidgets(
      'bank form remains in app, sends no app headers and closes only its own top-level return',
      (t) async {
    final platform = TestPlatform();
    WebViewPlatform.instance = platform;
    bool? returned;
    await t.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: FilledButton(
                    onPressed: () async {
                      returned = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                              builder: (_) => BankForm(
                                  entry: Uri.parse(
                                      'https://vtbkz.rbsuat.com/payment/merchants/ecom/payment.html?mdOrder=synthetic'),
                                  paymentId: 'own')));
                    },
                    child: const Text('Pay'))))));
    await t.tap(find.text('Pay'));
    await t.pumpAndSettle();
    expect(find.text('Bank-owned web content'), findsOneWidget);
    expect(platform.controller.loaded!.headers, isEmpty);
    expect(platform.controller.mode, JavaScriptMode.unrestricted);
    expect(
        await platform.delegate.navigate!(const NavigationRequest(
            url: 'https://issuer.example/3ds', isMainFrame: true)),
        NavigationDecision.navigate);
    expect(
        await platform.delegate.navigate!(const NavigationRequest(
            url:
                'https://joba.com.kz/api/v1/public/billing/vtb/return?payment_id=own',
            isMainFrame: false)),
        NavigationDecision.navigate);
    expect(returned, isNull);
    expect(
        await platform.delegate.navigate!(const NavigationRequest(
            url:
                'https://joba.com.kz/api/v1/public/billing/vtb/return?payment_id=own',
            isMainFrame: true)),
        NavigationDecision.prevent);
    await t.pumpAndSettle();
    expect(returned, true);
    expect(find.text('Bank-owned web content'), findsNothing);
  });
  testWidgets(
      'closing bank return refreshes authenticated server proof without an external browser',
      (t) async {
    final platform = TestPlatform();
    WebViewPlatform.instance = platform;
    var paid = false, reads = 0;
    final api = JobaApi('https://joba.com.kz', vault: MemoryVault(),
        transport: MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer isolated');
      reads++;
      return ok({
        'id': 'own',
        'status': paid ? 'completed' : 'pending',
        'amount_minor': 50000,
        'currency': 'KZT',
        'title': 'Подписка',
        'benefit': 'subscription',
        'payment_url': paid
            ? null
            : 'https://vtbkz.rbsuat.com/payment/merchants/ecom/payment.html?mdOrder=synthetic'
      });
    }));
    addTearDown(api.dispose);
    api.session = {
      'access_token': 'isolated',
      'user': {'id': 'synthetic'}
    };
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: BankPaymentScreen(api: api, id: 'own', onGo: (_, __) {}))));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Перейти к оплате в банке'));
    await t.tap(find.text('Перейти к оплате в банке'));
    await t.pumpAndSettle();
    expect(find.text('Bank-owned web content'), findsOneWidget);
    expect(find.text('Оплата подтверждена'), findsNothing);
    paid = true;
    await platform.delegate.navigate!(const NavigationRequest(
        url:
            'https://joba.com.kz/api/v1/public/billing/vtb/return?payment_id=own',
        isMainFrame: true));
    await t.pumpAndSettle();
    expect(reads, greaterThanOrEqualTo(2));
    expect(find.text('Оплата подтверждена'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'automatic opening survives checkout route replacement and test card help is sandbox-only',
      (t) async {
    final platform = TestPlatform();
    WebViewPlatform.instance = platform;
    final api = JobaApi('https://joba.com.kz',
        vault: MemoryVault(),
        transport: MockClient((request) async => ok({
              'id': 'own',
              'status': 'pending',
              'amount_minor': 50000,
              'currency': 'KZT',
              'title': 'Подписка',
              'bank_test': true,
              'payment_url':
                  'https://vtbkz.rbsuat.com/payment/merchants/ecom/payment.html?mdOrder=synthetic'
            })));
    addTearDown(api.dispose);
    api.session = {
      'access_token': 'isolated',
      'user': {'id': 'synthetic'}
    };
    var automatic = true;
    await t.pumpWidget(MaterialApp(
        home: StatefulBuilder(
            builder: (context, update) => Scaffold(
                body: BankPaymentScreen(
                    key: ValueKey(automatic),
                    api: api,
                    id: 'own',
                    autoOpen: automatic,
                    onGo: (route, id) {
                      expect(route, 'bank-payment');
                      update(() => automatic = false);
                    })))));
    await t.pumpAndSettle();
    expect(automatic, false);
    expect(find.text('Bank-owned web content'), findsOneWidget);
    await t.tap(find.byTooltip('Тестовая карта'));
    await t.pumpAndSettle();
    expect(find.textContaining('2201 3820 0000 0062'), findsOneWidget);
    await t.tap(find.text('Закрыть'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Вернуться к оплате'));
    expect(
        await platform.delegate.navigate!(const NavigationRequest(
            url:
                'https://joba.com.kz/api/v1/public/billing/vtb/return?payment_id=own',
            isMainFrame: true)),
        NavigationDecision.prevent);
    await t.pumpAndSettle();
    expect(find.text('Bank-owned web content'), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
