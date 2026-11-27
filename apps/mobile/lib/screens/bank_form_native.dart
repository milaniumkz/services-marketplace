import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'bank_navigation.dart';

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
  void closeOnReturn(String url) {
    final uri = Uri.tryParse(url);
    if (!closed &&
        mounted &&
        uri != null &&
        bankReturn(uri, widget.paymentId)) {
      closed = true;
      Navigator.of(context).pop(true);
    }
  }

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
        // Android does not call shouldOverrideUrlLoading for POST forms.
        // BCC returns by POST, so observe the actual main-frame load as well.
        onPageStarted: closeOnReturn,
        onProgress: (value) {
          if (mounted) setState(() => progress = value);
        },
        onNavigationRequest: (request) {
          if (closed) return NavigationDecision.prevent;
          final uri = Uri.tryParse(request.url);
          if (request.isMainFrame &&
              uri != null &&
              bankReturn(uri, widget.paymentId)) {
            closeOnReturn(request.url);
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
                          content: SelectableText(widget.entry.path
                                      .contains('/bcc/') ||
                                  widget.entry.host.contains('bcc.kz')
                              ? 'Тестовые карты БЦК указаны в инструкции банка. Настоящую карту здесь использовать не нужно.'
                              : '2201 3820 0000 0062\nСрок: 12/34\nCVC: 123\n\nНастоящую карту здесь использовать не нужно.'),
                          actions: [
                            TextButton(
                                onPressed: widget.entry.path
                                            .contains('/bcc/') ||
                                        widget.entry.host.contains('bcc.kz')
                                    ? null
                                    : () {
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
            Text(widget.entry.path.contains('/bcc/') ||
                    widget.entry.host.contains('bcc.kz')
                ? 'Оплата БЦК'
                : 'Оплата ВТБ'),
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
