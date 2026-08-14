-- orders · схема (Postgres 16 + PostGIS). Миграции — golang-migrate.
-- Схема принадлежит только сервису orders (schema-per-service, §2.3.11).
-- Cross-schema JOIN запрещён: имя заказчика и название категории клиент
-- получает у identity и catalog, здесь хранятся только идентификаторы.

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE SCHEMA IF NOT EXISTS orders;

-- Задание (ТЗ §1.12 Job). Черновик — то же задание в статусе draft: так
-- «продолжить черновик» и «мои задания» читаются одним запросом, а не двумя
-- (в прототипе черновик стоит в общем списке на главной заказчика).
CREATE TABLE IF NOT EXISTS orders.jobs (
  id             uuid PRIMARY KEY,
  client_id      uuid NOT NULL,                 -- заказчик (из проверенного JWT)

  -- Тип заказа (ТЗ §5.1). В этой фазе полностью реализован job, остальные
  -- принимаются и хранятся, их сценарии — следующие фазы.
  order_type     text NOT NULL DEFAULT 'job'
                 CHECK (order_type IN ('job','rental','transport','workers')),
  category_id    uuid,                          -- work-категория из catalog
  -- «Опишу задачу — пусть исполнители сами предложат технику» (§2.6 шаг 1).
  open_to_any    boolean NOT NULL DEFAULT false,

  title          text NOT NULL DEFAULT '',
  description    text NOT NULL DEFAULT '',
  params         jsonb NOT NULL DEFAULT '{}'::jsonb,   -- значения по specTemplate
  photos         jsonb NOT NULL DEFAULT '[]'::jsonb,   -- ссылки на медиа

  -- Место. geography(Point) — расстояния считает база в метрах по сфере,
  -- без самодельной математики; address — человеческий адрес для карточки.
  geo            geography(Point, 4326),
  address        text NOT NULL DEFAULT '',
  access         text NOT NULL DEFAULT 'unknown' CHECK (access IN ('yes','no','unknown')),

  -- Когда нужно (§2.6 шаг 3): как можно скорее | диапазон | точная дата.
  date_mode      text NOT NULL DEFAULT 'asap' CHECK (date_mode IN ('asap','range','exact')),
  date_start     timestamptz,
  date_end       timestamptz,

  -- Цена и режим (§2.6 шаг 4). Суммы — в минорных единицах нет смысла: AMD
  -- без копеек, но поле currency обязательно (ТЗ §18).
  budget_amount  bigint,
  currency       text NOT NULL DEFAULT 'AMD',
  mode           text NOT NULL DEFAULT 'fixed' CHECK (mode IN ('fixed','auction')),

  -- Параметры аукциона. reserve_amount скрыт от исполнителей — отдаётся
  -- только владельцу задания.
  auction_duration_h  int,
  auction_ends_at     timestamptz,
  reserve_amount      bigint,
  auto_extend         boolean NOT NULL DEFAULT true,
  decision_window_h   int NOT NULL DEFAULT 12,

  -- Разнорабочие как дополнение к любому типу заказа (§5.5).
  workers_count  int NOT NULL DEFAULT 0 CHECK (workers_count >= 0),

  status         text NOT NULL DEFAULT 'draft' CHECK (status IN (
                   'draft','published','collecting_offers','bidding','deal_pending',
                   'deciding','confirmed','in_progress','work_done','completed',
                   'disputed','cancelled','declined_all','expired','expired_no_bids')),
  draft_step     int NOT NULL DEFAULT 1 CHECK (draft_step BETWEEN 1 AND 5),

  views_count    int NOT NULL DEFAULT 0,
  offers_count   int NOT NULL DEFAULT 0,
  winner_bid_id  uuid,

  published_at   timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

-- Лента исполнителя: «что рядом и ещё открыто». Гео-индекс обязателен —
-- без него радиусный запрос читает всю таблицу.
CREATE INDEX IF NOT EXISTS idx_jobs_geo ON orders.jobs USING gist (geo)
  WHERE status IN ('published','collecting_offers','bidding');
CREATE INDEX IF NOT EXISTS idx_jobs_feed ON orders.jobs (status, published_at DESC)
  WHERE status IN ('published','collecting_offers','bidding');
-- Главная заказчика: его задания, свежие сверху, черновики вместе с ними.
CREATE INDEX IF NOT EXISTS idx_jobs_client ON orders.jobs (client_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_jobs_category ON orders.jobs (category_id)
  WHERE status IN ('published','collecting_offers','bidding');
-- Финиш аукционов ищет фоновый обработчик (следующая фаза).
CREATE INDEX IF NOT EXISTS idx_jobs_auction_ends ON orders.jobs (auction_ends_at)
  WHERE status = 'bidding';

-- Просмотры считаем по паре (задание, зритель): иначе счётчик накручивается
-- обновлением экрана, и цифра в карточке перестаёт что-либо значить.
CREATE TABLE IF NOT EXISTS orders.job_views (
  job_id     uuid NOT NULL REFERENCES orders.jobs(id) ON DELETE CASCADE,
  viewer_id  uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (job_id, viewer_id)
);

-- Ключи идемпотентности мутаций (§2.3.12): повтор запроса с тем же ключом
-- возвращает прежний результат, а не создаёт второе задание.
CREATE TABLE IF NOT EXISTS orders.idempotency (
  key         text PRIMARY KEY,
  user_id     uuid NOT NULL,
  endpoint    text NOT NULL,
  job_id      uuid,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_idempotency_created ON orders.idempotency (created_at);

-- Transactional outbox (ADR-5): события публикации/смены статуса уходят в
-- шину в одной транзакции с изменением задания.
CREATE TABLE IF NOT EXISTS orders.outbox (
  id           bigserial PRIMARY KEY,
  event_type   text NOT NULL,
  payload      jsonb NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_orders_outbox_unpublished ON orders.outbox(created_at) WHERE published_at IS NULL;
