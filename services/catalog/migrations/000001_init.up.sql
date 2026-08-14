-- catalog · схема (Postgres 16). Миграции — golang-migrate, expand→contract.
-- Схема принадлежит только сервису catalog (schema-per-service, §2.3.11).
-- Cross-schema JOIN запрещён: другие сервисы хранят у себя category_id и
-- спрашивают названия у catalog по API.

CREATE SCHEMA IF NOT EXISTS catalog;

-- Дерево категорий (ТЗ §1.12 Category): корень — вид работ («Земляные
-- работы»), потомки — техника («Экскаватор») и её исполнения («Гусеничный»).
--
-- kind различает две ветви дерева:
--   work — что нужно сделать (шаг 1 визарда задания, §2.6);
--   unit — чем это делают (визард техники, §2.5).
-- Задание ссылается на work-категорию, техника — на unit-категорию.
CREATE TABLE IF NOT EXISTS catalog.categories (
  id            uuid PRIMARY KEY,
  parent_id     uuid REFERENCES catalog.categories(id) ON DELETE RESTRICT,
  kind          text NOT NULL CHECK (kind IN ('work','unit')),
  slug          text NOT NULL UNIQUE,           -- стабильный ключ для кода и аналитики
  name_hy       text NOT NULL,
  name_ru       text NOT NULL,
  name_en       text NOT NULL,
  -- Имя иконки Phosphor из design_system (TkIcons). Эмодзи запрещены (правило 8).
  icon          text NOT NULL DEFAULT 'wrench',
  -- Шаблон характеристик: массив полей {key,type,unit,min,max,options,label_*}.
  -- Из него строятся динамические поля шага 2 визарда задания и шага 2 визарда
  -- техники — без правок кода клиента при добавлении категории.
  spec_template jsonb NOT NULL DEFAULT '[]'::jsonb,
  sort_order    int  NOT NULL DEFAULT 100,
  active        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_categories_parent ON catalog.categories(parent_id);
CREATE INDEX IF NOT EXISTS idx_categories_kind   ON catalog.categories(kind, sort_order) WHERE active;

-- Transactional outbox (ADR-5, §2.3.12): изменения справочника публикуются
-- событиями, чтобы поиск и лента могли обновить свои проекции.
CREATE TABLE IF NOT EXISTS catalog.outbox (
  id           bigserial PRIMARY KEY,
  event_type   text NOT NULL,
  payload      jsonb NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_catalog_outbox_unpublished ON catalog.outbox(created_at) WHERE published_at IS NULL;
