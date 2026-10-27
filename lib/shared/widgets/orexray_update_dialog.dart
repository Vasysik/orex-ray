import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../core/update/orexray_updates.dart';
import '../theme/orex_palette.dart';

Future<void> showOrexRayUpdateDialog(BuildContext context, OrexRayUpdates updates) {
  if (updates.available == null) return Future<void>.value();
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(updates: updates),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.updates});
  final OrexRayUpdates updates;
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  OrexRayUpdateToken? _token;
  String? _downloaded;
  String? _error;
  int _received = 0;
  int _total = 0;
  DateTime? _lastProgressRebuild;
  bool _busy = false;
  bool _permissionRequired = false;

  Future<void> _start() async {
    if (_busy) return;
    final token = OrexRayUpdateToken();
    _lastProgressRebuild = null;
    setState(() {
      _busy = true;
      _token = token;
      _error = null;
      if (_downloaded == null) {
        _received = 0;
        _total = 0;
      }
    });
    try {
      _downloaded ??= await widget.updates.download(token, (received, total) {
        if (!mounted) {
          return;
        }
        // Avoid rebuilding a long Markdown changelog for every network chunk.
        final now = DateTime.now();
        if (_lastProgressRebuild != null && received < total &&
            now.difference(_lastProgressRebuild!) <
                const Duration(milliseconds: 200)) {
          return;
        }
        _lastProgressRebuild = now;
        setState(() { _received = received; _total = total; });
      });
      token.check();
      final permissionRequired = await widget.updates.launchInstaller(_downloaded!);
      if (permissionRequired) {
        if (mounted) {
          setState(() {
            _permissionRequired = true;
            _error = 'Разреши установку из OrexRay в настройках Android, вернись сюда и снова нажми «Установить».';
          });
        }
        return;
      }
      _downloaded = null; // Android installer needs this APK until its activity reads it.
      if (mounted) Navigator.of(context).pop();
    } on OrexRayUpdateCancelled {
      if (_downloaded != null) await widget.updates.deleteFile(_downloaded!);
      _downloaded = null;
    } catch (e) {
      if (mounted) setState(() { _error = 'Ошибка обновления: $e'; });
    } finally {
      if (mounted) setState(() { _busy = false; _token = null; });
    }
  }

  Future<void> _close() async {
    if (_downloaded != null) await widget.updates.deleteFile(_downloaded!);
    _downloaded = null;
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.updates.available!;
    final palette = OrexPalette.of(context);
    final fraction = _total > 0 ? (_received / _total).clamp(0, 1).toDouble() : null;
    // Reserve vertical space for the progress footer on shorter screens.
    final notesMaxHeight = (MediaQuery.sizeOf(context).height *
            (_busy ? 0.25 : 0.32))
        .clamp(80.0, _busy ? 240.0 : 320.0).toDouble();
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(_busy ? 'Скачивание обновления' : 'Доступна новая версия'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('OrexRay ${release.tag}', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('Установлено: ${widget.updates.current.label}'),
              const SizedBox(height: 6),
              Text('${release.assetName} · ${(release.assetBytes / 1048576).toStringAsFixed(1)} МБ'),
              if (orexrayUpdateTestSameVersion && release.tag == widget.updates.current.label)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('ТЕСТ: повторная установка той же версии'),
                ),
              const SizedBox(height: 16),
              Text('Что нового', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              // Only release notes scroll. Download progress is pinned beneath.
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: notesMaxHeight),
                child: SingleChildScrollView(
                  child: MarkdownBody(
                    key: const ValueKey('orexray-update-markdown'),
                    data: release.notes,
                    selectable: true,
                  ),
                ),
              ),
              if (_busy) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: fraction, color: palette.accent),
                const SizedBox(height: 8),
                Text(_total == 0
                    ? 'Подключение к GitHub…'
                    : '${(_received / 1048576).toStringAsFixed(1)} из '
                      '${(_total / 1048576).toStringAsFixed(1)} МБ '
                      '(${(100 * (fraction ?? 0)).round()}%)'),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: palette.danger)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? () => _token?.cancel() : _close,
            child: Text(_busy ? 'Отменить загрузку' : 'Закрыть'),
          ),
          if (!_busy)
            FilledButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.download_rounded),
              label: Text(_permissionRequired ? 'Установить' : _error == null ? 'Скачать и установить' : 'Повторить'),
            ),
        ],
      ),
    );
  }
}
