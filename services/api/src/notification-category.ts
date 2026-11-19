export function notificationCategory(record:Record<string,any>):'orders'|'account'|'other' {
  const type=record.type??'',route=record.deep_link?.route;
  if(/^(order\.|offer\.|invite\.|amendment\.|cancel_request\.)/.test(type)||['order','offer'].includes(route??''))return 'orders';
  if(/^(verification\.|content\.|portfolio\.|subscription\.|review\.|refund\.|boost\.|privacy\.|referral\.|account\.|session\.)/.test(type)||['profile','subscription'].includes(route??''))return 'account';
  return 'other';
}
