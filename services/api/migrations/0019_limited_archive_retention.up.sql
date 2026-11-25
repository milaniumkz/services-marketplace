-- Immutable records may only become an irreversible minimal retention marker.
CREATE OR REPLACE FUNCTION protect_immutable_records() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.kind IN ('audit','payment_transaction','ad_reward','consent') THEN
  IF TG_OP='UPDATE' THEN
   IF NEW.id=OLD.id AND NEW.kind=OLD.kind AND NEW.owner=OLD.owner AND NEW.country=OLD.country
    AND NEW.version=OLD.version+1 AND NEW.data->>'status'='retention_minimized'
    AND NEW.data->>'created_at'=OLD.data->>'created_at'
    AND NEW.data - ARRAY['id','kind','owner','country','created_at','version','status','retention_policy_id','retention_policy_version','minimized_at']::text[]='{}'::jsonb
    AND (OLD.data->>'created_at')::timestamptz <= CURRENT_TIMESTAMP - INTERVAL '3 years'
    AND (OLD.kind NOT IN ('payment_transaction','ad_reward') OR OLD.data->>'status' IN ('succeeded','failed','cancelled','canceled','expired','refunded','completed','rejected','revoked','consumed','released','settled'))
    AND EXISTS(SELECT 1 FROM records u WHERE u.id::text=OLD.owner AND u.country=OLD.country AND u.kind='user' AND u.data->>'status'='deleted')
    AND EXISTS(SELECT 1 FROM records p WHERE p.id::text=NEW.data->>'retention_policy_id' AND p.kind='retention_policy' AND p.country=OLD.country AND p.data->>'status'='effective' AND p.data->'payload'->>'account_removal'='immediate' AND p.data->'payload'->>'legal_archive_years'='3')
    AND NOT EXISTS(SELECT 1 FROM records h WHERE h.country=OLD.country AND h.kind='legal_hold' AND h.data->>'status'='active' AND (h.data->>'target_id'=OLD.id::text OR h.data->>'subject_user_id'=OLD.owner))
    AND NOT EXISTS(SELECT 1 FROM records c WHERE c.country=OLD.country AND c.kind='case' AND COALESCE(c.data->>'status','') NOT IN ('resolved','closed','dismissed') AND (c.data->>'target_id' IN(OLD.id::text,OLD.owner) OR c.owner=OLD.owner OR c.data->>'subject_user_id'=OLD.owner OR COALESCE(c.data->'members','[]'::jsonb) ? OLD.owner))
   THEN RETURN NEW; END IF;
  END IF;
  RAISE EXCEPTION 'append-only record';
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $$;
