import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/currency.dart';
import '../core/design_icons.dart';
import '../core/design_widgets.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class ContractorProfile extends StatelessWidget {
  final JobaApi api;
  final Json profile;
  final String locale;
  final ValueChanged<Json> onProject;
  final VoidCallback onInvite,
      onPortfolio,
      onReviews,
      onReport,
      onBlock,
      onOverview;
  const ContractorProfile(
      {required this.api,
      required this.profile,
      required this.onProject,
      required this.locale,
      required this.onInvite,
      required this.onOverview,
      required this.onPortfolio,
      required this.onReviews,
      required this.onReport,
      required this.onBlock,
      super.key});
  Widget stat(String value, String label) => Expanded(
          child: Column(children: [
        Text(value,
            style: const TextStyle(
                fontSize: 20, height: 1.3, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        UiText(label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 9, height: 1.5, color: muted))
      ]));
  @override
  Widget build(BuildContext context) {
    final rating = profile['rating'] as Json?;
    final verified = profile['verification']?['status'] == 'passed';
    final price = profile['price'] as Json?;
    return Column(children: [
      Expanded(
          child: ListView(children: [
        Container(
            color: Colors.white,
            child: Column(children: [
              SizedBox(
                  height: 114,
                  child: Stack(children: [
                    Container(height: 62, color: const Color(0xFFE5EDFC)),
                    Positioned(
                        top: 38,
                        left: 20,
                        child: JobaAvatar(
                            api: api,
                            name: profile['display_name'] ?? '',
                            id: profile['owner_avatar_id'],
                            size: 68))
                  ])),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(profile['display_name'] ?? '',
                            style: const TextStyle(
                                fontSize: 24,
                                height: 1.3,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('${profile['title']} · ${profile['city'] ?? ''}',
                            style: const TextStyle(fontSize: 12, color: muted)),
                        if (verified)
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Row(children: [
                                const JobaIcon('shield',
                                    size: 16, color: primary),
                                const SizedBox(width: 6),
                                const UiText('Документ проверен',
                                    style: TextStyle(
                                        fontSize: 11, color: primary)),
                                if (profile['verification']?['checked_at'] !=
                                    null) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                      DateFormat.yMd(locale).format(
                                          DateTime.parse(profile['verification']
                                                  ['checked_at'])
                                              .toLocal()),
                                      style: const TextStyle(
                                          fontSize: 10, color: muted))
                                ]
                              ])),
                        const SizedBox(height: 14),
                        Row(children: [
                          stat(
                              rating?['average'] == null
                                  ? '—'
                                  : '${NumberFormat('0.0', locale).format(rating!['average'])} ★',
                              '${rating?['count'] ?? 0} ${localize(context, 'отзывов')}'),
                          stat('${profile['completed_orders'] ?? 0}',
                              'заказов выполнено'),
                          stat(
                              profile['experience_years'] == null
                                  ? '—'
                                  : '${profile['experience_years']} ${localize(context, 'лет')}',
                              'Опыт со слов мастера')
                        ]),
                        const SizedBox(height: 14)
                      ])),
              Row(children: [
                Expanded(
                    child: TextButton(
                        onPressed: onOverview, child: const UiText('Обзор'))),
                Expanded(
                    child: TextButton(
                        onPressed: onPortfolio,
                        child: const UiText('Портфолио'))),
                Expanded(
                    child: TextButton(
                        onPressed: onReviews, child: const UiText('Отзывы')))
              ])
            ])),
        Padding(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(profile['title'] ?? '',
                  style: const TextStyle(
                      fontSize: 19, height: 1.4, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text(profile['description'] ?? '',
                  style:
                      const TextStyle(fontSize: 12, height: 1.6, color: muted)),
              const SizedBox(height: 20),
              Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: line),
                      borderRadius: BorderRadius.circular(16)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const UiText('Стоимость услуг',
                            style: TextStyle(fontSize: 12, color: muted)),
                        const SizedBox(height: 8),
                        Text(
                            price == null ||
                                    price['mode'] == 'negotiable' ||
                                    price['amount_min'] == null
                                ? localize(context, 'По договорённости')
                                : '${localize(context, 'От')} ${formatMoney((price['amount_min'] as num).toInt(), price['currency'] ?? 'KZT', locale)}',
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w700))
                      ])),
              JobaSection('Последние работы', onPortfolio,
                  action: profile['portfolio_count'] == null
                      ? 'Все'
                      : '${localize(context, 'Все')} ${profile['portfolio_count']}'),
              ApiView(
                  load: () => api.request(
                      '/contractors/${profile['id']}/portfolio',
                      query: const {'limit': 2}),
                  builder: (context, data, reload) => Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < items(data).length; i++) ...[
                              if (i > 0) const SizedBox(width: 12),
                              Expanded(
                                  child: Material(
                                      color: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          side: const BorderSide(color: line)),
                                      child: InkWell(
                                          onTap: () =>
                                              onProject(items(data)[i]),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                if ((items(data)[i]['photos']
                                                            as List? ??
                                                        [])
                                                    .isNotEmpty)
                                                  PrivatePhoto(
                                                      api: api,
                                                      id: items(data)[i]
                                                              ['cover_id'] ??
                                                          items(data)[i]
                                                              ['photos'][0],
                                                      height: 110,
                                                      onOpen: () => onProject(
                                                          items(data)[i])),
                                                Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            10),
                                                    child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                              items(data)[i][
                                                                      'title'] ??
                                                                  '',
                                                              style: const TextStyle(
                                                                  fontSize: 12,
                                                                  height: 1.4,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700)),
                                                          const SizedBox(
                                                              height: 4),
                                                          Text(
                                                              items(data)[i][
                                                                          'linked_completed_order'] ==
                                                                      true
                                                                  ? localize(
                                                                      context,
                                                                      'Связано с завершённым заказом в JOBA')
                                                                  : localize(
                                                                      context,
                                                                      'Работа заявлена исполнителем'),
                                                              style:
                                                                  const TextStyle(
                                                                      color:
                                                                          muted,
                                                                      fontSize:
                                                                          10))
                                                        ]))
                                              ]))))
                            ]
                          ])),
              const SizedBox(height: 12),
              JobaMenu([
                JobaMenuEntry('Пожаловаться', 'shield', onReport),
                JobaMenuEntry('Заблокировать контакт', 'lock', onBlock)
              ])
            ]))
      ])),
      SafeArea(
          top: false,
          child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed:
                          profile['availability'] == 'paused' ? null : onInvite,
                      child: const UiText('Предложить заказ')))))
    ]);
  }
}
