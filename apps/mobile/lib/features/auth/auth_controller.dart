import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_client/api_client.dart';
import '../../core/env.dart';
import '../../core/app_settings.dart';
import '../../core/notifications/push_service.dart';
import '../../core/storage/session_store.dart';

/// Стадии входа.
enum AuthStage { signedOut, codeSent, needsProfile, signedIn }

class AuthState {
  const AuthState({this.stage = AuthStage.signedOut, this.phone, this.error});
  final AuthStage stage;
  final String? phone;
  final String? error;

  AuthState copyWith({AuthStage? stage, String? phone, String? error}) =>
      AuthState(stage: stage ?? this.stage, phone: phone ?? this.phone, error: error);
}

/// Абстракция входа: за ней либо реальный сервис identity (api_client), либо
/// fake для локальной разработки. Возвращает [Session] (токены + профиль).
abstract class AuthRepository {
  Future<void> startOtp(String phone);
  Future<Session> verifyOtp(String phone, String code);
}

/// Fake: код всегда 482915, выдаёт правдоподобную сессию без сервера.
class FakeAuthRepository implements AuthRepository {
  static const testCode = '482915';

  @override
  Future<void> startOtp(String phone) => Future.delayed(const Duration(milliseconds: 300));

  @override
  Future<Session> verifyOtp(String phone, String code) async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (code != testCode) {
      throw ApiException(401, 'Код неверный');
    }
    return Session(
      accessToken: 'fake.access.token',
      refreshToken: 'fake.refresh.token',
      expiresInSec: 900,
      user: ApiUser(id: 'fake-user', phone: phone, roles: const ['client'], activeRole: 'client'),
    );
  }
}

/// Реальный вход через сервис identity.
class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._api);
  final AuthApi _api;

  @override
  Future<void> startOtp(String phone) => _api.otpStart(phone);

  @override
  Future<Session> verifyOtp(String phone, String code) =>
      _api.otpVerify(phone, code, idempotencyKey: '$phone:$code');
}

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(Env.apiBaseUrl));

/// Клиент раздела notifications (регистрация push-токена устройства).
final devicesApiProvider = Provider<DevicesApi>((ref) => DevicesApi(Env.apiBaseUrl));

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (Env.useRealBackend) {
    return ApiAuthRepository(ref.read(authApiProvider));
  }
  return FakeAuthRepository();
});

/// Текущая сессия (токены + пользователь). При старте восстанавливается из
/// локального хранилища — вход переживает перезапуск.
final sessionProvider = StateProvider<Session?>((ref) => ref.read(sessionStoreProvider).load());

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> requestCode(String phone) async {
    try {
      await _repo.startOtp(phone);
      state = state.copyWith(stage: AuthStage.codeSent, phone: phone, error: null);
    } on ApiException catch (e) {
      state = state.copyWith(error: e.detail);
    }
  }

  Future<void> submitCode(String code) async {
    final phone = state.phone ?? '';
    try {
      final session = await _repo.verifyOtp(phone, code);
      ref.read(sessionProvider.notifier).state = session;
      unawaited(ref.read(sessionStoreProvider).save(session)); // персист входа
      // Регистрируем push-токен устройства (не блокирует вход).
      unawaited(_registerDeviceBestEffort(session));
      // Новый пользователь (без имени) → шаг профиля; иначе сразу внутрь.
      state = state.copyWith(
        stage: session.user.name.isEmpty ? AuthStage.needsProfile : AuthStage.signedIn,
        error: null,
      );
    } on ApiException catch (e) {
      state = state.copyWith(error: e.detail);
    }
  }

  /// Регистрация push-токена после успешного входа. Best-effort: любой сбой
  /// тихо игнорируется — уведомления не критичны для входа. Пока подключён
  /// FakePushService; при заведении Firebase-проекта провайдер заменится на FCM,
  /// код здесь не меняется. Без реального бэка (fake-вход) — пропускаем.
  Future<void> _registerDeviceBestEffort(Session session) async {
    if (!Env.useRealBackend) return;
    try {
      final push = ref.read(pushServiceProvider);
      if (!await push.requestPermission()) return;
      final token = await push.getToken();
      if (token == null || token.isEmpty) return;
      final locale = ref.read(appSettingsProvider).locale?.languageCode ?? 'ru';
      await ref.read(devicesApiProvider).register(
            accessToken: session.accessToken,
            token: token,
            platform: push.platform,
            locale: locale,
            idempotencyKey: '${session.user.id}:$token',
          );
    } catch (_) {
      // Токен устройства — не критичен для входа; сбой не показываем пользователю.
    }
  }

  /// Сохранить первый профиль (имя обязательно, город опционально). С реальным
  /// бэком шлёт PATCH /me и обновляет сессию свежим профилем; на fake-входе —
  /// просто завершает шаг. Возвращает true, если можно идти на домашний экран.
  Future<bool> saveProfile({required String name, String? city}) async {
    final session = ref.read(sessionProvider);
    if (Env.useRealBackend && session != null) {
      try {
        final updated = await ref.read(authApiProvider).updateMe(
              session.accessToken,
              name: name,
              city: (city != null && city.isNotEmpty) ? city : null,
              idempotencyKey: '${session.user.id}:profile',
            );
        final refreshed = Session(
          accessToken: session.accessToken,
          refreshToken: session.refreshToken,
          expiresInSec: session.expiresInSec,
          user: updated,
        );
        ref.read(sessionProvider.notifier).state = refreshed;
        unawaited(ref.read(sessionStoreProvider).save(refreshed)); // персист профиля
      } on ApiException catch (e) {
        state = state.copyWith(error: e.detail);
        return false;
      }
    }
    completeProfile();
    return true;
  }

  void completeProfile() => state = state.copyWith(stage: AuthStage.signedIn);
  void changeNumber() => state = state.copyWith(stage: AuthStage.signedOut, phone: null);

  /// Выход из аккаунта: чистим локальную сессию и состояние входа. Токен
  /// устройства снимаем best-effort (не блокирует выход).
  Future<void> logout() async {
    final session = ref.read(sessionProvider);
    if (Env.useRealBackend && session != null) {
      final push = ref.read(pushServiceProvider);
      final token = await push.getToken();
      if (token != null && token.isNotEmpty) {
        try {
          await ref.read(devicesApiProvider).unregister(
                accessToken: session.accessToken,
                token: token,
              );
        } catch (_) {
          // выход не должен падать из-за снятия токена
        }
      }
    }
    await ref.read(sessionStoreProvider).clear();
    ref.read(sessionProvider.notifier).state = null;
    state = const AuthState();
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
