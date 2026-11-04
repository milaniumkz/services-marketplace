-- Stop publishing identity selfies already converted into profile avatars.
-- Explicitly uploaded profile photos and verification approval stay unchanged.
UPDATE records person SET data=jsonb_set(person.data,'{avatar_id}','null'::jsonb),
 version=person.version+1
WHERE person.kind='user' AND EXISTS(SELECT 1 FROM records photo
 WHERE photo.kind='upload' AND photo.id::text=person.data->>'avatar_id'
 AND photo.data->>'source_verification_id' IS NOT NULL);
UPDATE records SET data=jsonb_set(data,'{purpose}','"identity"'::jsonb),version=version+1
WHERE kind='upload' AND data->>'purpose'='avatar'
 AND data->>'source_verification_id' IS NOT NULL;
