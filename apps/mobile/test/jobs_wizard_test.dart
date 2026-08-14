import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:traktor_mobile/features/auth/auth_controller.dart';
import 'package:traktor_mobile/features/jobs/create/step1_category.dart';
import 'package:traktor_mobile/features/jobs/create/wizard_controller.dart';
import 'package:traktor_mobile/features/jobs/feed_tab.dart';
import 'package:traktor_mobile/features/jobs/jobs_providers.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';

/// Тесты модуля заданий: сервер подменяется MockClient, поэтому проверяем
/// именно поведение экранов — что уходит на сервер и что видит человек.

Map<String, dynamic> _job({
  String id = 'j1',
  String status = 'draft',
  String title = 'Выкопать траншею',
  int? budget,
  String mode = 'fixed',
  double? distance,
  int draftStep = 1,
}) =>
    {
      'id': id,
      'clientId': 'c1',
      'status': status,
      'title': title,
      'mode': mode,
      'draftStep': draftStep,
      if (budget != null) 'budgetAmount': budget,
      if (distance != null) 'distanceM': distance,
      'currency': 'AMD',
    };

const _categories = {
  'items': [
    {
      'id': 'cat-earth',
      'kind': 'work',
      'slug': 'work-earth',
      'name': {'hy': 'Փորում', 'ru': 'Копка / земляные', 'en': 'Digging'},
      'icon': 'pickaxe',
      'specTemplate': [],
    },
    {
      'id': 'cat-transport',
      'kind': 'work',
      'slug': 'work-transport',
      'name': {'hy': 'Փոխադրում', 'ru': 'Перевозка', 'en': 'Transport'},
      'icon': 'truck',
      'specTemplate': [],
    },
  ]
};

/// Сессия «как после входа»: визард и «мои задания» работают только с ней,
/// а обновление токена по 401 читает её из этого же провайдера.
final _session = Session(
  accessToken: 'token',
  refreshToken: 'refresh',
  expiresInSec: 900,
  user: ApiUser(id: 'c1', phone: '+37491234567', roles: const ['client'], activeRole: 'client'),
);

/// Переопределения, общие для всех тестов модуля.
List<Override> _overrides(JobsApi api) => [
      jobsApiProvider.overrideWithValue(api),
      accessTokenProvider.overrideWithValue('token'),
      sessionProvider.overrideWith((ref) => _session),
    ];

http.Response _json(Object body, [int code = 200]) => http.Response(
      jsonEncode(body),
      code,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// Экраны визарда уходят на следующий шаг через go_router, поэтому в тесте
/// нужен настоящий роутер: заглушки на соседние шаги ловят переход.
Widget _wrap(Widget child, List<Override> overrides) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => child),
      for (final path in ['/home', '/jobs/create/2', '/jobs/create/3', '/jobs/create/4',
                          '/jobs/create/5'])
        GoRoute(path: path, builder: (_, __) => Scaffold(body: Text('экран $path'))),
      GoRoute(path: '/jobs/:id', builder: (_, state) =>
          Scaffold(body: Text('задание ${state.pathParameters['id']}'))),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('ru'),
      routerConfig: router,
    ),
  );
}

