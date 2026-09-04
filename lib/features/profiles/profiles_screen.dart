import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/egress/egress_identity.dart';
import '../../core/profiles/profiles_controller.dart';
import '../../core/profiles/vless_link_parser.dart';
import '../../core/profiles/xray_json_codec.dart';
import '../../core/profiles/xray_json_file.dart';
import '../../core/profiles/xray_json_source.dart';
import '../../core/tunnel/tunnel_models.dart';
import '../../shared/theme/glass.dart';
import '../../shared/theme/orex_theme.dart';
import '../../shared/widgets/egress_avatar.dart';
import '../../shared/widgets/orex_choice_sheet.dart';
import '../../shared/widgets/squirrel_mascot.dart';
import '../home/tunnel_controller.dart';

enum _ProfileCreateAction {
  importLink,
  importXrayJson,
  newProfile,
  balancer,
}

enum _XrayJsonExportAction { copy, saveFile }

class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({
    super.key,
    required this.profiles,
    required this.tunnel,
  });

  final ProfilesController profiles;
  final TunnelController tunnel;

  @override
  Widget build(BuildContext context) => _ProfilesBody(owner: this);

  Future<void> _showProfileMenu(BuildContext context) async {
    final action = await showOrexChoiceSheet<_ProfileCreateAction>(
      context,
      options: const [
        OrexChoiceSheetOption<_ProfileCreateAction>(
          value: _ProfileCreateAction.importLink,
          icon: Icons.add_link_rounded,
          title: 'Импорт ссылки',
          subtitle: 'VLESS, VMess, Trojan, Shadowsocks, SOCKS или HTTP',
        ),
        OrexChoiceSheetOption<_ProfileCreateAction>(
          value: _ProfileCreateAction.importXrayJson,
          icon: Icons.data_object_rounded,
          title: 'Импорт JSON Xray',
          subtitle: 'Файл, сырой JSON, массив [] или HTTP/HTTPS URL',
        ),
        OrexChoiceSheetOption<_ProfileCreateAction>(
          value: _ProfileCreateAction.newProfile,
          icon: Icons.add_circle_outline_rounded,
          title: 'Новый профиль',
          subtitle:
              'Настроить VLESS, VMess, Trojan, Shadowsocks, SOCKS или HTTP',
        ),
        OrexChoiceSheetOption<_ProfileCreateAction>(
          value: _ProfileCreateAction.balancer,
          icon: Icons.hub_rounded,
          title: 'Балансировщик',
          subtitle: 'Объединить несколько маршрутов Xray',
        ),
      ],
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _ProfileCreateAction.importLink:
        await _showImportDialog(context);
        break;
      case _ProfileCreateAction.importXrayJson:
        await _showXrayJsonImportDialog(context);
        break;
      case _ProfileCreateAction.newProfile:
        await _showCreateProfileDialog(context);
        break;
      case _ProfileCreateAction.balancer:
        await _showBalancerDialog(context);
        break;
    }
  }

  Future<void> _showImportDialog(BuildContext context) async {
    final profile = await showDialog<TunnelProfile>(
      context: context,
      builder: (context) => _ImportLinkDialog(profiles: profiles),
    );
    if (profile == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Профиль «${profile.name}» импортирован')),
    );
  }

  Future<void> _showXrayJsonImportDialog(BuildContext context) async {
    final result = await showDialog<XrayJsonImportResult>(
      context: context,
      builder: (context) => _ImportXrayJsonDialog(profiles: profiles),
    );
    if (result == null || !context.mounted) return;
    final parts = <String>[
      if (result.addedCount > 0) 'добавлено ${result.addedCount}',
      if (result.updatedCount > 0) 'обновлено ${result.updatedCount}',
      if (result.skippedUnsupported > 0)
        'пропущено неподдерживаемых ${result.skippedUnsupported}',
    ];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          parts.isEmpty ? 'JSON импортирован' : 'JSON Xray: ${parts.join(', ')}',
        ),
      ),
    );
  }

  Future<void> _showXrayJsonExportMenu(
    BuildContext context, {
    String? profileId,
    Iterable<String>? profileIds,
    String? suggestedBaseName,
  }) async {
    final selectedIds = profileIds?.toSet();
    if (profileId == null &&
        (selectedIds == null || selectedIds.isEmpty) &&
        profiles.profiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет профилей для экспорта')),
      );
      return;
    }

    final exportingMultiple = profileId == null;
    final exportCount = selectedIds?.length ?? profiles.profiles.length;
    final action = await showOrexChoiceSheet<_XrayJsonExportAction>(
      context,
      title: exportingMultiple ? 'Экспорт $exportCount профилей' : 'Экспорт профиля',
      options: [
        OrexChoiceSheetOption<_XrayJsonExportAction>(
          value: _XrayJsonExportAction.copy,
          icon: Icons.content_copy_rounded,
          title:
              exportingMultiple ? 'Копировать массив JSON' : 'Копировать JSON',
          subtitle: exportingMultiple
              ? 'Выбранные профили как массив полных Xray-конфигов'
              : 'Полный Xray-конфиг профиля в буфер обмена',
        ),
        const OrexChoiceSheetOption<_XrayJsonExportAction>(
          value: _XrayJsonExportAction.saveFile,
          icon: Icons.save_alt_rounded,
          title: 'Сохранить .json',
          subtitle: 'Выбрать файл через системный диалог',
        ),
      ],
    );
    if (action == null || !context.mounted) return;

    try {
      final payload = selectedIds == null
          ? profiles.exportXrayJson(profileId: profileId)
          : profiles.exportSelectedXrayJson(selectedIds);
      switch (action) {
        case _XrayJsonExportAction.copy:
          await Clipboard.setData(ClipboardData(text: payload));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                exportingMultiple
                    ? 'Массив JSON Xray скопирован'
                    : 'JSON Xray скопирован',
              ),
            ),
          );
          break;
        case _XrayJsonExportAction.saveFile:
          final baseName = _safeFileName(
            suggestedBaseName ?? 'orexray-selected-$exportCount',
          );
          final saved = await const XrayJsonFileExporter().save(
            content: payload,
            suggestedName: '$baseName.json',
          );
          if (!context.mounted || !saved) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('JSON Xray экспортирован')),
          );
          break;
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось экспортировать JSON: $error')),
      );
    }
  }

  String _safeFileName(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[\/:*?"<>|]+'), '-')
        .replaceAll(RegExp(r'\s+'), ' ');
    return sanitized.isEmpty ? 'orexray-xray' : sanitized;
  }

  Future<void> _showCreateProfileDialog(BuildContext context) async {
    final seed = TunnelProfile(
      id: 'profile-${DateTime.now().microsecondsSinceEpoch}',
      name: '',
      address: '',
      port: 443,
      userId: '',
    );
    final created = await showDialog<TunnelProfile>(
      context: context,
      builder: (context) => _EditProfileDialog(
        profile: seed,
        title: 'Новый профиль',
        allowProtocolSelection: true,
      ),
    );
    if (created == null) return;
    await profiles.createProfile(created);
  }

  Future<void> _showEditProfileDialog(
    BuildContext context,
    TunnelProfile profile,
  ) async {
    final updated = await showDialog<TunnelProfile>(
      context: context,
      builder: (context) => _EditProfileDialog(profile: profile),
    );
    if (updated == null) return;
    await profiles.updateProfile(updated);
  }

  Future<void> _showBalancerDialog(
    BuildContext context, {
    BalancerProfile? existing,
  }) async {
    if (existing == null && profiles.profiles.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Для балансировщика нужны минимум два профиля'),
        ),
      );
      return;
    }
    final value = await showDialog<_BalancerDraft>(
      context: context,
      builder: (context) => _BalancerDialog(
        profiles: profiles.profiles,
        existing: existing,
      ),
    );
    if (value == null) return;
    try {
      await profiles.saveBalancer(
        id: existing?.id,
        name: value.name,
        memberIds: value.memberIds,
        strategy: value.strategy,
        probeUrl: value.probeUrl,
        probeIntervalSeconds: value.probeIntervalSeconds,
        fallbackTarget: value.fallbackTarget,
      );
    } on FormatException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message.toString())),
      );
    }
  }

  Future<void> _deleteTarget(
    BuildContext context,
    String id,
    String name,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить?'),
        content: Text('«$name» будет удалён с этого устройства.'),
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
    if (confirmed == true) await profiles.delete(id);
  }
}

