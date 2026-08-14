-- Сделка (ТЗ §2.11): что происходит после выбора исполнителя.
--
-- Сделка живёт в схеме orders вместе с заданием: её статус и статус задания
-- меняются вместе, и разносить их по разным сервисам — это гонки на пустом
-- месте. Отдельный сервис deals появится, когда добавятся деньги и споры.

CREATE TABLE IF NOT EXISTS orders.deals (
  id           uuid PRIMARY KEY,
  job_id       uuid NOT NULL REFERENCES orders.jobs(id) ON DELETE CASCADE,
  offer_id     uuid,                          -- выбранное предложение (фикс-цена)
  client_id    uuid NOT NULL,
  owner_id     uuid NOT NULL,                 -- исполнитель

  -- Цена фиксируется в момент создания сделки и дальше не меняется: это то,
  -- о чём договорились. Любое изменение — новая договорённость, не правка.
  price        bigint NOT NULL CHECK (price > 0),
  currency     text NOT NULL DEFAULT 'AMD',

  status       text NOT NULL DEFAULT 'confirmed' CHECK (status IN (
                 'confirmed','on_the_way','in_progress','work_done',
                 'completed','disputed','cancelled')),

  -- Таймлайн: массив событий {status, at, byUserId, note}. Видят обе стороны,
  -- поэтому «когда именно исполнитель выехал» не превращается в спор на словах.
  timeline     jsonb NOT NULL DEFAULT '[]'::jsonb,

  -- Приёмка: 48 часов у заказчика, дальше автоприёмка (ТЗ §2.11).
  acceptance_deadline timestamptz,
  cancel_reason       text NOT NULL DEFAULT '',
  cancelled_by        uuid,

  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  closed_at    timestamptz
);

-- На задание — одна сделка.
CREATE UNIQUE INDEX IF NOT EXISTS uq_deals_job ON orders.deals (job_id);
CREATE INDEX IF NOT EXISTS idx_deals_client ON orders.deals (client_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_deals_owner  ON orders.deals (owner_id, updated_at DESC);
-- Фоновая автоприёмка ищет просроченные (следующая фаза).
CREATE INDEX IF NOT EXISTS idx_deals_acceptance ON orders.deals (acceptance_deadline)
  WHERE status = 'work_done';
