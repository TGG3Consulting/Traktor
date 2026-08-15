-- Жалобы на задания и людей (ТЗ §4.1, п.6).
--
-- Пока пожаловаться некуда, единственный способ отреагировать на обман —
-- уйти с площадки и рассказать знакомым. Жалоба даёт модерации повод
-- посмотреть и закрывает этот выход.

CREATE TABLE IF NOT EXISTS orders.complaints (
  id         uuid PRIMARY KEY,
  -- На что жалуются: job — задание, user — человек.
  target_kind text NOT NULL CHECK (target_kind IN ('job','user')),
  target_id   uuid NOT NULL,

  author_id  uuid NOT NULL,
  reason     text NOT NULL,

  -- open — ждёт модератора, reviewed — разобрано.
  status     text NOT NULL DEFAULT 'open' CHECK (status IN ('open','reviewed')),
  -- Что сделали: dismissed — жалоба не подтвердилась, removed — контент снят,
  -- warned — человеку вынесено предупреждение.
  action     text CHECK (action IN ('dismissed','removed','warned')),
  note       text NOT NULL DEFAULT '',
  reviewed_by uuid,
  reviewed_at timestamptz,

  created_at timestamptz NOT NULL DEFAULT now()
);

-- Один человек — одна жалоба на объект: повторные только раздувают очередь.
CREATE UNIQUE INDEX IF NOT EXISTS uq_complaints_author
  ON orders.complaints (author_id, target_kind, target_id) WHERE status = 'open';

-- Очередь модерации: старые сверху.
CREATE INDEX IF NOT EXISTS idx_complaints_queue ON orders.complaints (created_at) WHERE status = 'open';
-- Сколько жалоб на объект — это и есть сигнал важности.
CREATE INDEX IF NOT EXISTS idx_complaints_target ON orders.complaints (target_kind, target_id);
