import type { CountryCode } from './index';

export type MarketplaceRole = 'customer' | 'provider';
export type RewardedAccess =
  | { readonly kind: 'duration'; readonly seconds: number }
  | { readonly kind: 'quota'; readonly units: number; readonly unit: 'demo_action' };

/** Product switches do not prove purchase, ad completion or provider eligibility. */
export interface MonetizationPolicy {
  readonly schemaVersion: 1;
  readonly version: number;
  readonly scope: { readonly country: CountryCode; readonly role: MarketplaceRole };
  readonly subscription_enabled: true;
  readonly banner_ads_enabled: boolean;
  readonly rewarded_access_enabled: boolean;
  readonly rewardedAccess: RewardedAccess;
}

/** Provider eligibility is separate from policy. Unknown must never expose checkout. */
export interface CountryPaymentAvailability {
  readonly country: CountryCode;
  readonly status: 'unverified' | 'unavailable' | 'available';
}
export interface DemoMonetizationConfig {
  readonly demo: true;
  readonly integrationsEnabled: false;
  readonly preservePurchasedEntitlements: true;
  readonly policies: readonly MonetizationPolicy[];
  readonly paymentAvailability: readonly CountryPaymentAvailability[];
}
const countries: readonly CountryCode[] = ['RS', 'KZ', 'RU', 'BY'];
const roles: readonly MarketplaceRole[] = ['customer', 'provider'];
/** Synthetic examples only: all real provider eligibility remains unverified. */
export const DEMO_MONETIZATION_CONFIG: DemoMonetizationConfig = Object.freeze({
  demo: true,
  integrationsEnabled: false,
  preservePurchasedEntitlements: true,
  policies: Object.freeze(countries.flatMap((country, index) => roles.map(role => Object.freeze({
    schemaVersion: 1 as const, version: 1,
    scope: Object.freeze({ country, role }),
    subscription_enabled: true as const,
    banner_ads_enabled: index % 2 === 1,
    rewarded_access_enabled: index >= 2,
    rewardedAccess: Object.freeze(role === 'customer'
      ? { kind: 'duration' as const, seconds: 3600 }
      : { kind: 'quota' as const, units: 3, unit: 'demo_action' as const }),
  })))),
  paymentAvailability: Object.freeze(countries.map(country => Object.freeze({
    country, status: 'unverified' as const,
  }))),
});

/** Shape validation only; future writes still require authenticated authorization. */
export function isMonetizationPolicy(value: unknown): value is MonetizationPolicy {
  if (!value || typeof value !== 'object') return false;
  const policy = value as Record<string, unknown>;
  const scope = policy.scope as Record<string, unknown> | undefined;
  const reward = policy.rewardedAccess as Record<string, unknown> | undefined;
  const positiveInteger = (n: unknown) => typeof n === 'number' && Number.isSafeInteger(n) && n > 0;
  return policy.schemaVersion === 1 && positiveInteger(policy.version) &&
    !!scope && countries.includes(scope.country as CountryCode) &&
    roles.includes(scope.role as MarketplaceRole) &&
    policy.subscription_enabled === true && !('mode' in policy) &&
    typeof policy.banner_ads_enabled === 'boolean' &&
    typeof policy.rewarded_access_enabled === 'boolean' &&
    !!reward && ((reward.kind === 'duration' && positiveInteger(reward.seconds)) ||
      (reward.kind === 'quota' && positiveInteger(reward.units) && reward.unit === 'demo_action'));
}
/** Display guard only: real checkout also needs verified integration and server checks. */
export function canShowCheckout(availability: CountryPaymentAvailability, integrationsEnabled: boolean): boolean {
  return integrationsEnabled && availability.status === 'available';
}
