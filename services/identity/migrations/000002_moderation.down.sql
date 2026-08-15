DROP TABLE IF EXISTS identity.admin_actions;

DROP INDEX IF EXISTS identity.idx_users_status;
DROP INDEX IF EXISTS identity.idx_users_name;

ALTER TABLE identity.users
  DROP COLUMN IF EXISTS status_by,
  DROP COLUMN IF EXISTS status_at,
  DROP COLUMN IF EXISTS status_reason,
  DROP COLUMN IF EXISTS status;
