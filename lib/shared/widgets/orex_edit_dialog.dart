import 'package:flutter/material.dart';

typedef OrexEditValidator = String? Function(String value);
typedef OrexEditSave = Future<void> Function(String value);

Future<void> showOrexEditDialog(
  BuildContext context, {
  required String title,
  required String initialValue,
  required OrexEditSave onSave,
  OrexEditValidator? validator,
  TextInputType? keyboardType,
  TextInputAction? textInputAction,
  int minLines = 1,
  int maxLines = 1,
  double? width,
  String? labelText,
  String? hintText,
  String? helperText,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _OrexEditDialog(
      title: title,
      initialValue: initialValue,
      onSave: onSave,
      validator: validator,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      minLines: minLines,
      maxLines: maxLines,
      width: width,
      labelText: labelText,
      hintText: hintText,
      helperText: helperText,
    ),
  );
}

class _OrexEditDialog extends StatefulWidget {
  const _OrexEditDialog({
    required this.title,
    required this.initialValue,
    required this.onSave,
    required this.validator,
    required this.keyboardType,
    required this.textInputAction,
    required this.minLines,
    required this.maxLines,
    required this.width,
    required this.labelText,
    required this.hintText,
    required this.helperText,
  });

  final String title;
  final String initialValue;
  final OrexEditSave onSave;
  final OrexEditValidator? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int minLines;
  final int maxLines;
  final double? width;
  final String? labelText;
  final String? hintText;
  final String? helperText;

  @override
  State<_OrexEditDialog> createState() => _OrexEditDialogState();
}

class _OrexEditDialogState extends State<_OrexEditDialog> {
  late String _value;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  void _onChanged(String value) {
    _value = value;
    if (_error != null) {
      setState(() => _error = null);
    }
  }

  Future<void> _save() async {
    if (_saving) return;

    final validationError = widget.validator?.call(_value);
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.onSave(_value);
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message.toString();
        _saving = false;
      });
      return;
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
      }
      rethrow;
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final field = TextFormField(
      initialValue: widget.initialValue,
      enabled: !_saving,
      autofocus: true,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        helperText: widget.helperText,
        errorText: _error,
      ),
      onChanged: _onChanged,
      onFieldSubmitted: widget.maxLines == 1 ? (_) => _save() : null,
    );

    return AlertDialog(
      title: Text(widget.title),
      content: widget.width == null
          ? field
          : SizedBox(width: widget.width, child: field),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Сохранение…' : 'Сохранить'),
        ),
      ],
    );
  }
}