class _ProfilesBody extends StatefulWidget {
  const _ProfilesBody({required this.owner});

  final ProfilesScreen owner;

  @override
  State<_ProfilesBody> createState() => _ProfilesBodyState();
}

class _ProfilesBodyState extends State<_ProfilesBody> {
  final Set<String> _selectedProfileIds = <String>{};
  bool _reorderMode = false;

  ProfilesController get profiles => widget.owner.profiles;
  TunnelController get tunnel => widget.owner.tunnel;
  bool get _selectionMode => _selectedProfileIds.isNotEmpty;

  void _toggleSelection(String id) {
    setState(() {
      if (!_selectedProfileIds.add(id)) {
        _selectedProfileIds.remove(id);
      }
    });
  }

  void _enterSelection(String id) {
    if (_selectionMode) {
      _toggleSelection(id);
      return;
    }
    setState(() => _selectedProfileIds.add(id));
  }

  void _clearSelection() {
    if (!_selectionMode) return;
    setState(_selectedProfileIds.clear);
  }

  void _selectAll() {
    setState(() {
      _selectedProfileIds
        ..clear()
        ..addAll(profiles.profiles.map((profile) => profile.id));
    });
  }

  Future<void> _deleteSelected(BuildContext context) async {
    final count = _selectedProfileIds.length;
    if (count == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить $count профилей?'),
        content: const Text(
          'Выбранные серверы будут удалены с этого устройства. '
          'Балансировщики с недостаточным числом серверов тоже будут удалены.',
        ),
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
    if (confirmed != true || !mounted) return;
    final ids = Set<String>.from(_selectedProfileIds);
    await profiles.deleteProfiles(ids);
    if (mounted) _clearSelection();
  }

  Future<void> _exportSelected(BuildContext context) async {
    final ids = Set<String>.from(_selectedProfileIds);
    if (ids.isEmpty) return;
    await widget.owner._showXrayJsonExportMenu(
      context,
      profileIds: ids,
      suggestedBaseName: 'orexray-selected-${ids.length}',
    );
  }

  Future<void> _pingSelected() async {
    if (_selectedProfileIds.isEmpty || tunnel.refreshingLatency) return;
    await tunnel.refreshProfileLatencies(
      Set<String>.from(_selectedProfileIds),
    );
  }

  void _startReorder() {
    setState(() {
      _selectedProfileIds.clear();
      _reorderMode = true;
    });
  }

  void _finishReorder() {
    if (!_reorderMode) return;
    setState(() => _reorderMode = false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([profiles, tunnel, tunnel.egressChanges]),
      builder: (context, _) {
        final currentProfiles = profiles.profiles;
        final validIds = currentProfiles.map((profile) => profile.id).toSet();
        _selectedProfileIds.removeWhere((id) => !validIds.contains(id));
        final activeTarget = profiles.selectedTarget;

        if (_reorderMode) {
          return ReorderableListView.builder(
            padding: const EdgeInsets.all(20),
            buildDefaultDragHandles: false,
            header: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProfilesReorderHeader(onDone: _finishReorder),
                const SizedBox(height: 20),
                _SectionTitle(
                  title: 'Серверы',
                  count: currentProfiles.length,
                ),
                const SizedBox(height: 10),
              ],
            ),
            itemCount: currentProfiles.length,
            onReorderItem: profiles.reorderProfiles,
            itemBuilder: (context, index) {
              final profile = currentProfiles[index];
              return Padding(
                key: ValueKey(profile.id),
                padding: const EdgeInsets.only(bottom: 12),
                child: _ProfileCard(
                  profile: profile,
                  identity: tunnel.egressIdentityFor(profile.id),
                  selected: activeTarget?.id == profile.id,
                  multiSelected: false,
                  selectionMode: false,
                  reorderIndex: index,
                  onSelect: () {},
                  onLongPress: null,
                  latencyMs: profile.latencyMs,
                  onRefreshPing: null,
                  onEdit: () {},
                  onExport: () {},
                  onDelete: () {},
                ),
              );
            },
          );
        }

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_selectionMode)
              _ProfilesSelectionHeader(
                selectedCount: _selectedProfileIds.length,
                allSelected: _selectedProfileIds.length == currentProfiles.length,
                refreshingLatency: tunnel.refreshingLatency,
                onClose: _clearSelection,
                onSelectAll: _selectAll,
                onPing: _pingSelected,
                onExport: () => _exportSelected(context),
                onReorder: _startReorder,
                onDelete: () => _deleteSelected(context),
              )
            else
              _ProfilesHeader(
                refreshingLatency: tunnel.refreshingLatency,
                canRefreshLatency: currentProfiles.isNotEmpty,
                onOpenProfileMenu: () => widget.owner._showProfileMenu(context),
                onRefreshLatency: tunnel.refreshAllLatencies,
              ),
            const SizedBox(height: 20),
            if (currentProfiles.isEmpty)
              _EmptyProfiles(
                onImport: () => widget.owner._showProfileMenu(context),
              )
            else ...[
              _SectionTitle(title: 'Серверы', count: currentProfiles.length),
              const SizedBox(height: 10),
              for (final profile in currentProfiles)
                  Padding(
                    key: ValueKey(profile.id),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ProfileCard(
                      profile: profile,
                      identity: tunnel.egressIdentityFor(profile.id),
                      selected: activeTarget?.id == profile.id,
                      multiSelected: _selectedProfileIds.contains(profile.id),
                      selectionMode: _selectionMode,
                      onSelect: () => _selectionMode
                          ? _toggleSelection(profile.id)
                          : tunnel.selectTarget(profile.id),
                      onLongPress: () => _enterSelection(profile.id),
                      latencyMs: profile.latencyMs,
                      onRefreshPing: tunnel.canRefreshTargetLatency(profile.id)
                          ? () => tunnel.refreshProfileLatency(profile.id)
                          : null,
                      onEdit: () =>
                          widget.owner._showEditProfileDialog(context, profile),
                      onExport: () => widget.owner._showXrayJsonExportMenu(
                        context,
                        profileId: profile.id,
                        suggestedBaseName: profile.name,
                      ),
                      onDelete: () => widget.owner._deleteTarget(
                        context,
                        profile.id,
                        profile.name,
                      ),
                    ),
                  ),
              if (!_selectionMode && profiles.balancers.isNotEmpty) ...[
                const SizedBox(height: 10),
                _SectionTitle(
                  title: 'Балансировщики',
                  count: profiles.balancers.length,
                ),
                const SizedBox(height: 10),
                for (final balancer in profiles.balancers)
                  Padding(
                    key: ValueKey(balancer.id),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _BalancerCard(
                      balancer: balancer,
                      identity: tunnel.egressIdentityFor(balancer.id),
                      members: [
                        for (final id in balancer.memberIds)
                          ...currentProfiles.where((item) => item.id == id),
                      ],
                      selected: activeTarget?.id == balancer.id,
                      latencyMs: profiles.targetById(balancer.id)?.latencyMs,
                      onRefreshPing: tunnel.canRefreshTargetLatency(balancer.id)
                          ? () => tunnel.refreshTargetLatency(balancer.id)
                          : null,
                      onSelect: _selectionMode
                          ? () {}
                          : () => tunnel.selectTarget(balancer.id),
                      onEdit: () => widget.owner._showBalancerDialog(
                        context,
                        existing: balancer,
                      ),
                      onDelete: () => widget.owner._deleteTarget(
                        context,
                        balancer.id,
                        balancer.name,
                      ),
                    ),
                  ),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _ProfilesSelectionHeader extends StatelessWidget {
  const _ProfilesSelectionHeader({
    required this.selectedCount,
    required this.allSelected,
    required this.refreshingLatency,
    required this.onClose,
    required this.onSelectAll,
    required this.onPing,
    required this.onExport,
    required this.onReorder,
    required this.onDelete,
  });

  final int selectedCount;
  final bool allSelected;
  final bool refreshingLatency;
  final VoidCallback onClose;
  final VoidCallback onSelectAll;
  final Future<void> Function() onPing;
  final VoidCallback onExport;
  final VoidCallback onReorder;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Закрыть выбор',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
              Expanded(
                child: Text(
                  'Выбрано: $selectedCount',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: allSelected ? 'Выбраны все' : 'Выбрать все',
                onPressed: allSelected ? null : onSelectAll,
                icon: const Icon(Icons.select_all_rounded),
              ),
            ],
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            children: [
              IconButton(
                tooltip: 'Проверить пинг выбранных',
                onPressed: refreshingLatency ? null : () => onPing(),
                icon: const Icon(Icons.network_ping_rounded),
              ),
              IconButton(
                tooltip: 'Экспортировать выбранные',
                onPressed: onExport,
                icon: const Icon(Icons.ios_share_rounded),
              ),
              IconButton(
                tooltip: 'Изменить порядок',
                onPressed: onReorder,
                icon: const Icon(Icons.swap_vert_rounded),
              ),
              IconButton(
                tooltip: 'Удалить выбранные',
                onPressed: onDelete,
                color: OrexColors.danger,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfilesReorderHeader extends StatelessWidget {
  const _ProfilesReorderHeader({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.drag_indicator_rounded, color: OrexColors.copper),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Порядок серверов',
                    style: Theme.of(context).textTheme.titleMedium),
                Text(
                  'Перетаскивай карточки за ручку справа',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: onDone,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Готово'),
          ),
        ],
      ),
    );
  }
}

class _ProfilesHeader extends StatelessWidget {
  const _ProfilesHeader({
    required this.refreshingLatency,
    required this.canRefreshLatency,
    required this.onOpenProfileMenu,
    required this.onRefreshLatency,
  });

  final bool refreshingLatency;
  final bool canRefreshLatency;
  final VoidCallback onOpenProfileMenu;
  final Future<void> Function() onRefreshLatency;

  @override
  Widget build(BuildContext context) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Профили', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Серверы, пинг и балансировщики Xray',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );

    final actions = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        OutlinedButton.icon(
          onPressed: onOpenProfileMenu,
          icon: const Icon(Icons.add_rounded),
          label: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Профиль'),
              SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down_rounded, size: 18),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed:
              refreshingLatency || !canRefreshLatency ? null : onRefreshLatency,
          icon: const Icon(Icons.network_ping_rounded),
          label: const Text('Проверить пинг'),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 700) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: title),
              const SizedBox(width: 20),
              actions,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            const SizedBox(height: 14),
            actions,
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title.toUpperCase(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: OrexColors.copper,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                )),
        const SizedBox(width: 8),
        Text('$count', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
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
            'Импортируйте ссылку или JSON Xray с одним или несколькими профилями.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.add_link_rounded),
            label: const Text('Импортировать профиль'),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.identity,
    required this.selected,
    required this.multiSelected,
    required this.selectionMode,
    required this.onSelect,
    required this.onLongPress,
    required this.latencyMs,
    required this.onRefreshPing,
    required this.onEdit,
    required this.onExport,
    required this.onDelete,
    this.reorderIndex,
  });

  final TunnelProfile profile;
  final EgressIdentity? identity;
  final bool selected;
  final bool multiSelected;
  final bool selectionMode;
  final VoidCallback onSelect;
  final VoidCallback? onLongPress;
  final int? latencyMs;
  final VoidCallback? onRefreshPing;
  final VoidCallback onEdit;
  final VoidCallback onExport;
  final VoidCallback onDelete;
  final int? reorderIndex;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 22,
      tint: multiSelected || selected ? OrexColors.copper : null,
      opacity: multiSelected
          ? 0.24
          : selected
              ? 0.16
              : 0.50,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: onSelect,
        onLongPress: onLongPress,
        leading: EgressAvatar(
          identity: identity,
          selected: selected || multiSelected,
        ),
        title: Row(
          children: [
            Expanded(
                child: Text(profile.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
            _PingBadge(
              latencyMs: latencyMs,
              onTap: onRefreshPing,
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            '${profile.endpoint}\n${profile.protocol} · ${profile.transportLabel}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        isThreeLine: true,
        trailing: reorderIndex != null
            ? ReorderableDragStartListener(
                index: reorderIndex!,
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.drag_handle_rounded),
                ),
              )
            : selectionMode
                ? Checkbox(
                    value: multiSelected,
                    onChanged: (_) => onSelect(),
                  )
                : PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') onEdit();
                      if (value == 'ping') onRefreshPing?.call();
                      if (value == 'export') onExport();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Редактировать'),
                      ),
                      PopupMenuItem(
                        value: 'ping',
                        enabled: onRefreshPing != null,
                        child: const Text('Проверить пинг'),
                      ),
                      const PopupMenuItem(
                        value: 'export',
                        child: Text('Экспорт JSON Xray'),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Удалить'),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _PingBadge extends StatelessWidget {
  const _PingBadge({
    required this.latencyMs,
    required this.onTap,
  });

  final int? latencyMs;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final latency = latencyMs;
    final color = latency == null
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : latency < 100
            ? OrexColors.online
            : latency < 1000
                ? OrexColors.copper
                : OrexColors.danger;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          latency == null ? 'Пинг —' : '$latency мс',
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _BalancerCard extends StatelessWidget {
  const _BalancerCard({
    required this.balancer,
    required this.identity,
    required this.members,
    required this.selected,
    required this.latencyMs,
    required this.onRefreshPing,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  final BalancerProfile balancer;
  final EgressIdentity? identity;
  final List<TunnelProfile> members;
  final bool selected;
  final int? latencyMs;
  final VoidCallback? onRefreshPing;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
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
        leading: EgressAvatar(
          identity: identity,
          fallbackIcon: Icons.hub_rounded,
          selected: selected,
        ),
        title: Row(
          children: [
            Expanded(
                child: Text(balancer.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
            _PingBadge(
              latencyMs: latencyMs,
              onTap: onRefreshPing,
            ),
          ],
        ),
        subtitle: Text(
          '${members.length} серверов · ${balancer.strategy.title}\n${members.map((e) => e.name).join(' · ')}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') onEdit();
            if (value == 'delete') onDelete();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'edit', child: Text('Редактировать')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'delete', child: Text('Удалить')),
          ],
        ),
      ),
    );
  }
}

class _ImportLinkDialog extends StatefulWidget {
  const _ImportLinkDialog({required this.profiles});

  final ProfilesController profiles;

  @override
  State<_ImportLinkDialog> createState() => _ImportLinkDialogState();
}

class _ImportLinkDialogState extends State<_ImportLinkDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  bool _importing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      setState(() => _error = 'В буфере обмена нет текста');
      return;
    }
    setState(() {
      _controller.text = text;
      _controller.selection = TextSelection.collapsed(offset: text.length);
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final profile = await widget.profiles.importLink(_controller.text);
      if (mounted) Navigator.of(context).pop(profile);
    } on VlessLinkFormatException catch (error) {
      if (mounted) {
        setState(() {
          _importing = false;
          _error = error.message;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _importing = false;
          _error = 'Не удалось импортировать: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Импорт профиля'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              minLines: 4,
              maxLines: 8,
              autofocus: true,
              enabled: !_importing,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: 'vless://…, vmess://…, ss://…, socks5://…',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _importing ? null : _pasteFromClipboard,
                icon: const Icon(Icons.content_paste_rounded),
                label: const Text('Вставить из буфера обмена'),
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
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}

class _ImportXrayJsonDialog extends StatefulWidget {
  const _ImportXrayJsonDialog({required this.profiles});

  final ProfilesController profiles;

  @override
  State<_ImportXrayJsonDialog> createState() => _ImportXrayJsonDialogState();
}

class _ImportXrayJsonDialogState extends State<_ImportXrayJsonDialog> {
  final TextEditingController _controller = TextEditingController();
  final XrayJsonSource _source = XrayJsonSource();
  String? _error;
  bool _importing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      setState(() => _error = 'В буфере обмена нет JSON или URL');
      return;
    }
    setState(() {
      _controller.text = text;
      _controller.selection = TextSelection.collapsed(offset: text.length);
      _error = null;
    });
  }

  Future<void> _pickFile() async {
    if (_importing) return;
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Xray JSON',
            extensions: ['json'],
          ),
        ],
      );
      if (file == null || !mounted) return;
      setState(() {
        _importing = true;
        _error = null;
      });
      if (await file.length() > XrayJsonCodec.maxPayloadBytes) {
        throw const FormatException('JSON Xray больше 5 МБ');
      }
      final payload = await file.readAsString();
      await _importPayload(payload, sourceLabel: file.name);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _submit() async {
    if (_importing) return;
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Вставь JSON, массив [] или URL');
      return;
    }
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final uri = Uri.tryParse(raw);
      if (uri != null &&
          uri.hasAuthority &&
          (uri.scheme == 'http' || uri.scheme == 'https')) {
        final payload = await _source.loadUrl(raw);
        await _importPayload(payload, sourceLabel: raw);
      } else {
        await _importPayload(raw);
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _importPayload(
    String payload, {
    String sourceLabel = '',
  }) async {
    final result = await widget.profiles.importXrayJson(
      payload,
      sourceLabel: sourceLabel,
    );
    if (mounted) Navigator.of(context).pop(result);
  }

  void _showError(Object error) {
    if (!mounted) return;
    setState(() {
      _importing = false;
      _error = error is FormatException
          ? error.message.toString()
          : 'Не удалось импортировать JSON: $error';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Импорт JSON Xray'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Поддерживается полный Xray config, один outbound, массив [] '
              'из нескольких конфигов и HTTP/HTTPS ссылка с JSON.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              minLines: 5,
              maxLines: 12,
              autofocus: true,
              enabled: !_importing,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: '{ "outbounds": [...] }\nили https://example.com/config.json',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _importing ? null : _pickFile,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Выбрать .json'),
                ),
                TextButton.icon(
                  onPressed: _importing ? null : _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste_rounded),
                  label: const Text('Из буфера'),
                ),
              ],
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
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Импортировать'),
        ),
      ],
    );
  }
}

