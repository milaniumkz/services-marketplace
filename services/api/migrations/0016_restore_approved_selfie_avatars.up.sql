-- Owner confirmed approved selfies must be profile photos. Restore only legacy
-- derivatives detached by the briefly superseded privacy migration; never use
-- a document page or unapproved verification as an avatar.
WITH candidates AS (
 SELECT DISTINCT ON (photo.owner) photo.owner,photo.id::text AS avatar_id
 FROM records photo JOIN records verification
 ON verification.id::text=photo.data->>'source_verification_id'
 WHERE photo.kind='upload' AND photo.data->>'purpose'='identity'
 AND photo.data->>'source_verification_id' IS NOT NULL
 AND photo.data->>'derived_from' IS NOT NULL AND verification.kind='verification'
 AND verification.data->>'status'='passed'
 AND verification.owner=photo.owner AND verification.country=photo.country
 AND photo.data->>'derived_from'=verification.data->'document_refs'->>2
 ORDER BY photo.owner,photo.data->>'created_at' DESC,photo.id
)
UPDATE records person SET data=jsonb_set(jsonb_set(person.data,'{avatar_id}',to_jsonb(c.avatar_id)),'{version}',to_jsonb(person.version+1)),version=person.version+1
FROM candidates c WHERE person.kind='user' AND person.id::text=c.owner
AND person.data->>'status'<>'deleted' AND person.data->>'verification'='passed'
AND person.data->>'avatar_id' IS NULL;
UPDATE records SET data=jsonb_set(jsonb_set(data,'{purpose}','"avatar"'::jsonb),'{version}',to_jsonb(version+1)),version=version+1
WHERE kind='upload' AND data->>'purpose'='identity'
AND data->>'source_verification_id' IS NOT NULL AND data->>'derived_from' IS NOT NULL;
