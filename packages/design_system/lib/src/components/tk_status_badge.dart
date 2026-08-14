import 'package:flutter/material.dart';
import '../status.dart';

/// Бейдж статуса (ТЗ §1.10). Цвет — из единой статусной карты, подпись —
/// локализованная (передаётся, т.к. l10n живёт в приложении). Смысл не
/// передаётся ТОЛЬКО цветом — всегда есть текст (ТЗ §1.6 доступность).
class TkStatusBadge extends StatelessWidget {
  const TkStatusBadge({super.key, required this.status, required this.label});

  final TkStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: status.color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          height: 1.2,
        ),
      ),
    );
  }
}
