-- Откат первой миграции identity. Расширение pgcrypto не удаляем: оно общее
-- для базы и может использоваться другими схемами.
DROP TABLE IF EXISTS identity.outbox;
DROP TABLE IF EXISTS identity.refresh_tokens;
DROP TABLE IF EXISTS identity.otps;
DROP TABLE IF EXISTS identity.users;
DROP SCHEMA IF EXISTS identity;
