import 'package:flutter/widgets.dart';

/// Токены Traktor — синхронизированы с брендбуком `design/brand/tokens.dart`.
/// ИСТОЧНИК ПРАВДЫ для цвета/радиуса/типографики. Меняются только вместе с
/// брендбуком (с версией). В фичах — только эти константы, без сырых hex.

class TkColors {
  TkColors._();

  // ── Brand ─────────────────────────────────────────────
  static const primary = Color(0xFFE8730C);
  static const primaryPress = Color(0xFFC96208);
  static const primaryLight = Color(0xFFF5A055);
  static const primaryDark = Color(0xFFDB6A0A); // primary в тёмной теме
  static const graphite = Color(0xFF1A1D21);

  // ── Semantic ──────────────────────────────────────────
  static const success = Color(0xFF2E9E5B);
  static const warning = Color(0xFFE5A400);
  static const error = Color(0xFFD64545);
  static const info = Color(0xFF3478C6);

  // ── Surfaces · light ──────────────────────────────────
  static const bgLight = Color(0xFFF5F6F8);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surface2Light = Color(0xFFF5F6F8);
  static const textLight = Color(0xFF1A1D21);
  static const text2Light = Color(0xFF6B7280);
  static const borderLight = Color(0xFFE7E9EC);

  // ── Surfaces · dark ───────────────────────────────────
  static const bgDark = Color(0xFF1A1D21);
  static const surfaceDark = Color(0xFF23272C);
  static const surface2Dark = Color(0xFF2A2F35);
  static const textDark = Color(0xFFF3F4F6);
  static const text2Dark = Color(0xFF9CA3AF);
  static const borderDark = Color(0xFF33383F);
}

class TkRadius {
  TkRadius._();
  static const double card = 12;
  static const double button = 10;
  static const double sheet = 20;

  static const BorderRadius cardR = BorderRadius.all(Radius.circular(card));
  static const BorderRadius buttonR = BorderRadius.all(Radius.circular(button));
}

class TkSpace {
  TkSpace._();
  static const double unit = 4; // базовый шаг сетки (ТЗ §1.8)
  static const double padMobile = 16;
  static const double padWeb = 24;

  static const EdgeInsets screenMobile = EdgeInsets.all(padMobile);
}

/// Типографическая шкала (ТЗ §1.8). Семейство подключается в теме
/// (Inter + Noto Sans Armenian), здесь — размеры/начертания.
class TkText {
  TkText._();
  static const h1 = TextStyle(fontSize: 24, height: 32 / 24, fontWeight: FontWeight.w600);
  static const h2 = TextStyle(fontSize: 20, height: 28 / 20, fontWeight: FontWeight.w600);
  static const h3 = TextStyle(fontSize: 17, height: 24 / 17, fontWeight: FontWeight.w600);
  static const body = TextStyle(fontSize: 15, height: 22 / 15, fontWeight: FontWeight.w400);
  static const caption = TextStyle(fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w400);

  /// Цены — всегда табличные цифры, чтобы не «прыгали» в аукционе (ТЗ §1.8).
  static const price = TextStyle(
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