void main() {
  group('Шаг 1 визарда — выбор вида работ', () {
    testWidgets('категории приходят из справочника и показываются плитками',
        (tester) async {
      final api = JobsApi('http://x/v1', client: MockClient((_) async => _json(_categories)));

      await tester.pumpWidget(_wrap(
        const CreateStep1(),
        _overrides(api),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Копка / земляные'), findsOneWidget);
      expect(find.text('Перевозка'), findsOneWidget);
    });

    testWidgets('пока ничего не выбрано, «Далее» не работает и объясняет почему',
        (tester) async {
      final api = JobsApi('http://x/v1', client: MockClient((_) async => _json(_categories)));

      await tester.pumpWidget(_wrap(
        const CreateStep1(),
        _overrides(api),
      ));
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Далее'));
      expect(button.onPressed, isNull, reason: 'нельзя идти дальше без выбора');
      expect(find.textContaining('Выберите вид работ'), findsOneWidget);
    });

    testWidgets('выбор категории отправляет черновик на сервер', (tester) async {
      Map<String, dynamic>? sent;
      final api = JobsApi('http://x/v1', client: MockClient((req) async {
        if (req.url.path.endsWith('/categories')) return _json(_categories);
        sent = (jsonDecode(req.body) as Map).cast<String, dynamic>();
        return _json(_job(), 201);
      }));

      await tester.pumpWidget(_wrap(
        const CreateStep1(),
        _overrides(api),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Копка / земляные'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Далее'));
      await tester.pumpAndSettle();

      expect(sent, isNotNull, reason: 'черновик должен уйти на сервер сразу');
      expect(sent!['categoryId'], 'cat-earth');
      expect(sent!['draftStep'], 2);
    });
  });

  group('Контроллер визарда', () {
    test('первый шаг создаёт черновик, второй — обновляет его', () async {
      final calls = <String>[];
      final api = JobsApi('http://x/v1', client: MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        return _json(_job(draftStep: 2), req.method == 'POST' ? 201 : 200);
      }));
      final container = ProviderContainer(overrides: _overrides(api));
      addTearDown(container.dispose);
      final ctrl = container.read(wizardControllerProvider.notifier);

      await ctrl.save(const JobDraftInput(categoryId: 'cat-earth', draftStep: 2), goToStep: 2);
      await ctrl.save(const JobDraftInput(title: 'Копать', draftStep: 3), goToStep: 3);

      // Между шагами может уйти обновление списка «мои задания» — важно, что
      // первый шаг создаёт черновик, а второй правит уже существующий.
      expect(calls, containsAllInOrder(['POST /v1/jobs/drafts', 'PATCH /v1/jobs/drafts/j1']));
      expect(container.read(wizardControllerProvider).step, 3);
    });

    test('без входа черновик не создаётся, и об этом говорится прямо', () async {
      final api = JobsApi('http://x/v1', client: MockClient((_) async => _json(_job(), 201)));
      final container = ProviderContainer(overrides: [
        jobsApiProvider.overrideWithValue(api),
        accessTokenProvider.overrideWithValue(''),
      ]);
      addTearDown(container.dispose);

      final ok = await container
          .read(wizardControllerProvider.notifier)
          .save(const JobDraftInput(title: 'x'));

      expect(ok, isFalse);
      expect(container.read(wizardControllerProvider).error, contains('вход'));
    });

    test('неполный черновик: сервер возвращает разбор по полям, он попадает в состояние',
        () async {
      final api = JobsApi('http://x/v1', client: MockClient((req) async {
        if (req.method == 'POST' && req.url.path.endsWith('/publish')) {
          return http.Response(
            jsonEncode({
              'status': 422,
              'title': 'Не хватает данных для публикации',
              'fields': {'description': 'опишите подробнее', 'geo': 'укажите место'},
            }),
            422,
            headers: {'content-type': 'application/problem+json; charset=utf-8'},
          );
        }
        return _json(_job(), 201);
      }));
      final container = ProviderContainer(overrides: _overrides(api));
      addTearDown(container.dispose);
      final ctrl = container.read(wizardControllerProvider.notifier);
      await ctrl.save(const JobDraftInput(title: 'x'));

      final published = await ctrl.publish();

      expect(published, isNull);
      final state = container.read(wizardControllerProvider);
      expect(state.fieldErrors['geo'], 'укажите место');
      expect(state.fieldErrors['description'], isNotNull);
    });
  });

  group('Лента заданий', () {
    testWidgets('карточки показывают цену и расстояние', (tester) async {
      final api = JobsApi('http://x/v1', client: MockClient((req) async {
        if (req.url.path.endsWith('/categories')) return _json(_categories);
        return _json({
          'items': [
            _job(id: 'j1', status: 'bidding', title: 'Траншея 40 м',
                budget: 120000, mode: 'auction', distance: 4200),
          ]
        });
      }));

      await tester.pumpWidget(_wrap(
        const Scaffold(body: FeedTab()),
        _overrides(api),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Траншея 40 м'), findsOneWidget);
      expect(find.textContaining('120\u00A0000'), findsWidgets);
      expect(find.textContaining('4,2 км'), findsOneWidget);
    });

    testWidgets('пустая лента предлагает расширить радиус, а не молчит',
        (tester) async {
      final api = JobsApi('http://x/v1', client: MockClient((req) async {
        if (req.url.path.endsWith('/categories')) return _json(_categories);
        return _json({'items': []});
      }));

      await tester.pumpWidget(_wrap(
        const Scaffold(body: FeedTab()),
        _overrides(api),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Заданий поблизости нет'), findsOneWidget);
      expect(find.text('Радиус 100 км'), findsOneWidget);
    });

    testWidgets('сбой сети показывает причину и кнопку «Повторить»', (tester) async {
      final api = JobsApi('http://x/v1', client: MockClient((req) async {
        if (req.url.path.endsWith('/categories')) return _json(_categories);
        return _json({'title': 'сервис недоступен'}, 503);
      }));

      await tester.pumpWidget(_wrap(
        const Scaffold(body: FeedTab()),
        _overrides(api),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Не удалось загрузить'), findsOneWidget);
      expect(find.text('Повторить'), findsOneWidget);
    });
  });
}
