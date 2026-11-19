import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'bank_frame_web.dart';
import 'bank_navigation.dart';

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
  web.HTMLIFrameElement? frame;
  late final JSFunction listener;
  bool closed = false;

  @override
  void initState() {
    super.initState();
    listener = ((web.MessageEvent event) {
      final current = frame;
      if (!closed &&
          mounted &&
          current != null &&
          isOwnBankReturn(
              event, current, widget.paymentId, 'https://joba.com.kz')) {
        closed = true;
        Navigator.of(context).pop(true);
      }
    }).toJS;
    web.window.addEventListener('message', listener);
  }

  @override
  void dispose() {
    closed = true;
    web.window.removeEventListener('message', listener);
    frame?.src = 'about:blank';
    frame?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Вернуться к оплате',
              onPressed: () => Navigator.of(context).pop(false)),
          title: Text(widget.entry.path.contains('/bcc/') ||
                  widget.entry.host.contains('bcc.kz')
              ? 'Оплата БЦК'
              : 'Оплата ВТБ'),
        ),
        body: SafeArea(
            child: !trustedBankEntry(widget.entry)
                ? const Center(
                    child: Text('Некорректный адрес банковской страницы'))
                : Column(children: [
                    if (widget.testMode)
                      const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                              'Тестовый шлюз. Используйте только тестовые карты банка.')),
                    Expanded(
                        child: HtmlElementView.fromTagName(
                            tagName: 'div',
                            onElementCreated: (element) {
                              final host = element as web.HTMLDivElement;
                              host.style.width = '100%';
                              host.style.height = '100%';
                              if (closed || !mounted) return;
                              frame = createBankFrame(widget.entry);
                              host.append(frame!);
                            })),
                  ])),
      );
}
