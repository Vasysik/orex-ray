import 'package:flutter/material.dart';

import '../../core/profiles/profiles_controller.dart';
import '../../core/profiles/vless_link_parser.dart';
import '../../core/tunnel/tunnel_models.dart';
import '../../shared/theme/glass.dart';
import '../../shared/theme/orex_theme.dart';
import '../../shared/widgets/squirrel_mascot.dart';

class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({
    super.key,
    required this.profiles,
  });

  final ProfilesController profiles;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: profiles,
      builder: (context, _) {
        final items = profiles.profiles;
        final selected = profiles.selectedProfile;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Профили',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text(
                        'Импортируйте VLESS-ссылку и выберите сервер',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () => _showImportDialog(context),
                  icon: const Icon(Icons.add_link_rounded),
                  label: const Text('Импорт'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (items.isEmpty)
              _EmptyProfiles(onImport: () => _showImportDialog(context))
            else
              ...items.map(
                (profile) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ProfileCard(
                    profile: profile,
                    selected: selected?.id == profile.id,
                    onSelect: () => profiles.select(profile.id),
                    onDelete: () => _deleteProfile(context, profile),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _showImportDialog(BuildContext context) async {
    final profile = await showDialog<TunnelProfile>(
      context: context,
      builder: (context) => _ImportVlessDialog(profiles: profiles),
    );
    if (profile == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Профиль «${profile.name}» импортирован')),
    );
  }

  Future<void> _deleteProfile(
    BuildContext context,
    TunnelProfile profile,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить профиль?'),
        content: Text('«${profile.name}» будет удалён с этого устройства.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await profiles.delete(profile.id);
    }
  }
}

class _EmptyProfiles extends StatelessWidget {
  const _EmptyProfiles({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 28,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 44),
      child: Column(
        children: [
          const SquirrelMascot(size: 104),
          const SizedBox(height: 22),
          Text('Белочка ждёт сервер',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Добавьте первую VLESS-ссылку — и она появится здесь.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.add_link_rounded),
            label: const Text('Импортировать VLESS'),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.selected,
    required this.onSelect,
    required this.onDelete,
  });

  final TunnelProfile profile;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 22,
      tint: selected ? OrexColors.copper : null,
      opacity: selected ? 0.16 : 0.50,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: onSelect,
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: selected ? OrexColors.copperGradient : null,
            color: selected
                ? null
                : OrexColors.copper.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(
            selected ? Icons.check_rounded : Icons.public_rounded,
            color: selected ? OrexColors.cream : OrexColors.copper,
          ),
        ),
        title: Text(profile.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            '${profile.endpoint}\n${profile.protocol} · ${profile.transportLabel}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Text(
                  'Активный',
                  style: TextStyle(color: OrexColors.online, fontSize: 12),
                ),
              ),
            IconButton(
              tooltip: 'Удалить',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportVlessDialog extends StatefulWidget {
  const _ImportVlessDialog({required this.profiles});

  final ProfilesController profiles;

  @override
  State<_ImportVlessDialog> createState() => _ImportVlessDialogState();
}

class _ImportVlessDialogState extends State<_ImportVlessDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  bool _importing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _error = null;
    });

    try {
      final profile = await widget.profiles.importVlessLink(_controller.text);
      if (!mounted) return;
      Navigator.of(context).pop(profile);
    } on VlessLinkFormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _error = 'Не удалось импортировать профиль: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Импорт VLESS'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Вставьте ссылку vless://. OrexRay сохранит профиль только на этом устройстве.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              minLines: 4,
              maxLines: 8,
              autofocus: true,
              enabled: !_importing,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'vless://uuid@server:443?...',
                errorText: _error,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _importing ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _importing ? null : _submit,
          child: _importing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}
