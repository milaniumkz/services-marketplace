-- Only documents remain in the pre-publication review queue. Do not reopen
-- content hidden or rejected after a complaint or an administrator decision.
UPDATE records SET data=jsonb_set(jsonb_set(
 (data || COALESCE(data->'draft','{}'::jsonb)) - 'draft',
 '{status}','"published"'::jsonb),'{moderation_status}','"visible"'::jsonb)
 || jsonb_build_object('version',version+1,'published_at',COALESCE(data->>'published_at',to_char(CURRENT_TIMESTAMP AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))),version=version+1
WHERE kind IN('portfolio','contractor')
AND COALESCE(data->'draft'->>'status',data->>'status')='pending_review'
AND COALESCE(data->>'moderation_status','') NOT IN('hidden','rejected','quarantined');
