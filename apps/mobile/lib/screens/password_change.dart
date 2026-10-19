import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class PasswordChangeContent extends StatefulWidget {
  final JobaApi api;
  final VoidCallback onChanged;
  const PasswordChangeContent(
      {required this.api, required this.onChanged, super.key});
  @override
  State<PasswordChangeContent> createState() => _PasswordChangeContentState();
}

class _PasswordChangeContentState extends State<PasswordChangeContent> {
  String nextPassword = '';
  @override
  Widget build(BuildContext context) => ApiView(
      load: () => widget.api.request('/me/security-policy'),
      builder: (context, data, reload) {
        final minimum = data['password_min'];
        if (minimum is! int ||
            minimum < 15 ||
            minimum > 128 ||
            data['password_max'] != 128) {
          return ListView(padding: const EdgeInsets.all(20), children: [
            const Notice('Не удалось загрузить требования к паролю',
                error: true),
            TextButton(onPressed: reload, child: const UiText('Повторить'))
          ]);
        }
        return form(context, minimum);
      });
  Widget form(BuildContext context, int minimum) => ActionForm(
      authLayout: true,
      stickySubmit: true,
      before: const [
        UiText('Новый пароль',
            style: TextStyle(
                fontSize: 26,
                height: 33 / 26,
                letterSpacing: -.9,
                fontWeight: FontWeight.w700)),
        SizedBox(height: 10),
        UiText('После изменения остальные сессии завершатся.',
            style:
                TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF627187))),
        SizedBox(height: 18)
      ],
      fields: [
        const InputSpec('current_password', 'Текущий пароль',
            secret: true,
            hint: 'Введите текущий пароль',
            minHeight: 74,
            inputAction: TextInputAction.next,
            autofillHints: [AutofillHints.password]),
        InputSpec('new_password', 'Новый пароль',
            secret: true,
            hint:
                '${localize(context, 'Не менее')} $minimum ${localize(context, 'символов')}',
            minHeight: 74,
            inputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            changed: (v) => nextPassword = v,
            validate: (v) => v.length < minimum || v.length > 128
                ? '${localize(context, 'Пароль должен содержать от')} $minimum ${localize(context, 'до 128 символов')}'
                : null),
        InputSpec('repeat', 'Повторите новый пароль',
            secret: true,
            hint: 'Введите новый пароль ещё раз',
            minHeight: 74,
            inputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            validate: (v) => v != nextPassword ? 'Пароли не совпадают' : null)
      ],
      afterFields: const [
        Notice(
            'Другие устройства потребуют повторный вход. Текущая сессия останется активной.',
            icon: 'info',
            margin: EdgeInsets.zero)
      ],
      submit: (values) async {
        final client = widget.api, generation = widget.api.sessionGeneration;
        final owner = client.session?['user']?['id'];
        bool current() =>
            mounted &&
            identical(client, widget.api) &&
            !client.disposed &&
            client.authenticated &&
            client.sessionGeneration == generation &&
            client.session?['user']?['id'] == owner;
        try {
          await client.request('/me/password/change', method: 'POST', body: {
            'current_password': values['current_password'],
            'new_password': values['new_password']
          });
          if (current()) widget.onChanged();
        } catch (_) {
          if (current()) rethrow;
        }
      });
}
