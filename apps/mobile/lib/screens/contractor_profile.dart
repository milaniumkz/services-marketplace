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
  Widget stat(String value, String label,
          {bool first = false, bool star = false}) =>
      Expanded(
          child: Container(
              padding: EdgeInsets.only(left: first ? 0 : 16),
              decoration: BoxDecoration(
                  border: first
                      ? null
                      : const Border(left: BorderSide(color: line))),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(value,
                          style: const TextStyle(
                              fontSize: 18,
                              height: 1.3,
                              fontWeight: FontWeight.w700)),
                      if (star) ...[
                        const SizedBox(width: 5),
                        const JobaIcon('star',
                            size: 12,
                            color: Color(0xFFBD8B14),
                            fill: Color(0xFFBD8B14))
                      ]
                    ]),
                    const SizedBox(height: 8),
                    UiText(label,
                        style: const TextStyle(
                            fontSize: 9, height: 1.5, color: muted))
                  ])));
  Widget tab(String title, VoidCallback onTap, {bool selected = false}) =>
      Container(
          margin: const EdgeInsets.only(right: 22),
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: selected ? primary : Colors.transparent,
                      width: 2))),
          child: TextButton(
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 48),
                  foregroundColor: selected ? primary : muted,
                  textStyle: TextStyle(
                      fontFamily: 'Noto',
                      fontSize: 12,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w400)),
              onPressed: onTap,
              child: Text(title)));
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
                    SizedBox(
                        height: 62,
                        width: double.infinity,
                        child: CustomPaint(painter: _ProfileCover())),
                    Positioned(
                        top: 48,
                        right: 20,
                        child: IconButton.filledTonal(
                            tooltip: localize(context, 'Пожаловаться'),
                            style: IconButton.styleFrom(
                                backgroundColor: canvas,
                                minimumSize: const Size(48, 48),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14))),
                            onPressed: onReport,
                            icon: const JobaIcon('flag'))),
                    Positioned(
                        top: 38,
                        left: 20,
                        child: Container(
                            width: 68,
                            height: 68,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(28)),
                            child: JobaAvatar(
                                api: api,
                                name: profile['display_name'] ?? '',
                                id: profile['owner_avatar_id'],
                                size: 60)))
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
                                Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                        color: const Color(0xFFE8F5EF),
                                        borderRadius: BorderRadius.circular(7)),
                                    child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          JobaIcon('shield',
                                              size: 14,
                                              color: Color(0xFF147657)),
                                          SizedBox(width: 4),
                                          UiText('Документ проверен',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  height: 1.6,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF147657))),
                                        ])),
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
                                  : NumberFormat('0.0', locale)
                                      .format(rating!['average']),
                              '${rating?['count'] ?? 0} ${localize(context, 'отзывов')}',
                              first: true,
                              star: rating?['average'] != null),
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
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    tab(localize(context, 'Обзор'), onOverview, selected: true),
                    tab('${localize(context, 'Портфолио')}${profile['portfolio_count'] == null ? '' : ' · ${profile['portfolio_count']}'}',
                        onPortfolio),
                    tab(localize(context, 'Отзывы'), onReviews),
                  ])),
            ])),
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(profile['title'] ?? '',
                  style: const TextStyle(
                      fontSize: 16, height: 1.4, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(profile['description'] ?? '',
                  style:
                      const TextStyle(fontSize: 12, height: 1.6, color: muted)),
              const SizedBox(height: 20),
              Row(children: [
                const Expanded(
                    child: UiText('Стоимость услуг',
                        style: TextStyle(fontSize: 12, color: muted))),
                Text(
                    price == null ||
                            price['mode'] == 'negotiable' ||
                            price['amount_min'] == null
                        ? localize(context, 'По договорённости')
                        : '${localize(context, 'От')} ${formatMoney((price['amount_min'] as num).toInt(), price['currency'] ?? 'KZT', locale)}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ]),
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
                                                      height: 120,
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
              decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: line))),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed:
                          profile['availability'] == 'paused' ? null : onInvite,
                      child: const UiText('Предложить заказ')))))
    ]);
  }
}

class _ProfileCover extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFE5EDFC));
    canvas.drawCircle(
        Offset(size.width * .65, 0),
        size.width * .296,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 40
          ..color = const Color(0xFFD1E1FA));
  }

  @override
  bool shouldRepaint(covariant _ProfileCover oldDelegate) => false;
}
