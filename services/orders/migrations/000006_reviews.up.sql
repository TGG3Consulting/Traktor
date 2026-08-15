-- Взаимные оценки после сделки (ТЗ §2.13).
--
-- Отзыв принадлежит сделке: без завершённой работы оценивать нечего. Он живёт
-- в схеме orders, а профиль в identity хранит только сводку (schema-per-service).
--
-- published_at пустой, пока отзыв «в ожидании»: он открывается либо когда
-- оценили обе стороны, либо через неделю. Так оценка не подстраивается под
-- чужую и не превращается в месть за низкий балл.

CREATE TABLE IF NOT EXISTS orders.reviews (
  id           uuid PRIMARY KEY,
  deal_id      uuid NOT NULL REFERENCES orders.deals(id) ON DELETE CASCADE,
  job_id       uuid NOT NULL REFERENCES orders.jobs(id) ON DELETE CASCADE,

  author_id    uuid NOT NULL,
  target_id    uuid NOT NULL,
  -- Кем был автор в сделке: client оценивает исполнителя, owner — заказчика.
  author_role  text NOT NULL CHECK (author_role IN ('client','owner')),

  stars        smallint NOT NULL CHECK (stars BETWEEN 1 AND 5),
  tags         text[] NOT NULL DEFAULT '{}',
  body         text NOT NULL DEFAULT '',

  -- «Что пошло не так» при оценке ниже трёх звёзд — материал для модерации,
  -- публично не показывается.
  issue        text NOT NULL DEFAULT '',

  -- Ответ на отзыв: один раз, публично (ТЗ §2.13).
  reply_text   text NOT NULL DEFAULT '',
  reply_at     timestamptz,

  published_at timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- Одна оценка на человека в сделке: вторая попытка должна получать отказ,
-- а не тихо добавлять ещё одну звезду в рейтинг.
CREATE UNIQUE INDEX IF NOT EXISTS uq_reviews_deal_author ON orders.reviews (deal_id, author_id);

-- Карточка профиля: опубликованные отзывы о человеке, свежие сверху.
CREATE INDEX IF NOT EXISTS idx_reviews_target ON orders.reviews (target_id, published_at DESC NULLS LAST);

-- Фоновая публикация «просроченных» одиночных оценок ищет именно по этому.
CREATE INDEX IF NOT EXISTS idx_reviews_pending ON orders.reviews (created_at) WHERE published_at IS NULL;
