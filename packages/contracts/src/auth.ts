/** Proposed policy only: no credential DTOs, tokens or real auth integration. */
export interface AuthPolicy {
  readonly schemaVersion: 1;
  readonly primaryLogin: 'phone_password';
  readonly phoneOwnership: 'unverified';
  readonly smsEnabled: false;
  readonly googleRequired: false;
  readonly appleRequired: false;
  readonly persistSession: true;
  readonly recovery: 'pending_decision';
  readonly phoneCanResetPassword: false;
}
export type LocalUnlockMethod = 'pin' | 'face_id' | 'touch_id' | 'android_biometric';
/** No biometric templates or PIN values may be sent to backend. */
export interface LocalUnlockState {
  readonly method: LocalUnlockMethod;
  readonly unlocked: boolean;
}
export type ServerSessionState = 'active' | 'expired' | 'revoked';
export const DEMO_AUTH_POLICY: Readonly<AuthPolicy> = Object.freeze({
  schemaVersion: 1, primaryLogin: 'phone_password', phoneOwnership: 'unverified',
  smsEnabled: false, googleRequired: false, appleRequired: false,
  persistSession: true, recovery: 'pending_decision', phoneCanResetPassword: false,
});
/** Client display guard only. API must independently validate session and permissions.
 * The active state must come from a trusted server check, not local unlock evidence.
 */
export function canOpenProtectedDemoScreen(
  session: ServerSessionState, localUnlock: LocalUnlockState, serverAccessAllowed: boolean,
): boolean {
  return session === 'active' && localUnlock.unlocked === true && serverAccessAllowed === true;
}
