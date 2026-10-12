const { test } = require('node:test');
const assert = require('node:assert/strict');
const { DEMO_MONETIZATION_CONFIG: config, isMonetizationPolicy, canShowCheckout } = require('../dist');
test('synthetic config keeps subscriptions and covers independent ad switches', () => {
  assert.equal(config.demo, true);
  assert.equal(config.integrationsEnabled, false);
  assert.equal(config.preservePurchasedEntitlements, true);
  assert.equal(config.policies.length, 8);
  assert.ok(config.policies.every(p => p.subscription_enabled && isMonetizationPolicy(p)));
  assert.deepEqual(new Set(config.policies.map(p => `${p.banner_ads_enabled}/${p.rewarded_access_enabled}`)),
    new Set(['false/false', 'true/false', 'false/true', 'true/true']));
  assert.ok(Object.isFrozen(config.policies[0].rewardedAccess));
});
test('reject disabling subscription, legacy modes and malformed policies', () => {
  const base = config.policies[0];
  for (const value of [null, {}, { ...base, subscription_enabled: false },
    { ...base, mode: 'ads_only' }, { ...base, banner_ads_enabled: 'true' },
    { ...base, rewarded_access_enabled: null }, { ...base, version: 0 },
    { ...base, schemaVersion: 2 }, { ...base, scope: { country: 'US', role: 'provider' } },
    { ...base, scope: { country: 'RU', role: 'admin' } },
    { ...base, rewardedAccess: { kind: 'duration', seconds: -1 } },
    { ...base, rewardedAccess: { kind: 'quota', units: 1.5, unit: 'demo_action' } },
    { ...base, rewardedAccess: { kind: 'quota', units: 2, unit: 'money' } }]) {
    assert.equal(isMonetizationPolicy(value), false);
  }
});
test('unverified or unavailable country never exposes checkout', () => {
  for (const country of config.paymentAvailability) assert.equal(canShowCheckout(country, true), false);
  assert.equal(canShowCheckout({ country: 'RU', status: 'unavailable' }, true), false);
  assert.equal(canShowCheckout({ country: 'RS', status: 'available' }, false), false);
  assert.equal(canShowCheckout({ country: 'RS', status: 'available' }, true), true);
});
