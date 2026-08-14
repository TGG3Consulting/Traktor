import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:design_system/design_system.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';
import 'auth_controller.dart';

/// §2.2 Вход · OTP. 6 ячеек, автопереход при вводе 6-й цифры, таймер повтора,
/// «Изменить номер». 3 неверных → пауза (на бэке). Тест-код: 000000.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});
  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _onChanged(String v) async {
    setState(() {});
    if (v.length == 6) {
      await ref.read(authControllerProvider.notifier).submitCode(v);
      final st = ref.read(authControllerProvider);
      if (st.stage == AuthStage.needsProfile && mounted) {
        context.go('/auth/profile');
      } else {
        _c.clear();
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final st = ref.watch(authControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: TkSpace.screenMobile,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.codeTitle, style: TkText.h1),
              const SizedBox(height: 6),
              Text('${l.codeSentTo(st.phone ?? '')} · ',
                  style: TkText.caption.copyWith(color: scheme.onSurface.withValues(alpha: 0.6))),
              GestureDetector(
                onTap: () {
                  ref.read(authControllerProvider.notifier).changeNumber();
                  context.go('/auth/phone');
                },
                child: Text(l.changeNumber, style: TkText.caption.copyWith(color: TkColors.info)),
              ),
              const SizedBox(height: 24),
              _OtpBoxes(controller: _c, onChanged: _onChanged),
              if (st.error != null) ...[
                const SizedBox(height: 12),
                Text(st.error!, style: TkText.caption.copyWith(color: TkColors.error)),
              ],
              const SizedBox(height: 16),
              Center(child: Text(l.resendIn('0:59'), style: TkText.caption.copyWith(color: scheme.onSurface.withValues(alpha: 0.6)))),
            ],
          ),
        ),
      ),
    );
  }
}

/// Визуальные 6 ячеек поверх скрытого поля ввода (простая реализация каркаса;
/// автоподстановка SMS-кода iOS/Android — на шаге полировки).
class _OtpBoxes extends StatelessWidget {
  const _OtpBoxes({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      alignment: Alignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (i) {
            final filled = i < controller.text.length;
            return Container(
              width: 46,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: filled ? scheme.primary : scheme.outline, width: 1.5),
              ),
              child: Text(filled ? controller.text[i] : '', style: TkText.h2),
            );
          }),
        ),
        Opacity(
          opacity: 0,
          child: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
