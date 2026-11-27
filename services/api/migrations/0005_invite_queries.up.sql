CREATE INDEX IF NOT EXISTS records_invite_pair ON records(country,(data->>'order_id'),(data->>'recipient_id')) WHERE kind='invite' AND data->>'status'='pending';
CREATE INDEX IF NOT EXISTS records_invite_sender_time ON records(country,owner,(data->>'created_at')) WHERE kind='invite';
