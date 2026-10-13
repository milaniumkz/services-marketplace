import {Store} from './store';

// Counts are computed before pagination and scoped to this account and region.
export async function accountOverview(store:Store, owner:string, country:string) {
  const row=(await store.db.query<any>(`
    SELECT
      count(*) FILTER (WHERE kind='order' AND owner=$1 AND data->>'status' IN ('open','assigned','in_progress','completion_requested')) AS orders_active,
      count(*) FILTER (WHERE kind='order' AND owner=$1 AND data->>'status'='open') AS orders_open,
      count(*) FILTER (WHERE kind='order' AND owner=$1 AND data->>'status'='draft') AS orders_draft,
      count(*) FILTER (WHERE kind='order' AND owner=$1 AND data->>'status'='completed') AS orders_completed,
      count(*) FILTER (WHERE kind='order' AND data->>'executor_id'=$1 AND data->>'status' IN ('assigned','in_progress','completion_requested')) AS assigned_active,
      count(*) FILTER (WHERE kind='order' AND data->>'executor_id'=$1 AND data->>'status'='completed') AS assigned_completed,
      count(*) FILTER (WHERE kind='invite' AND data->>'recipient_id'=$1 AND data->>'status'='pending') AS invitations_pending,
      count(*) FILTER (WHERE kind='portfolio' AND owner=$1 AND data->>'status'='published') AS projects_published,
      count(*) FILTER (WHERE kind='portfolio' AND owner=$1 AND COALESCE(data->'draft'->>'status',data->>'status')='pending_review') AS projects_pending,
      count(*) FILTER (WHERE kind='review' AND data->>'target_id'=$1 AND data->>'status'='published' AND COALESCE(data->>'moderation_status','') NOT IN ('quarantined','hidden','rejected')) AS reviews_count,
      avg((data->>'rating')::numeric) FILTER (WHERE kind='review' AND data->>'target_id'=$1 AND data->>'status'='published' AND COALESCE(data->>'moderation_status','') NOT IN ('quarantined','hidden','rejected')) AS reviews_average,
      max((data->>'valid_until')::timestamptz) FILTER (WHERE kind='grant' AND owner=$1 AND data->>'source'='subscription' AND (data->>'valid_until')::timestamptz > CURRENT_TIMESTAMP) AS subscription_until
    FROM records WHERE country=$2 AND (
      (owner=$1 AND kind IN ('order','portfolio','grant')) OR
      (kind='order' AND data->>'executor_id'=$1) OR
      (kind='invite' AND data->>'recipient_id'=$1) OR
      (kind='review' AND data->>'target_id'=$1))`,[owner,country])).rows[0];
  const profiles=await store.select('contractor',country,{owner,limit:1});
  return {
    orders:{active:Number(row.orders_active),open:Number(row.orders_open),draft:Number(row.orders_draft),completed:Number(row.orders_completed)},
    assigned_orders:{active:Number(row.assigned_active),completed:Number(row.assigned_completed)},
    invitations:{pending:Number(row.invitations_pending)},
    portfolio:{published:Number(row.projects_published),pending:Number(row.projects_pending)},
    rating:{count:Number(row.reviews_count),average:row.reviews_average===null?null:Number(row.reviews_average)},
    subscription_until:row.subscription_until===null?null:new Date(row.subscription_until).toISOString(),
    contractor:profiles[0]?{status:profiles[0].status,availability:profiles[0].availability??'available'}:null,
  };
}
