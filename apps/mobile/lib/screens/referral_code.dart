import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/l10n.dart';
import '../core/widgets.dart';
import '../core/theme.dart';
import '../core/design_icons.dart';

class ReferralCodeScreen extends StatelessWidget {
  final JobaApi api;
  final VoidCallback onAccepted;
  const ReferralCodeScreen(
      {required this.api, required this.onAccepted, super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: canvas,
        appBar: AppBar(
            leadingWidth: 72,
            leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const JobaIcon('back')),
            title: Transform.translate(
                offset: const Offset(0, -11),
                child: const UiText('Код приглашения'))),
        body: ActionForm(
          stickySubmit: true,
          fields: [
            InputSpec('code', 'Код',
                minHeight: 52,
                hint: 'Код из приглашения',
                validate: (value) => value.trim().length > 50
                    ? 'Код должен содержать не больше 50 символов'
                    : null)
          ],
          before: const [
            UiHeading('Вас пригласил друг?',
                'Введите его код, чтобы проверить условия бонуса.')
          ],
          afterFields: [
            DataCard('Сначала проверим код',
                translateTitle: true,
                subtitle: localize(context,
                    'Бонус появится после выполнения правил программы. Нельзя использовать собственный код или активировать приглашение повторно.'))
          ],
          button: 'Проверить код',
          submit: (values) async {
            await api.request('/referrals/attribute',
                method: 'POST', body: {'code': values['code']!.trim()});
            if (!context.mounted) return;
            Navigator.pop(context);
            onAccepted();
          },
        ),
      );
}
