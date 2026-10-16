CREATE TABLE IF NOT EXISTS rate_limits (
  scope_hash text PRIMARY KEY,
  window_start timestamptz NOT NULL,
  attempts integer NOT NULL CHECK (attempts > 0)
);
CREATE INDEX IF NOT EXISTS rate_limits_expiry ON rate_limits(window_start);
