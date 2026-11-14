import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/design_states.dart';
import '../core/widgets.dart';

enum ReceiptKind { published, offer, review }

class ActionReceipt extends StatelessWidget {
  final JobaApi api;
  final String id;
  final ReceiptKind kind;
  final VoidCallback onOrders, onOffers, onJobs;
  final ValueChanged<String> onOrder;
  const ActionReceipt(
      {required this.api,
      required this.id,
      required this.kind,
      required this.onOrders,
      required this.onOffers,
      required this.onJobs,
      required this.onOrder,
      super.key});
  @override
  Widget build(BuildContext context) => ApiView(
      key: ValueKey('${kind.name}:$id'),
      load: () => api
          .request(kind == ReceiptKind.offer ? '/offers/$id' : '/orders/$id'),
      builder: (context, data, reload) {
        final row = data as Json;
        if (kind == ReceiptKind.published) {
          final open = row['status'] == 'open' &&
              !['hidden', 'quarantined', 'rejected']
                  .contains(row['moderation_status']);
          final pending = row['status'] == 'pending_moderation' ||
              row['moderation_status'] == 'quarantined';
          return ListView(padding: const EdgeInsets.all(20), children: [
            JobaStatePanel(
                brand: true,
                icon: 'check',
                title: open
                    ? 'Заказ на виду'
                    : pending
                        ? 'Заказ на проверке'
                        : 'Статус заказа изменился',
                message: open
                    ? 'Заказ опубликован. Здесь будут появляться отклики специалистов.'
                    : pending
                        ? 'Заказ сохранён и ожидает проверки. Статус доступен в ваших заказах.'
                        : 'Откройте заказ, чтобы посмотреть актуальное состояние.',
                primaryLabel: open ? 'Посмотреть отклики' : 'Открыть заказ',
                onPrimary: open ? onOffers : () => onOrder(id),
                secondaryLabel: 'Мои заказы',
                onSecondary: onOrders)
          ]);
        }
        if (kind == ReceiptKind.offer) {
          final active =
              row['status'] == 'active' && row['order']?['status'] == 'open';
          return ListView(padding: const EdgeInsets.all(20), children: [
            JobaStatePanel(
                title: active
                    ? 'Предложение\nу заказчика'
                    : 'Статус отклика изменился',
                message: active
                    ? 'Заказчик сможет уточнить детали и выбрать вас. Договорённость ещё не подтверждена.'
                    : 'Откройте заказ, чтобы посмотреть актуальное состояние отклика.',
                icon: 'send',
                primaryLabel: active ? 'К подходящим заказам' : 'Открыть заказ',
                onPrimary: active ? onJobs : () => onOrder(row['order_id']))
          ]);
        }
        final review = row['my_review'];
        if (review == null)
          return ListView(padding: const EdgeInsets.all(20), children: [
            JobaStatePanel(
                title: 'Отзыв не найден',
                message:
                    'Откройте заказ, чтобы проверить возможность оставить отзыв.',
                icon: 'info',
                primaryLabel: 'Открыть заказ',
                onPrimary: () => onOrder(id))
          ]);
        final published = review['status'] == 'published' &&
            !['hidden', 'quarantined', 'rejected']
                .contains(review['moderation_status']);
        final sealed = review['status'] == 'sealed' &&
            !['hidden', 'quarantined', 'rejected']
                .contains(review['moderation_status']);
        return ListView(padding: const EdgeInsets.all(20), children: [
          JobaStatePanel(
              title: 'Спасибо за отзыв',
              message: published
                  ? 'Ваш отзыв опубликован.'
                  : sealed
                      ? 'Ваша оценка появится после встречного отзыва или окончания окна оценок. Пока она скрыта от другой стороны.'
                      : 'Отзыв сохранён. Актуальный статус доступен в заказе.',
              icon: 'star',
              iconColor: const Color(0xFFB98712),
              iconFill: const Color(0xFFFFD65A),
              primaryLabel: 'Мои заказы',
              onPrimary: onOrders)
        ]);
      });
}
