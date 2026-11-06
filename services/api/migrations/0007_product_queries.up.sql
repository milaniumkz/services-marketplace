CREATE INDEX IF NOT EXISTS records_offer_order ON records(country,(data->>'order_id')) WHERE kind='offer';
CREATE INDEX IF NOT EXISTS records_review_order ON records(country,(data->>'order_id'),owner) WHERE kind='review';
CREATE INDEX IF NOT EXISTS records_case_target ON records(country,(data->>'target_id'),(data->>'target_type')) WHERE kind='case';
CREATE INDEX IF NOT EXISTS records_order_published ON records(country,(data->>'published_at')) WHERE kind='order';
