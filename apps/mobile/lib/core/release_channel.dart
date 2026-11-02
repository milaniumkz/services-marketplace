import 'package:flutter/foundation.dart';

/// Public pricing channel, never an authentication or identity credential.
const freeMobileRelease = !kIsWeb &&
    bool.fromEnvironment('JOBA_FREE_MOBILE', defaultValue: false);
const mobilePaidRoutes = {
  'access', 'my-access', 'checkout', 'test-payment-success', 'payment-pending',
  'manage-subscription', 'subscription-canceled', 'restore', 'reward',
  'reward-granted', 'reward-nofill', 'reward-pending', 'promotion',
  'promotion-checkout', 'promotion-no-slots', 'promotion-terms',
  'promotion-pending', 'promotion-resolution', 'promotion-history', 'referrals',
};
