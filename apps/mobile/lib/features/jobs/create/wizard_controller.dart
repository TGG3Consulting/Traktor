import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session_refresh.dart';
import '../jobs_providers.dart';

/// Состояние визарда создания задания (ТЗ §2.6, 5 шагов).
///
/// Черновик живёт на сервере: он создаётся на первом шаге и досохраняется после
/// каждого следующего. Поэтому закрытое приложение, разряженный телефон и
/// «вернусь завтра» ничего не теряют — на главной заказчика черновик виден с
/// номером шага, как в прототипе.
class WizardState {
  const WizardState({
    this.job,
    this.step = 1,
    this.saving = false,
    this.error,
    this.fieldErrors = const {},
  });

  /// Черновик с сервера. null — ещё не создан (первый шаг не сохранён).
  final Job? job;
  final int step;
  final bool saving;
  final String? error;

  /// Разбор по полям от сервера при неудачной публикации: экран подсвечивает
  /// именно то, чего не хватает.
  final Map<String, String> fieldErrors;

  WizardState copyWith({
    Job? job,
    int? step,
    bool? saving,
    String? error,
    Map<String, String>? fieldErrors,
    bool clearError = false,
  }) =>
      WizardState(
        job: job ?? this.job,
        step: step ?? this.step,
        saving: saving ?? this.saving,
        error: clearError ? null : (error ?? this.error),
        fieldErrors: fieldErrors ?? this.fieldErrors,
      );
}

class WizardController extends Notifier<WizardState> {
  @override
  WizardState build() => const WizardState();

  JobsApi get _api => ref.read(jobsApiProvider);
  String get _token => ref.read(accessTokenProvider);
  SessionRefresher get _refresher => ref.read(sessionRefresherProvider);

  /// Начать новое задание. Черновик на сервере пока не создаётся: пустая
  /// карточка на главной заказчика до выбора категории только мешала бы.
  void startNew() => state = const WizardState();

  /// Продолжить существующий черновик (тап по карточке «Черновик · шаг 3»).
  void resume(Job draft) => state = WizardState(job: draft, step: draft.draftStep);

  /// Сохранить шаг: первый раз создаёт черновик, дальше досохраняет.
  /// Возвращает true, если можно переходить дальше.
  Future<bool> save(JobDraftInput input, {int? goToStep}) async {
    if (_token.isEmpty) {
      state = state.copyWith(error: 'Нужен вход, чтобы создать задание');
      return false;
    }
    state = state.copyWith(saving: true, clearError: true, fieldErrors: const {});
    try {
      final current = state.job;
      final key = _newKey();
      final saved = await _refresher.run((token) => current == null
          ? _api.createDraft(token, input, idempotencyKey: key)
          : _api.updateDraft(token, current.id, input, idempotencyKey: key));
      state = state.copyWith(
        job: saved,
        saving: false,
        step: goToStep ?? state.step,
        clearError: true,
      );
      // Главная заказчика должна сразу увидеть черновик.
      ref.invalidate(myJobsProvider);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(saving: false, error: e.detail);
      return false;
    }
  }

  void goToStep(int step) => state = state.copyWith(step: step, clearError: true);

  /// Опубликовать. При нехватке данных сервер возвращает разбор по полям —
  /// показываем его, а не общее «ошибка».
  Future<Job?> publish() async {
    final draft = state.job;
    if (draft == null) {
      state = state.copyWith(error: 'Черновик ещё не сохранён');
      return null;
    }
    state = state.copyWith(saving: true, clearError: true, fieldErrors: const {});
    try {
      final key = _newKey();
      final published =
          await _refresher.run((token) => _api.publish(token, draft.id, idempotencyKey: key));
      state = state.copyWith(job: published, saving: false, clearError: true);
      ref.invalidate(myJobsProvider);
      ref.invalidate(feedProvider);
      return published;
    } on ValidationException catch (e) {
      state = state.copyWith(saving: false, error: e.title, fieldErrors: e.fields);
      return null;
    } on ApiException catch (e) {
      state = state.copyWith(saving: false, error: e.detail);
      return null;
    }
  }

  /// Ключ идемпотентности: повтор отправки при плохой связи не должен
  /// создавать второе задание.
  String _newKey() =>
      'job-${DateTime.now().microsecondsSinceEpoch}-${state.job?.id ?? 'new'}';
}

final wizardControllerProvider =
    NotifierProvider<WizardController, WizardState>(WizardController.new);
