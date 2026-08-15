-- Верификация человека (ТЗ §2.3, §1.4 «доверие на каждом экране»).
--
-- Бейдж «Проверен» показывается в карточке и в ленте, но выдать его сейчас
-- некому: verified меняется только руками в базе. Здесь — заявка человека
-- с документом и решение модерации.

CREATE TABLE IF NOT EXISTS identity.verifications (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES identity.users(id) ON DELETE CASCADE,

  -- Ссылки на снимки документа в хранилище (media): паспорт или права.
  -- Сами файлы лежат в приватном бакете, здесь только адреса.
  documents   text[] NOT NULL DEFAULT '{}',
  -- Что за документ: passport | license | other. Модератор должен понимать,
  -- что он открывает, до того как откроет.
  doc_kind    text NOT NULL DEFAULT 'passport'
                CHECK (doc_kind IN ('passport','license','other')),

  -- pending — ждёт модерации, approved — бейдж выдан, rejected — отказ.
  status      text NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending','approved','rejected')),
  -- Причина отказа обязательна: без неё человек не поймёт, что переснять.
  reason      text NOT NULL DEFAULT '',

  reviewed_by uuid,
  reviewed_at timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Одна заявка в работе на человека: вторая только удлиняет очередь.
CREATE UNIQUE INDEX IF NOT EXISTS uq_verifications_pending
  ON identity.verifications (user_id) WHERE status = 'pending';

-- Очередь модерации: старые сверху — людям обещан ответ за сутки.
CREATE INDEX IF NOT EXISTS idx_verifications_queue
  ON identity.verifications (created_at) WHERE status = 'pending';
