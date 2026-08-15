-- Управление пользователями у модерации (ТЗ §4.1, п.3 и 8).
--
-- Жалобы разбираются, но нарушитель продолжает работать: без блокировки
-- решение модерации ничего не меняет. Бан обратимый — ошибку модератора
-- должно быть можно исправить, не заводя человеку новый аккаунт.

ALTER TABLE identity.users
  -- active — обычная работа, frozen — нельзя откликаться и ставить ставки,
  -- banned — вход закрыт полностью.
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'frozen', 'banned')),
  -- Причина обязательна: человек должен понимать, за что, иначе он заведёт
  -- новый номер и вернётся с тем же поведением.
  ADD COLUMN IF NOT EXISTS status_reason text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS status_at timestamptz,
  ADD COLUMN IF NOT EXISTS status_by uuid;

-- Поиск по имени в панели модерации: телефон ищется по хэшу, имя — по тексту.
CREATE INDEX IF NOT EXISTS idx_users_name ON identity.users (lower(name));
CREATE INDEX IF NOT EXISTS idx_users_status ON identity.users (status) WHERE status <> 'active';

-- Журнал действий модерации (ТЗ §4.1, п.8): кто, что, над кем и почему.
-- Без него ошибку или злоупотребление невозможно ни найти, ни оспорить.
CREATE TABLE IF NOT EXISTS identity.admin_actions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id    uuid NOT NULL,
  action      text NOT NULL,
  target_id   uuid NOT NULL,
  reason      text NOT NULL DEFAULT '',
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_admin_actions_target
  ON identity.admin_actions (target_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_actions_recent
  ON identity.admin_actions (created_at DESC);
