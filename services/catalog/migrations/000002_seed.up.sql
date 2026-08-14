-- Первичное наполнение справочника (ТЗ §2.5, §2.6 и прототип, экран create1).
--
-- Идентификаторы детерминированные (uuid v5 от slug) — одинаковые в dev, stage
-- и prod, поэтому ссылки на категорию переносимы между средами.
-- Наполнение — часть схемы: справочник нужен приложению с первого запуска.
-- Тигран расширит список вместе со мной (Фаза 3), тогда правки пойдут
-- отдельными миграциями, а не переписыванием этой.
--
-- icon — имя иконки Phosphor из design_system (TkIcons), эмодзи запрещены.
-- spec_template — поля характеристик: они превращаются в поля формы на клиенте.
--   type: number | text | select | bool; unit — единица измерения для подписи.

-- ── Виды работ (шаг 1 визарда задания) ───────────────────────────────────────
INSERT INTO catalog.categories (id, parent_id, kind, slug, name_hy, name_ru, name_en, icon, sort_order, spec_template) VALUES
('c02b2502-1789-5217-be9f-d5fc04fe1cae', NULL, 'work', 'work-earth',
 'Փորում / հողային աշխատանքներ', 'Копка / земляные', 'Digging / earthworks', 'pickaxe', 10,
 '[{"key":"length","type":"number","unit":"м","min":1,"max":10000,"label_hy":"Երկարություն","label_ru":"Длина","label_en":"Length"},
   {"key":"depth","type":"number","unit":"м","min":0.2,"max":20,"label_hy":"Խորություն","label_ru":"Глубина","label_en":"Depth"},
   {"key":"volume","type":"number","unit":"м³","min":1,"max":100000,"label_hy":"Ծավալ","label_ru":"Объём","label_en":"Volume"},
   {"key":"soil","type":"select","options":["soft","clay","rocky","unknown"],"label_hy":"Հողի տեսակ","label_ru":"Тип грунта","label_en":"Soil type"}]'::jsonb),

('53c1323a-bcf6-5f4e-bed4-08e1884f61ac', NULL, 'work', 'work-transport',
 'Փոխադրում', 'Перевозка', 'Transport', 'truck', 20,
 '[{"key":"weight","type":"number","unit":"т","min":0.1,"max":60,"label_hy":"Քաշ","label_ru":"Вес","label_en":"Weight"},
   {"key":"volume","type":"number","unit":"м³","min":1,"max":200,"label_hy":"Ծավալ","label_ru":"Объём","label_en":"Volume"},
   {"key":"loading","type":"select","options":["mine","need_workers"],"label_hy":"Բեռնում","label_ru":"Погрузка","label_en":"Loading"}]'::jsonb),

('2bba63e8-221c-5cf9-a1f1-1df837b8ae8d', NULL, 'work', 'work-crane',
 'Ամբարձիչ / բարձրացում', 'Кран / подъём', 'Crane / lifting', 'crane', 30,
 '[{"key":"weight","type":"number","unit":"т","min":0.1,"max":200,"label_hy":"Բեռի քաշ","label_ru":"Вес груза","label_en":"Load weight"},
   {"key":"height","type":"number","unit":"м","min":1,"max":120,"label_hy":"Բարձրություն","label_ru":"Высота подъёма","label_en":"Lift height"},
   {"key":"hours","type":"number","unit":"ч","min":1,"max":24,"label_hy":"Ժամեր","label_ru":"Часов работы","label_en":"Hours"}]'::jsonb),

('4a4c7705-c7bd-576e-a2e6-66d984aa40cb', NULL, 'work', 'work-demolition',
 'Քանդում', 'Снос', 'Demolition', 'demolition', 40,
 '[{"key":"area","type":"number","unit":"м²","min":1,"max":100000,"label_hy":"Մակերես","label_ru":"Площадь","label_en":"Area"},
   {"key":"floors","type":"number","unit":"эт","min":1,"max":30,"label_hy":"Հարկեր","label_ru":"Этажей","label_en":"Floors"},
   {"key":"debris_removal","type":"bool","label_hy":"Աղբի հեռացում","label_ru":"Вывоз мусора","label_en":"Debris removal"}]'::jsonb),

('88e48020-e3c7-5db7-8b3f-b2aaeb2ec27b', NULL, 'work', 'work-agro',
 'Գյուղատնտեսություն', 'Сельхоз', 'Agriculture', 'plant', 50,
 '[{"key":"area","type":"number","unit":"га","min":0.01,"max":1000,"label_hy":"Մակերես","label_ru":"Площадь","label_en":"Area"},
   {"key":"work_type","type":"select","options":["plowing","harrowing","sowing","harvest","other"],"label_hy":"Աշխատանքի տեսակ","label_ru":"Вид работ","label_en":"Work type"}]'::jsonb),

