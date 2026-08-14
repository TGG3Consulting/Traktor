import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('Справочник категорий', () {
    test('разбирает дерево, три языка и шаблон характеристик', () async {
      final api = JobsApi('http://x/v1', client: MockClient((req) async {
        expect(req.url.queryParameters['kind'], 'unit');
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'a',
                'kind': 'unit',
                'slug': 'unit-excavator',
                'name': {'hy': 'Էքսկավատոր', 'ru': 'Экскаватор', 'en': 'Excavator'},
                'icon': 'pickaxe',
                'specTemplate': [
                  {
                    'key': 'bucket',
                    'type': 'number',
                    'unit': 'м³',
                    'min': 0.05,
                    'max': 10,
                    'label_ru': 'Объём ковша',
                  }
                ],
                'children': [
                  {
                    'id': 'b',
                    'kind': 'unit',
                    'slug': 'unit-excavator-crawler',
                    'name': {'ru': 'Гусеничный'},
                    'icon': 'pickaxe',
                  }
                ],
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }));

      final cats = await api.categories(kind: 'unit');

      expect(cats, hasLength(1));
      expect(cats.first.name.forLang('hy'), 'Էքսկավատոր');
      expect(cats.first.name.forLang('en'), 'Excavator');
      expect(cats.first.icon, 'pickaxe');
      expect(cats.first.specTemplate.first.unit, 'м³');
      expect(cats.first.children.single.name.forLang('ru'), 'Гусеничный');
    });

    test('пустой перевод подменяется русским, чтобы экран не был пустым', () {
      const name = LocalizedName(ru: 'Перевозка');
      expect(name.forLang('hy'), 'Перевозка');
      expect(name.forLang('en'), 'Перевозка');
    });
  });

  group('Задания', () {
    test('лента передаёт фильтры и разбирает расстояние', () async {
      late Uri seen;
      final api = JobsApi('http://x/v1', client: MockClient((req) async {
        seen = req.url;
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'j1',
                'clientId': 'c1',
                'status': 'bidding',
                'title': 'Траншея',
                'mode': 'auction',
                'budgetAmount': 120000,
                'distanceM': 4200.0,
                'auction': {'durationH': 24, 'endsAt': '2026-08-16T10:00:00Z'},
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }));

      final jobs = await api.feed(
        lat: 40.18,
        lng: 44.51,
        radiusKm: 25,
        categoryIds: ['c-1', 'c-2'],
        mode: 'auction',
        sort: 'near',
      );

      expect(seen.queryParameters['radiusKm'], '25.0');
      expect(seen.queryParameters['categoryIds'], 'c-1,c-2');
      expect(seen.queryParameters['sort'], 'near');
      expect(jobs.single.distanceM, 4200.0);
      expect(jobs.single.isAuction, isTrue);
      expect(jobs.single.auction!.endsAt, isNotNull);
    });

    test('черновик отправляет только заданные поля', () async {
      late Map<String, dynamic> body;
      final api = JobsApi('http://x/v1', client: MockClient((req) async {
        body = (jsonDecode(req.body) as Map).cast<String, dynamic>();
        return http.Response(
          jsonEncode({'id': 'j1', 'clientId': 'c1', 'status': 'draft'}),
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }));

      await api.createDraft(
        'token',
        const JobDraftInput(title: 'Копать', draftStep: 2),
        idempotencyKey: 'k1',
      );

      expect(body.keys, containsAll(['title', 'draftStep']));
      expect(body.containsKey('budgetAmount'), isFalse,
          reason: 'незаданное поле не должно уходить: сервер иначе затрёт его');
    });

    test('422 превращается в разбор по полям для визарда', () async {
      final api = JobsApi('http://x/v1', client: MockClient((req) async {
        return http.Response(
          jsonEncode({
            'status': 422,
            'code': 'validation_failed',
            'title': 'Не хватает данных для публикации',
            'fields': {'description': 'опишите задачу подробнее', 'geo': 'укажите место'},
          }),
          422,
          headers: {'content-type': 'application/problem+json; charset=utf-8'},
        );
      }));

      expect(
        () => api.publish('token', 'j1', idempotencyKey: 'k'),
        throwsA(isA<ValidationException>()
            .having((e) => e.fields['geo'], 'поле geo', 'укажите место')),
      );
    });

    test('прочие ошибки приходят как ApiException с кодом', () async {
      final api = JobsApi('http://x/v1', client: MockClient((req) async {
        return http.Response(
          jsonEncode({'status': 409, 'title': 'менять можно только черновик'}),
          409,
          headers: {'content-type': 'application/problem+json; charset=utf-8'},
        );
      }));

      expect(
        () => api.publish('token', 'j1', idempotencyKey: 'k'),
        throwsA(isA<ApiException>().having((e) => e.status, 'код', 409)),
      );
    });
  });
}
