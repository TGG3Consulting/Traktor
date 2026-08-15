import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session_refresh.dart';
import '../jobs/jobs_providers.dart';

/// Пользователи у модерации (ТЗ §4.1, п.3).
///
/// Жалобы разбираются, но нарушитель продолжает работать: без блокировки
/// решение модерации ничего не меняет. Поиск — по телефону (с плюсом),
/// идентификатору или части имени; пустой запрос показывает последних.
final adminUsersProvider =
    FutureProvider.family<List<AdminUser>, String>((ref, query) async {
  final token = ref.watch(accessTokenProvider);
  if (token.isEmpty) return const [];
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).searchUsers(t, query: query));
});

final adminUserProvider =
    FutureProvider.family<AdminUser, String>((ref, userId) async {
  // Раздел закрыт ролью, но без входа запрашивать нечего.
  if (ref.watch(accessTokenProvider).isEmpty) {
    throw StateError('Требуется вход');
  }
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).adminUser(t, userId));
});

class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final users = ref.watch(adminUsersProvider(_query));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Пользователи'),
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
          icon: TkIcon(TkIcons.arrowLeft, size: 20, color: scheme.onSurface),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TkTextField(
              controller: _search,
              label: 'Поиск',
              hint: '+374… , имя или идентификатор',
              onSubmitted: (v) => setState(() => _query = v.trim()),
              onChanged: (v) {
                if (v.trim().isEmpty && _query.isNotEmpty) {
                  setState(() => _query = '');
                }
              },
            ),
          ),
          Expanded(
            child: users.when(
              loading: () => const TkSkeletonList(count: 4),
              error: (e, _) => TkErrorState(
                message: '$e',
                onRetry: () => ref.invalidate(adminUsersProvider(_query)),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const TkEmptyState(
                    icon: TkIcons.usersThree,
                    title: 'Никого не нашлось',
                    description: 'Телефон ищется целиком, с плюсом и кодом страны',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _UserRow(user: items[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TkCard(
      onTap: () => context.push('/moderation/users/${user.id}'),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.displayName, style: TkText.body.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  '${user.phone}${user.city.isEmpty ? '' : ' · ${user.city}'}',
                  style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (!user.isActive) _StatusPill(user: user),
          const SizedBox(width: 6),
          const TkIcon(TkIcons.caretRight, size: 16),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    final color = user.isBanned ? TkColors.error : TkColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        user.isBanned ? 'Забанен' : 'Заморожен',
        style: TkText.caption.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
