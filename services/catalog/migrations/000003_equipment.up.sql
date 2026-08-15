-- Техника исполнителя (ТЗ §2.5).
--
-- Живёт в схеме catalog: это карточка единицы техники, привязанная к категории
-- справочника, и по архитектуре именно catalog владеет техникой, тарифами и
-- её верификацией. Связь с пользователем — по owner_id из проверенного JWT,
-- без FK на чужую схему (schema-per-service).

CREATE TABLE IF NOT EXISTS catalog.equipment (
  id          uuid PRIMARY KEY,
  owner_id    uuid NOT NULL,
  category_id uuid NOT NULL REFERENCES catalog.categories(id),

  brand       text NOT NULL DEFAULT '',
  model       text NOT NULL DEFAULT '',
  year        smallint,

  -- Характеристики по specTemplate категории: у экскаватора ковш и глубина,
  -- у самосвала — тоннаж и кузов. Хранятся как есть, форму строит клиент.
  specs       jsonb NOT NULL DEFAULT '{}'::jsonb,

  -- Тарифы аренды (ТЗ §2.5, v1.1). NULL — техника не сдаётся почасово.
  price_hour  bigint,
  price_shift bigint,
  price_day   bigint,
  min_hours   smallint,
  delivery    bigint,

  -- Бригада рабочих, которую исполнитель привозит с техникой.
  crew_size   smallint NOT NULL DEFAULT 0,
  crew_price  bigint,

  photos      text[] NOT NULL DEFAULT '{}',
  -- Документы видит только модерация, в профиле они не публикуются (ТЗ §2.5).
  docs        text[] NOT NULL DEFAULT '{}',

  -- draft — черновик визарда, pending — на проверке, verified — «Проверен ✓»,
  -- unverified — опубликована без документов, rejected — отклонена модерацией,
  -- archived — снята владельцем.
  status      text NOT NULL DEFAULT 'draft'
              CHECK (status IN ('draft','pending','verified','unverified','rejected','archived')),
  reject_reason text NOT NULL DEFAULT '',

  -- Шаг визарда, на котором остановились: черновик открывается там же.
  draft_step  smallint NOT NULL DEFAULT 1,

  -- Сколько работ выиграно этой машиной — показывается в карточке.
  wins        integer NOT NULL DEFAULT 0,

  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- Список «Моя техника»: свои машины, свежие сверху.
CREATE INDEX IF NOT EXISTS idx_equipment_owner ON catalog.equipment (owner_id, created_at DESC);
-- Очередь модерации.
CREATE INDEX IF NOT EXISTS idx_equipment_pending ON catalog.equipment (created_at) WHERE status = 'pending';
-- Подбор техники по категории (для откликов и аукциона).
CREATE INDEX IF NOT EXISTS idx_equipment_category ON catalog.equipment (category_id) WHERE status IN ('verified','unverified');
