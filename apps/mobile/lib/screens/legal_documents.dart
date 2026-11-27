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
      'verification' ||
      'identity_verification' ||
      'verification_consent' =>
        'Согласие на проверку личности и фото профиля',
      'payments' => 'Условия оплаты',
      'refunds' => 'Условия возврата и отмены',
      'public_offer' => 'Публичная оферта',
      'contacts' => 'Контакты и реквизиты',
      'community' => 'Правила сообщества',
      'subscription' || 'subscriptions' || 'billing' => 'Подписка и отмена',
      'promotion' || 'boost' => 'Правила продвижения',
      _ => (document['title'] as String?)?.trim().isNotEmpty == true
          ? document['title']
          : 'Документ JOBA'
    };
String legalDocumentVersion(BuildContext context, Json document) {
  final published = DateTime.tryParse('${document['published_at'] ?? ''}');
  return '${localize(context, 'Версия')} ${document['version']}${published == null ? '' : ' · ${DateFormat('dd.MM.yyyy').format(published.toUtc())}'}';
}

class LoginLegalLinks extends StatelessWidget {
  final JobaApi api;
  final String country, locale;
  final bool enabled;
  const LoginLegalLinks(
      {super.key,
      required this.api,
      required this.country,
      required this.locale,
      this.enabled = true});

  Future<void> open(BuildContext context, String? type) => showDialog<void>(
      context: context,
      builder: (_) => Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
            child: SizedBox(
                width: 720,
                height: MediaQuery.sizeOf(context).height * .85,
                child: _LoginLegalDialog(
                    api: api,
                    country: country,
                    locale: locale,
                    initialType: type)),
          ));

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Wrap(alignment: WrapAlignment.center, children: [
          for (final link in const {
            'privacy': 'Политика конфиденциальности',
            'terms': 'Пользовательское соглашение',
            'all': 'Другие документы',
          }.entries)
            TextButton(
                onPressed: enabled
                    ? () => open(context, link.key == 'all' ? null : link.key)
                    : null,
                child: UiText(link.value, textAlign: TextAlign.center)),
        ]),
      );
}

class _LoginLegalDialog extends StatefulWidget {
  final JobaApi api;
  final String country, locale;
  final String? initialType;
  const _LoginLegalDialog(
      {required this.api,
      required this.country,
      required this.locale,
      this.initialType});
  @override
  State<_LoginLegalDialog> createState() => _LoginLegalDialogState();
}

class _LoginLegalDialogState extends State<_LoginLegalDialog> {
  String? selected;
  @override
  void initState() {
    super.initState();
    selected = widget.initialType;
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
            child: Row(children: [
              if (selected != null)
                IconButton(
                    tooltip: 'Список документов',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => setState(() => selected = null)),
              const Expanded(
                  child: UiText('Документы JOBA',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold))),
              IconButton(
                  tooltip: 'Закрыть документ',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop()),
            ])),
        const Divider(height: 1),
        Expanded(
            child: ApiView(
          load: () => widget.api.request('/legal/documents',
              authenticated: false,
              query: {'country': widget.country, 'locale': widget.locale}),
          builder: (context, data, reload) {
            final documents = items(data);
            final matches = documents.where((doc) =>
                doc['id'] == selected ||
                doc['type'] == selected ||
                selected == 'privacy' && doc['type'] == 'privacy_policy' ||
                selected == 'terms' && doc['type'] == 'terms_of_use');
            final document =
                selected == null || matches.isEmpty ? null : matches.first;
            if (document != null)
              return SelectionArea(
                  child: ListView(padding: const EdgeInsets.all(20), children: [
                UiHeading(legalDocumentTitle(document)),
                Text(legalDocumentVersion(context, document),
                    style: const TextStyle(fontSize: 12, color: muted)),
                const SizedBox(height: 20),
                Text('${document['content'] ?? ''}',
                    style: const TextStyle(fontSize: 14, height: 1.6)),
              ]));
            return ListView(padding: const EdgeInsets.all(16), children: [
              if (selected != null)
                const Notice(
                    'Этот документ пока не опубликован для выбранной страны и языка.'),
              if (documents.isEmpty)
                const Notice('Утверждённые документы ещё не опубликованы.'),
              for (final doc in documents)
                ListTile(
                  title: UiText(legalDocumentTitle(doc)),
                  subtitle: Text(legalDocumentVersion(context, doc)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => setState(() => selected = doc['id'] as String),
                ),
            ]);
          },
        )),
      ]);
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
