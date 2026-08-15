-- Центр уведомлений (ТЗ §2.14).
--
-- Push доходит не всегда: телефон был выключен, разрешение не выдано, человек
-- смахнул баннер. Поэтому каждое отправленное уведомление сохраняется здесь —
-- центр уведомлений и есть надёжный канал, а push лишь ускоряет доставку.
--
-- Хранение 90 дней (ТЗ §2.14): старое чистится фоновой уборкой.

CREATE TABLE IF NOT EXISTS notifications.feed (
  id         uuid PRIMARY KEY,
  user_id    uuid NOT NULL,

  -- Тип события из push-матрицы: по нему клиент рисует иконку и группирует.
  kind       text NOT NULL DEFAULT 'system',
  title      text NOT NULL,
  body       text NOT NULL DEFAULT '',

  -- Куда вести по нажатию (deep link) и всё, что нужно экрану назначения.
  data       jsonb NOT NULL DEFAULT '{}'::jsonb,

  read_at    timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Лента пользователя: свежие сверху.
CREATE INDEX IF NOT EXISTS idx_feed_user ON notifications.feed (user_id, created_at DESC);
-- Счётчик непрочитанного на иконке вкладки.
CREATE INDEX IF NOT EXISTS idx_feed_unread ON notifications.feed (user_id) WHERE read_at IS NULL;
-- Фоновая уборка старше 90 дней.
CREATE INDEX IF NOT EXISTS idx_feed_old ON notifications.feed (created_at);
