-- Operational admin read model. Private retention remains in records.
-- Traverse references as well as ownership: e.g. user -> order -> chat -> message.
-- UNION deduplicates cycles. Account identity is the UUID, never a reused phone.
CREATE OR REPLACE VIEW admin_visible_records AS
WITH RECURSIVE hidden(id) AS (
 SELECT id::text FROM records WHERE kind='user' AND data->>'status'='deleted'
 UNION
 SELECT r.id::text FROM records r JOIN hidden h ON
  h.id=r.owner OR h.id IN (
   r.data->>'user_id',r.data->>'subject_user_id',r.data->>'recipient_id',
   r.data->>'actor_id',r.data->>'customer_id',r.data->>'executor_id',
   r.data->>'target_user_id',r.data->>'target_id',r.data->>'order_id',
   r.data->>'verification_id',r.data->>'contractor_id',r.data->>'portfolio_id',
   r.data->>'conversation_id',r.data->>'thread_id',r.data->>'source_id'
  ) OR COALESCE(r.data->'members','[]'::jsonb) ? h.id
)
SELECT r.* FROM records r WHERE NOT EXISTS(SELECT 1 FROM hidden h WHERE h.id=r.id::text);
