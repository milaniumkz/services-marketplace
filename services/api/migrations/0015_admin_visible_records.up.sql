-- Operational admin read model. Private retention remains in records.
-- Traverse references as well as ownership: e.g. user -> order -> chat -> message.
-- UNION deduplicates cycles. Account identity is the UUID, never a reused phone.
CREATE OR REPLACE VIEW admin_visible_records AS
WITH RECURSIVE links AS MATERIALIZED (
 SELECT r.id::text AS id, unnest(array_remove(ARRAY[
  r.owner,r.data->>'user_id',r.data->>'subject_user_id',r.data->>'recipient_id',
  r.data->>'actor_id',r.data->>'customer_id',r.data->>'executor_id',
  r.data->>'target_user_id',r.data->>'target_id',r.data->>'order_id',
  r.data->>'verification_id',r.data->>'contractor_id',r.data->>'portfolio_id',
  r.data->>'conversation_id',r.data->>'thread_id',r.data->>'source_id',
  r.data->>'case_id',r.data->>'offer_id',r.data->>'review_id',
  r.data->>'payment_id',r.data->>'subscription_id',r.data->>'grant_id',
  r.data->>'record_id',r.data->>'source_verification_id',r.data->>'source_private_case_id'
 ]::text[],NULL) || ARRAY(SELECT jsonb_array_elements_text(
  CASE WHEN jsonb_typeof(r.data->'members')='array' THEN r.data->'members' ELSE '[]'::jsonb END
  ))) AS reference FROM records r
), hidden(id) AS (
 SELECT id::text FROM records WHERE kind='user' AND data->>'status'='deleted'
 UNION
 SELECT links.id FROM links JOIN hidden h ON links.reference=h.id
)
SELECT r.* FROM records r WHERE NOT EXISTS(SELECT 1 FROM hidden h WHERE h.id=r.id::text);
