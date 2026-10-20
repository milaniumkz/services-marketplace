-- Membership is filtered before cursor pagination. The default GIN class supports ?.
CREATE INDEX IF NOT EXISTS records_conversation_members ON records USING GIN ((COALESCE(data->'members','[]'::jsonb))) WHERE kind='conversation';
-- Reuse the same prefix for latest-message and unread-range queries.
CREATE INDEX IF NOT EXISTS records_message_thread_sequence ON records(country,(data->>'thread_id'),((data->>'sequence')::integer) DESC) WHERE kind='message';
