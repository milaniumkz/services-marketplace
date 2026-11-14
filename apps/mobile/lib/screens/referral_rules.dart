import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import 'referral_terms.dart';

class ReferralRulesContent extends StatelessWidget {
  final List<Json> campaigns;
  const ReferralRulesContent({required this.campaigns, super.key});
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const UiText('Как получить бонус',
              style: TextStyle(
                  fontSize: 26,
                  letterSpacing: -.9,
                  fontWeight: FontWeight.w700,
                  height: 1.269,
                  color: navy)),
          if (campaigns.isNotEmpty)
            const Padding(
                padding: EdgeInsets.only(top: 8),
                child: UiText('Условия действующей программы приглашений.',
                    style: TextStyle(
                        fontSize: 12, height: 1.5, color: Color(0xFF627187)))),
          const SizedBox(height: 12),
          if (campaigns.isEmpty)
            const Notice('Активных программ приглашений пока нет.'),
          for (final campaign in campaigns) ...[
            const _RuleStep(
                title: 'Поделитесь своим кодом',
                description: 'Друг вводит ваш код после регистрации.'),
            const _RuleStep(
                title: 'Друг выполняет условия',
                description: 'Допуск и действия проверяются сервером'),
            _RuleStep(
                title: 'Получите доступ',
                description: referralTerms(context, campaign),
                translateDescription: false),
          ],
          const Notice(
              'Самоприглашение недопустимо. Бонус не превращается в деньги и не меняет рейтинг.',
              warning: true,
              icon: 'info',
              margin: EdgeInsets.symmetric(vertical: 12)),
          const SizedBox(height: 8),
          const UiText(
              'Принятые приглашения сохраняют свои условия. Награду можно активировать в течение 30 дней после выдачи.',
              style: TextStyle(
                  color: Color(0xFF627187), fontSize: 12, height: 1.5)),
        ],
      );
}

class _RuleStep extends StatelessWidget {
  final String title, description;
  final bool translateDescription;
  const _RuleStep(
      {required this.title,
      required this.description,
      this.translateDescription = true});
  @override
  Widget build(BuildContext context) => IntrinsicHeight(
          child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
              width: 18,
              child: Stack(children: [
                Positioned(
                    top: 0,
                    bottom: 0,
                    left: 8,
                    child: Container(width: 1, color: const Color(0xFFD9E1EC))),
                Positioned(
                    top: 3,
                    left: 0,
                    child: Container(
                        width: 18,
                        height: 18,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFD9E1EC))),
                        child: const DecoratedBox(
                            decoration: BoxDecoration(
                                color: primary, shape: BoxShape.circle)))),
              ])),
          const SizedBox(width: 14),
          Expanded(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 64),
                  child: Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            UiText(title,
                                style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.5,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(
                                translateDescription
                                    ? localize(context, description)
                                    : description,
                                style: const TextStyle(
                                    fontSize: 11,
                                    height: 1.5,
                                    color: Color(0xFF627187))),
                          ])))),
        ],
      ));
}
