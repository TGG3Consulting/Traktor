import 'dart:async';

import 'package:flutter/material.dart';

import '../format.dart';
import '../icons/tk_icon.dart';
import '../icons/tk_icons.dart';
import '../tokens.dart';

/// Карточка задания в ленте (ТЗ §2.7, прототип `jobCard`).
///
/// Собрана из данных, а не из готового текста: цена, режим, счётчики и таймер
/// рисуются одинаково в ленте, на карте и в превью визарда — иначе одно и то же
/// задание выглядело бы в трёх местах по-разному.
class TkJobCard extends StatelessWidget {
  const TkJobCard({
    super.key,
    required this.title,
    required this.icon,
    this.city = '',
    this.distanceM,
    this.needBy = '',
    this.price,
    this.startPrice,
    this.currency = 'AMD',
    this.isAuction = false,
    this.auctionEndsAt,
    this.offersCount = 0,
    this.viewsCount = 0,
    this.workersCount = 0,
    this.hasPhoto = false,
    this.onTap,
    this.labels = const TkJobCardLabels(),
  });

  final String title;

  /// SVG-путь иконки Phosphor (TkIcons) — категория работ.
  final String icon;
  final String city;
  final double? distanceM;
  final String needBy;

  /// Для фикс-цены — цена; для аукциона — текущая лучшая ставка.
  final int? price;

  /// Стартовая цена аукциона: показывается зачёркнутой рядом с лучшей ставкой.
  final int? startPrice;
  final String currency;
  final bool isAuction;
  final DateTime? auctionEndsAt;
  final int offersCount;
  final int viewsCount;
  final int workersCount;
  final bool hasPhoto;
  final VoidCallback? onTap;

  /// Подписи карточки. Дизайн-система не знает про язык приложения, поэтому
  /// переведённые слова приходят снаружи (ТЗ §1.4).
  final TkJobCardLabels labels;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sub = [
      if (city.isNotEmpty) city,
      if (distanceM != null) tkDistance(distanceM),
      if (needBy.isNotEmpty) labels.needBy(needBy),
    ].join(' · ');

    return Material(
      color: scheme.surface,
      borderRadius: TkRadius.cardR,
      child: InkWell(
        onTap: onTap,
        borderRadius: TkRadius.cardR,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TkIcon(icon, size: 24, color: TkColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: TkText.h3, maxLines: 2, overflow: TextOverflow.ellipsis),
                        if (sub.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(sub,
                              style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ],
                    ),
                  ),
                  if (hasPhoto) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: TkIcon(TkIcons.image, size: 20, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(tkMoney(price, currency: currency),
                      style: TkText.h2.copyWith(fontSize: 19, color: TkColors.primary)),
                  if (isAuction && startPrice != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      tkMoney(startPrice, currency: currency),
                      style: TkText.caption.copyWith(
                        color: scheme.onSurfaceVariant,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (workersCount > 0) _WorkersBadge(count: workersCount),
                  if (workersCount > 0) const SizedBox(width: 6),
                  _ModeBadge(
                      isAuction: isAuction,
                      endsAt: auctionEndsAt,
                      labels: labels),
                ],
              ),
              if (offersCount > 0 || viewsCount > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '${labels.offers(offersCount)} · ${labels.views(viewsCount)}',
                  style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}


class _WorkersBadge extends StatelessWidget {
  const _WorkersBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TkIcon(TkIcons.usersThree, size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text('+$count',
              style: TkText.caption.copyWith(color: scheme.onSurfaceVariant, fontSize: 11.5)),
        ],
      ),
    );
  }
}

/// Бейдж режима: у аукциона — живой таймер до финиша, у фикс-цены — метка.
class _ModeBadge extends StatefulWidget {
  const _ModeBadge({required this.isAuction, this.endsAt, required this.labels});
  final bool isAuction;
  final DateTime? endsAt;
  final TkJobCardLabels labels;

  @override
  State<_ModeBadge> createState() => _ModeBadgeState();
}

class _ModeBadgeState extends State<_ModeBadge> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Тикаем раз в секунду только когда есть что отсчитывать: лишний таймер на
    // каждой карточке фикс-цены жёг бы батарею впустую.
    if (widget.isAuction && widget.endsAt != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isAuction) {
      return _Badge(
        color: TkColors.primary,
        background: TkColors.primary.withValues(alpha: 0.12),
        icon: TkIcons.money,
        text: widget.labels.fixed,
      );
    }
    final left = widget.endsAt?.difference(DateTime.now());
    return _Badge(
      color: TkColors.warning,
      background: TkColors.warning.withValues(alpha: 0.15),
      icon: TkIcons.lightning,
      text: left == null
          ? widget.labels.auction
          : widget.labels.auctionLeft(tkTimeLeft(left)),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.color,
    required this.background,
    required this.icon,
    required this.text,
  });

  final Color color;
  final Color background;
  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TkIcon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(text,
              style: TkText.caption.copyWith(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }
}

/// Подписи карточки задания на языке приложения.
///
/// Значения по умолчанию — русские: карточка используется и в местах, где
/// локализации ещё нет, и пустая подпись выглядела бы как поломка.
class TkJobCardLabels {
  const TkJobCardLabels({
    this.fixed = 'Фикс-цена',
    this.auction = 'Аукцион',
    this.offersFn,
    this.viewsFn,
    this.needByFn,
    this.auctionLeftFn,
  });

  final String fixed;
  final String auction;

  final String Function(int)? offersFn;
  final String Function(int)? viewsFn;
  final String Function(String)? needByFn;
  final String Function(String)? auctionLeftFn;

  String offers(int n) =>
      offersFn?.call(n) ?? '$n ${tkPlural(n, 'отклик', 'отклика', 'откликов')}';

  String views(int n) =>
      viewsFn?.call(n) ?? '$n ${tkPlural(n, 'просмотр', 'просмотра', 'просмотров')}';

  String needBy(String when) => needByFn?.call(when) ?? 'нужна: $when';

  String auctionLeft(String left) => auctionLeftFn?.call(left) ?? '$auction · $left';
}
