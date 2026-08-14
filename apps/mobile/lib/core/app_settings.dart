import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'storage/local_store.dart';

/// Глобальные настройки приложения: тема, язык, активная роль.
/// Персистятся локально (SharedPreferences) и переживают перезапуск. Позже
/// дополнительно синхронизируются через профиль (User.settings) на сервере.
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.locale,
    this.role,
  });

  final ThemeMode themeMode;
  final Locale? locale; // null = системный до выбора на онбординге
  final TkRole? role;

  AppSettings copyWith({ThemeMode? themeMode, Locale? locale, TkRole? role}) => AppSettings(
        themeMode: themeMode ?? this.themeMode,
        locale: locale ?? this.locale,
        role: role ?? this.role,
      );
}

/// Роль пользователя в приложении (совпадает с contracts Role: client|owner).
enum TkRole { client, owner }

// Ключи хранилища.
const _kTheme = 'settings.themeMode';
const _kLocale = 'settings.locale';
const _kRole = 'settings.role';

class AppSettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final p = ref.read(sharedPrefsProvider);
    final loc = p.getString(_kLocale);
    return AppSettings(
      themeMode: _decodeTheme(p.getString(_kTheme)),
      locale: loc == null ? null : Locale(loc),
      role: _decodeRole(p.getString(_kRole)),
    );
  }

  SharedPreferences get _p => ref.read(sharedPrefsProvider);

  void setTheme(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _p.setString(_kTheme, mode.name);
  }

  void setLocale(Locale locale) {
    state = state.copyWith(locale: locale);
    _p.setString(_kLocale, locale.languageCode);
  }

  void setRole(TkRole role) {
    state = state.copyWith(role: role);
    _p.setString(_kRole, role.name);
  }

  void toggleTheme() =>
      setTheme(state.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
}

ThemeMode _decodeTheme(String? s) {
  switch (s) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

TkRole? _decodeRole(String? s) {
  switch (s) {
    case 'client':
      return TkRole.client;
    case 'owner':
      return TkRole.owner;
    default:
      return null;
  }
}

final appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(AppSettingsController.new);
