-- Чаты по заданиям и сделкам (ТЗ §2.12).
--
-- Чат привязан к заданию и всегда состоит из двух сторон: заказчик и один
-- исполнитель. Он живёт рядом с заданием, потому что права на переписку
-- целиком определяются заданием: кто откликнулся, кто выбран, закрыто ли оно.

CREATE TABLE IF NOT EXISTS orders.chats (
  id          uuid PRIMARY KEY,
  job_id      uuid NOT NULL REFERENCES orders.jobs(id) ON DELETE CASCADE,
  client_id   uuid NOT NULL,
  owner_id    uuid NOT NULL,

  -- pre_deal — до выбора исполнителя (контакты маскируются),
  -- deal — чат сделки, там стороны уже знают телефоны друг друга.
  kind        text NOT NULL DEFAULT 'pre_deal' CHECK (kind IN ('pre_deal','deal')),

  last_message_at timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- На пару «задание + исполнитель» — один чат: иначе переписка расползётся по
-- нескольким веткам и стороны потеряют контекст.
CREATE UNIQUE INDEX IF NOT EXISTS uq_chats_job_owner ON orders.chats (job_id, owner_id);
CREATE INDEX IF NOT EXISTS idx_chats_client ON orders.chats (client_id, last_message_at DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_chats_owner  ON orders.chats (owner_id,  last_message_at DESC NULLS LAST);

CREATE TABLE IF NOT EXISTS orders.messages (
  id         uuid PRIMARY KEY,
  chat_id    uuid NOT NULL REFERENCES orders.chats(id) ON DELETE CASCADE,
  -- Отправитель. NULL — системное сообщение о смене статуса сделки.
  sender_id  uuid,
  kind       text NOT NULL DEFAULT 'text' CHECK (kind IN ('text','photo','system')),
  text       text NOT NULL DEFAULT '',
  media_url  text,

  -- Кто прочитал: массив идентификаторов. Пар в чате две, поэтому этого
  -- достаточно, и отдельная таблица прочтений здесь была бы лишней.
  read_by    uuid[] NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_messages_chat ON orders.messages (chat_id, created_at DESC);