('9fe9e36e-3cfa-5bff-88c2-d3cb185b5b01', NULL, 'work', 'work-clearing',
 'Մաքրում / ձյուն', 'Расчистка / снег', 'Clearing / snow', 'snowflake', 60,
 '[{"key":"area","type":"number","unit":"м²","min":10,"max":100000,"label_hy":"Մակերես","label_ru":"Площадь","label_en":"Area"},
   {"key":"removal","type":"bool","label_hy":"Դուրս բերել","label_ru":"Вывезти с участка","label_en":"Haul away"}]'::jsonb),

('ac1a993d-8d9d-5496-8c26-3d2e80163260', NULL, 'work', 'work-other',
 'Այլ', 'Другое', 'Other', 'wrench', 900, '[]'::jsonb);

-- ── Техника (визард техники исполнителя, §2.5) ───────────────────────────────
INSERT INTO catalog.categories (id, parent_id, kind, slug, name_hy, name_ru, name_en, icon, sort_order, spec_template) VALUES
('9e436346-39f0-59a1-b03b-d44b67d0176b', NULL, 'unit', 'unit-excavator',
 'Էքսկավատոր', 'Экскаватор', 'Excavator', 'pickaxe', 10,
 '[{"key":"bucket","type":"number","unit":"м³","min":0.05,"max":10,"label_hy":"Շերեփի ծավալ","label_ru":"Объём ковша","label_en":"Bucket volume"},
   {"key":"dig_depth","type":"number","unit":"м","min":1,"max":20,"label_hy":"Փորման խորություն","label_ru":"Глубина копания","label_en":"Digging depth"},
   {"key":"weight","type":"number","unit":"т","min":0.5,"max":100,"label_hy":"Զանգված","label_ru":"Масса","label_en":"Weight"}]'::jsonb),

('d715cbe5-bafe-518a-b82d-3b982379f859', '9e436346-39f0-59a1-b03b-d44b67d0176b', 'unit', 'unit-excavator-crawler',
 'Թրթուրավոր', 'Гусеничный', 'Crawler', 'pickaxe', 10, '[]'::jsonb),
('3d92664a-b079-57a2-9182-485182d8d467', '9e436346-39f0-59a1-b03b-d44b67d0176b', 'unit', 'unit-excavator-wheel',
 'Անվավոր', 'Колёсный', 'Wheeled', 'pickaxe', 20, '[]'::jsonb),
('07613493-48b3-5c5a-81d1-01baebf236b6', '9e436346-39f0-59a1-b03b-d44b67d0176b', 'unit', 'unit-mini-excavator',
 'Մինի-էքսկավատոր', 'Мини-экскаватор', 'Mini excavator', 'pickaxe', 30, '[]'::jsonb),

('e696351b-2afa-5b8f-a30f-91042a760a2f', NULL, 'unit', 'unit-backhoe',
 'Էքսկավատոր-բեռնիչ', 'Экскаватор-погрузчик', 'Backhoe loader', 'tractor', 20,
 '[{"key":"bucket","type":"number","unit":"м³","min":0.05,"max":3,"label_hy":"Շերեփի ծավալ","label_ru":"Объём ковша","label_en":"Bucket volume"},
   {"key":"dig_depth","type":"number","unit":"м","min":1,"max":8,"label_hy":"Փորման խորություն","label_ru":"Глубина копания","label_en":"Digging depth"}]'::jsonb),

('41a41248-9ad2-537c-8b1e-fd3e575cd92c', NULL, 'unit', 'unit-bulldozer',
 'Բուլդոզեր', 'Бульдозер', 'Bulldozer', 'tractor', 30,
 '[{"key":"blade","type":"number","unit":"м","min":1,"max":6,"label_hy":"Դանակի լայնություն","label_ru":"Ширина отвала","label_en":"Blade width"},
   {"key":"weight","type":"number","unit":"т","min":1,"max":100,"label_hy":"Զանգված","label_ru":"Масса","label_en":"Weight"}]'::jsonb),

('6baa51f0-8898-5d6b-9107-4108cd6c984f', NULL, 'unit', 'unit-dump-truck',
 'Ինքնաթափ', 'Самосвал', 'Dump truck', 'truck', 40,
 '[{"key":"payload","type":"number","unit":"т","min":1,"max":60,"label_hy":"Բեռնունակություն","label_ru":"Грузоподъёмность","label_en":"Payload"},
   {"key":"body_volume","type":"number","unit":"м³","min":1,"max":40,"label_hy":"Թափքի ծավալ","label_ru":"Объём кузова","label_en":"Body volume"}]'::jsonb),

('be60cef7-92d4-55d5-8cf5-7d0b3fac916f', NULL, 'unit', 'unit-mobile-crane',
 'Ավտոամբարձիչ', 'Автокран', 'Mobile crane', 'crane', 50,
 '[{"key":"capacity","type":"number","unit":"т","min":1,"max":500,"label_hy":"Բեռնունակություն","label_ru":"Грузоподъёмность","label_en":"Capacity"},
   {"key":"boom","type":"number","unit":"м","min":5,"max":120,"label_hy":"Սլաքի երկարություն","label_ru":"Длина стрелы","label_en":"Boom length"}]'::jsonb),

