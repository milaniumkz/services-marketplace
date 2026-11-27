import type {BillingProvider} from './providers';
import type {RecordData} from './store';
export interface HostedBank extends BillingProvider {
 readonly countries:readonly string[];
 readonly environment:'sandbox'|'production';
 readonly currencies?:readonly string[];
 readonly config:{public_origin:string};
 register(payment:RecordData,callback:string):Promise<{order_id:string;form_url:string|null}>;
 status(values:{orderId?:string;orderNumber?:string}):Promise<any>;
 validateStatus(payment:RecordData,data:any):number;
 decline(payment:RecordData):Promise<any>;
}
