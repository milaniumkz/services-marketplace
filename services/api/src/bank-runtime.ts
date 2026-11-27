import {Providers} from './providers';
import {Store} from './store';
/** Owner diagnostics contain no merchant identifiers, passwords or signing keys. */
export async function bankRuntime(providers:Providers,store:Store,country:string){
 const payments=await store.all('bank_checkout',country);
 return {server_configured:true,client_update_required_for_environment_switch:false,
  country_routing:{KZ:'bcc',KG:'bcc',RU:'vtb',BY:'vtb'},
  banks:[...providers.billing.values()].filter(p=>p.hostedCheckout).map(p=>({provider:p.name,environment:p.environment,...(p.name==='bcc'?{status_confirmation:'independent_bank_status',http_callback_enabled:!!(p as any).config?.notify_user}:{}),countries:p.countries??[],currencies:p.currencies??[],invoice_currencies:p.invoiceCurrencies??p.currencies??[],
   pending_payments:payments.filter(x=>x.provider===p.name&&['registering','pending','cancel_requested','resolution_required'].includes(x.status)).length,
   previous_environment_pending:payments.filter(x=>x.provider===p.name&&x.environment!==p.environment&&['registering','pending','cancel_requested','resolution_required'].includes(x.status)).length})),
  switching_note:'Перед сменой среды завершите или сверите незавершённые платежи в прежней среде. Установите выданные банком параметры только на сервере и перезапустите API. Клиент получает предложение, цену, валюту и ссылку оплаты с сервера.'};
}
