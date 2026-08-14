import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_client/api_client.dart';
import '../../core/env.dart';
import '../../core/app_settings.dart';
import '../../core/notifications/push_service.dart';

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

/// Текущая сессия (токены + пользователь). Позже — персист в Drift + refresh.
final sessionProvider = StateProvider<Session?>((ref) => null);

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

  void completeProfile() => state = state.copyWith(stage: AuthStage.signedIn);
  void changeNumber() => state = state.copyWith(stage: AuthStage.signedOut, phone: null);
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
