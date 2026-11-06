import 'package:flutter/widgets.dart';
import '../core/l10n.dart';

String referralTerms(BuildContext context, Map<String, dynamic> policy) {
  String tr(String value) => localize(context, value);
  final capabilities = (policy['capabilities'] as List? ?? const [])
      .map((value) => tr(switch (value) {
            'search_full' => 'Полный поиск',
            'send_offer' => 'Отклики на заказы',
            'publish_profile' => 'Публикация профиля',
            _ => 'Привилегия доступа',
          }))
      .join(' · ');
  final seconds = policy['reward_duration_seconds'];
  final window = policy['attribution_window_days'];
  final event = switch (policy['qualifying_event']) {
    'registered' => tr('Регистрация и ввод кода'),
    'executor_verified' => tr('Проверка исполнителя'),
    'completed_order' => tr('Завершённый заказ'),
    _ => '—',
  };
  return [
    '${tr('Приглашений для награды')}: ${policy['threshold'] ?? '—'}',
    '${tr('Условие')}: $event',
    if(policy['reward_kind']=='discount') '${tr('Персональная скидка')}: ${policy['discount_percent']}%',
    if(policy['reward_kind']=='discount') (policy['discount_services'] as List? ?? []).map((v)=>switch(v){'all'=>'Все услуги','standard'=>'Стандарт','premium'=>'Премиум','customer'=>'Подписка заказчика','renewal'=>'Продление','upgrade'=>'Переход на Премиум','top100'=>'Топ-100','boost'=>'Продвижение',_=>'Услуга'}).join(' · '),
    if(policy['reward_kind']=='subscription_days') 'Бонусные дни: ${switch(policy['reward_plan']){'current'=>'Текущий тариф','standard'=>'Стандарт','premium'=>'Премиум','customer'=>'Подписка заказчика','top100'=>'Топ-100',_=>'Подписка'}}',
    if (capabilities.isNotEmpty) capabilities,
    if (seconds is num) '${tr(policy['reward_kind']=='discount'?'Срок скидки, мин':'Срок доступа, мин')}: ${seconds.toInt() ~/ 60}',
    if (window is num)
      '${tr('Код можно ввести после регистрации в течение')} ${window.toInt()} ${tr('суток')}',
  ].join('\n');
}

bool referralRewardAvailable(Map<String, dynamic> reward, DateTime now) {
  final expiry = DateTime.tryParse('${reward['expires_at'] ?? ''}');
  return reward['status'] == 'available' &&
      expiry != null &&
      expiry.isAfter(now);
}
