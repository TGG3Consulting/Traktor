import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';

import '../../core/realtime.dart';
import '../../core/session_refresh.dart';
import '../jobs/jobs_providers.dart';
import 'chat_providers.dart';

/// Экран переписки (ТЗ §2.12, прототип `chat` и `chat_precontract`).
///
/// До подтверждения сделки телефоны и ники маскируются на сервере. Экран
/// объясняет это заранее плашкой и мягко предупреждает того, чей контакт
/// скрыли: молчаливая правка чужого текста выглядит как поломка.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.chatId});

  final String chatId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  void Function()? _unsubscribe;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  /// Сообщение собеседника появляется сразу: переписка, которая обновляется
  /// раз в минуту, превращается в переписку по почте (ADR-6).
  Future<void> _listen() async {
    // Канал переписки закрыт — сначала берём билет, он же подтверждает, что
    // человек участник этого чата.
    String ticket;
    try {
      ticket = await ref.read(sessionRefresherProvider).run(
            (t) => ref.read(jobsApiProvider).chatRealtimeToken(t, widget.chatId),
          );
    } catch (_) {
      return; // живые обновления недоступны — экран работает как обычно
    }

    final off = await ref.read(realtimeProvider).subscribe(
      'chat:${widget.chatId}',
      (event) {
        if (!mounted) return;
        // Своё сообщение уже на экране — перечитывать историю незачем.
        if (event['senderId'] == ref.read(userIdProvider)) return;
        ref.invalidate(messagesProvider(widget.chatId));
        _toBottom();
      },
      subscriptionToken: ticket,
    );
    if (!mounted) {
      off();
      return;
    }
    _unsubscribe = off;
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l = AppLocalizations.of(context);
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      final sent = await ref.read(chatActionsProvider).send(widget.chatId, text);
      _input.clear();
      _toBottom();
      if (sent.contactsMasked && mounted) _warnMasked();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.sendFailed('$e'))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Мягкое предупреждение вместо блокировки (ТЗ §2.10): человек должен
  /// понимать, почему номер в его сообщении заменился точками.
  void _warnMasked() {
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(l.contactsHidden),
      ),
    );
  }

  void _toBottom() {
    // Кадр на отрисовку нового сообщения, потом прокрутка к нему.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final chat = ref.watch(chatProvider(widget.chatId));
    final messages = ref.watch(messagesProvider(widget.chatId));
    final row = chat.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          tooltip: l.back,
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
          icon: TkIcon(TkIcons.arrowLeft, size: 20, color: scheme.onSurface),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(row?.peerName ?? l.chatTitle, style: TkText.h3),
            if (row != null)
              Text(
                row.isDeal ? l.chatDealOpen : l.chatBeforeDeal,
                style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
        actions: [
          if (row != null && row.jobId.isNotEmpty)
            IconButton(
              tooltip: l.jobTitle,
              onPressed: () => context.push('/jobs/${row.jobId}'),
              icon: TkIcon(TkIcons.clipboardText, size: 20, color: scheme.onSurface),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.when(
              loading: () => const TkSkeletonList(count: 3),
              error: (e, _) => TkErrorState(
                message: '$e',
                onRetry: () => ref.invalidate(messagesProvider(widget.chatId)),
              ),
              data: (list) => ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                itemCount: list.length + 1,
                itemBuilder: (context, i) {
                  // Первой строкой — почему контакты спрятаны (прототип
                  // chat_precontract). В сделке напоминание не нужно.
                  if (i == 0) {
                    if (row == null || row.isDeal) return const SizedBox.shrink();
                    return _SystemLine(text: l.chatHint);
                  }
                  final msg = list[i - 1];
                  if (msg.isSystem) return _SystemLine(text: msg.text);
                  return _Bubble(message: msg, mine: _mine(msg));
                },
              ),
            ),
          ),
          _Composer(
            controller: _input,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  /// Своё сообщение или чужое. Идентификатор пользователя лежит в сессии,
  /// сервер отдаёт senderId — сравнение честное, без догадок по времени.
  bool _mine(ChatMessage msg) => msg.senderId != null && msg.senderId == ref.read(userIdProvider);
}

/// Пузырь сообщения. Свои — справа основным цветом, чужие — слева на
/// поверхности (прототип, .msg.me / .msg.them).
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = mine ? TkColors.primary : scheme.surface;
    final fg = mine ? Colors.white : scheme.onSurface;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(mine ? 14 : 4),
              bottomRight: Radius.circular(mine ? 4 : 14),
            ),
            border: mine ? null : Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(message.text, style: TkText.body.copyWith(color: fg)),
              const SizedBox(height: 3),
              Text(
                tkClock(message.createdAt),
                style: TextStyle(fontSize: 10.5, color: fg.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Системная строка по центру: смена статуса сделки, пояснение о маскировке.
class _SystemLine extends StatelessWidget {
  const _SystemLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 6, bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Строка ввода с круглой кнопкой отправки (прототип, sticky-cta).
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: l.messageHint,
                  counterText: '',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(21),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(21),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _SendButton(sending: sending, onPressed: onSend),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.sending, required this.onPressed});

  final bool sending;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: AppLocalizations.of(context).sendAction,
        child: InkWell(
          onTap: sending ? null : onPressed,
          borderRadius: const BorderRadius.all(Radius.circular(21)),
          child: Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: sending ? TkColors.primaryLight : TkColors.primary,
              shape: BoxShape.circle,
            ),
            child: sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const TkIcon(TkIcons.paperPlane, size: 20, color: Colors.white),
          ),
        ),
      );
}
