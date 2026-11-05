import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter/webview_flutter.dart';

bool trustedBankEntry(Uri uri) =>
    uri.scheme == 'https' &&
    uri.port == 443 &&
    uri.userInfo.isEmpty &&
    ['vtbkz.rbsuat.com', 'payment.vtb.kz'].contains(uri.host) &&
    uri.path.startsWith('/payment/');

bool bankReturn(Uri uri, String paymentId) =>
    uri.scheme == 'https' &&
    uri.port == 443 &&
    uri.userInfo.isEmpty &&
    uri.host == 'joba.com.kz' &&
    uri.path == '/api/v1/public/billing/vtb/return' &&
    uri.queryParameters['payment_id'] == paymentId;

bool bankNavigationAllowed(Uri uri) =>
    uri.toString() == 'about:blank' ||
    uri.scheme == 'https' && uri.userInfo.isEmpty && uri.host.isNotEmpty;

/// Bank-owned content: no JOBA credentials, script bridges or card interception.
class BankForm extends StatefulWidget {
  final Uri entry;
  final String paymentId;
  final bool testMode;
  const BankForm(
      {super.key,
      required this.entry,
      required this.paymentId,
      this.testMode = false});
  @override
  State<BankForm> createState() => _BankFormState();
}

class _BankFormState extends State<BankForm> {
  WebViewController? controller;
  int progress = 0;
  bool failed = false, closed = false;
  String host = '';
  @override
  void initState() {
    super.initState();
    host = widget.entry.host;
    initialize();
  }

  Future<void> initialize() async {
    try {
      if (!trustedBankEntry(widget.entry))
        throw StateError('Invalid bank entry');
      final view = WebViewController();
      await view.setJavaScriptMode(JavaScriptMode.unrestricted);
      final native = view.platform;
      if (native is AndroidWebViewController) {
        // ACS challenges may use issuer cookies inside a third-party frame.
        await AndroidWebViewCookieManager(
                const PlatformWebViewCookieManagerCreationParams())
            .setAcceptThirdPartyCookies(native, true);
      }
      await view.setBackgroundColor(Colors.white);
      await view.setNavigationDelegate(NavigationDelegate(
        onProgress: (value) {
          if (mounted) setState(() => progress = value);
        },
        onNavigationRequest: (request) {
          if (closed) return NavigationDecision.prevent;
          final uri = Uri.tryParse(request.url);
          if (request.isMainFrame &&
              uri != null &&
              bankReturn(uri, widget.paymentId)) {
            if (!closed && mounted) {
              closed = true;
              Navigator.of(context).pop(true);
            }
            return NavigationDecision.prevent;
          }
          if (uri == null || !bankNavigationAllowed(uri)) {
            if (request.isMainFrame && mounted) setState(() => failed = true);
            return NavigationDecision.prevent;
          }
          if (request.isMainFrame && uri.scheme == 'https' && mounted)
            setState(() => host = uri.host);
          return NavigationDecision.navigate;
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && mounted)
            setState(() => failed = true);
        },
      ));
      if (!mounted) return;
      setState(() => controller = view);
      await view.loadRequest(widget.entry);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) closed = true;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Вернуться к оплате',
              onPressed: () => Navigator.of(context).pop(false)),
          actions: [
            if (widget.testMode)
              IconButton(
                tooltip: 'Тестовая карта',
                icon: const Icon(Icons.info_outline),
                onPressed: () => showDialog<void>(
                    context: context,
                    builder: (dialog) => AlertDialog(
                          title: const Text('Карта для тестовой оплаты'),
                          content: const SelectableText(
                              '2201 3820 0000 0062\nСрок: 12/34\nCVC: 123\n\nНастоящую карту здесь использовать не нужно.'),
                          actions: [
                            TextButton(
                                onPressed: () {
                                  Clipboard.setData(const ClipboardData(
                                      text: '2201382000000062'));
                                  Navigator.of(dialog).pop();
                                },
                                child: const Text('Скопировать номер')),
                            TextButton(
                                onPressed: () => Navigator.of(dialog).pop(),
                                child: const Text('Закрыть'))
                          ],
                        )),
              )
          ],
          title:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Оплата ВТБ'),
            Text(host, style: const TextStyle(fontSize: 12)),
          ]),
        ),
        body: SafeArea(
            child: Column(children: [
          if (progress < 100 && !failed)
            LinearProgressIndicator(
                value: progress == 0 ? null : progress / 100),
          Expanded(
              child: failed
                  ? Center(
                      child: Padding(
                          padding: const EdgeInsets.all(24),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            const Text(
                                'Не удалось открыть банковскую страницу. Вернитесь и проверьте статус оплаты, прежде чем пробовать снова.'),
                            const SizedBox(height: 16),
                            FilledButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('Вернуться в JOBA')),
                          ])))
                  : controller == null
                      ? const Center(child: CircularProgressIndicator())
                      : WebViewWidget(controller: controller!)),
        ])),
      ));
}
