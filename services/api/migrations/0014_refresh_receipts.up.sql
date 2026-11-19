-- One encrypted retry receipt per current session family. No plaintext credentials.
CREATE TABLE IF NOT EXISTS refresh_receipts (
 token_hash text PRIMARY KEY REFERENCES tokens(hash) ON DELETE CASCADE,
 family uuid NOT NULL,
 request_id uuid NOT NULL,
 response_sealed text NOT NULL,
 expires_at timestamptz NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS refresh_receipts_family ON refresh_receipts(family);
CREATE INDEX IF NOT EXISTS refresh_receipts_expiry ON refresh_receipts(expires_at);
