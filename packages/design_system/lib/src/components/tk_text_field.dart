import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';

/// Поле ввода UI-kit (ТЗ §1.10, §4.6): лейбл СВЕРХ поля (не placeholder-as-label),
/// helper/error СНИЗУ, опциональный счётчик символов.
class TkTextField extends StatefulWidget {
  const TkTextField({
    super.key,
    required this.label,
    this.controller,
    this.initialValue,
    this.hint,
    this.helper,
    this.error,
    this.keyboardType,
    this.inputFormatters,
    this.maxLength,
    this.currentLength,
    this.maxLines = 1,
    this.obscure = false,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
  }) : assert(controller == null || initialValue == null,
            'Задайте либо controller, либо initialValue');

  final String label;
  final TextEditingController? controller;

  /// Начальное значение, когда контроллер держать негде (поля, собранные по
  /// шаблону характеристик).
  final String? initialValue;
  final String? hint;
  final String? helper;
  final String? error;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;

  /// Если не задан, счётчик считает символы сам — вызывающему не нужно
  /// дублировать состояние.
  final int? currentLength;
  final int maxLines;
  final bool obscure;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  /// Нажатие «Готово» на клавиатуре. Нужно там, где ввод сам по себе является
  /// действием — например поиск: заставлять тянуться к отдельной кнопке после
  /// набора запроса неудобно.
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  @override
  State<TkTextField> createState() => _TkTextFieldState();
}

class _TkTextFieldState extends State<TkTextField> {
  TextEditingController? _own;
  int _length = 0;

  TextEditingController? get _controller => widget.controller ?? _own;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null && widget.initialValue != null) {
      _own = TextEditingController(text: widget.initialValue);
    }
    _length = (_controller?.text ?? '').characters.length;
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text2 = scheme.onSurface.withValues(alpha: 0.55);
    final counter = widget.currentLength ?? _length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label,
            style: TkText.caption.copyWith(color: text2, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextField(
          controller: _controller,
          keyboardType: widget.keyboardType,
          inputFormatters: widget.inputFormatters,
          obscureText: widget.obscure,
          autofocus: widget.autofocus,
          maxLines: widget.obscure ? 1 : widget.maxLines,
          minLines: widget.maxLines > 1 ? widget.maxLines : null,
          onChanged: (v) {
            setState(() => _length = v.characters.length);
            widget.onChanged?.call(v);
          },
          onSubmitted: widget.onSubmitted,
          textInputAction: widget.textInputAction ??
              (widget.onSubmitted != null ? TextInputAction.search : null),
          maxLength: widget.maxLength,
          // Свой счётчик снизу — вместе с helper, поэтому стандартный убираем.
          buildCounter: (_, {required currentLength, maxLength, required isFocused}) => null,
          style: TkText.body.copyWith(color: scheme.onSurface),
          decoration: InputDecoration(
            hintText: widget.hint,
            errorText: widget.error,
            errorStyle: TkText.caption.copyWith(color: TkColors.error),
          ),
        ),
        if (widget.helper != null || widget.maxLength != null)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.helper != null)
                  Expanded(
                      child: Text(widget.helper!,
                          style: TkText.caption.copyWith(color: text2))),
                if (widget.maxLength != null)
                  Text('$counter / ${widget.maxLength}',
                      style: TkText.caption.copyWith(color: text2)),
              ],
            ),
          ),
      ],
    );
  }
}
