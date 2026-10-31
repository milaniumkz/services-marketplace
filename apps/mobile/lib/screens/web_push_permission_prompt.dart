import 'package:flutter/material.dart';
import '../core/push_permission_controller.dart';
import '../core/push_prompt_preferences.dart';

/// The visible button supplies the user gesture required by web browsers.
/// Permission is never requested automatically during rendering or startup.
class WebPushPermissionPrompt extends StatefulWidget {
  final PushPermissionController controller;
  final PushPromptPreferences? preferences;
  final DateTime Function()? now;
  const WebPushPermissionPrompt(
      {required this.controller, this.preferences, this.now, super.key});
  @override
  State<WebPushPermissionPrompt> createState() =>
      _WebPushPermissionPromptState();
}

class _WebPushPermissionPromptState extends State<WebPushPermissionPrompt> {
  late final preferences = widget.preferences ?? PushPromptPreferences();
  bool busy = false, dismissed = false;
  String? error;
  DateTime get now => widget.now?.call() ?? DateTime.now();
  bool get deferred => preferences.read()?.isAfter(now) ?? false;

  void later() {
    if (busy) return;
    preferences.write(now.add(const Duration(days: 7)));
    setState(() => dismissed = true);
  }

  Future<void> enable() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      // Invoke immediately in the click handler: do not await storage or HTTP first.
      await widget.controller.enable();
      if (mounted)
        setState(() {
          dismissed = !widget.controller.needsPermission;
        });
    } catch (_) {
      if (mounted)
        setState(() => error =
            'Не удалось включить уведомления. Проверьте соединение и попробуйте ещё раз.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (dismissed ||
            deferred ||
            (!widget.controller.needsPermission && !busy && error == null))
          return const SizedBox.shrink();
        return LayoutBuilder(builder: (context, constraints) {
          // Delay the offer while a keyboard or a short landscape window leaves no room.
          if (constraints.maxHeight < 230) return const SizedBox.shrink();
          return Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Material(
                          elevation: 8,
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          child: SingleChildScrollView(
                              child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Row(children: [
                                          Icon(Icons
                                              .notifications_active_outlined),
                                          SizedBox(width: 12),
                                          Expanded(
                                              child: Text(
                                                  'Включить уведомления?',
                                                  style: TextStyle(
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.w700)))
                                        ]),
                                        const SizedBox(height: 10),
                                        const Text(
                                            'Сообщим о новых сообщениях, откликах и результатах проверки, даже когда JOBA закрыта.'),
                                        if (error != null) ...[
                                          const SizedBox(height: 10),
                                          Text(error!,
                                              style: const TextStyle(
                                                  color: Colors.red))
                                        ],
                                        const SizedBox(height: 12),
                                        Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            alignment: WrapAlignment.end,
                                            children: [
                                              TextButton(
                                                  onPressed:
                                                      busy ? null : later,
                                                  child: const Text('Позже')),
                                              FilledButton(
                                                  onPressed:
                                                      busy ? null : enable,
                                                  child: Text(busy
                                                      ? 'Подключаем…'
                                                      : error == null
                                                          ? 'Разрешить уведомления'
                                                          : 'Повторить')),
                                            ]),
                                      ])))))));
        });
      });
}
