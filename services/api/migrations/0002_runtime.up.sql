-- JOBA backend runtime schema. Run with a migration role, never against unrelated databases.
CREATE TABLE IF NOT EXISTS records (
      id uuid PRIMARY KEY, kind text NOT NULL, owner text NOT NULL,
      country text NOT NULL, version integer NOT NULL, data jsonb NOT NULL
    ); CREATE INDEX IF NOT EXISTS records_scope ON records(kind,country,owner);
    CREATE INDEX IF NOT EXISTS records_page ON records(kind,country,id);
    CREATE INDEX IF NOT EXISTS records_status_page ON records(kind,country,(data->>'status'),id);
    CREATE INDEX IF NOT EXISTS records_download_tokens ON records((data->>'token_hash')) WHERE kind='download_ticket';
    CREATE TABLE IF NOT EXISTS events (sequence bigserial PRIMARY KEY,event_id uuid NOT NULL UNIQUE,recipient_id uuid NOT NULL,country text NOT NULL,data jsonb NOT NULL);
    CREATE INDEX IF NOT EXISTS events_recipient_sequence ON events(recipient_id,country,sequence);
    CREATE TABLE IF NOT EXISTS credentials (country text NOT NULL, phone text NOT NULL, user_id uuid NOT NULL, password_hash text NOT NULL, PRIMARY KEY(country,phone));
    CREATE TABLE IF NOT EXISTS tokens (hash text PRIMARY KEY, family uuid NOT NULL, user_id uuid NOT NULL, country text NOT NULL, kind text NOT NULL, expires_at timestamptz NOT NULL, used boolean NOT NULL DEFAULT false, revoked boolean NOT NULL DEFAULT false, mfa_verified boolean NOT NULL DEFAULT false);
    ALTER TABLE tokens ADD COLUMN IF NOT EXISTS mfa_verified boolean NOT NULL DEFAULT false;
    CREATE TABLE IF NOT EXISTS idempotency (scope text NOT NULL, key text NOT NULL, body_hash text NOT NULL, result jsonb NOT NULL, PRIMARY KEY(scope,key));
    CREATE TABLE IF NOT EXISTS votes (voter uuid NOT NULL, target uuid NOT NULL, value integer NOT NULL CHECK(value IN(-1,1)), created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(voter,target));
    CREATE UNIQUE INDEX IF NOT EXISTS records_active_offer ON records((data->>'order_id'),owner) WHERE kind='offer' AND data->>'status'='active';
    CREATE UNIQUE INDEX IF NOT EXISTS records_grant_source ON records((data->>'source_id'),owner) WHERE kind='grant' AND data->>'source_id' IS NOT NULL;
    CREATE UNIQUE INDEX IF NOT EXISTS records_webhook_event ON records(country,(data->>'provider'),(data->>'event_id')) WHERE kind='webhook_inbox';
    CREATE UNIQUE INDEX IF NOT EXISTS records_review_author ON records((data->>'order_id'),owner) WHERE kind='review';
    CREATE UNIQUE INDEX IF NOT EXISTS records_message_dedupe ON records(kind,owner,(data->>'client_message_id')) WHERE kind IN('message','support_message');
    CREATE OR REPLACE FUNCTION protect_immutable_records() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
      IF OLD.kind IN('audit','payment_transaction','ad_reward','consent') THEN RAISE EXCEPTION 'append-only record'; END IF;
      IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
    END $$;
    DROP TRIGGER IF EXISTS immutable_records ON records;
    CREATE TRIGGER immutable_records BEFORE UPDATE OR DELETE ON records FOR EACH ROW EXECUTE FUNCTION protect_immutable_records();
