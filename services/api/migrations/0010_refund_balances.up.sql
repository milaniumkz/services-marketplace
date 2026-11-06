CREATE INDEX IF NOT EXISTS records_refund_balance ON records(country,(data->>'payment_id')) WHERE kind='refund_request';
CREATE INDEX IF NOT EXISTS records_refund_events ON records(country,(data->>'original_payment_id')) WHERE kind='payment_transaction' AND data->>'operation'='refund';
CREATE UNIQUE INDEX IF NOT EXISTS records_provider_refund ON records(country,(data->>'provider'),(data->>'refund_id')) WHERE kind='payment_transaction' AND data->>'operation'='refund';
CREATE INDEX IF NOT EXISTS records_payment_identity ON records(country,(data->>'provider'),(data->>'transaction_id')) WHERE kind='payment_transaction';
