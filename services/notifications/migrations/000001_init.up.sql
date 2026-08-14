-- notifications · схема (Postgres 16). Миграции — golang-migrate, expand→contract.
-- Схема принадлежит только сервису notifications (schema-per-service, §2.3.11).
-- Cross-schema JOIN запрещён; связь с пользователем — по user_id (без FK на
-- чужую схему identity).

CREATE SCHEMA IF NOT EXISTS notifications;

-- Реестр push-токенов устройств. Токен уникален (одно устройство = один токен
-- FCM). Протухшие токены удаляются сервисом при ответе провайдера UNREGISTERED.
CREATE TABLE IF NOT EXISTS notifications.devices (
  token        text PRIMARY KEY,               -- регистрационный токен FCM
  user_id      uuid NOT NULL,                  -- владелец (из проверенного JWT)
  platform     text NOT NULL DEFAULT 'android' CHECK (platform IN ('android','ios','web')),
  locale       text NOT NULL DEFAULT 'ru',     -- hy|ru|en — язык текста пуша
  app_version  text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now()
);
-- Быстрый поиск всех устройств пользователя при рассылке.
CREATE INDEX IF NOT EXISTS idx_devices_user ON notifications.devices(user_id);

-- Transactional outbox: на Фазе 5 сюда пишутся события доставки/квитанции в
-- одной транзакции с данными, релей публикует в Pub/Sub (ADR-5, §2.3.12).
CREATE TABLE IF NOT EXISTS notifications.outbox (
  id           bigserial PRIMARY KEY,
  event_type   text NOT NULL,
  payload      jsonb NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_outbox_unpublished ON notifications.outbox(created_at) WHERE published_at IS NULL;
