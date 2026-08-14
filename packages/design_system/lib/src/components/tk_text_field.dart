import 'package:flutter/material.dart';
import '../tokens.dart';

/// Поле ввода UI-kit (ТЗ §1.10, §4.6): лейбл СВЕРХ поля (не placeholder-as-label),
/// helper/error СНИЗУ, опциональный счётчик символов. gap-2 между блоками.
class TkTextField extends StatelessWidget {
  const TkTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.helper,
    this.error,
    this.keyboardType,
    this.maxLength,
    this.currentLength,
    this.obscure = false,
    this.onChanged,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? helper;
  final String? error;
  final TextInputType? keyboardType;
  final int? maxLength;
  final int? currentLength;
  final bool obscure;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text2 = scheme.onSurface.withValues(alpha: 0.55);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TkText.caption.copyWith(color: text2, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscure,
          onChanged: onChanged,
          maxLength: maxLength,
          buildCounter: (_, {required currentLength, maxLength, required isFocused}) => null,
          style: TkText.body.copyWith(color: scheme.onSurface),
          decoration: InputDecoration(
            hintText: hint,
            errorText: error,
            errorStyle: TkText.caption.copyWith(color: TkColors.error),
          ),
        ),
        if (helper != null || maxLength != null)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Row(
              children: [
                if (helper != null)
                  Expanded(child: Text(helper!, style: TkText.caption.copyWith(color: text2))),
                if (maxLength != null)
                  Text('${currentLength ?? 0} / $maxLength',
                      style: TkText.caption.copyWith(color: text2)),
              ],
            ),
          ),
      ],
    );
  }
}
