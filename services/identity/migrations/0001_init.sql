-- identity · схема (Postgres 16). Миграции — golang-migrate, expand→contract.
-- Схема принадлежит только сервису identity (schema-per-service, ADR-3/4).

CREATE SCHEMA IF NOT EXISTS identity;

-- Пользователи. Телефон шифруется на уровне колонки (pgcrypto) — раскрытие
-- второй стороне только при статусе сделки ≥ confirmed (проверка в deals-API).
CREATE TABLE identity.users (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_enc    bytea NOT NULL,                 -- pgp_sym_encrypt(phone, key)
  phone_hash   text  NOT NULL UNIQUE,          -- для поиска по номеру
  name         text,
  city         text,
  roles        text[] NOT NULL DEFAULT '{client}',
  active_role  text  NOT NULL DEFAULT 'client',
  verified     boolean NOT NULL DEFAULT false,
  created_at   timestamptz NOT NULL DEFAULT now(),
  deleted_at   timestamptz
);

-- Одноразовые коды (хэш кода, срок, попытки). Чистятся по TTL.
CREATE TABLE identity.otps (
  phone_hash  text PRIMARY KEY,
  code_hash   text NOT NULL,
  expires_at  timestamptz NOT NULL,
  attempts    int NOT NULL DEFAULT 0
);

-- Refresh-сессии: ротация + обнаружение повторного использования по family_id.
CREATE TABLE identity.refresh_tokens (
  token_hash  text PRIMARY KEY,
  user_id     uuid NOT NULL REFERENCES identity.users(id) ON DELETE CASCADE,
  family_id   uuid NOT NULL,
  expires_at  timestamptz NOT NULL,
  used        boolean NOT NULL DEFAULT false,
  revoked     boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_refresh_family ON identity.refresh_tokens(family_id);

-- Transactional outbox: события пишутся в одной транзакции с данными,
-- релей публикует в Pub/Sub (ADR-5).
CREATE TABLE identity.outbox (
  id           bigserial PRIMARY KEY,
  event_type   text NOT NULL,
  payload      jsonb NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz
);
CREATE INDEX idx_outbox_unpublished ON identity.outbox(created_at) WHERE published_at IS NULL;
