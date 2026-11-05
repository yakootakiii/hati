import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../money/money.dart';

/// A peso amount input that parses straight into centavos (spec §11).
///
/// Nothing here ever holds a decimal: the text is parsed by [Money.tryParse]
/// and handed on as an integer, so a typo can produce null but never a
/// rounding error.
class AmountField extends StatefulWidget {
  const AmountField({
    required this.initial,
    required this.onChanged,
    this.label = 'Amount',
    this.helperText,
    this.errorText,
    this.enabled = true,
    this.autofocus = false,
    this.textAlign = TextAlign.start,
    super.key,
  });

  final Money initial;
  final ValueChanged<Money> onChanged;
  final String label;
  final String? helperText;
  final String? errorText;
  final bool enabled;
  final bool autofocus;
  final TextAlign textAlign;

  @override
  State<AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<AmountField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial.isZero ? '' : widget.initial.formatBare(),
  );

  @override
  void didUpdateWidget(AmountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow programmatic changes (the derived total in itemized mode) without
    // fighting the user while they are typing.
    if (!widget.enabled && widget.initial != oldWidget.initial) {
      _controller.text = widget.initial.isZero ? '' : widget.initial.formatBare();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      textAlign: widget.textAlign,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
      ],
      decoration: InputDecoration(
        labelText: widget.label,
        prefixText: '₱ ',
        helperText: widget.helperText,
        errorText: widget.errorText,
      ),
      onChanged: (text) {
        final parsed = Money.tryParse(text);
        if (parsed != null) widget.onChanged(parsed);
        if (text.trim().isEmpty) widget.onChanged(Money.zero);
      },
    );
  }
}

/// An amount rendered with tabular figures, so columns of pesos line up
/// (spec §11).
class AmountText extends StatelessWidget {
  const AmountText(
    this.amount, {
    this.style,
    this.color,
    this.semanticsPrefix,
    super.key,
  });

  final Money amount;
  final TextStyle? style;
  final Color? color;
  final String? semanticsPrefix;

  @override
  Widget build(BuildContext context) {
    final text = amount.format();
    return Text(
      text,
      style: (style ?? Theme.of(context).textTheme.bodyMedium)?.copyWith(
        color: color,
      ),
      semanticsLabel: semanticsPrefix == null ? null : '$semanticsPrefix $text',
    );
  }
}
