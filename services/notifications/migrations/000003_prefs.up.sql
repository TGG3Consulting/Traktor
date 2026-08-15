-- Настройки уведомлений (ТЗ §2.14).
--
-- Человек должен управлять тем, что ему приходит, иначе он отключит уведомления
-- целиком — и пропустит важное. Поэтому тумблеры по группам, а не один рубильник.
--
-- Тихие часы 22:00–08:00 действуют на некритичные группы: ночью push молчит,
-- а событие всё равно ложится в центр уведомлений.

CREATE TABLE IF NOT EXISTS notifications.prefs (
  user_id     uuid PRIMARY KEY,

  -- Группы из ТЗ §2.14. Маркетинг выключен по умолчанию: рассылка — opt-in.
  auctions    boolean NOT NULL DEFAULT true,
  deals       boolean NOT NULL DEFAULT true,
  chat        boolean NOT NULL DEFAULT true,
  new_jobs    boolean NOT NULL DEFAULT true,
  marketing   boolean NOT NULL DEFAULT false,

  quiet_hours boolean NOT NULL DEFAULT true,
  -- Часы начала и конца тишины в местном времени (Ереван).
  quiet_from  smallint NOT NULL DEFAULT 22 CHECK (quiet_from BETWEEN 0 AND 23),
  quiet_to    smallint NOT NULL DEFAULT 8  CHECK (quiet_to   BETWEEN 0 AND 23),

  -- «Вашу ставку перебили» — единственное исключение из тишины по выбору
  -- пользователя: на аукционе минуты решают (ТЗ §2.14).
  outbid_always boolean NOT NULL DEFAULT false,

  updated_at  timestamptz NOT NULL DEFAULT now()
);
