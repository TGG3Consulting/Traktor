import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';

import '../../core/session_refresh.dart';
import '../auth/auth_controller.dart';
import '../equipment/photo_picker.dart';
import '../jobs/jobs_providers.dart';

/// Проверка человека и бейдж «Проверен» (ТЗ §2.3).
///
/// Бейдж — главный сигнал доверия в ленте: рядом с ним отклик читается иначе.
/// Поэтому здесь не «загрузите файл», а понятный обмен: что просим, зачем и
/// когда ответим.
final myVerificationProvider = FutureProvider<Verification>((ref) async {
  final token = ref.watch(accessTokenProvider);
  if (token.isEmpty) return const Verification();
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).myVerification(t));
});

class VerificationScreen extends ConsumerStatefulWidget {
  const VerificationScreen({super.key});

  @override
  ConsumerState<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends ConsumerState<VerificationScreen> {
  final _docs = <String>[];
  String _kind = 'passport';
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(myVerificationProvider);
    final verified = ref.watch(sessionProvider)?.user.verified ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.verifyTitle),
        leading: IconButton(
          tooltip: l.back,
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
          icon: TkIcon(TkIcons.arrowLeft, size: 20, color: scheme.onSurface),
        ),
      ),
      body: state.when(
        loading: () => const TkSkeletonList(count: 2),
        error: (e, _) => TkErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(myVerificationProvider),
        ),
        data: (v) {
          if (verified || v.isApproved) return const _Approved();
          if (v.isPending) return _Pending(verification: v);
          return _Form(
            rejectedReason: v.isRejected ? v.reason : '',
            docs: _docs,
            kind: _kind,
            busy: _busy,
            onKind: (k) => setState(() => _kind = k),
            onAdd: _addPhotos,
            onRemove: (i) => setState(() => _docs.removeAt(i)),
            onSubmit: _submit,
          );
        },
      ),
    );
  }

  Future<void> _addPhotos() async {
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final urls = await ref
          .read(photoUploaderProvider)
          .pickAndUpload(folder: 'documents', limit: 4 - _docs.length);
      if (urls.isNotEmpty) setState(() => _docs.addAll(urls));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.uploadFailed('$e'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(sessionRefresherProvider).run(
            (t) => ref.read(jobsApiProvider).submitVerification(
                  t,
                  docKind: _kind,
                  documents: _docs,
                  idempotencyKey: 'verify-${DateTime.now().microsecondsSinceEpoch}',
                ),
          );
      ref.invalidate(myVerificationProvider);
      setState(() => _docs.clear());
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.detail)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _Approved extends StatelessWidget {
  const _Approved();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return TkEmptyState(
      icon: TkIcons.checkCircle,
      title: l.profileVerified,
      description: l.verifiedBadgeSeen,
    );
  }
}

class _Pending extends StatelessWidget {
  const _Pending({required this.verification});

  final Verification verification;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        TkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const TkIcon(TkIcons.hourglass, size: 20),
                  const SizedBox(width: 8),
                  Text(l.docUnderReview, style: TkText.h3),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                l.reviewWithinDay,
                style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (verification.createdAt != null) ...[
                const SizedBox(height: 8),
                Text(l.submittedOn(tkShortDate(verification.createdAt)),
                    style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({
    required this.rejectedReason,
    required this.docs,
    required this.kind,
    required this.busy,
    required this.onKind,
    required this.onAdd,
    required this.onRemove,
    required this.onSubmit,
  });

  final String rejectedReason;
  final List<String> docs;
  final String kind;
  final bool busy;
  final ValueChanged<String> onKind;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (rejectedReason.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TkColors.error.withValues(alpha: 0.12),
              borderRadius: TkRadius.cardR,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.lastRejected,
                    style: TkText.body.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(rejectedReason, style: TkText.caption),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        Text(l.whyVerify, style: TkText.h3),
        const SizedBox(height: 4),
        Text(
          l.whyVerifyBody,
          style: TkText.body.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Text(l.whichDoc, style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            TkChip(label: l.docPassport, selected: kind == 'passport', onTap: () => onKind('passport')),
            TkChip(label: l.docLicense, selected: kind == 'license', onTap: () => onKind('license')),
            TkChip(label: l.docOther, selected: kind == 'other', onTap: () => onKind('other')),
          ],
        ),
        const SizedBox(height: 16),
        TkPhotoGrid(
          photos: docs,
          onAdd: onAdd,
          onRemove: onRemove,
          max: 4,
          busy: busy,
          coverLabel: l.mainPhoto,
        ),
        const SizedBox(height: 6),
        Text(
          l.docShootHint,
          style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy || docs.isEmpty ? null : onSubmit,
          child: busy
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l.sendForReview),
        ),
        const SizedBox(height: 8),
        Text(
          l.answerWithinDay,
          textAlign: TextAlign.center,
          style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
