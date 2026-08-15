-- Ставки обратного аукциона (ТЗ §2.9).
--
-- Аукцион идёт внутри задания, поэтому ставки живут в схеме orders: лучшая
-- ставка, автопродление и финиш меняются вместе со статусом задания, и разнести
-- это по сервисам — значит получить гонки на самом чувствительном месте
-- продукта.

CREATE TABLE IF NOT EXISTS orders.bids (
  id         uuid PRIMARY KEY,
  job_id     uuid NOT NULL REFERENCES orders.jobs(id) ON DELETE CASCADE,
  owner_id   uuid NOT NULL,                   -- исполнитель
  unit_id    uuid,                            -- единица техники

  price      bigint NOT NULL CHECK (price > 0),
  currency   text NOT NULL DEFAULT 'AMD',
  comment    text NOT NULL DEFAULT '',

  status     text NOT NULL DEFAULT 'active'
             CHECK (status IN ('active','withdrawn','outbid','won','lost','expired')),

  -- Скоринг считается на финише (0.6 цена + 0.25 рейтинг + 0.15 близость),
  -- храним результат: по нему заказчик видит «Рекомендуем» и порядок списка.
  score      double precision,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Один активный оффер на исполнителя: новая ставка заменяет прежнюю, иначе
-- лента торга превращается в список одного и того же человека.
CREATE UNIQUE INDEX IF NOT EXISTS uq_bids_active_owner
  ON orders.bids (job_id, owner_id) WHERE status = 'active';

-- Лента ставок и поиск лучшей: сортировка по цене вверх (обратный аукцион).
CREATE INDEX IF NOT EXISTS idx_bids_job_price ON orders.bids (job_id, price ASC)
  WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_bids_job_time ON orders.bids (job_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bids_owner ON orders.bids (owner_id, created_at DESC);

-- Победитель аукциона (после расчёта скоринга).
ALTER TABLE orders.jobs ADD COLUMN IF NOT EXISTS decision_deadline timestamptz;
