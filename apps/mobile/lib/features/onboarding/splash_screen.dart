import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// §2.1 Splash. ≤2 сек: логотип + проверка сессии. Есть сессия → домашний экран
/// роли; иначе → онбординг. Лого — марка брендбука (концепт B «T-балка»).
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) context.go('/onboarding/language');
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: TkColors.graphite,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _LogoMark(size: 84),
            const SizedBox(height: 18),
            const Text('Traktor',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 6),
            Text(l.appTagline, style: TkText.caption.copyWith(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

/// Марка логотипа (T-балка) — из брендбука. В проде — asset SVG (logo-mark.svg);
/// здесь нарисована теми же токенами, чтобы каркас работал без asset-пайплайна.
class _LogoMark extends StatelessWidget {
  const _LogoMark({this.size = 64});
  final double size;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: TkColors.primary,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: CustomPaint(painter: _TPainter()),
    );
  }
}

class _TPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = s.width * 0.12
      ..strokeCap = StrokeCap.round;
    final top = s.height * 0.36, bottom = s.height * 0.70, l = s.width * 0.31, r = s.width * 0.69;
    canvas.drawLine(Offset(l, top), Offset(r, top), p);
    canvas.drawLine(Offset(s.width / 2, top), Offset(s.width / 2, bottom), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
