import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'banner_policy.dart';
import 'google_banner.dart';
import 'package:flutter/material.dart';
import 'package:yandex_mobileads/mobile_ads.dart';
import '../core/api.dart';
import '../core/external_activity.dart';

String get _platform => Platform.isIOS ? 'ios' : 'android';
String _message(Object e) => e is ApiException
    ? e.message
    : 'Реклама сейчас недоступна. Попробуйте позже.';

class WebAdsPanel extends StatefulWidget {
  final JobaApi api;
  final VoidCallback onReward;
  final VoidCallback? onPrivacy;
  final bool compact;
  const WebAdsPanel(
      {required this.api,
      required this.onReward,
      this.onPrivacy,
      this.compact = false,
      super.key});
  @override
  State<WebAdsPanel> createState() => _BannerState();
}

// Keep one SDK platform view per signed-in shell and contain async cleanup.
Future<void>? _adsInitialization;
Future<void> _initializeAds() async {
  final future = _adsInitialization ??= YandexAds.initialize();
  try {
    await future.timeout(const Duration(seconds: 20));
  } catch (_) {
    if (identical(_adsInitialization, future)) _adsInitialization = null;
    rethrow;
  }
}

void _releaseAd(Future<void> Function() release) {
  Future<void>.sync(release).catchError((Object _) {});
}

class _BannerState extends State<WebAdsPanel> {
  Json? config;
  List<String> networks = [];
  int index = 0;
  @override
  void initState() {
    super.initState();
    final generation = widget.api.sessionGeneration;
    widget.api.request('/me/web-ads').then((c) {
      if (!mounted || generation != widget.api.sessionGeneration) return;
      setState(() {
        config = Json.from(c);
        networks = nativeBannerNetworks(config!,
            android: Platform.isAndroid,
            googleFirst: Random.secure().nextBool());
      });
    }).catchError((Object _) {});
  }

  void fallback() {
    if (mounted) setState(() => index++);
  }

  @override
  Widget build(BuildContext context) {
    if (index >= networks.length || MediaQuery.sizeOf(context).width < 320) {
      return const SizedBox.shrink();
    }
    return networks[index] == 'google'
        ? GoogleBanner(
            unitId: config!['admob_android_banner_id'],
            personalized: config!['consent'] == true,
            onFailed: fallback)
        : _YandexBanner(api: widget.api, onFailed: fallback);
  }
}

class _YandexBanner extends StatefulWidget {
  final JobaApi api;
  final VoidCallback onFailed;
  const _YandexBanner({required this.api, required this.onFailed});
  @override
  State<_YandexBanner> createState() => _YandexBannerState();
}

class _YandexBannerState extends State<_YandexBanner> {
  BannerAd? ad;
  bool failed = false, loading = false;
  StreamSubscription<BannerAdLoadState>? states;
  void fail() {
    if (!mounted || failed) return;
    setState(() => failed = true);
    widget.onFailed();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ad == null && !failed) load();
  }

  Future<void> load() async {
    if (loading) return;
    loading = true;
    BannerAd? created;
    final api = widget.api, generation = widget.api.sessionGeneration;
    bool current() =>
        mounted &&
        identical(api, widget.api) &&
        generation == api.sessionGeneration;
    try {
      final c = await api.request('/me/web-ads');
      final id = c['${_platform}_banner_id'];
      if (!current() ||
          c['enabled'] != true ||
          c['consent_recorded'] == true && c['consent'] != true ||
          id is! String ||
          id.isEmpty) return;
      await _initializeAds();
      await YandexAds.setUserConsent(c['consent'] == true);
      if (!current()) return;
      final width = MediaQuery.sizeOf(context).width.floor().clamp(1, 1200);
      final banner =
          BannerAd(adSize: BannerAdSize.inline(width: width, maxHeight: 50));
      created = banner;
      await banner.load(AdRequest(adUnitId: id));
      if (!current()) {
        _releaseAd(banner.destroy);
        created = null;
        return;
      }
      states = banner.loadStateStream.listen((state) {
        if (state is BannerAdLoadStateError) fail();
      }, onError: (Object _) => fail());
      setState(() => ad = banner);
      created = null;
    } catch (_) {
      if (current()) fail();
    } finally {
      if (created != null) _releaseAd(created.destroy);
      loading = false;
    }
  }

  @override
  void dispose() {
    states?.cancel();
    final banner = ad;
    ad = null;
    if (banner != null) _releaseAd(banner.destroy);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ad == null || failed
      ? const SizedBox.shrink()
      : SizedBox(height: 50, child: ClipRect(child: AdWidget(bannerAd: ad!)));
}

class WebRewardEntry extends StatefulWidget {
  final JobaApi api;
  final void Function(String) onSelect;
  final String? target;
  const WebRewardEntry(
      {required this.api, required this.onSelect, this.target, super.key});
  @override
  State<WebRewardEntry> createState() => _EntryState();
}

class _EntryState extends State<WebRewardEntry> {
  Json? config;
  @override
  void initState() {
    super.initState();
    widget.api.request('/me/web-ads').then((c) {
      if (mounted) setState(() => config = Json.from(c));
    }).catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final c = config;
    if (c?['rewarded_enabled'] != true) return const SizedBox.shrink();
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Подписка за рекламу',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  for (final o in (c!['offers'] as List? ?? []))
                    if (widget.target == null || widget.target == o['target'])
                      OutlinedButton(
                          onPressed: () => widget.onSelect(o['target']),
                          child: Text(
                              '${o['title']} · ${o['completed_views']}/${o['required_views']} просмотров · 30 дней'))
                ])));
  }
}

