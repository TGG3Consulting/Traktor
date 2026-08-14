// Traktor — Design Tokens (v1.0, 13.08.2026) — источник: ТЗ §1.7–1.8
// Пойдёт в packages/design_system/lib/tokens.dart (Фаза 2).
// Компоненты берут цвета/радиусы/типографику ТОЛЬКО отсюда — никакого хардкода.
import 'package:flutter/material.dart';

class TkColors {
  // Brand
  static const primary = Color(0xFFE8730C);
  static const primaryPress = Color(0xFFC96208);
  static const primaryLight = Color(0xFFF5A055);
  static const primaryDark = Color(0xFFDB6A0A); // primary в тёмной теме
  static const graphite = Color(0xFF1A1D21);

  // Semantic
  static const success = Color(0xFF2E9E5B);
  static const warning = Color(0xFFE5A400);
  static const error   = Color(0xFFD64545);
  static const info    = Color(0xFF3478C6);

  // Surfaces — light
  static const bgLight = Color(0xFFF5F6F8);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surface2Light = Color(0xFFF5F6F8);
  static const textLight = Color(0xFF1A1D21);
  static const text2Light = Color(0xFF6B7280);
  static const borderLight = Color(0xFFE7E9EC);

  // Surfaces — dark
  static const bgDark = Color(0xFF1A1D21);
  static const surfaceDark = Color(0xFF23272C);
  static const surface2Dark = Color(0xFF2A2F35);
  static const textDark = Color(0xFFF3F4F6);
  static const text2Dark = Color(0xFF9CA3AF);
  static const borderDark = Color(0xFF33383F);
}

// Статусная карта заказа/сделки (ТЗ §1.10) — единая во всём приложении.
enum TkStatus { draft, published, bidding, deciding, confirmed, inProgress, acceptance, completed, dispute, cancelled }

const tkStatusColor = <TkStatus, Color>{
  TkStatus.draft: Color(0xFF8A919B),
  TkStatus.published: Color(0xFF3478C6),
  TkStatus.bidding: Color(0xFFE5A400),
  TkStatus.deciding: Color(0xFF8B5CF6),
  TkStatus.confirmed: Color(0xFF14B8A6),
  TkStatus.inProgress: Color(0xFFE8730C),
  TkStatus.acceptance: Color(0xFF38BDF8),
  TkStatus.completed: Color(0xFF2E9E5B),
  TkStatus.dispute: Color(0xFFD64545),
  TkStatus.cancelled: Color(0xFF4B5563),
};

class TkRadius {
  static const card = 12.0;
  static const button = 10.0;
}

class TkSpace {
  static const unit = 4.0;        // базовый шаг 4dp
  static const padMobile = 16.0;
  static const padWeb = 24.0;
}

// Типографика (ТЗ §1.8). fontFamily подключается через google_fonts/локальные Inter+Noto Sans Armenian.
class TkText {
  static const h1 = TextStyle(fontSize: 24, height: 32/24, fontWeight: FontWeight.w600);
  static const h2 = TextStyle(fontSize: 20, height: 28/20, fontWeight: FontWeight.w600);
  static const h3 = TextStyle(fontSize: 17, height: 24/17, fontWeight: FontWeight.w600);
  static const body = TextStyle(fontSize: 15, height: 22/15, fontWeight: FontWeight.w400);
  static const caption = TextStyle(fontSize: 13, height: 18/13, fontWeight: FontWeight.w400);
  // Цены — всегда табличные цифры, чтобы не «прыгали» в аукционе.
  static const price = TextStyle(fontSize: 20, height: 28/20, fontWeight: FontWeight.w700,
      fontFeatures: [FontFeature.tabularFigures()]);
}
