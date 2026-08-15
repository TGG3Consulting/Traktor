-- Удаление аккаунта с отсрочкой (ТЗ §2.3, §4.3 «приватность»).
--
-- Уйти с площадки человек должен мочь. Но удаление без отсрочки — это
-- необратимая кнопка рядом с обычными настройками: нажимают в сердцах, а
-- возвращаются через день. Поэтому запрос ставится в очередь на 30 дней,
-- и вход в этот срок отменяет удаление.
--
-- Профиль потом анонимизируется, а не стирается: на сделки ссылаются отзывы
-- и рейтинги второй стороны, и вычистить их значило бы наказать того, кто
-- остался.

ALTER TABLE identity.users
  -- Когда истекает отсрочка. NULL — удаление не запрошено.
  ADD COLUMN IF NOT EXISTS delete_after timestamptz,
  ADD COLUMN IF NOT EXISTS delete_requested_at timestamptz,
  -- Профиль обезличен: имя и телефон стёрты, идентификатор остался.
  ADD COLUMN IF NOT EXISTS anonymized_at timestamptz;

-- Обработчик забирает тех, у кого срок истёк.
CREATE INDEX IF NOT EXISTS idx_users_delete_due
  ON identity.users (delete_after) WHERE delete_after IS NOT NULL AND anonymized_at IS NULL;
