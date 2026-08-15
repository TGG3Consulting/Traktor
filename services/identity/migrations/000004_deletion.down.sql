DROP INDEX IF EXISTS identity.idx_users_delete_due;

ALTER TABLE identity.users
  DROP COLUMN IF EXISTS anonymized_at,
  DROP COLUMN IF EXISTS delete_requested_at,
  DROP COLUMN IF EXISTS delete_after;
