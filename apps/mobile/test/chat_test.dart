import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:traktor_mobile/features/auth/auth_controller.dart';
import 'package:traktor_mobile/features/chat/chat_screen.dart';
import 'package:traktor_mobile/features/chat/chats_tab.dart';
import 'package:traktor_mobile/features/jobs/jobs_providers.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';

/// Тесты переписки (ТЗ §2.12). Сервер подменён MockClient — проверяем то, что
/// видит человек: свои и чужие сообщения, предупреждение о скрытом телефоне,
/// счётчик непрочитанного.

final _session = Session(
  accessToken: 'token',
  refreshToken: 'refresh',
  expiresInSec: 900,
  user: ApiUser(id: 'me', phone: '+37491234567', roles: const ['client'], activeRole: 'client'),
);

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

Widget _wrap(Widget child, List<Override> overrides) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => Scaffold(body: child)),
      GoRoute(
        path: '/chats/:id',
        builder: (_, state) => Scaffold(body: Text('чат ${state.pathParameters['id']}')),
      ),
      GoRoute(path: '/home', builder: (_, __) => const Scaffold(body: Text('дом'))),
      GoRoute(
        path: '/jobs/:id',
        builder: (_, state) => Scaffold(body: Text('задание ${state.pathParameters['id']}')),
      ),
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

Map<String, dynamic> _chat({String kind = 'pre_deal'}) => {
      'id': 'chat-1',
      'jobId': 'job-1',
      'kind': kind,
      'peerName': 'Карен Саркисян',
      'jobTitle': 'Убрать снег',
    };

void main() {
  group('Список переписок', () {
    testWidgets('показывает собеседника, задание и счётчик непрочитанного',
        (tester) async {
      final api = JobsApi(
        'http://x/v1',
        client: MockClient((_) async => _json({
              'items': [
                {
                  ..._chat(),
                  'lastText': 'Буду на месте к 9 утра',
                  'lastMessageAt': DateTime.now().toIso8601String(),
                  'unread': 2,
                }
              ]
            })),
      );

      await tester.pumpWidget(_wrap(const ChatsTab(), _overrides(api)));
      await tester.pumpAndSettle();

      expect(find.textContaining('Карен Саркисян'), findsOneWidget);
      expect(find.textContaining('Убрать снег'), findsOneWidget);
      expect(find.text('Буду на месте к 9 утра'), findsOneWidget);
      expect(find.text('2'), findsOneWidget, reason: 'непрочитанные видны бейджем');
    });

    testWidgets('пустой список объясняет, откуда берутся переписки',
        (tester) async {
      final api = JobsApi(
        'http://x/v1',
        client: MockClient((_) async => _json({'items': []})),
      );

      await tester.pumpWidget(_wrap(const ChatsTab(), _overrides(api)));
      await tester.pumpAndSettle();

      expect(find.text('Переписок пока нет'), findsOneWidget);
    });

    testWidgets('нажатие открывает переписку', (tester) async {
      final api = JobsApi(
        'http://x/v1',
        client: MockClient((_) async => _json({
              'items': [
                {..._chat(), 'lastText': 'Здравствуйте', 'unread': 0}
              ]
            })),
      );

      await tester.pumpWidget(_wrap(const ChatsTab(), _overrides(api)));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Карен Саркисян'));
      await tester.pumpAndSettle();

      expect(find.text('чат chat-1'), findsOneWidget);
    });
  });

  group('Экран переписки', () {
    Widget screen(JobsApi api) => _wrap(const ChatScreen(chatId: 'chat-1'), _overrides(api));

    JobsApi apiWith({
      String kind = 'pre_deal',
      List<Map<String, dynamic>> messages = const [],
      void Function(http.Request req)? onPost,
      Map<String, dynamic>? sent,
    }) {
      return JobsApi(
        'http://x/v1',
        client: MockClient((req) async {
          if (req.method == 'POST') {
            onPost?.call(req);
            return _json(
              sent ??
                  {
                    'message': {
                      'id': 'm-new',
                      'chatId': 'chat-1',
                      'senderId': 'me',
                      'kind': 'text',
                      'text': 'Хорошо',
                      'createdAt': DateTime.now().toIso8601String(),
                    },
                    'contactsMasked': false,
                  },
              201,
            );
          }
          if (req.url.path.endsWith('/messages')) {
            return _json({'items': messages});
          }
          return _json(_chat(kind: kind));
        }),
      );
    }

    testWidgets('до сделки экран честно предупреждает, что контакты скрыты',
        (tester) async {
      await tester.pumpWidget(screen(apiWith()));
      await tester.pumpAndSettle();

      expect(find.textContaining('До сделки'), findsOneWidget);
      expect(
        find.textContaining('Телефоны откроются после подтверждения'),
        findsOneWidget,
      );
    });

    testWidgets('в чате сделки напоминания о маскировке нет', (tester) async {
      await tester.pumpWidget(screen(apiWith(kind: 'deal')));
      await tester.pumpAndSettle();

      expect(find.textContaining('контакты открыты'), findsOneWidget);
      expect(find.textContaining('Телефоны откроются'), findsNothing);
    });

    testWidgets('системные сообщения отделены от переписки', (tester) async {
      await tester.pumpWidget(screen(apiWith(kind: 'deal', messages: [
        {
          'id': 'm1',
          'chatId': 'chat-1',
          'kind': 'system',
          'text': 'Сделка подтверждена',
          'createdAt': DateTime.now().toIso8601String(),
        },
        {
          'id': 'm2',
          'chatId': 'chat-1',
          'senderId': 'peer',
          'kind': 'text',
          'text': 'Добрый вечер!',
          'createdAt': DateTime.now().toIso8601String(),
        },
      ])));
      await tester.pumpAndSettle();

      expect(find.text('Сделка подтверждена'), findsOneWidget);
      expect(find.text('Добрый вечер!'), findsOneWidget);
    });

    testWidgets('отправка уходит на сервер и очищает поле', (tester) async {
      String? body;
      final api = apiWith(onPost: (req) => body = req.body);

      await tester.pumpWidget(screen(api));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Хорошо');
      await tester.tap(find.bySemanticsLabel('Отправить'));
      await tester.pumpAndSettle();

      expect(body, contains('Хорошо'));
      expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, isEmpty);
    });

    testWidgets('скрытый телефон объясняется отправителю, а не молча правится',
        (tester) async {
      final api = apiWith(sent: {
        'message': {
          'id': 'm-new',
          'chatId': 'chat-1',
          'senderId': 'me',
          'kind': 'text',
          'text': 'Звоните ••• ••',
          'createdAt': DateTime.now().toIso8601String(),
        },
        'contactsMasked': true,
      });

      await tester.pumpWidget(screen(api));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Звоните +374 91 234 567');
      await tester.tap(find.bySemanticsLabel('Отправить'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Похоже на обмен контактами'), findsOneWidget);
    });

    testWidgets('пустое сообщение не отправляется', (tester) async {
      var posts = 0;
      final api = apiWith(onPost: (_) => posts++);

      await tester.pumpWidget(screen(api));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.bySemanticsLabel('Отправить'));
      await tester.pumpAndSettle();

      expect(posts, 0);
    });
  });
}
