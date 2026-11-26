-- Deduplicate real registered visitors; no IP addresses or guest fingerprints.
CREATE UNIQUE INDEX IF NOT EXISTS records_profile_view_unique ON records(country,owner,(data->>'target_id')) WHERE kind='profile_view';
CREATE INDEX IF NOT EXISTS records_profile_view_target ON records(country,(data->>'target_id')) WHERE kind='profile_view';
CREATE INDEX IF NOT EXISTS records_completed_work_pair ON records(country,owner,(data->>'executor_id')) WHERE kind='order' AND data->>'status'='completed';
