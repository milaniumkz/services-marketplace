-- Owner request, 2026-10-20: minimum password length 6 instead of 15.
-- Apply once, preserving future changes made by the owner in the admin panel.
-- Credential hashes and current sessions are not modified.
CREATE TABLE IF NOT EXISTS joba_data_migrations (
  name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now()
);
WITH applied AS (
  INSERT INTO joba_data_migrations(name) VALUES ('owner-password-minimum-6-2026-10-20')
  ON CONFLICT DO NOTHING RETURNING name
)
UPDATE records SET version=version+1,
  data=jsonb_set(jsonb_set(data,'{payload,password_min}','6'::jsonb),'{version}',to_jsonb(version+1))
WHERE kind='runtime_settings' AND country IN ('KZ','KG','RU','BY')
  AND data->>'status'='effective' AND EXISTS (SELECT 1 FROM applied);
