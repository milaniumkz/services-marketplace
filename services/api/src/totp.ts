import { createHmac, timingSafeEqual } from 'node:crypto';
// RFC 6238, SHA-1 / 30 seconds / six digits. Secrets are never exposed by HTTP.
export function totp(secret: string, time = Date.now()): string {
  const counter=Buffer.alloc(8);counter.writeBigUInt64BE(BigInt(Math.floor(time/30000)));
  const h=createHmac('sha1',Buffer.from(secret,'hex')).update(counter).digest();
  const offset=h[h.length-1]&15;
  return String((h.readUInt32BE(offset)&0x7fffffff)%1_000_000).padStart(6,'0');
}
export function verifyTotp(secret: string, code: string, time=Date.now()): boolean {
  if(!/^[0-9]{6}$/.test(code))return false;
  return [-1,0,1].some(w=>timingSafeEqual(Buffer.from(totp(secret,time+w*30000)),Buffer.from(code)));
}