('e6bb346a-e810-5d63-9b13-46f16a424f6d', NULL, 'unit', 'unit-knuckle-truck',
 'Մանիպուլյատոր', 'Манипулятор', 'Knuckle boom truck', 'crane', 60,
 '[{"key":"capacity","type":"number","unit":"т","min":0.5,"max":40,"label_hy":"Բեռնունակություն","label_ru":"Грузоподъёмность","label_en":"Capacity"},
   {"key":"boom","type":"number","unit":"м","min":3,"max":40,"label_hy":"Սլաքի երկարություն","label_ru":"Длина стрелы","label_en":"Boom length"}]'::jsonb),

('8fcc219f-3807-58b5-9121-3d8b034751d4', NULL, 'unit', 'unit-tractor',
 'Տրակտոր', 'Трактор', 'Tractor', 'tractor', 70,
 '[{"key":"power","type":"number","unit":"л.с.","min":10,"max":600,"label_hy":"Հզորություն","label_ru":"Мощность","label_en":"Power"},
   {"key":"attachments","type":"text","label_hy":"Կցորդներ","label_ru":"Навесное оборудование","label_en":"Attachments"}]'::jsonb),

('35ad77d4-32d7-5e4c-aca1-10d486148491', NULL, 'unit', 'unit-wheel-loader',
 'Ճակատային բեռնիչ', 'Фронтальный погрузчик', 'Wheel loader', 'tractor', 80,
 '[{"key":"bucket","type":"number","unit":"м³","min":0.3,"max":15,"label_hy":"Շերեփի ծավալ","label_ru":"Объём ковша","label_en":"Bucket volume"}]'::jsonb),

('b5fff974-74fc-5e17-a6c7-aa85c869e910', NULL, 'unit', 'unit-aerial-platform',
 'Ավտոաշտարակ', 'Автовышка', 'Aerial platform', 'crane', 90,
 '[{"key":"height","type":"number","unit":"м","min":5,"max":100,"label_hy":"Աշխատանքային բարձրություն","label_ru":"Рабочая высота","label_en":"Working height"}]'::jsonb),

('f0d1d80d-7d32-5a03-91e8-732600b7cce0', NULL, 'unit', 'unit-auger',
 'Հորատող', 'Ямобур', 'Auger drill', 'pickaxe', 100,
 '[{"key":"diameter","type":"number","unit":"мм","min":100,"max":2000,"label_hy":"Տրամագիծ","label_ru":"Диаметр","label_en":"Diameter"},
   {"key":"depth","type":"number","unit":"м","min":1,"max":30,"label_hy":"Խորություն","label_ru":"Глубина","label_en":"Depth"}]'::jsonb),

('4940ea1a-4cfd-5b19-9490-9a96ff08735a', NULL, 'unit', 'unit-grader',
 'Գրեյդեր', 'Грейдер', 'Grader', 'tractor', 110,
 '[{"key":"blade","type":"number","unit":"м","min":2,"max":8,"label_hy":"Դանակի լայնություն","label_ru":"Ширина отвала","label_en":"Blade width"}]'::jsonb),

('90c7cac4-69a6-5ac4-b603-11f9baa6f6a4', NULL, 'unit', 'unit-roller',
 'Գլդոն', 'Каток', 'Road roller', 'tractor', 120,
 '[{"key":"weight","type":"number","unit":"т","min":0.5,"max":30,"label_hy":"Զանգված","label_ru":"Масса","label_en":"Weight"}]'::jsonb),

('08de701b-6e0e-5abe-9948-f49c8372733f', NULL, 'unit', 'unit-mixer',
 'Բետոնախառնիչ', 'Бетоносмеситель', 'Concrete mixer', 'truck', 130,
 '[{"key":"volume","type":"number","unit":"м³","min":1,"max":15,"label_hy":"Ծավալ","label_ru":"Объём","label_en":"Volume"}]'::jsonb),

('37373f0f-1d4f-5a00-8183-2e52e239aa01', NULL, 'unit', 'unit-tow-truck',
 'Էվակուատոր', 'Эвакуатор', 'Tow truck', 'truck', 140,
 '[{"key":"payload","type":"number","unit":"т","min":1,"max":40,"label_hy":"Բեռնունակություն","label_ru":"Грузоподъёмность","label_en":"Payload"}]'::jsonb),

('a14628f4-bde4-5591-93c3-9b497e0d9887', NULL, 'unit', 'unit-other',
 'Այլ տեխնիկա', 'Другая техника', 'Other machinery', 'wrench', 900, '[]'::jsonb);
