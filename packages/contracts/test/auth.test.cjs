const { test } = require('node:test');
const assert = require('node:assert/strict');
const { DEMO_AUTH_POLICY: policy, canOpenProtectedDemoScreen } = require('../dist');
test('phone remains unverified; SMS and mandatory OAuth are disabled; recovery unresolved', () => {
  assert.equal(policy.primaryLogin, 'phone_password');
  assert.equal(policy.phoneOwnership, 'unverified');
  assert.equal(policy.smsEnabled, false);
  assert.equal(policy.googleRequired, false);
  assert.equal(policy.appleRequired, false);
  assert.equal(policy.phoneCanResetPassword, false);
  assert.equal(policy.recovery, 'pending_decision');
  assert.equal(policy.persistSession, true);
  assert.ok(Object.isFrozen(policy));
});
test('local PIN or biometrics never revive expired/revoked session or denied access', () => {
  for (const method of ['pin', 'face_id', 'touch_id', 'android_biometric']) {
    const unlocked = { method, unlocked: true };
    assert.equal(canOpenProtectedDemoScreen('revoked', unlocked, true), false);
    assert.equal(canOpenProtectedDemoScreen('expired', unlocked, true), false);
    assert.equal(canOpenProtectedDemoScreen('active', unlocked, false), false);
    assert.equal(canOpenProtectedDemoScreen('active', { method, unlocked: false }, true), false);
    assert.equal(canOpenProtectedDemoScreen('active', unlocked, true), true);
  }
});
