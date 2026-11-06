import 'api.dart';

/// Device/provider operations are injected when the real integration is supplied.
abstract class CommerceGateway {
  const CommerceGateway();
  Future<Json> purchase(Json offer);
  Future<List<Json>> restore();
  Future<void> manage(Json subscription);
  Future<bool> playReward(Json session);
}

class DisconnectedCommerceGateway extends CommerceGateway {
  const DisconnectedCommerceGateway();
  Never missing() =>
      throw ApiException('PROVIDER_UNAVAILABLE', 'Провайдер ещё не подключён');
  @override
  Future<Json> purchase(Json offer) async => missing();
  @override
  Future<List<Json>> restore() async => missing();
  @override
  Future<void> manage(Json subscription) async => missing();
  @override
  Future<bool> playReward(Json session) async => missing();
}