class WebRewardScreen extends StatefulWidget {
  final JobaApi api;
  final VoidCallback? onPrivacy;
  final void Function(String)? onNavigate;
  final String? target;
  const WebRewardScreen(
      {required this.api,
      this.onPrivacy,
      this.onNavigate,
      this.target,
      super.key});
  @override
  State<WebRewardScreen> createState() => _RewardState();
}

class _RewardState extends State<WebRewardScreen> {
  Json? config, pending;
  bool? completed;
  String? selected, message;
  bool busy = false;
  List<Json> get offers =>
      (config?['offers'] as List? ?? []).map((o) => Json.from(o)).toList();
  Json? get offer =>
      offers
          .where((o) => o['target'] == (selected ?? widget.target))
          .firstOrNull ??
      offers.firstOrNull;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final c = await widget.api.request('/me/web-ads');
      if (mounted) setState(() => config = Json.from(c));
    } catch (e) {
      if (mounted) setState(() => message = _message(e));
    }
  }

  Future<void> confirm() async {
    final s = pending!;
    final result = await widget.api.request(
        '/me/web-ads/reward-sessions/${s['id']}/outcome',
        method: 'POST',
        body: {'nonce': s['nonce'], 'completed': completed});
    if (!mounted) return;
    setState(() {
      pending = null;
      completed = null;
      message = result['status'] == 'granted'
          ? 'Подписка активирована на 30 дней. Деньги не списывались.'
          : result['status'] == 'progress'
              ? 'Засчитано ${result['completed_views']} из ${result['required_views']} просмотров.'
              : result['message'] ??
                  'Ролик не завершён. Прогресс не изменился.';
    });
    await load();
  }

  Future<void> play() async {
    if (busy || offer == null) return;
    setState(() => busy = true);
    final api = widget.api, generation = api.sessionGeneration;
    bool current() =>
        mounted && api.authenticated && generation == api.sessionGeneration;
    RewardedAdLoader? loader;
    RewardedAd? ad;
    try {
      if (pending != null) {
        await confirm();
        return;
      }
      if (offer!['ready'] == true) {
        final r = await api.request('/me/web-ads/redeem',
            method: 'POST', body: {'target': offer!['target']});
        if (current())
          setState(() => message = r['status'] == 'granted'
              ? 'Подписка активирована на 30 дней.'
              : r['message']);
        await load();
        return;
      }
      if (config?['consent'] != true)
        await api.request('/me/web-ads/consent',
            method: 'POST', body: {'accepted': true});
      await _initializeAds();
      if (!current()) return;
      await YandexAds.setUserConsent(true);
      final s = Json.from(await api.request('/me/web-ads/reward-sessions',
          method: 'POST',
          body: {'platform': _platform, 'target': offer!['target']}));
      if (!current()) return;
      pending = s;
      completed = false;
      loader = RewardedAdLoader();
      ad = await loader
          .loadAd(adRequest: AdRequest(adUnitId: s['block_id']))
          .timeout(const Duration(seconds: 45));
      if (!current()) return;
      await ad.setAdEventListener(
          eventListener: RewardedAdEventListener(onRewarded: (_) {
        completed = true;
      }));
      await withExternalActivity(() async {
        await ad!.show();
        await ad.waitForDismiss();
      });
      if (current()) await confirm();
    } catch (e) {
      if (current()) setState(() => message = _message(e));
    } finally {
      ad?.destroy();
      loader?.destroy();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = offer;
    return ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Подписка за рекламу',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      if (o != null) ...[
        DropdownButtonFormField<String>(
            initialValue: o['target'],
            items: offers
                .map((v) => DropdownMenuItem<String>(
                    value: v['target'], child: Text('${v['title']} · 30 дней')))
                .toList(),
            onChanged: busy || pending != null
                ? null
                : (v) => setState(() => selected = v)),
        Text(
            'Завершено ${o['completed_views']} из ${o['required_views']} просмотров'),
        const Text(
            'Подписка и Топ-100 выдаются отдельно после всех завершённых просмотров. Неполный ролик не засчитывается.'),
        if (o['reason'] != null) Text(o['reason'])
      ],
      if (config == null && message == null)
        const Center(child: CircularProgressIndicator()),
      FilledButton(
          onPressed: busy ||
                  o == null ||
                  (pending == null &&
                      (config?['rewarded_enabled'] != true ||
                          o['eligible'] != true))
              ? null
              : play,
          child: Text(busy
              ? 'Ожидаем завершения…'
              : pending != null
                  ? 'Повторить подтверждение просмотра'
                  : o?['ready'] == true
                      ? 'Активировать'
                      : 'Согласен, посмотреть ролик')),
      if (message != null) Text(message!),
      if (widget.onPrivacy != null)
        TextButton(
            onPressed: widget.onPrivacy, child: const Text('Документы JOBA')),
      if (widget.onNavigate != null)
        TextButton(
            onPressed: busy ? null : () => widget.onNavigate!('my-access'),
            child: const Text('Моя подписка')),
    ]);
  }
}
