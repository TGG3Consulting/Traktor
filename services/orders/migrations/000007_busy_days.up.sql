-- Ручная блокировка дат «не работаю» (ТЗ §3.1, календарь занятости).
--
-- Дни с подтверждёнными сделками система знает сама, а вот отпуск, ремонт
-- техники или занятость на стороне — нет. Без этой таблицы исполнитель
-- получает ставки на даты, в которые он всё равно не выйдет, и вынужден
-- отказываться уже после выбора: хуже и для него, и для заказчика.

CREATE TABLE IF NOT EXISTS orders.busy_days (
  owner_id uuid NOT NULL,
  day      date NOT NULL,
  -- Короткая пометка для себя: «ремонт», «отпуск». Видит только владелец.
  note     text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (owner_id, day)
);

-- Календарь открывается помесячно: выборка идёт по владельцу и диапазону дат.
CREATE INDEX IF NOT EXISTS idx_busy_days_range ON orders.busy_days (owner_id, day);
