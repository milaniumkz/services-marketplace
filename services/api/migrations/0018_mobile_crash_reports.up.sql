-- Diagnostics are separate from user records and contain no account identifiers.
CREATE TABLE IF NOT EXISTS mobile_crash_reports (
 id uuid PRIMARY KEY,
 received_at timestamptz NOT NULL DEFAULT now(),
 report jsonb NOT NULL
);
CREATE INDEX IF NOT EXISTS mobile_crash_reports_received ON mobile_crash_reports(received_at DESC);
