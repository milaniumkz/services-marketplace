CREATE INDEX IF NOT EXISTS records_outbox_campaign ON records(country,(data->>'campaign_id'),(data->>'status')) WHERE kind='outbox';
CREATE UNIQUE INDEX IF NOT EXISTS records_outbox_campaign_recipient ON records(country,(data->>'campaign_id'),(data->>'recipient_id')) WHERE kind='outbox' AND data->>'campaign_id' IS NOT NULL;
CREATE INDEX IF NOT EXISTS records_outbox_claim ON records((data->>'status'),(data->>'next_attempt_at'),id) WHERE kind='outbox';
CREATE INDEX IF NOT EXISTS records_campaign_cohort ON records(country,(data->>'created_at'),id) WHERE kind='user';
CREATE INDEX IF NOT EXISTS records_push_owner ON records(country,owner,(data->>'status')) WHERE kind='push_token';
