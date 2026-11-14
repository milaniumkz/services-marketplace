CREATE INDEX IF NOT EXISTS records_review_target ON records(country,(data->>'target_id')) WHERE kind='review';
CREATE INDEX IF NOT EXISTS records_order_executor ON records(country,(data->>'executor_id')) WHERE kind='order';
CREATE INDEX IF NOT EXISTS records_invite_recipient ON records(country,(data->>'recipient_id')) WHERE kind='invite';
