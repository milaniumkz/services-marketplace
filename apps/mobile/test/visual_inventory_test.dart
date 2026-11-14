import 'package:crypto/crypto.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/main.dart';
import 'package:services_marketplace/screens/marketplace.dart';

class _Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String value) async {}
  Future<void> clear() async {}
}

void main() {
  testWidgets(
      'visual inventory captures all 42 mobile roots with isolated API scenarios',
      (tester) async {
    final output = Platform.environment['JOBA_ALL_SCREENS_DIR'];
    if (output == null) return;
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    tester.view.padding = const FakeViewPadding(top: 86, bottom: 44);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    final font = FontLoader('Noto')
      ..addFont(rootBundle.load('assets/NotoSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/NotoSans-Bold.ttf'));
    await font.load();
    final material = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await material.load();
    final audit = jsonDecode((await tester.runAsync(
            () => File('../../docs/design/screen-audit.json').readAsString()))!)
        as Json;
    final source = (await tester
        .runAsync(() => File('lib/screens/marketplace.dart').readAsString()))!;
    final routes = RegExp(r"case '([^']+)':")
        .allMatches(source)
        .map((m) => m.group(1)!)
        .toSet();
    const aliases = {
      'verification-status': 'verification',
      'verification-review': 'verification',
      'verification-resubmit': 'verification',
      'redeem': 'referrals',
      'empty-search': 'catalog',
      'empty-orders': 'orders',
      'error': 'catalog',
      'offline': 'catalog',
      'loading': 'catalog',
      'session-expired': 'catalog',
      'photo-view': 'portfolio-project',
      'login-error': 'login',
      'appeal': 'case',
      'appeal-sent': 'case',
      'top-orders': 'top'
    };
    final roots = (audit['frames'] as List).cast<Json>().where((f) =>
        f['surface'] == 'mobile' &&
        (f['root'] == true ||
            routes.contains(f['design_route']) ||
            aliases.containsKey(f['design_route'])));
    final pictures = <String, List<int>>{};
    for (final name in ['interior', 'kitchen']) {
      final file = File(
          '${Platform.environment['JOBA_VISUAL_ASSETS_DIR'] ?? '/tmp'}/joba-visual-$name.png');
      if (await tester.runAsync(() => file.exists()) != true)
        throw StateError(
            'Prepare visual assets with scripts/prepare-visual-assets.py');
      if (await tester.runAsync(() => file.exists()) == true)
        pictures['visual-$name'] =
            (await tester.runAsync(() => file.readAsBytes()))!;
    }
    var route = 'home';
    Completer<http.Response>? pendingSearch;
    final user = <String, dynamic>{
      'id': 'visual-owner',
      'version': 1,
      'display_name': 'Дарья А.',
      'city': 'Алматы',
      'country': 'KZ',
      'locale': 'ru',
      'roles': ['customer', 'executor'],
      'active_role': 'customer',
      'verification': 'passed',
      'status': 'active',
      'phone': '+77000000001',
      'languages': ['ru']
    };
    Json order() => {
          'id': 'visual-object',
          'owner': route == 'order' ? 'visual-customer' : user['id'],
          if (route == 'review-sent')
            'my_review': {
              'id': 'visual-own-review',
              'owner': user['id'],
              'status': 'sealed',
              'rating': 5
            },
          'version': 1,
          'revision': 1,
          'status': route == 'review-sent'
              ? 'completed'
              : route == 'complete'
                  ? 'completion_requested'
                  : route == 'work' || route == 'cancel'
                      ? 'in_progress'
                      : route == 'publish'
                          ? 'draft'
                          : 'open',
          'title': 'Нужно покрасить комнату',
          'description':
              'Подготовить стены и покрасить комнату площадью 18 м². Материалы есть.',
          'city': 'Алматы',
          'category_id': 'repair',
          'currency': 'KZT',
          'budget_amount': 25000,
          'upload_ids': [],
          if(const ['offer','offers'].contains(route)) ...{'title':'Собрать кухню и подключить мойку','budget_amount':4500000},
          if(route == 'order') ...{'title':'Собрать кухню и подключить мойку','description':'Собрать прямую кухню длиной 2,8 м, установить столешницу и подключить мойку. Мебель уже доставлена. Нужны свои инструменты.','budget_amount':4500000,'upload_ids':['visual-kitchen'],'time_window':{'start_date':'2026-10-14','end_date':'2026-10-16','time_zone':'Asia/Almaty'}},
          if(route == 'complete') ...{ 'completion_upload_ids': ['visual-kitchen'], 'completion_note':'Всё собрано и подключено, проверил соединения. Фото результата приложил.', 'completion_requested_at':'2026-10-12T15:12:00Z', 'title':'Кухня готова'},
          'expires_at': '2027-01-01T12:00:00Z',
          'created_at': '2026-10-14T10:00:00Z',
          'work_mode': 'onsite',
          'country':'KZ',
          'offer_policy':{'time_zone':'Asia/Almaty','latest_expires_local':'2026-10-18T18:00'},
          'attributes': {},
          'customer': {'id': user['id'], 'display_name': 'Дарья А.'},
          'executor': {'id': 'visual-executor', 'display_name': 'Алексей К.'},
          'executor_id': 'visual-executor',
          'assignment': {
            'executor_id': 'visual-executor',
            'customer_id': user['id'],
            'offer_id': 'visual-offer',
            'order_revision': 1,
            'amount': 25000,
            'currency': 'KZT'
          }
        };
    final profile = {
      'id': 'visual-object',
      'owner': 'visual-executor',
      'version': 1,
      'status': 'published',
      'display_name': 'Алексей К.',
      'title': 'Ремонт и отделка',
      'description':
          'Аккуратный ремонт без лишних хлопот. Берусь за небольшие и комплексные задачи.',
      'city': 'Алматы',
      'rating': {'count': 32, 'average': 4.9},
      'price': {'amount_min': 750000, 'currency': 'KZT'},
      'verification': {
        'status': 'passed',
        'checked_at': '2026-09-12T12:00:00Z'
      },
      'completed_orders': 38,
      'portfolio_count': 2,
      'experience_years': 5,
      'gallery_ids': [],
      'category_ids': ['repair'],
      'availability': 'available',
      'languages': ['ru'],
      'work_modes': ['onsite'],
      'service_cities': ['Алматы']
    };
    final api = JobaApi('https://isolated-visual.example', vault: _Vault(),
        transport: MockClient((request) async {
      final path = request.url.path.replaceFirst('/api/v1', '');
      http.Response response(dynamic data) =>
          http.Response(jsonEncode({'data': data, 'meta': {}}), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
      if (path == '/auth/login' && route == 'login-error')
        return http.Response(
            '{"error":{"code":"RATE_LIMITED","message":"Слишком много попыток. Повторите позже.","details":{"retry_after_seconds":30}}}',
            429,
            headers: {'content-type': 'application/json; charset=utf-8'});
      if (path == '/auth/refresh' && route == 'session-expired')
        return http.Response(
            jsonEncode({
              'error': {
                'code': 'TOKEN_EXPIRED',
                'message': 'Session revoked in isolated test'
              }
            }),
            401);
      if (path == '/contractors') {
        if (route == 'loading') {
          pendingSearch = Completer<http.Response>();
          return pendingSearch!.future;
        }
        if (route == 'offline')
          throw http.ClientException('Isolated unavailable transport');
        if (route == 'error')
          return http.Response(
              jsonEncode({
                'error': {
                  'code': 'SERVER_ERROR',
                  'message': 'Isolated read failure'
                }
              }),
              500);
        if (route == 'session-expired')
          return http.Response(
              jsonEncode({
                'error': {
                  'code': 'TOKEN_EXPIRED',
                  'message': 'Isolated expired access'
                }
              }),
              401);
        if (route == 'empty-search') return response({'items': []});
      }
      if (path == '/me/orders' && route == 'empty-orders')
        return response({
          'items': [],
          'meta': {'has_any': false}
        });

      if (path.startsWith('/uploads/') && path.endsWith('/download')) {
        final id = path.split('/')[2];
        if (pictures.containsKey(id))
          return http.Response.bytes(pictures[id]!, 200,
              headers: {'content-type': 'image/png'});
      }
      if(path=='/order-invites/visual-object'||path=='/cancel-requests/visual-object')return response({'id':'visual-object','order_id':'visual-object','status':'pending','owner':user['id'],'version':1});
      if(path=='/me/conversations')return response({'items':[
        {'id':'visual-object','status':'working','peer':{'id':'visual-peer','display_name':'Алексей К.'},'order_id':'visual-object','order_title':'Сборка кухни','order_status':'in_progress','unread_count':2,'last_message':{'text':'Спасибо, до встречи!','created_at':'2026-10-15T09:32:00Z'}},
        {'id':'visual-second-chat','status':'open','peer':{'id':'visual-second-peer','display_name':'Николай С.'},'order_id':'visual-object','order_title':'Установка светильников','unread_count':0,'last_message':{'text':'Могу в пятницу после 14:00.','created_at':'2026-10-14T16:10:00Z'}}
      ]});
      if(path=='/conversations/visual-object')return response({'id':'visual-object','order_id':'visual-object','order_title':'Сборка кухни','order_status':'assigned','order_amount':4500000,'currency':'KZT','peer':{'id':'visual-peer','display_name':'Алексей М.'},'status':route == 'frozen-chat' ? 'frozen' : 'active','blocked':route == 'frozen-chat'});
      if(path=='/me/subscriptions/visual-object')return response({'id':'visual-object','status':route=='subscription-canceled'?'canceled_at_period_end':'active','valid_until':'2026-11-12T09:41:00Z','price':{'amount_minor':249000,'currency':'KZT','period':'month'}});
      if(path=='/me/purchase-checks/visual-object')return response({'id':'visual-object','status':'pending'});
      if(path=='/me/subscriptions')return response({'items':[{'id':'visual-object','status':'active','valid_until':'2026-11-12T09:41:00Z','price':{'amount_minor':249000,'currency':'KZT','period':'month'}}]});
      if(path=='/me/notifications') {
        final today=DateTime.now().toUtc();
        String at(int delta,int hour,int minute)=>DateTime.utc(today.year,today.month,today.day+delta,hour,minute).toIso8601String();
        return response({'items':[
          {'id':'visual-notice-1','type':'offer.created','title':'Новый отклик от Алексея','body':'Сборка кухни','created_at':at(0,9,24),'read':false,'category':'orders'},
          {'id':'visual-notice-2','type':'order.completion_requested','title':'Работа готова к приёмке','body':'Проверьте результат заказа','created_at':at(0,15,12),'read':true,'category':'orders'},
          {'id':'visual-notice-3','type':'support.message.created','title':'Поддержка ждёт ответ','body':'Обращение № 1032','created_at':at(0,10,45),'read':true,'category':'other'},
          {'id':'visual-notice-4','type':'verification.updated','title':'Документ проверен','body':'Теперь доступны функции исполнителя','created_at':at(-1,14,0),'read':true,'category':'account'},
          {'id':'visual-notice-5','type':'subscription.updated','title':'Ваша подписка активна','body':'Доступ до 12 ноября 2026','created_at':at(-1,13,0),'read':true,'category':'account'},
          {'id':'visual-notice-6','type':'portfolio.published','title':'Проект опубликован','body':'Гостиная в тёплых тонах','created_at':at(-1,12,0),'read':true,'category':'account'}
        ],'meta':{'read_before':today.toIso8601String(),'unread_count':1}});
      }
      if(path=='/me/entitlements')return response({'items':[{'id':'visual-access','source':'subscription','valid_until':'2026-11-12T09:41:00Z','capabilities':['search_full','send_offer','publish_profile']}]});
      if(path=='/billing/offers')return response({'items':[{'id':'visual-offer','title':'Полный доступ','amount_minor':249000,'currency':'KZT','period':'month','provider':'isolated','product_id':'monthly','product_type':'subscription'}]});
      if(path=='/ads/reward-sessions/visual-object')return response({'id':'visual-object','status':route=='reward-granted'?'granted':'pending','grant':route=='reward-granted'?{'valid_until':'2026-12-13T09:41:00Z','capabilities':['search_full']}:null});
      if(path=='/me/processing-consents')return response({'version':1,'marketing':false,'ad_personalization':false,'optional_analytics':false});
      if(path=='/me/deletion-preview')return response({'active_orders':2,'policy_ready':true,'grace_hours':24});
      if(path=='/me/orders' && route=='promotion') return response({'items':[{...order(),'id':'visual-order-target'}]});
      if(path=='/boost-offers')return response({'items':[{'id':'visual-price','amount_minor':199000,'currency':'KZT','period':'week','provider':'isolated','product_id':'boost'}],'placements':[{'id':'visual-placement','title':'Каталог услуг','payload':{'placement_id':'search.services.promoted','capacity':1}}]});
      if(path=='/contractors/map')return response({'items':[{...profile,'id':'visual-profile','display_name':'Алексей К.','public_location':{'latitude':43.24,'longitude':76.91,'approximate':true}}],'meta':{'map_provider_configured':false}});
      dynamic data = {'items': []};
      if (path == '/me')
        data = route == 'onboarding' ? {...user, 'display_name': 'Марина', 'roles': ['customer'], 'active_role': 'customer', 'verification': 'not_started'} : user;
      else if (path == '/cases/visual-object' ||
          path == '/cases/visual-object/appeals')
        data = {
          'id': 'visual-object',
          'owner': user['id'],
          'subject_user_id': user['id'],
          'version': path.endsWith('/appeals') ? 2 : 1,
          'status': path.endsWith('/appeals') ? 'appealed' : 'resolved',
          'decision': 'content_removed',
          'reason_code': 'dictionary_match',
          'description': 'Материал ограничен после проверки.',
          'upload_ids': []
        };
      else if (path == '/me/privacy-requests/visual-object')
        data = {
          'id': 'visual-object',
          'type': route=='delete-scheduled'?'delete':'export',
          'status': route=='delete-scheduled'?'scheduled':'processing',
          'execute_after':'2026-10-17T09:41:00Z',
          'download_available': false
        };
      else if (path == '/me/restrictions')
        data = {
          'items': [
            {
              'id': 'isolated-limit',
              'type': 'automatic_review',
              'ends_at': '2026-10-16T10:00:00Z',
              'reason': 'Проверка содержания',
              'case_id': 'visual-object',
              'case_status': 'resolved',
              'can_appeal': true
            }
          ],
          'meta': {'restricted': true, 'account_status': 'restricted'}
        };
      else if (path == '/public/config')
        data = {
          'countries': [
            {'code': 'KZ', 'name': 'Казахстан','stop_new_business':route=='country-unavailable'}
          ]
        };
      else if (path == '/legal/documents')
        data = {
          'items': [
            {
              'id': 'terms',
              'type': 'terms',
              'version': 1,
              'hash': 'terms-hash',
              'minimum_age': 18,
              'content': 'Изолированные условия для визуального теста.'
            },
            {
              'id': 'privacy',
              'type': 'privacy',
              'version': 1,
              'hash': 'privacy-hash',
              'content': 'Изолированная политика для визуального теста.'
            }
          ]
        };
      else if (path == '/me/security-policy')
        data = {'password_min':6,'password_max':128};
      else if (path == '/me/notification-preferences')
        data = {'marketing': false, 'chat': true, 'service': true};
      else if (path == '/catalog/categories')
        data = {
          'items': [
            for (final e in {
              'repair': 'Ремонт',
              'cleaning': 'Уборка',
              'transport': 'Перевозки',
              'beauty': 'Красота',
              'education': 'Обучение'
            }.entries)
              {
                'id': e.key,
                'name': e.value,
                'schema': {'properties': {}, 'required': []}
              }
          ]
        };
      else if (path == '/geo/cities')
        data = {
          'items': [
            for (final name in ['Алматы', 'Астана', 'Шымкент'])
              {'id': name, 'name': name, 'country': 'KZ'}
          ]
        };
      else if (path == '/me/overview')
        data = {
          'orders': {'active': 3, 'open': 1},
          'assigned_orders': {'active': 2},
          'invitations': {'pending': 1},
          'rating': {'average': 4.9, 'count': 32},
          'contractor': {'status': 'published'}
        };
      else if (path == '/me/contractor-profile')
        data = {
          'profile': {
            ...profile,
            'owner': user['id'],
            if (route == 'profile-pending') ...{
              'status': 'pending_review',
              'public_status': 'published',
              'public_visible': true
            }
          }
        };
      else if (path == '/contractors')
        data = {
          'items': [profile]
        };
      else if (path == '/contractors/visual-object')
        data = profile;
      else if (path == '/contractors/visual-object/portfolio')
        data = {
          'items': [
            {
              'id': 'visual-interior',
              'title': 'Гостиная в тёплых тонах',
              'description': 'Обновили отделку стен.',
              'photos': pictures.containsKey('visual-interior')
                  ? ['visual-interior']
                  : [],
              'linked_completed_order': true
            },
            {
              'id': 'visual-kitchen',
              'title': 'Кухня для семьи',
              'description': 'Собрали кухню.',
              'photos': pictures.containsKey('visual-kitchen')
                  ? ['visual-kitchen']
                  : [],
              'linked_completed_order': false
            }
          ]
        };
      else if (path == '/orders/visual-object')
        data = order();
      else if (path == '/offers/visual-object')
        data = {
          'id': 'visual-object',
          'version': 1,
          'status': 'active',
          'amount': 25000,
          'currency': 'KZT',
          'text': 'Готов выполнить в удобное время',
          'acknowledged_revision': 1,
          'order_id': 'visual-object',
          'order': {...order(), if(route=='offer-revision') 'revision':2, if(route=='select-contractor') 'title':'Сборка кухни'},
          if(route=='select-contractor') ...{'amount':4500000,'proposed_start_local':'2026-10-16T10:00','duration_minutes':300,'time_zone':'Asia/Almaty'},
          'executor': profile,
          if(route=='offer-revision') ...{'acknowledged_revision':3,'acknowledged_order':{'revision':3,'budget_amount':4500000,'currency':'KZT'},'order':{...order(),'revision':4,'title':'Сборка кухни','description':'Установить две настенные полки.','budget_amount':5000000}},
        };
      else if (path.endsWith('/offers'))
        data = {
          'items': [
            {
              'id': 'visual-offer',
              'owner': 'visual-executor',
              'version': 1,
              'order_id': 'visual-object',
              'order_revision': 1,
              'status': 'active',
              'amount': 25000,
              'currency': 'KZT',
              'text': 'Готов выполнить в удобное время',
              'contractor': profile,
              'executor': {...profile,'available':true,'verified':true,'rating':{'count':32,'average':4.9}},
              if(route=='offers') ...{'amount':4500000,'proposed_start_local':'2026-10-16T10:00','duration_minutes':300,'conversation_id':'visual-object'},
            }
          ]
        };
      else if (['/orders', '/me/orders', '/me/assigned-orders'].contains(path))
        data = {
          'items': [order()]
        };
      else if (path == '/me/portfolio-projects')
        data = {
          'items': [
            {
              'id': 'visual-object',
              'version': 1,
              'position': 0,
              'status': 'published',
              'title': 'Ремонт комнаты',
              'description': 'Покраска стен и отделка',
              'photos': []
            }
          ]
        };
      else if (path == '/me/portfolio-projects/visual-object')
        data = {
          'id': 'visual-object',
          'version': 1,
          'status':
              route == 'portfolio-pending' ? 'pending_review' : route == 'portfolio-edit' ? 'draft' : 'published',
          'public_status': 'published',
          'public_visible': true,
          'title': route == 'portfolio-edit' ? 'Гостиная в тёплых тонах' : 'Ремонт комнаты',
          'description': route == 'portfolio-edit' ? 'Обновили отделку стен, уложили покрытие и собрали мебель. Сохранили много света.' : 'Покраска стен и отделка',
          'category_id': 'repair',
          'rights_confirmed': true,
          'category_name': 'Ремонт',
          'linked_completed_order': true,
          'photos': ['visual-interior', 'visual-kitchen']
        };
      else if (path == '/me/boosts/visual-object')
        data={'id':'visual-object','title':'Ремонт и отделка','city':'Алматы','price':{'amount_minor':199000,'currency':'KZT','period':'week','time_zone':'Asia/Almaty'},'starts_local':'2026-10-12T14:41:00','ends_local':'2026-10-19T14:41:00','placement_id':'search.services.promoted','reservation_expires_at':DateTime.now().add(const Duration(minutes:10)).toIso8601String(),'starts_at':'2026-10-12T09:41:00Z','ends_at':'2026-10-19T09:41:00Z','status':route=='promotion-checkout'?'reserved':route=='promotion-resolution'?'resolution_required':'payment_pending','payment_confirmed':route=='promotion-resolution'};
      else if (path == '/me/boosts')
        data={'items':[{'id':'visual-object','status':'active','title':'Ремонт и отделка','city':'Алматы','placement_id':'search.services.promoted','provenance':'paid','payment_confirmed':true,'starts_at':'2026-10-12T10:00:00Z','ends_at':'2026-10-19T10:00:00Z','price':{'amount_minor':199000,'currency':'KZT'}}]};
      else if (path == '/me/sessions')
        data = {'items':[{'family':'visual-current','current':true,'expires_at':'2026-11-15T12:00:00Z'}, {'family':'visual-object','current':false,'expires_at':'2026-11-15T12:00:00Z'}]};
      else if (path == '/top-listings')
        data = {'items': [
          for (final entry in ['Алексей К.', 'Николай С.'].indexed)
            {'id':'visual-top-${entry.$1}', 'title': request.url.queryParameters['target_type'] == 'orders' ? 'Нужно покрасить комнату' : entry.$1 == 0 ? 'Ремонт и отделка' : 'Сантехника и электрика',
             'display_name':entry.$2, 'city':'Алматы', 'likes':entry.$1 == 0 ? 128 : 96, 'dislikes':entry.$1 == 0 ? 4 : 2,
             'my_vote':null, 'rating':{'average':4.9,'count':32}}
        ], 'promotions': [], 'meta':{'calculated_at':'2026-10-15T09:40:00Z'}};
      else if (path == '/me/referrals')
        data = {
          'code': 'JOBA-VISUAL',
          'campaigns': [
            {
              'threshold': 1,
              'qualifying_event': 'completed_order',
              'reward_duration_seconds': 259200
            }
          ],
          'attributions': [
            {'status': 'pending'}
          ],
          'rewards': []
        };
      else if (path == '/me/verification')
        data = {
          'status': route == 'verification-status'
              ? 'passed'
              : route == 'verification-review'
                  ? 'pending_review'
                  : route == 'verification-resubmit'
                      ? 'rejected'
                      : 'not_started',
          'policy': {
            'id': 'visual-policy',
            'version': 1,
            'document_id': 'legal',
            'document_types': ['id_card', 'passport'],
            'required_pages': {
              'id_card': ['Лицевая и оборотная сторона'],
              'passport': ['Только страница с данными']
            },
            'consent_accepted': false
          },
          'items': route.startsWith('verification-')
              ? [
                  {
                    'id': 'visual-check',
                    'created_at': '2026-09-12',
                    'version': 1,
                    'status': route == 'verification-status'
                        ? 'passed'
                        : route == 'verification-review'
                            ? 'pending_review'
                            : 'rejected',
                    'document_type': 'id_card',
                    'required_pages': ['Лицевая сторона', 'Оборотная сторона'],
                    'decided_at': '2026-09-12T12:00:00Z',
                    'expires_at': '2027-09-12T12:00:00Z',
                    'reason':
                        'Не удаётся прочитать документ: блик закрывает часть текста.'
                  }
                ]
              : []
        };
      else if (path == '/me/cases/overview')
        data = {'open': 1, 'resolved': 0};
      else if (path == '/me/monetization-config')
        data = {
          'subscription_enabled': true,
          'rewarded_access_enabled': false,
          'reward_provider_ready':false,
          'reward_policy':{'kind':'duration','duration_seconds':86400},
          'reward_usage':{'used_today':2,'daily_cap':3,'remaining_today':1},
          'checkout_enabled': false,
          'offers': [{'id':'visual-offer','product_type':'subscription','amount_minor':249000,'currency':'KZT','period':'month'}]
        };
      else if (path.endsWith('/messages'))
        data = {
          'items': route == 'chat' ? [
            {'id':'visual-message-1','owner':'visual-peer','sequence':1,'text':'Здравствуйте! Смогу приехать завтра к 10:00.','created_at':'2026-10-12T09:24:00Z','upload_ids':[],'delivery_state':'read'},
            {'id':'visual-message-2','owner':'visual-owner','sequence':2,'text':'Здравствуйте! Отлично, буду ждать. Инструменты у вас с собой?','created_at':'2026-10-12T09:25:00Z','upload_ids':[],'delivery_state':'read'},
            {'id':'visual-message-3','owner':'visual-peer','sequence':3,'text':'Да, всё необходимое возьму с собой. Пришлите, пожалуйста, фото кухни.','created_at':'2026-10-12T09:26:00Z','upload_ids':[],'delivery_state':'read'},
          ] : [],
          'meta': {'has_more': false, 'server_time': '2026-10-14T12:00:00Z'}
        };
      return http.Response(jsonEncode({'data': data, 'meta': {}}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    final boundary = GlobalKey();
    await tester
        .pumpWidget(RepaintBoundary(key: boundary, child: JobaApp(api: api)));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(Marketplace));
    api.session = {'access_token': 'isolated-visual-token', 'user': user};
    state.me = user;
    final results = <Json>[];
    final stateDigests = <String, String>{};
    await tester.runAsync(() => Directory(output).create(recursive: true));
    for (final frame in roots) {
      route = frame['design_route'];
      if (!api.authenticated) {
        await api.forget();
        await tester.pumpAndSettle();
        api.session = {'access_token': 'isolated-visual-token', 'user': user};
        state.me = user;
      }
      if (route == 'session-expired')
        api.session = {
          'access_token': 'isolated-expired-token',
          'refresh_token': 'isolated-revoked-refresh',
          'user': user
        };
      state.ordersHasAny = null;
      state.ordersBucket = 'active';

      Navigator.of(state.context).popUntil((route) => route.isFirst);
      state.recovery = {
        'id': 'visual-recovery',
        'capability': 'isolated-visual-capability'
      };
      state.registrationInProgress = route == 'terms';
      // Isolated S36 reference state: cached account only; two entered digits are not runtime defaults.
      api.session!['user'] = route == 'unlock' ? {...user, 'display_name': 'Марина П.'} : user;
      state.listingFilters = route == 'filters'
          ? <String, dynamic>{
              'city': 'Алматы',
              'work_mode': 'onsite',
              'price_max': 5000000,
              'rating_min': '4.8'
            }
          : route == 'loading'
              ? <String, dynamic>{'q': 'Ремонт и отделка'}
              : <String, dynamic>{};
      state.executor = route == 'executor-home' || const ['notifications','order','access','my-access','checkout','manage-subscription','subscription-canceled','payment-pending','restore','reward','reward-granted','reward-nofill','reward-pending'].contains(route);
      user['active_role'] = state.executor ? 'executor' : 'customer';
      state.objectId = 'visual-object';
      state.history.clear();
      if (route == 'redeem') {
        state.go('referrals');
        await tester.pumpAndSettle();
        state.enterReferralCode();
      } else {
        state.go(
            frame['native_route'] ?? aliases[route] ?? route,
            route == 'checkout' ? 'visual-offer' : 'visual-object');
      }
      final errors = <String>[];
      try {
        await tester.pumpAndSettle();
        if(route=='offer') {
          await tester.enterText(find.byKey(const ValueKey('offer-note')),'Здравствуйте! Соберу кухню и подключу мойку. Все инструменты привезу с собой.');
          await tester.enterText(find.byKey(const ValueKey('offer-price')),'45000');
          await tester.tap(find.text('Выберите дату'));await tester.pumpAndSettle();
          Navigator.of(tester.element(find.byType(DatePickerDialog))).pop(DateTime(2026,10,16));await tester.pumpAndSettle();
          await tester.ensureVisible(find.byKey(const ValueKey('offer-duration')));await tester.enterText(find.byKey(const ValueKey('offer-duration')),'5');
          FocusManager.instance.primaryFocus?.unfocus();await tester.pumpAndSettle();
          await tester.scrollUntilVisible(find.byType(CheckboxListTile),150,scrollable:find.byType(Scrollable).first);await tester.tap(find.byType(CheckboxListTile));await tester.pumpAndSettle();
          await tester.drag(find.byType(Scrollable).first,const Offset(0,1600));await tester.pumpAndSettle();
        }
        if(route=='pin-setup'){await tester.enterText(find.byKey(const ValueKey('secure-pin-input')),'123456');FocusManager.instance.primaryFocus?.unfocus();await tester.pumpAndSettle();}
        if(route=='biometric'){await tester.tap(find.text('Включить биометрию'));await tester.pumpAndSettle();}
        if (route == 'top-orders') {
          await tester.tap(find.text('Заказы'));
          await tester.pumpAndSettle();
        }
        if (route == 'profile-pending')
          expect(find.text('Получили изменения'), findsOneWidget);
        if (route == 'portfolio-pending')
          expect(find.text('Проверяем ваш проект'), findsOneWidget);
        if (route == 'published')
          expect(find.text('Заказ на виду'), findsOneWidget);
        if (route == 'offer-sent')
          expect(find.text('Предложение\nу заказчика'), findsOneWidget);
        if (route == 'review-sent')
          expect(find.text('Спасибо за отзыв'), findsOneWidget);
        if (route == 'appeal' || route == 'appeal-sent') {
          await tester.tap(find.text('Обжаловать решение'));
          await tester.pumpAndSettle();
          if (route == 'appeal-sent') {
            await tester.enterText(find.byType(TextFormField),
                'Прошу пересмотреть решение по материалу.');
            await tester.tap(find.text('Отправить апелляцию'));
            await tester.pumpAndSettle();
          }
        }
        if (route == 'login-error') {
          final fields = find.byType(TextFormField);
          await tester.enterText(fields.at(0), '+77000000001');
          await tester.enterText(fields.at(1), 'Isolated rejected password');
          await tester.tap(find.text('Войти'));
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
        }
        if (route == 'promotion') {
          await tester.tap(find.byType(DropdownButtonFormField<String>).first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Ремонт и отделка').last);
          await tester.pumpAndSettle();
        }
        if (route == 'photo-view') {
          await tester.tap(find.text('Увеличить'));
          await tester.pumpAndSettle();
        }
        if (route == 'support-new') {
          await tester.tap(find.text('Без связи с заказом'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Нужно покрасить комнату'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextFormField),
              'Здравствуйте! Хочу уточнить, как запросить доработку результата.');
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
        }
        // Image decoding runs outside the widget test's fake clock. Wait for
        // the actual image providers before exporting a supposedly ready frame.
        for (final photo in tester.widgetList<Image>(find.byType(Image))) {
          await tester.runAsync(() => precacheImage(photo.image, state.context,
              onError: (error, stack) => errors.add('$error')));
        }
        await tester.pumpAndSettle();
      } catch (e) {
        errors.add('$e');
      }
      if (route == 'unlock') {
        await tester.tap(find.byKey(const ValueKey('unlock-key-1')));
        await tester.tap(find.byKey(const ValueKey('unlock-key-2')));
        await tester.pumpAndSettle();
      }
      Object? issue;
      while ((issue = tester.takeException()) != null) {
        errors.add('$issue');
      }
      final filename = '${frame['id']}-${frame['design_route']}.png';
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if ([
          'empty-search',
          'empty-orders',
          'error',
          'offline',
          'loading',
          'session-expired'
        ].contains(route))
          stateDigests[route] =
              sha256.convert(bytes!.buffer.asUint8List()).toString();
        await File('$output/$filename')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      if (pendingSearch != null && !pendingSearch!.isCompleted) {
        pendingSearch!.complete(http.Response(
            jsonEncode({
              'data': {'items': []},
              'meta': {}
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'}));
        await tester.pumpAndSettle();
        pendingSearch = null;
      }
      results.add({
        'id': frame['id'],
        'route': frame['design_route'],
        'capture': filename,
        'reference_png': frame['reference_png'],
        'actual_route': route == 'session-expired'
            ? state.route
            : frame['native_route'] ?? aliases[route] ?? route,
        'errors': errors,
        'visual_acceptance': 'pending'
      });
    }
    expect(stateDigests.length, 6);
    expect(stateDigests.values.toSet().length, 6,
        reason:
            'Distinct API states must not reuse a stale search widget capture');
    await tester.pumpWidget(const SizedBox());
    api.dispose();
    await tester.runAsync(() => File('$output/inventory.json').writeAsString(
            const JsonEncoder.withIndent('  ').convert({
          'scenario': 'isolated API fixtures; not production data',
          'frames': results
        })));
    expect(
        results
            .where((r) =>
                roots.any((f) => f['id'] == r['id'] && f['root'] == true))
            .length,
        42);
    expect(
        results
            .where((r) => (r['errors'] as List).isNotEmpty)
            .map((r) => '${r['id']}: ${r['errors']}')
            .toList(),
        isEmpty);
  }, skip: Platform.environment['JOBA_ALL_SCREENS_DIR'] == null);
}
