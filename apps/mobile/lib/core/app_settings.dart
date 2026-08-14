import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:design_system/design_system.dart';

/// Глобальные настройки приложения: тема, язык, активная роль.
/// Синхронизируются между устройствами через профиль (User.settings) — Фаза 2 бэка.
/// Пока — в памяти + позже локальный кэш (Drift) и сервер.
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

class AppSettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => const AppSettings();

  void setTheme(ThemeMode mode) => state = state.copyWith(themeMode: mode);
  void setLocale(Locale locale) => state = state.copyWith(locale: locale);
  void setRole(TkRole role) => state = state.copyWith(role: role);
  void toggleTheme() =>
      state = state.copyWith(themeMode: state.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
}

final appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(AppSettingsController.new);
