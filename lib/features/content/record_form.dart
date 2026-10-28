import 'package:flutter/material.dart';

import '../../ui/widgets.dart';

enum FieldKind { text, multiline, number, phone, email, date, select, toggle }

/// One input of a [RecordForm].
class FieldSpec {
  const FieldSpec(
    this.key,
    this.label, {
    this.kind = FieldKind.text,
    this.required = false,
    this.options = const [],
    this.hint,
  });

  final String key;
  final String label;
  final FieldKind kind;
  final bool required;
  final String? hint;

  /// Choices for [FieldKind.select]; shown through [titleCase].
  final List<String> options;
}

/// A generic add/edit form shown in a bottom sheet. It posts a new record to
/// [path], or puts changes to [path] when [editing], and offers a delete
/// button when [deletePath] is set. Empty optional fields are sent as null
/// so they can be cleared.
class RecordForm extends StatefulWidget {
  const RecordForm({
    super.key,
    required this.fields,
    required this.path,
    required this.savedMessage,
    this.initial = const {},
    this.editing = false,
    this.deletePath,
    this.deleteWarning,
    this.extraBody = const {},
    this.saveLabel = 'Save',
  });

  final List<FieldSpec> fields;
  final String path;
  final String savedMessage;
  final Map<String, dynamic> initial;
  final bool editing;
  final String? deletePath;
  final String? deleteWarning;
  final Map<String, dynamic> extraBody;
  final String saveLabel;

  @override
  State<RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<RecordForm> {
  final Map<String, TextEditingController> _text = {};
  final Map<String, Object?> _value = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      final initial = widget.initial[f.key];
      switch (f.kind) {
        case FieldKind.toggle:
          _value[f.key] = initial == null ? true : (initial == true || initial == 1);
        case FieldKind.select:
          _value[f.key] = initial?.toString() ?? (f.required && f.options.isNotEmpty ? f.options.first : null);
        case FieldKind.date:
          _value[f.key] = _dateOnly(initial) ?? (f.required ? _today() : null);
        default:
          _text[f.key] = TextEditingController(text: initial == null ? '' : '$initial');
      }
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  static String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String? _dateOnly(Object? v) {
    final s = v?.toString();
    return s == null || s.length < 10 ? null : s.substring(0, 10);
  }

  Future<void> _pickDate(FieldSpec f) async {
    final current = DateTime.tryParse('${_value[f.key] ?? _today()}') ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _value[f.key] =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    final body = <String, dynamic>{...widget.extraBody};
    for (final f in widget.fields) {
      Object? v;
      switch (f.kind) {
        case FieldKind.toggle || FieldKind.select || FieldKind.date:
          v = _value[f.key];
        case FieldKind.number:
          final raw = _text[f.key]!.text.trim();
          v = raw.isEmpty ? null : num.tryParse(raw);
          if (raw.isNotEmpty && v == null) {
            snack(context, '${f.label} must be a number.', error: true);
            return;
          }
        default:
          final raw = _text[f.key]!.text.trim();
          v = raw.isEmpty ? null : raw;
      }
      if (f.required && (v == null || v == '')) {
        snack(context, '${f.label} is required.', error: true);
        return;
      }
      body[f.key] = v;
    }
    setState(() => _busy = true);
    final ok = await guarded(context, () async {
      if (widget.editing) {
        await app.api.put(widget.path, body: body);
      } else {
        await app.api.post(widget.path, body: body);
      }
    });
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (ok) {
      Navigator.pop(context, true);
      snack(context, widget.savedMessage);
    }
  }

  Future<void> _delete() async {
    final app = AppScope.read(context);
    if (!await confirm(context, 'Delete this record?', body: widget.deleteWarning ?? 'This cannot be undone.', action: 'Delete')) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _busy = true);
    final ok = await guarded(context, () async => app.api.delete(widget.deletePath!));
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (ok) {
      Navigator.pop(context, true);
      snack(context, 'Deleted.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final f in widget.fields) _input(f),
      FilledButton(onPressed: _busy ? null : _save, child: Text(widget.saveLabel)),
      if (widget.deletePath != null) ...[
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _busy ? null : _delete,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete'),
          style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
        ),
      ],
    ]);
  }

  Widget _input(FieldSpec f) {
    final label = f.required ? f.label : '${f.label} (optional)';
    switch (f.kind) {
      case FieldKind.toggle:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          value: _value[f.key] == true,
          onChanged: (v) => setState(() => _value[f.key] = v),
        );
      case FieldKind.select:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            initialValue: _value[f.key] as String?,
            decoration: InputDecoration(labelText: f.label),
            items: [for (final o in f.options) DropdownMenuItem(value: o, child: Text(titleCase(o)))],
            onChanged: (v) => setState(() => _value[f.key] = v),
          ),
        );
      case FieldKind.date:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: OutlinedButton.icon(
            onPressed: () => _pickDate(f),
            icon: const Icon(Icons.event, size: 18),
            label: Text('${f.label}: ${_value[f.key] ?? 'not set'}'),
          ),
        );
      case FieldKind.multiline:
        return field(_text[f.key]!, label, maxLines: 5, hint: f.hint);
      case FieldKind.number:
        return field(_text[f.key]!, label,
            type: const TextInputType.numberWithOptions(decimal: true), hint: f.hint);
      case FieldKind.phone:
        return field(_text[f.key]!, label, type: TextInputType.phone, hint: f.hint);
      case FieldKind.email:
        return field(_text[f.key]!, label, type: TextInputType.emailAddress, hint: f.hint);
      case FieldKind.text:
        return field(_text[f.key]!, label, hint: f.hint);
    }
  }
}