class _EditProfileDialog extends StatefulWidget {
  const _EditProfileDialog({
    required this.profile,
    this.title = 'Редактировать профиль',
    this.allowProtocolSelection = false,
  });

  final TunnelProfile profile;
  final String title;
  final bool allowProtocolSelection;

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.profile.name);
  late final TextEditingController _address =
      TextEditingController(text: widget.profile.address);
  late final TextEditingController _port =
      TextEditingController(text: '${widget.profile.port}');
  late final TextEditingController _uuid =
      TextEditingController(text: widget.profile.userId);
  late final TextEditingController _protocolPassword =
      TextEditingController(text: widget.profile.password);
  late final TextEditingController _encryption =
      TextEditingController(text: widget.profile.encryption);
  late final TextEditingController _vmessSecurity =
      TextEditingController(text: widget.profile.vmessSecurity);
  late final TextEditingController _serverName =
      TextEditingController(text: widget.profile.serverName);
  late final TextEditingController _fingerprint =
      TextEditingController(text: widget.profile.fingerprint);
  late final TextEditingController _password =
      TextEditingController(text: widget.profile.realityPassword);
  late final TextEditingController _shortId =
      TextEditingController(text: widget.profile.shortId);
  late final TextEditingController _path =
      TextEditingController(text: widget.profile.path);
  late final TextEditingController _host =
      TextEditingController(text: widget.profile.host);
  late final TextEditingController _serviceName =
      TextEditingController(text: widget.profile.serviceName);
  late final TextEditingController _flow =
      TextEditingController(text: widget.profile.flow);
  late String _security = widget.profile.security;
  late String _transport = widget.profile.transport;
  late OutboundProtocol _protocol = widget.profile.outboundProtocol;
  bool _allowInsecure = false;
  String? _error;

  bool get _usesStreamSettings => switch (_protocol) {
        OutboundProtocol.vless ||
        OutboundProtocol.vmess ||
        OutboundProtocol.trojan ||
        OutboundProtocol.http =>
          true,
        OutboundProtocol.shadowsocks || OutboundProtocol.socks => false,
      };

  bool get _needsUserId =>
      _protocol == OutboundProtocol.vless ||
      _protocol == OutboundProtocol.vmess;
  bool get _canUseOptionalCredentials =>
      _protocol == OutboundProtocol.socks || _protocol == OutboundProtocol.http;
  bool get _needsPassword =>
      _protocol == OutboundProtocol.trojan ||
      _protocol == OutboundProtocol.shadowsocks ||
      _canUseOptionalCredentials;

  int get _defaultPort => switch (_protocol) {
        OutboundProtocol.vless ||
        OutboundProtocol.vmess ||
        OutboundProtocol.trojan =>
          443,
        OutboundProtocol.shadowsocks => 8388,
        OutboundProtocol.socks => 1080,
        OutboundProtocol.http => 80,
      };

  String get _defaultSecurity => switch (_protocol) {
        OutboundProtocol.trojan => 'tls',
        _ => 'none',
      };

  void _changeProtocol(OutboundProtocol value) {
    if (value == _protocol) return;
    setState(() {
      _protocol = value;
      _uuid.clear();
      _protocolPassword.clear();
      _flow.clear();
      _serverName.clear();
      _fingerprint.text = 'chrome';
      _password.clear();
      _shortId.clear();
      _path.clear();
      _host.clear();
      _serviceName.clear();
      _vmessSecurity.text = 'auto';
      _encryption.text =
          value == OutboundProtocol.shadowsocks ? 'aes-256-gcm' : 'none';
      _security = _defaultSecurity;
      _transport = 'raw';
      _allowInsecure = false;
      _error = null;
      _port.text = '$_defaultPort';
    });
  }

  @override
  void initState() {
    super.initState();
    _allowInsecure = widget.profile.allowInsecure;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _address,
      _port,
      _uuid,
      _protocolPassword,
      _encryption,
      _vmessSecurity,
      _serverName,
      _fingerprint,
      _password,
      _shortId,
      _path,
      _host,
      _serviceName,
      _flow,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final port = int.tryParse(_port.text.trim());
    if (_name.text.trim().isEmpty || _address.text.trim().isEmpty) {
      setState(() => _error = 'Имя и адрес обязательны');
      return;
    }
    if (_needsUserId && _uuid.text.trim().isEmpty) {
      setState(() => _error = 'Для ${_protocol.title} нужен UUID');
      return;
    }
    if ((_protocol == OutboundProtocol.trojan ||
            _protocol == OutboundProtocol.shadowsocks) &&
        _protocolPassword.text.isEmpty) {
      setState(() => _error = 'Для ${_protocol.title} нужен пароль');
      return;
    }
    if (_canUseOptionalCredentials &&
        (_uuid.text.trim().isEmpty != _protocolPassword.text.isEmpty)) {
      setState(() => _error = 'Укажите и имя пользователя, и пароль');
      return;
    }
    if (_protocol == OutboundProtocol.shadowsocks &&
        _encryption.text.trim().isEmpty) {
      setState(() => _error = 'Для Shadowsocks нужен метод шифрования');
      return;
    }
    if (_protocol == OutboundProtocol.vmess &&
        !{
          'auto',
          'aes-128-gcm',
          'chacha20-poly1305',
        }.contains(_vmessSecurity.text.trim().toLowerCase())) {
      setState(
        () =>
            _error = 'VMess security: auto, aes-128-gcm или chacha20-poly1305',
      );
      return;
    }
    if (_usesStreamSettings &&
        _security == 'reality' &&
        _password.text.trim().isEmpty) {
      setState(() => _error = 'Для REALITY нужен public key');
      return;
    }
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = 'Некорректный порт');
      return;
    }
    Navigator.pop(
      context,
      widget.profile.copyWith(
        name: _name.text.trim(),
        address: _address.text.trim(),
        port: port,
        userId: _uuid.text.trim(),
        outboundProtocol: _protocol,
        password: _protocolPassword.text,
        encryption: _encryption.text.trim(),
        vmessSecurity: _vmessSecurity.text.trim().isEmpty
            ? 'auto'
            : _vmessSecurity.text.trim().toLowerCase(),
        flow: _flow.text.trim(),
        security: _security,
        transport: _transport,
        serverName: _serverName.text.trim(),
        fingerprint: _fingerprint.text.trim().isEmpty
            ? 'chrome'
            : _fingerprint.text.trim(),
        realityPassword: _password.text.trim(),
        shortId: _shortId.text.trim(),
        path: _path.text.trim(),
        host: _host.text.trim(),
        serviceName: _serviceName.text.trim(),
        allowInsecure: _allowInsecure,
        clearLatency: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: OrexColors.danger)),
                const SizedBox(height: 10),
              ],
              _field(_name, 'Имя'),
              if (widget.allowProtocolSelection)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: DropdownButtonFormField<OutboundProtocol>(
                    key: ValueKey(_protocol),
                    initialValue: _protocol,
                    decoration: const InputDecoration(labelText: 'Протокол'),
                    items: [
                      for (final protocol in OutboundProtocol.values)
                        DropdownMenuItem(
                          value: protocol,
                          child: Text(protocol.title),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) _changeProtocol(value);
                    },
                  ),
                ),
              Row(children: [
                Expanded(flex: 3, child: _field(_address, 'Адрес')),
                const SizedBox(width: 10),
                Expanded(child: _field(_port, 'Порт', number: true)),
              ]),
              if (_needsUserId || _canUseOptionalCredentials)
                _field(
                  _uuid,
                  _needsUserId ? 'UUID' : 'Имя пользователя (необязательно)',
                ),
              if (_needsPassword)
                _field(
                  _protocolPassword,
                  _canUseOptionalCredentials
                      ? 'Пароль (необязательно)'
                      : 'Пароль',
                ),
              if (_protocol == OutboundProtocol.shadowsocks)
                _field(
                  _encryption,
                  'Метод шифрования (например aes-256-gcm)',
                ),
              if (_protocol == OutboundProtocol.vmess)
                _field(
                  _vmessSecurity,
                  'VMess security (auto / aes-128-gcm / chacha20-poly1305)',
                ),
              if (_usesStreamSettings) ...[
                if (_protocol == OutboundProtocol.vless)
                  _field(_flow, 'Flow (например xtls-rprx-vision)'),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _security,
                      decoration: const InputDecoration(labelText: 'Security'),
                      items: const [
                        DropdownMenuItem(value: 'none', child: Text('None')),
                        DropdownMenuItem(value: 'tls', child: Text('TLS')),
                        DropdownMenuItem(
                            value: 'reality', child: Text('REALITY')),
                      ],
                      onChanged: (value) =>
                          setState(() => _security = value ?? 'none'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _transport,
                      decoration: const InputDecoration(labelText: 'Transport'),
                      items: const [
                        DropdownMenuItem(
                            value: 'raw', child: Text('RAW / TCP')),
                        DropdownMenuItem(
                            value: 'websocket', child: Text('WebSocket')),
                        DropdownMenuItem(value: 'grpc', child: Text('gRPC')),
                        DropdownMenuItem(value: 'xhttp', child: Text('XHTTP')),
                        DropdownMenuItem(
                            value: 'httpupgrade', child: Text('HTTPUpgrade')),
                      ],
                      onChanged: (value) =>
                          setState(() => _transport = value ?? 'raw'),
                    ),
                  ),
                ]),
                if (_security == 'tls' || _security == 'reality') ...[
                  _field(_serverName, 'Server Name / SNI'),
                  _field(_fingerprint, 'Fingerprint'),
                ],
                if (_security == 'reality') ...[
                  _field(_password, 'REALITY public key / password'),
                  _field(_shortId, 'Short ID'),
                ],
                if (_security == 'tls')
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Allow insecure'),
                    value: _allowInsecure,
                    onChanged: (value) =>
                        setState(() => _allowInsecure = value),
                  ),
                if (_transport == 'websocket' ||
                    _transport == 'xhttp' ||
                    _transport == 'httpupgrade') ...[
                  _field(_path, 'Path'),
                  _field(_host, 'Host'),
                ],
                if (_transport == 'grpc')
                  _field(_serviceName, 'gRPC service name'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена')),
        FilledButton(onPressed: _submit, child: const Text('Сохранить')),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label,
      {bool number = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

class _BalancerDraft {
  const _BalancerDraft({
    required this.name,
    required this.memberIds,
    required this.strategy,
    required this.probeUrl,
    required this.probeIntervalSeconds,
    required this.fallbackTarget,
  });

  final String name;
  final List<String> memberIds;
  final BalancerStrategy strategy;
  final String probeUrl;
  final int probeIntervalSeconds;
  final String? fallbackTarget;
}

class _BalancerDialog extends StatefulWidget {
  const _BalancerDialog({required this.profiles, this.existing});

  final List<TunnelProfile> profiles;
  final BalancerProfile? existing;

  @override
  State<_BalancerDialog> createState() => _BalancerDialogState();
}

class _BalancerDialogState extends State<_BalancerDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _probeUrl = TextEditingController(
    text: widget.existing?.probeUrl ?? 'https://www.gstatic.com/generate_204',
  );
  late final TextEditingController _interval = TextEditingController(
    text: '${widget.existing?.probeIntervalSeconds ?? 30}',
  );
  late final Set<String> _members =
      widget.existing?.memberIds.toSet() ?? <String>{};
  late BalancerStrategy _strategy =
      widget.existing?.strategy ?? BalancerStrategy.random;
  String _fallbackValue = 'none';
  String? _error;

  @override
  void initState() {
    super.initState();
    final fallback = widget.existing?.fallbackTarget;
    final knownProfileFallback = fallback != null &&
        fallback.startsWith(BalancerProfile.fallbackProfilePrefix) &&
        widget.profiles.any(
          (profile) => BalancerProfile.fallbackProfile(profile.id) == fallback,
        );
    if (fallback == BalancerProfile.fallbackDirect ||
        fallback == BalancerProfile.fallbackBlock ||
        knownProfileFallback) {
      _fallbackValue = fallback!;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _probeUrl.dispose();
    _interval.dispose();
    super.dispose();
  }

  void _submit() {
    final interval = int.tryParse(_interval.text.trim()) ?? 30;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Укажи имя балансировщика');
      return;
    }
    if (_members.length < 2) {
      setState(() => _error = 'Выбери минимум два сервера');
      return;
    }
    Navigator.pop(
      context,
      _BalancerDraft(
        name: _name.text.trim(),
        memberIds: _members.toList(growable: false),
        strategy: _strategy,
        probeUrl: _probeUrl.text.trim(),
        probeIntervalSeconds: interval,
        fallbackTarget: _fallbackValue == 'none' ? null : _fallbackValue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Новый балансировщик'
          : 'Редактировать балансировщик'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: OrexColors.danger)),
                const SizedBox(height: 10),
              ],
              TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Имя')),
              const SizedBox(height: 12),
              DropdownButtonFormField<BalancerStrategy>(
                initialValue: _strategy,
                decoration: const InputDecoration(labelText: 'Стратегия'),
                items: [
                  for (final strategy in BalancerStrategy.values)
                    DropdownMenuItem(
                      value: strategy,
                      child: Text(strategy.title),
                    ),
                ],
                onChanged: (value) => setState(
                  () => _strategy = value ?? BalancerStrategy.random,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _fallbackValue,
                decoration: const InputDecoration(labelText: 'Fallback'),
                items: [
                  const DropdownMenuItem(
                    value: 'none',
                    child: Text('Нет fallback'),
                  ),
                  const DropdownMenuItem(
                    value: BalancerProfile.fallbackDirect,
                    child: Text('Напрямую · direct'),
                  ),
                  const DropdownMenuItem(
                    value: BalancerProfile.fallbackBlock,
                    child: Text('Блокировать · block'),
                  ),
                  for (final profile in widget.profiles)
                    DropdownMenuItem(
                      value: BalancerProfile.fallbackProfile(profile.id),
                      child: Text('Профиль · ${profile.name}'),
                    ),
                ],
                onChanged: (value) => setState(
                  () => _fallbackValue = value ?? 'none',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Xray использует fallbackTag, когда по результатам наблюдения '
                'все маршруты балансировщика недоступны.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_strategy == BalancerStrategy.leastPing ||
                  _fallbackValue != 'none') ...[
                const SizedBox(height: 12),
                TextField(
                    controller: _probeUrl,
                    decoration:
                        const InputDecoration(labelText: 'URL проверки')),
                const SizedBox(height: 12),
                TextField(
                  controller: _interval,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Интервал проверки, секунд'),
                ),
              ],
              const SizedBox(height: 16),
              Text('Серверы', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              for (final profile in widget.profiles)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _members.contains(profile.id),
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _members.add(profile.id);
                      } else {
                        _members.remove(profile.id);
                      }
                    });
                  },
                  title: Text(profile.name),
                  subtitle: Text(
                    '${profile.endpoint} · '
                    '${profile.latencyMs == null ? 'Пинг —' : '${profile.latencyMs} мс'}',
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена')),
        FilledButton(onPressed: _submit, child: const Text('Сохранить')),
      ],
    );
  }
}
