import {Store} from './store';

export async function operationsOverview(store:Store,country:string,days=7,now=new Date()) {
  const today=Date.UTC(now.getUTCFullYear(),now.getUTCMonth(),now.getUTCDate());
  const from=new Date(today-(days-1)*86400000).toISOString();
  const counts=(await store.db.query<any>(`
    SELECT
      count(*) FILTER (WHERE kind='user' AND data->>'status'='active' AND COALESCE(jsonb_array_length(data->'staff_permissions'),0)=0) AS users,
      count(*) FILTER (WHERE kind='order') AS orders,
      count(*) FILTER (WHERE kind='order' AND data->>'published_at'>=$2 AND data->>'published_at'<=$3) AS published,
      count(*) FILTER (WHERE kind='order' AND data->>'completed_at'>=$2 AND data->>'completed_at'<=$3 AND data->>'status'='completed') AS completed,
      count(*) FILTER (WHERE kind='subscription' AND data->>'status' IN ('active','grace','canceled_at_period_end') AND data->>'valid_until'>$3) AS subscriptions,
      count(*) FILTER (WHERE kind='support' AND data->>'status' NOT IN ('resolved','closed')) AS support,
      count(*) FILTER (WHERE kind='support' AND data->>'status' NOT IN ('resolved','closed') AND data->>'assignee_id' IS NULL) AS unassigned_support,
      count(*) FILTER (WHERE kind='verification' AND data->>'status'='pending_review') AS verifications,
      count(*) FILTER (WHERE kind='case' AND data->>'status' NOT IN ('resolved','closed')) AS cases,
      count(*) FILTER (WHERE kind='outbox' AND data->>'status' IN ('pending','retry','dead_letter')) AS outbox
    FROM records WHERE country=$1`,[country,from,now.toISOString()])).rows[0];
  const active=(await store.db.query<any>(`
    SELECT count(*) AS total FROM records u WHERE u.country=$1 AND u.kind='user'
    AND u.data->>'status'='active' AND COALESCE(jsonb_array_length(u.data->'staff_permissions'),0)=0
    AND EXISTS(SELECT 1 FROM records action WHERE action.country=u.country
      AND action.kind IN ('order','offer','message','support_message','review','portfolio')
      AND (action.owner=u.id::text OR action.kind='order' AND action.data->>'executor_id'=u.id::text)
      AND greatest(action.data->>'created_at',action.data->>'published_at',action.data->>'started_at',action.data->>'completed_at')>=$2 AND greatest(action.data->>'created_at',action.data->>'published_at',action.data->>'started_at',action.data->>'completed_at')<=$3)`,[country,from,now.toISOString()])).rows[0];
  const rows=(await store.db.query<any>(`
    SELECT substring(value,1,10) AS day, type, count(*) AS total FROM (
      SELECT data->>'published_at' AS value,'published' AS type FROM records
      WHERE country=$1 AND kind='order' AND data->>'published_at'>=$2 AND data->>'published_at'<=$3
      UNION ALL
      SELECT data->>'completed_at' AS value,'completed' AS type FROM records
      WHERE country=$1 AND kind='order' AND data->>'status'='completed' AND data->>'completed_at'>=$2 AND data->>'completed_at'<=$3
    ) actions GROUP BY substring(value,1,10),type`,[country,from,now.toISOString()])).rows;
  const series=[];
  for(let index=days-1;index>=0;index--) {
    const day=new Date(now.getTime()-index*86400000).toISOString().slice(0,10);
    series.push({day,published:Number(rows.find(row=>row.day===day&&row.type==='published')?.total??0),
      completed:Number(rows.find(row=>row.day===day&&row.type==='completed')?.total??0)});
  }
  return {country,days,from,server_time:now.toISOString(),time_zone:'UTC',
    users:Number(counts.users),orders:Number(counts.orders),support:Number(counts.support),
    active_users:Number(active.total),published_orders:Number(counts.published),completed_orders:Number(counts.completed),active_subscriptions:Number(counts.subscriptions),
    attention:{support:Number(counts.support),unassigned_support:Number(counts.unassigned_support),verifications:Number(counts.verifications),cases:Number(counts.cases),outbox:Number(counts.outbox)},
    series,checkout_enabled:false,
    definitions:{active_users:'Активные аккаунты с созданием заказа, отклика, сообщения, отзыва, проекта или изменением статуса рабочего заказа за период.',
      published_orders:'Заказы, опубликованные за период в текущей стране.',completed_orders:'Заказы, подтверждённые завершёнными за период.',
      active_subscriptions:'Подтверждённые подписки с действующим сроком и статусом доступа. Валюты разных стран не суммируются.'}};
}

export function operationJob(record:any) {
  return {id:record.id,source_kind:record.kind,
    type:record.kind==='upload'?'media.safe-derivative':record.kind==='privacy'?'privacy.export':record.kind==='outbox'?'push.delivery':'webhook.inbox',
    status:record.status,attempts:record.scan_attempts??record.attempts??0,
    next_attempt_at:record.next_attempt_at??null,lease_until:record.scan_lease_until??record.lease_expires_at??null,
    failure_code:record.failure_code??null,created_at:record.created_at,version:record.version};
}
