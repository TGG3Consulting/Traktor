import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:design_system/design_system.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';
import '../../core/app_settings.dart';

/// §2.1 Онбординг · ценность + роль. Две карточки-роли, «можно изменить в любой
/// момент», внизу — гостевой просмотр (web-паритет).
class RoleScreen extends ConsumerWidget {
  const RoleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    void pick(TkRole role) {
      ref.read(appSettingsProvider.notifier).setRole(role);
      context.go('/auth/phone');
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: TkSpace.screenMobile,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.onbTitle, style: TkText.h1, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              _RoleCard(
                icon: Icons.build_outlined,
                title: l.roleOwnerTitle,
                sub: l.roleOwnerSub,
                onTap: () => pick(TkRole.owner),
              ),
              const SizedBox(height: 14),
              _RoleCard(
                icon: Icons.assignment_outlined,
                title: l.roleClientTitle,
                sub: l.roleClientSub,
                onTap: () => pick(TkRole.client),
              ),
              const SizedBox(height: 16),
              Text(l.roleChangeHint,
                  style: TkText.caption.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55)),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              TkButton(
                label: '${l.justBrowse} →',
                kind: TkButtonKind.ghost,
                onPressed: () => context.go('/home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.icon, required this.title, required this.sub, required this.onTap});
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TkCard(
      onTap: onTap,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(icon, size: 34, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TkText.h3),
                const SizedBox(height: 2),
                Text(sub, style: TkText.caption.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
