-- Отклики по фикс-цене (ТЗ §2.10) и один раунд встречного торга.
--
-- Отклики живут в схеме orders рядом с заданиями: они читаются и меняются
-- только вместе с заданием (посчитать offers_count, выбрать победителя), и
-- разносить это по двум сервисам значило бы гонки на ровном месте.

CREATE TABLE IF NOT EXISTS orders.offers (
  id           uuid PRIMARY KEY,
  job_id       uuid NOT NULL REFERENCES orders.jobs(id) ON DELETE CASCADE,
  owner_id     uuid NOT NULL,                 -- исполнитель (из проверенного JWT)

  -- accept — согласен на цену заказчика; counter — предлагает свою.
  kind         text NOT NULL CHECK (kind IN ('accept','counter')),
  price        bigint NOT NULL CHECK (price > 0),
  currency     text NOT NULL DEFAULT 'AMD',
  comment      text NOT NULL DEFAULT '',
  -- Когда исполнитель сможет приступить: свободный текст («завтра с утра»)
  -- честнее календаря — у техники расписание меняется по ходу дня.
  eta          text NOT NULL DEFAULT '',
  unit_id      uuid,                          -- единица техники (сервис catalog/equipment)

  status       text NOT NULL DEFAULT 'active'
               CHECK (status IN ('active','withdrawn','declined','accepted','counter_offered')),
  decline_reason text NOT NULL DEFAULT '',

  -- Встречное предложение заказчика: один раунд (ТЗ §2.10), иначе торг
  -- превращается в базар. Заполняется только заказчиком.
  client_counter_price bigint CHECK (client_counter_price IS NULL OR client_counter_price > 0),
  client_counter_at    timestamptz,

  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

-- Один активный отклик на исполнителя: повторный тап не должен плодить
-- дубликаты в списке заказчика.
CREATE UNIQUE INDEX IF NOT EXISTS uq_offers_active_owner
  ON orders.offers (job_id, owner_id)
  WHERE status IN ('active','counter_offered','accepted');

CREATE INDEX IF NOT EXISTS idx_offers_job ON orders.offers (job_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_offers_owner ON orders.offers (owner_id, created_at DESC);

-- Победитель фикс-цены: ссылка на выбранный отклик.
ALTER TABLE orders.jobs ADD COLUMN IF NOT EXISTS winner_offer_id uuid;
