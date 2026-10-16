import {Store} from './store';
import {operationsOverview} from './operations-overview';
export async function productAnalytics(store:Store,country:string,days=7,now=new Date()) {
 const overview=await operationsOverview(store,country,days,now);
 const result=(await store.db.query<any>(`
  WITH cohort AS (SELECT id,data FROM records WHERE kind='order' AND country=$1
    AND data->>'published_at'>=$2 AND data->>'published_at'<=$3)
  SELECT count(*) AS published,
   count(*) FILTER(WHERE EXISTS(SELECT 1 FROM records o WHERE o.kind='offer' AND o.country=$1 AND o.data->>'order_id'=cohort.id::text)) AS with_offer,
   count(*) FILTER(WHERE cohort.data->>'executor_id' IS NOT NULL) AS selected,
   count(*) FILTER(WHERE cohort.data->>'status'='completed') AS completed,
   count(*) FILTER(WHERE EXISTS(SELECT 1 FROM records c WHERE c.kind='case' AND c.country=$1 AND c.data->>'target_type'='order' AND c.data->>'target_id'=cohort.id::text)) AS with_case,
   count(*) FILTER(WHERE cohort.data->>'status'='completed' AND
    (SELECT count(DISTINCT v.owner) FROM records v WHERE v.kind='review' AND v.country=$1 AND v.data->>'order_id'=cohort.id::text
     AND v.data->>'status'='published' AND COALESCE(v.data->>'moderation_status','') NOT IN('hidden','rejected','quarantined')
     AND v.owner IN(cohort.data->>'owner',cohort.data->>'executor_id'))=2) AS mutual_review
  FROM cohort`,[country,overview.from,overview.server_time])).rows[0];
 const funnel=Object.fromEntries(Object.entries(result).map(([key,value])=>[key,Number(value)]));
 const rate=(value:number)=>funnel.published?value/funnel.published:null;
 return {country,days,from:overview.from,server_time:overview.server_time,time_zone:'UTC',funnel,
  rates:{selection:rate(funnel.selected),completion:rate(funnel.completed),cases:rate(funnel.with_case)},
  series:overview.series,definitions:{cohort:'Заказы, опубликованные за выбранный период в текущей стране. Воронка показывает их состояние на момент расчёта, включая более поздние отклики и завершение.',
   with_offer:'Есть хотя бы один сохранённый отклик; отозванные отклики учитываются как состоявшееся действие.',
   selected:'У заказа сохранён ID выбранного исполнителя.',completed:'Заказ сейчас находится в состоянии completed.',
   with_case:'Есть хотя бы одно обращение на заказ. Это не подтверждённое нарушение и не число судебных споров.',
   mutual_review:'У завершённого заказа опубликованы отзывы обоих участников; скрытые и запечатанные отзывы исключены.',
   series:'Публикации и подтверждённые завершения по дате события UTC; дневная динамика не является накопительной воронкой.'}};
}
