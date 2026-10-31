import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api.dart';
import '../core/design_widgets.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

String legalDocumentTitle(Json document) => switch (document['type']) {
      'terms' || 'terms_of_use' => 'Пользовательское соглашение',
      'privacy' || 'privacy_policy' => 'Политика конфиденциальности',
      'verification' || 'identity_verification' || 'verification_consent' => 'Согласие на проверку личности и фото профиля',
      'payments' => 'Условия оплаты',
      'refunds' => 'Условия возврата и отмены',
      'public_offer' => 'Публичная оферта',
      'contacts' => 'Контакты и реквизиты',
      'community' => 'Правила сообщества',
      'subscription' || 'subscriptions' || 'billing' => 'Подписка и отмена',
      'promotion' || 'boost' => 'Правила продвижения',
      _ => (document['title'] as String?)?.trim().isNotEmpty == true ? document['title'] : 'Документ JOBA'
    };
String legalDocumentVersion(BuildContext context, Json document) {
  final published = DateTime.tryParse('${document['published_at'] ?? ''}');
  return '${localize(context, 'Версия')} ${document['version']}${published == null ? '' : ' · ${DateFormat('dd.MM.yyyy').format(published.toUtc())}'}';
}

class LegalDocuments extends StatelessWidget {
  final JobaApi api;
  final String country, locale, countryLabel, localeLabel;
  const LegalDocuments(
      {required this.api,
      required this.country,
      required this.locale,
      required this.countryLabel,
      required this.localeLabel,
      super.key});
  @override
  Widget build(BuildContext context) => ApiView(
      key: ValueKey('legal:$country:$locale'),
      load: () => api.request('/legal/documents',
          authenticated: false, query: {'country': country, 'locale': locale}),
      builder: (context, data, reload) {
        final documents = items(data);
        return ListView(padding: const EdgeInsets.all(20), children: [
          const UiHeading('Документы JOBA'),
          Text('$countryLabel · $localeLabel',
              style: const TextStyle(fontSize: 12, color: muted)),
          const Notice(
              'Здесь опубликованы документы выбранной страны и языка с номером версии и датой.',
              icon: 'info',
              margin: EdgeInsets.symmetric(vertical: 20)),
          if (documents.isEmpty)
            const Notice('Утверждённые документы ещё не опубликованы.')
          else
            JobaMenu([
              for (final doc in documents)
                JobaMenuEntry(
                    legalDocumentTitle(doc),
                    ['privacy', 'privacy_policy'].contains(doc['type'])
                        ? 'shield'
                        : 'file',
                    () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) =>
                                LegalDocumentReader(document: Json.from(doc)))),
                    subtitle: legalDocumentVersion(context, doc),
                    translateSubtitle: false)
            ]),
          const SizedBox(height: 24),
          const UiText(
              'Документы относятся к выбранному региону. Принятие и отзыв согласий доступны отдельно.',
              style: TextStyle(fontSize: 12, color: muted, height: 1.55)),
        ]);
      });
}

class LegalDocumentReader extends StatelessWidget {
  final Json document;
  const LegalDocumentReader({required this.document, super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: canvas,
      appBar:
          AppBar(leadingWidth: 72, title: UiText(legalDocumentTitle(document))),
      body: SelectionArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
        UiHeading(legalDocumentTitle(document)),
        Text(legalDocumentVersion(context, document),
            style: const TextStyle(fontSize: 12, color: muted)),
        const SizedBox(height: 20),
        Text('${document['content'] ?? ''}',
            style: const TextStyle(fontSize: 14, height: 1.6)),
      ])));
}
