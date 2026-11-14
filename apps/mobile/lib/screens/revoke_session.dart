import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/design_states.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class RevokeSession extends StatefulWidget {
  final JobaApi api;
  final String family;
  final VoidCallback onCancel;
  final ValueChanged<bool> onRevoked;
  const RevokeSession(
      {required this.api,
      required this.family,
      required this.onCancel,
      required this.onRevoked,
      super.key});
  @override
  State<RevokeSession> createState() => _RevokeSessionState();
}

class _RevokeSessionState extends State<RevokeSession> {
  bool busy = false;
  Object? error;
  Future<void> revoke(bool current) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    final client = widget.api;
    final generation = client.sessionGeneration;
    final owner = client.session?['user']?['id'];
    bool active() =>
        mounted &&
        !client.disposed &&
        client.authenticated &&
        client.sessionGeneration == generation &&
        client.session?['user']?['id'] == owner;
    try {
      await client.request('/me/sessions/${widget.family}', method: 'DELETE');
      if (active()) widget.onRevoked(current);
    } catch (e) {
      if (active()) setState(() => error = e);
    } finally {
      if (active()) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ApiView(
      load: () => widget.api.request('/me/sessions'),
      builder: (context, data, reload) {
        final found =
            items(data).where((r) => r['family'] == widget.family).toList();
        if (found.isEmpty)
          return ListView(padding: const EdgeInsets.all(20), children: [
            JobaStatePanel(
                icon: 'phone',
                title: 'Сессия уже завершена',
                message:
                    'Это устройство больше не входит в список активных сессий.',
                primaryLabel: 'К списку устройств',
                onPrimary: widget.onCancel)
          ]);
        final current = found.single['current'] == true;
        return ListView(padding: const EdgeInsets.all(20), children: [
          JobaStatePanel(
              icon: 'phone',
              title: current
                  ? 'Выйти на этом\nустройстве?'
                  : 'Выйти на другом\nустройстве?',
              message: current
                  ? 'Для следующего входа потребуется номер и пароль. PIN не открывает отозванную сессию.'
                  : 'На другом устройстве потребуется полный вход. PIN не откроет отозванную сессию. Текущее устройство останется авторизовано.',
              primaryLabel: 'Завершить сеанс',
              onPrimary: () => revoke(current),
              destructive: true,
              busy: busy,
              secondaryLabel: 'Отмена',
              onSecondary: widget.onCancel),
          if (error != null) Notice(errorText(context, error!), error: true)
        ]);
      });
}
