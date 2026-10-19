import 'dart:convert';
import 'package:flutter/material.dart';
import 'legal_documents.dart';
import '../core/api.dart';
import '../core/design_widgets.dart';
import '../core/l10n.dart';
import '../core/theme.dart';

class OnboardingConsent extends StatefulWidget {
  final JobaApi api;
  final List<Json> documents;
  final VoidCallback onAccepted;
  final VoidCallback? onReload;
  final String countryLabel, localeLabel;
  const OnboardingConsent(
      {required this.api,
      required this.documents,
      required this.onAccepted,
      this.onReload,
      required this.countryLabel,
      required this.localeLabel,
      super.key});
  @override
  State<OnboardingConsent> createState() => _OnboardingConsentState();
}

class _OnboardingConsentState extends State<OnboardingConsent> {
  bool terms = false, privacy = false, marketing = false, busy = false;
  Object? error;
  int documentGeneration = 0;
  Json? document(List<String> types) {
    for (final d in widget.documents) {
      if (types.contains(d['type'])) return d;
    }
    return null;
  }

  Json? get agreement => document(['terms', 'terms_of_use']);
  Json? get policy => document(['privacy', 'privacy_policy']);
  bool get enabled =>
      terms && privacy && agreement != null && policy != null && !busy;
  @override
  void didUpdateWidget(covariant OnboardingConsent oldWidget) {
    super.didUpdateWidget(oldWidget);
    String revision(List<Json> records) {
      final revisions = records
          .map((d) => jsonEncode([
                d['id'],
                d['type'],
                d['version'],
                d['hash'],
                d['minimum_age'],
                d['country'],
                d['locale'],
              ]))
          .toList()
        ..sort();
      return jsonEncode(revisions);
    }

    if (oldWidget.api != widget.api ||
        oldWidget.countryLabel != widget.countryLabel ||
        oldWidget.localeLabel != widget.localeLabel ||
        revision(oldWidget.documents) != revision(widget.documents)) {
      documentGeneration++;
      terms = false;
      privacy = false;
      error = null;
    }
  }

  Future<void> submit() async {
    if (!enabled) return;
    setState(() {
      busy = true;
      error = null;
    });
    final api = widget.api;
    final generation = api.sessionGeneration;
    final documentsGeneration = documentGeneration;
    final selected = [Json.from(agreement!), Json.from(policy!)];
    final selectedMarketing = marketing;
    bool current() =>
        mounted &&
        widget.api == api &&
        generation == api.sessionGeneration &&
        api.authenticated &&
        documentsGeneration == documentGeneration;
    try {
      for (var index = 0; index < selected.length; index++) {
        if (!current()) return;
        final d = selected[index];
        await api.request('/me/consents', method: 'POST', body: {
          'document_id': d['id'],
          'document_hash': d['hash'],
          'accepted': true,
          if (index == 0) 'age_confirmed': true
        });
        if (!current()) return;
      }
      final preferences =
          await api.request('/me/notification-preferences') as Json;
      if (!current()) return;
      final user = await api.request('/me') as Json;
      if (!current()) return;
      await api.request('/me/notification-preferences', method: 'PATCH', body: {
        'expected_version': user['version'],
        'preferences': {...preferences, 'marketing': selectedMarketing}
      });
      if (current()) widget.onAccepted();
    } catch (e) {
      if (current()) {
        setState(() {
          error = e;
          if (e is ApiException && e.code == 'LEGAL_VERSION_CHANGED') {
            terms = false;
            privacy = false;
          }
        });
        if (e is ApiException && e.code == 'LEGAL_VERSION_CHANGED')
          widget.onReload?.call();
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void read(Json? d, String title) {
    if (d == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: UiText('Утверждённые документы ещё не опубликованы.')));
      return;
    }
    Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (context) => LegalDocumentReader(document: Json.from(d))));
  }

  Widget check(String label, bool value, ValueChanged<bool> change) =>
      CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: value,
          onChanged: busy ? null : (v) => change(v == true),
          title: UiText(label,
              style: const TextStyle(fontSize: 12, height: 1.55)));
  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(
            child: ListView(padding: const EdgeInsets.all(20), children: [
          const UiHeading('Понятные правила'),
          Text('${widget.countryLabel} · ${widget.localeLabel}',
              style: const TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 20),
          JobaMenu([
            JobaMenuEntry('Пользовательское соглашение', 'file',
                () => read(agreement, 'Пользовательское соглашение'),
                subtitle: agreement == null
                    ? 'Утверждённые документы ещё не опубликованы.'
                    : '${localize(context, 'Версия')} ${agreement!['version']}',
                translateSubtitle: agreement == null),
            JobaMenuEntry('Политика конфиденциальности', 'shield',
                () => read(policy, 'Политика конфиденциальности'),
                subtitle: policy == null
                    ? 'Утверждённые документы ещё не опубликованы.'
                    : '${localize(context, 'Версия')} ${policy!['version']}',
                translateSubtitle: policy == null)
          ]),
          const SizedBox(height: 24),
          if (agreement == null || policy == null) ...[
            const Notice(
                'Регистрация временно недоступна: соглашение и политика конфиденциальности ещё не опубликованы. После публикации обновите документы.',
                icon: 'info'),
            if (widget.onReload != null)
              TextButton(
                  onPressed: busy ? null : widget.onReload,
                  child: const UiText('Обновить')),
          ],
          check(
              'Принимаю пользовательское соглашение и подтверждаю, что мне исполнилось 18 лет.',
              terms,
              (v) => setState(() => terms = v)),
          check('Ознакомился с политикой конфиденциальности.', privacy,
              (v) => setState(() => privacy = v)),
          check('Хочу получать новости и предложения JOBA. Необязательно.',
              marketing, (v) => setState(() => marketing = v)),
          const Notice(
              'Необязательные согласия можно изменить в разделе «Приватность».',
              icon: 'info'),
          if (error != null) Notice(errorText(context, error!), error: true)
        ])),
        SafeArea(
            top: false,
            child: Container(
                decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: line))),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                        onPressed: enabled ? submit : null,
                        child: const UiText('Принять и продолжить')))))
      ]);
}
