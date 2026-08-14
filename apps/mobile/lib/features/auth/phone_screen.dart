import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:design_system/design_system.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';
import 'auth_controller.dart';

/// §2.2 Вход · телефон. Маска +374, кнопка активна только при валидном номере
/// И согласии с офертой.
class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});
  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _c = TextEditingController();
  bool _agree = false;
  bool _busy = false;

  bool get _valid => _c.text.replaceAll(RegExp(r'\D'), '').length >= 8 && _agree;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    await ref.read(authControllerProvider.notifier).requestCode('+374${_c.text}');
    if (!mounted) return;
    setState(() => _busy = false);
    // Переходим к вводу кода только если код реально отправлен.
    if (ref.read(authControllerProvider).stage == AuthStage.codeSent) {
      context.go('/auth/otp');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: TkSpace.screenMobile,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.signIn, style: TkText.h1),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 84,
                    child: TkTextField(label: l.phoneLabel, controller: TextEditingController(text: '+374')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TkTextField(
                      label: ' ',
                      controller: _c,
                      hint: l.phoneHint,
                      keyboardType: TextInputType.phone,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => setState(() => _agree = !_agree),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(value: _agree, onChanged: (v) => setState(() => _agree = v ?? false)),
                    Expanded(child: Text(l.agreeOffer, style: TkText.caption.copyWith(color: scheme.onSurface.withValues(alpha: 0.7)))),
                  ],
                ),
              ),
              const Spacer(),
              TkButton(
                label: l.getCode,
                loading: _busy,
                onPressed: _valid ? _submit : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
