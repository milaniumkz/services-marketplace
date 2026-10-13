/** Provider implementations must verify server evidence. Client callbacks are never proof. */
export interface VerifiedPurchase {
  provider: string; transaction_id: string; original_transaction_id: string;
  user_id: string; country: string; product_id: string; environment: 'sandbox' | 'production';
  amount_minor: number; currency: string; valid_until: string;
  state: 'active' | 'grace' | 'billing_retry' | 'paused' | 'expired' | 'revoked' | 'canceled_at_period_end';
  revision: number;
}
export interface BillingProvider {
  readonly name: string;
  verifyPurchase(reference: string, accountId: string): Promise<VerifiedPurchase>;
  verifyWebhook(rawBody: Buffer, headers: Record<string,string>): Promise<{event_id:string;purchase:VerifiedPurchase}>;
  validateProduct(productId: string, country: string): Promise<{product_id:string;amount_minor:number;currency:string}>;
}
export interface VerifiedReward { transaction_id:string;session_id:string;provider:string;verified_at:string; }
export interface RewardProvider {
  readonly name:string;
  verifyCallback(rawBody:Buffer,headers:Record<string,string>):Promise<VerifiedReward>;
}
export interface BannerProvider {
  readonly name:string;
  validatePlacement(placementId:string,country:string):Promise<{allowed:boolean}>;
}
export interface PushProvider {
  send(token:string,event:{event_id:string;title:string;body:string}):Promise<{provider_message_id:string}>;
}
export interface FileScanner { scan(file:Buffer,mime:string):Promise<'clean'|'infected'>; }
export interface PdfSanitizer { sanitize(file:Buffer):Promise<Buffer>; }
export class Providers {
  readonly billing=new Map<string,BillingProvider>();
  readonly rewards=new Map<string,RewardProvider>();
  readonly banners=new Map<string,BannerProvider>();
  push?:PushProvider;
  scanner?:FileScanner;
  pdfSanitizer?:PdfSanitizer;
}
