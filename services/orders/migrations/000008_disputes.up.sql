-- Споры по сделкам (ТЗ §4.1, п.4).
--
-- Конфликт без арбитра — это потерянный клиент с обеих сторон: заказчик
-- считает, что работа сделана плохо, исполнитель — что придираются, и оба
-- уходят с площадки. Поэтому спор ведётся внутри: модератор видит сделку
-- целиком и выносит решение с обоснованием, которое получают обе стороны.

CREATE TABLE IF NOT EXISTS orders.disputes (
  id        uuid PRIMARY KEY,
  deal_id   uuid NOT NULL REFERENCES orders.deals(id) ON DELETE CASCADE,
  job_id    uuid NOT NULL REFERENCES orders.jobs(id) ON DELETE CASCADE,

  -- Кто открыл спор и кто вторая сторона: решение уходит обоим.
  opened_by uuid NOT NULL,
  client_id uuid NOT NULL,
  owner_id  uuid NOT NULL,

  reason    text NOT NULL,
  -- Фотографии и документы, приложенные к жалобе.
  photos    text[] NOT NULL DEFAULT '{}',

  -- open — ждёт модератора, resolved — решение вынесено.
  status    text NOT NULL DEFAULT 'open' CHECK (status IN ('open','resolved')),

  -- В чью пользу: client, owner или compromise (обе стороны частично правы).
  outcome   text CHECK (outcome IN ('client','owner','compromise')),
  -- Обоснование обязательно: решение без объяснения обе стороны считают
  -- несправедливым, каким бы оно ни было.
  resolution text NOT NULL DEFAULT '',
  resolved_by uuid,
  resolved_at timestamptz,

  created_at timestamptz NOT NULL DEFAULT now()
);

-- На сделку — один открытый спор: второй только запутает разбор.
CREATE UNIQUE INDEX IF NOT EXISTS uq_disputes_open
  ON orders.disputes (deal_id) WHERE status = 'open';

-- Очередь модерации: старые сверху, разбираем по возрасту.
CREATE INDEX IF NOT EXISTS idx_disputes_queue ON orders.disputes (created_at) WHERE status = 'open';
-- Споры конкретного человека — для его экрана сделки.
CREATE INDEX IF NOT EXISTS idx_disputes_parties ON orders.disputes (client_id, owner_id);
