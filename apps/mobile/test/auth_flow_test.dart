// Тесты вертикали входа: контроллер входа, персист сессии и выход.
// Логика проверяется без сети — на fake-репозитории и in-memory настройках
// SharedPreferences (правило 7: интерактивное поведение подтверждается тестом).

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:traktor_mobile/core/storage/local_store.dart';
import 'package:traktor_mobile/core/storage/session_store.dart';
import 'package:traktor_mobile/features/auth/auth_controller.dart';

/// Пользователь без имени — как при первом входе (ведёт на шаг профиля).
Session _session({String name = ''}) => Session(
      accessToken: 'a.b.c',
      refreshToken: 'refresh-1',
      expiresInSec: 900,
      user: ApiUser(
        id: 'user-1',
        phone: '+37491234567',
        name: name,
        roles: const ['client'],
        activeRole: 'client',
      ),
    );

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthController (fake-вход)', () {
    test('запрос кода переводит на шаг ввода кода и запоминает телефон', () async {
      final c = await _container();
      addTearDown(c.dispose);

      await c.read(authControllerProvider.notifier).requestCode('+37491234567');

      final state = c.read(authControllerProvider);
      expect(state.stage, AuthStage.codeSent);
      expect(state.phone, '+37491234567');
      expect(state.error, isNull);
    });

    test('неверный код не пускает внутрь и показывает ошибку', () async {
      final c = await _container();
      addTearDown(c.dispose);
      final auth = c.read(authControllerProvider.notifier);

      await auth.requestCode('+37491234567');
      await auth.submitCode('000000');

      final state = c.read(authControllerProvider);
      expect(state.stage, AuthStage.codeSent, reason: 'остаёмся на экране кода');
      expect(state.error, isNotNull);
      expect(c.read(sessionProvider), isNull, reason: 'сессия не создаётся');
    });

    test('верный код создаёт сессию и ведёт на шаг профиля (имени ещё нет)', () async {
      final c = await _container();
      addTearDown(c.dispose);
      final auth = c.read(authControllerProvider.notifier);

      await auth.requestCode('+37491234567');
      await auth.submitCode(FakeAuthRepository.testCode);

      expect(c.read(authControllerProvider).stage, AuthStage.needsProfile);
      final session = c.read(sessionProvider);
      expect(session, isNotNull);
      expect(session!.user.phone, '+37491234567');
    });

    test('после сохранения профиля пользователь внутри', () async {
      final c = await _container();
      addTearDown(c.dispose);
      final auth = c.read(authControllerProvider.notifier);

      await auth.requestCode('+37491234567');
      await auth.submitCode(FakeAuthRepository.testCode);
      final ok = await auth.saveProfile(name: 'Тигран', city: 'Ереван');

      expect(ok, isTrue);
      expect(c.read(authControllerProvider).stage, AuthStage.signedIn);
    });

    test('смена номера возвращает к вводу телефона', () async {
      final c = await _container();
      addTearDown(c.dispose);
      final auth = c.read(authControllerProvider.notifier);

      await auth.requestCode('+37491234567');
      auth.changeNumber();

      expect(c.read(authControllerProvider).stage, AuthStage.signedOut);
      expect(c.read(authControllerProvider).phone, isNull);
    });
  });

  group('SessionStore (вход переживает перезапуск)', () {
    test('сохранённая сессия читается обратно целиком', () async {
      final c = await _container();
      addTearDown(c.dispose);
      final store = c.read(sessionStoreProvider);

      await store.save(_session(name: 'Тигран'));
      final restored = store.load();

      expect(restored, isNotNull);
      expect(restored!.accessToken, 'a.b.c');
      expect(restored.refreshToken, 'refresh-1');
      expect(restored.user.name, 'Тигран');
      expect(restored.user.activeRole, 'client');
    });

    test('пустое хранилище — это отсутствие входа, а не ошибка', () async {
      final c = await _container();
      addTearDown(c.dispose);
      expect(c.read(sessionStoreProvider).load(), isNull);
    });

    test('повреждённые данные не роняют приложение', () async {
      SharedPreferences.setMockInitialValues({'auth.session': 'не-json'});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);

      expect(c.read(sessionStoreProvider).load(), isNull);
    });

    test('выход стирает сессию и сбрасывает состояние входа', () async {
      final c = await _container();
      addTearDown(c.dispose);
      final auth = c.read(authControllerProvider.notifier);

      await auth.requestCode('+37491234567');
      await auth.submitCode(FakeAuthRepository.testCode);
      await c.read(sessionStoreProvider).save(c.read(sessionProvider)!);

      await auth.logout();

      expect(c.read(sessionProvider), isNull);
      expect(c.read(sessionStoreProvider).load(), isNull, reason: 'на диске тоже пусто');
      expect(c.read(authControllerProvider).stage, AuthStage.signedOut);
    });
  });
}
