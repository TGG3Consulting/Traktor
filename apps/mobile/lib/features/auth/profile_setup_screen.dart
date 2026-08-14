import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:design_system/design_system.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';
import 'auth_controller.dart';

/// §2.2 Первый вход. Имя обязательно (2–50), фото опционально с подсказкой
/// доверия, город — автоопределение по гео.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});
  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _name = TextEditingController();

  bool get _valid => _name.text.trim().length >= 2;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
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
              Text(l.firstEntryTitle, style: TkText.h1),
              const SizedBox(height: 16),
              Center(
                child: CircleAvatar(
                  radius: 46,
                  backgroundColor: scheme.surfaceContainerHighest,
                  child: Icon(Icons.photo_camera_outlined, color: scheme.onSurface.withValues(alpha: 0.5), size: 30),
                ),
              ),
              const SizedBox(height: 8),
              Center(child: Text(l.photoTrust, style: TkText.caption.copyWith(color: scheme.onSurface.withValues(alpha: 0.6)))),
              const SizedBox(height: 16),
              TkTextField(label: '${l.nameLabel} *', controller: _name, onChanged: (_) => setState(() {})),
              const SizedBox(height: 14),
              TkTextField(
                label: l.cityLabel,
                controller: TextEditingController(text: 'Ереван'),
                helper: l.cityDetected,
              ),
              const Spacer(),
              TkButton(
                label: l.start,
                onPressed: _valid
                    ? () {
                        ref.read(authControllerProvider.notifier).completeProfile();
                        context.go('/home');
                      }
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
