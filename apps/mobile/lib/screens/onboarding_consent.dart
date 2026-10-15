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
  final String countryLabel, localeLabel;
  const OnboardingConsent(
      {required this.api,
      required this.documents,
      required this.onAccepted,
      required this.countryLabel,
      required this.localeLabel,
      super.key});
  @override
  State<OnboardingConsent> createState() => _OnboardingConsentState();
}

class _OnboardingConsentState extends State<OnboardingConsent> {
  bool terms = false, privacy = false, marketing = false, busy = false;
  Object? error;
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
    String revision(List<Json> records) => records
        .map((d) => '${d['id']}:${d['hash']}:${d['minimum_age']}')
        .join('|');
    if (revision(oldWidget.documents) != revision(widget.documents)) {
      terms = false;
      privacy = false;
    }
  }

  Future<void> submit() async {
    if (!enabled) return;
    setState(() {
      busy = true;
      error = null;
    });
    final generation = widget.api.sessionGeneration;
    try {
      for (final d in [agreement!, policy!]) {
        await widget.api.request('/me/consents', method: 'POST', body: {
          'document_id': d['id'],
          'document_hash': d['hash'],
          'accepted': true,
          if (d == agreement) 'age_confirmed': true
        });
        if (!mounted ||
            generation != widget.api.sessionGeneration ||
            !widget.api.authenticated) return;
      }
      final preferences =
          await widget.api.request('/me/notification-preferences') as Json;
      final user = await widget.api.request('/me') as Json;
      if (!mounted ||
          generation != widget.api.sessionGeneration ||
          !widget.api.authenticated) return;
      await widget.api
          .request('/me/notification-preferences', method: 'PATCH', body: {
        'expected_version': user['version'],
        'preferences': {...preferences, 'marketing': marketing}
      });
      if (mounted &&
          generation == widget.api.sessionGeneration &&
          widget.api.authenticated) widget.onAccepted();
    } catch (e) {
      if (mounted) setState(() => error = e);
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
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                        onPressed: enabled ? submit : null,
                        child: const UiText('Принять и продолжить')))))
      ]);
}
