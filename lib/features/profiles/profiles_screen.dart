import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/egress/egress_identity.dart';
import '../../core/profiles/profiles_controller.dart';
import '../../core/profiles/proxy_subscription.dart';
import '../../core/profiles/vless_link_parser.dart';
import '../../core/profiles/xray_json_codec.dart';
import '../../core/profiles/xray_json_file.dart';
import '../../core/profiles/xray_json_source.dart';
import '../../core/tunnel/tunnel_models.dart';
import '../../platform/external_url_launcher.dart';
import '../../shared/theme/glass.dart';
import '../../shared/theme/orex_theme.dart';
import '../../shared/widgets/egress_avatar.dart';
import '../../shared/widgets/orex_choice_sheet.dart';
import '../../shared/widgets/squirrel_mascot.dart';
import '../home/tunnel_controller.dart';

enum _ProfileCreateAction {
  importLink,
  subscription,
  importXrayJson,
  newProfile,
  balancer,
}

enum _XrayJsonExportAction { copy, saveFile }

class _ProfileSection {
  const _ProfileSection({
    required this.key,
    required this.title,
    required this.profiles,
    this.subscription,
    this.manualGroupName,
  });

  final String key;
  final String title;
  final List<TunnelProfile> profiles;
  final ProxySubscription? subscription;
  final String? manualGroupName;
}

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
          value: _ProfileCreateAction.subscription,
          icon: Icons.sync_rounded,
          title: 'Подписка',
          subtitle: 'HTTP/HTTPS URL со списком серверов',
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
      case _ProfileCreateAction.subscription:
        await _showSubscriptionDialog(context);
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

  Future<void> _showSubscriptionDialog(BuildContext context) async {
    final result = await showDialog<SubscriptionSyncResult>(
      context: context,
      builder: (context) => _ImportSubscriptionDialog(profiles: profiles),
    );
    if (result == null || !context.mounted) return;
    final parts = <String>[
      if (result.addedCount > 0) 'добавлено ${result.addedCount}',
      if (result.updatedCount > 0) 'обновлено ${result.updatedCount}',
      if (result.removedCount > 0) 'удалено ${result.removedCount}',
      if (result.skippedUnsupported > 0)
        'пропущено ${result.skippedUnsupported}',
    ];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          parts.isEmpty
              ? 'Подписка «${result.subscription.name}» обновлена'
              : 'Подписка «${result.subscription.name}»: ${parts.join(', ')}',
        ),
      ),
    );
  }

  Future<void> _refreshSubscription(
    BuildContext context,
    ProxySubscription subscription,
  ) async {
    try {
      final result = await profiles.refreshSubscription(subscription.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '«${result.subscription.name}» обновлена: '
            '${result.subscription.profileIds.length} серверов',
          ),
        ),
      );
    } on FormatException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message.toString())),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось обновить подписку: $error')),
      );
    }
  }

  Future<void> _deleteSubscription(
    BuildContext context,
    ProxySubscription subscription,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить подписку?'),
        content: Text(
          '«${subscription.name}» и ${subscription.profileIds.length} '
          'серверов этой подписки будут удалены.',
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
    if (confirmed == true) await profiles.deleteSubscription(subscription.id);
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
    if (existing == null && profiles.profiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Для балансировщика нужен хотя бы один профиль'),
        ),
      );
      return;
    }
    final value = await showDialog<_BalancerDraft>(
      context: context,
      builder: (context) => _BalancerDialog(
        profiles: profiles.profiles,
        groups: profiles.profileGroups,
        probeUrl: tunnel.latencyProbeUrl,
        existing: existing,
      ),
    );
    if (value == null) return;
    try {
      await profiles.saveBalancer(
        id: existing?.id,
        name: value.name,
        memberIds: value.memberIds,
        memberGroupKeys: value.memberGroupKeys,
        strategy: value.strategy,
        probeUrl: tunnel.latencyProbeUrl,
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

enum _ProfileSelectionScope { servers, subscriptions }

class _ProfilesBodyState extends State<_ProfilesBody> {
  final Set<String> _selectedProfileIds = <String>{};
  final Set<String> _expandedSectionKeys = <String>{};
  final Set<String> _collapsedSectionKeys = <String>{};
  _ProfileSelectionScope? _selectionScope;
  String? _draggingProfileId;

  ProfilesController get profiles => widget.owner.profiles;
  TunnelController get tunnel => widget.owner.tunnel;
  bool get _selectionMode =>
      _selectionScope != null && _selectedProfileIds.isNotEmpty;
  bool get _selectingServers =>
      _selectionScope == _ProfileSelectionScope.servers;
  bool get _selectingSubscriptions =>
      _selectionScope == _ProfileSelectionScope.subscriptions;

  Set<String> get _manualProfileIds => {
        for (final profile in profiles.profiles)
          if (!profiles.isSubscriptionProfile(profile.id)) profile.id,
      };

  List<ProxySubscription> get _selectedSubscriptions => profiles.subscriptions
      .where(
        (subscription) => subscription.profileIds.isNotEmpty &&
            subscription.profileIds.every(_selectedProfileIds.contains),
      )
      .toList(growable: false);

  void _toggleSelection(String id) {
    if (!_selectingServers || profiles.isSubscriptionProfile(id)) return;
    setState(() {
      if (!_selectedProfileIds.add(id)) {
        _selectedProfileIds.remove(id);
      }
      if (_selectedProfileIds.isEmpty) _selectionScope = null;
    });
  }

  void _enterSelection(String id) {
    if (profiles.isSubscriptionProfile(id)) return;
    if (_selectionScope != null && !_selectingServers) return;
    if (_selectedProfileIds.contains(id)) return;
    setState(() {
      _selectionScope = _ProfileSelectionScope.servers;
      _selectedProfileIds.add(id);
    });
  }

  void _clearSelection() {
    if (_selectionScope == null && _selectedProfileIds.isEmpty) return;
    setState(() {
      _selectionScope = null;
      _selectedProfileIds.clear();
    });
  }

  void _selectAll() {
    final scope = _selectionScope;
    if (scope == null) return;
    setState(() {
      _selectedProfileIds.clear();
      switch (scope) {
        case _ProfileSelectionScope.servers:
          _selectedProfileIds.addAll(_manualProfileIds);
          break;
        case _ProfileSelectionScope.subscriptions:
          for (final subscription in profiles.subscriptions) {
            _selectedProfileIds.addAll(subscription.profileIds);
          }
          break;
      }
      if (_selectedProfileIds.isEmpty) _selectionScope = null;
    });
  }

  Future<void> _deleteSelected(BuildContext context) async {
    final ids = Set<String>.from(_selectedProfileIds);
    final scope = _selectionScope;
    if (ids.isEmpty || scope == null) return;

    if (scope == _ProfileSelectionScope.subscriptions) {
      final selectedSubscriptions = _selectedSubscriptions;
      if (selectedSubscriptions.isEmpty) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            selectedSubscriptions.length == 1
                ? 'Удалить подписку?'
                : 'Удалить ${selectedSubscriptions.length} подписки?',
          ),
          content: const Text(
            'Подписки и все принадлежащие им серверы будут удалены с устройства.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Удалить'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      for (final subscription in selectedSubscriptions) {
        await profiles.deleteSubscription(subscription.id);
        if (!mounted) return;
      }
      _clearSelection();
      return;
    }

    final manualIds = ids.where((id) => !profiles.isSubscriptionProfile(id)).toSet();
    if (manualIds.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Удалить ${manualIds.length} профилей?'),
        content: const Text(
          'Выбранные серверы будут удалены с этого устройства.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await profiles.deleteProfiles(manualIds);
    if (!mounted) return;
    _clearSelection();
  }

  Future<void> _exportSelected(BuildContext context) async {
    final ids = Set<String>.from(_selectedProfileIds);
    final scope = _selectionScope;
    if (ids.isEmpty || scope == null) return;
    if (scope == _ProfileSelectionScope.subscriptions) {
      final selectedSubscriptions = _selectedSubscriptions;
      if (selectedSubscriptions.isEmpty) return;
      const copyUrls = '__copy_subscription_urls__';
      const exportServers = '__export_subscription_servers__';
      final action = await showOrexChoiceSheet<String>(
        context,
        title: selectedSubscriptions.length == 1
            ? 'Экспорт подписки'
            : 'Экспорт подписок',
        options: const [
          OrexChoiceSheetOption<String>(
            value: copyUrls,
            icon: Icons.link_rounded,
            title: 'Скопировать исходную ссылку',
            subtitle: 'Для нескольких подписок — по одной ссылке на строку',
          ),
          OrexChoiceSheetOption<String>(
            value: exportServers,
            icon: Icons.data_object_rounded,
            title: 'Экспортировать серверы JSON Xray',
          ),
        ],
      );
      if (action == null || !context.mounted) return;
      if (action == copyUrls) {
        await Clipboard.setData(
          ClipboardData(
            text: selectedSubscriptions.map((item) => item.url).join('\n'),
          ),
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              selectedSubscriptions.length == 1
                  ? 'Ссылка подписки скопирована'
                  : 'Ссылки подписок скопированы',
            ),
          ),
        );
        return;
      }
      final profileIds = <String>{
        for (final subscription in selectedSubscriptions) ...subscription.profileIds,
      };
      if (profileIds.isEmpty) return;
      await widget.owner._showXrayJsonExportMenu(
        context,
        profileIds: profileIds,
        suggestedBaseName: selectedSubscriptions.length == 1
            ? selectedSubscriptions.single.name
            : 'orexray-subscriptions-${selectedSubscriptions.length}',
      );
      return;
    }

    await widget.owner._showXrayJsonExportMenu(
      context,
      profileIds: ids,
      suggestedBaseName: 'orexray-selected-${ids.length}',
    );
  }

  Future<void> _pingSelected() async {
    if (!_selectingServers ||
        _selectedProfileIds.isEmpty ||
        tunnel.refreshingLatency) {
      return;
    }
    await tunnel.refreshProfileLatencies(
      Set<String>.from(_selectedProfileIds),
    );
  }

  List<_ProfileSection> _buildProfileSections(
    List<TunnelProfile> currentProfiles, {
    required bool subscriptions,
  }) {
    final byId = <String, TunnelProfile>{
      for (final profile in currentProfiles) profile.id: profile,
    };
    final sections = <_ProfileSection>[];
    for (final group in profiles.profileGroups) {
      if (group.isSubscription != subscriptions) continue;
      final items = <TunnelProfile>[
        for (final id in group.profileIds)
          if (byId[id] case final profile?) profile,
      ];
      if (items.isEmpty) continue;
      sections.add(
        _ProfileSection(
          key: group.key,
          title: group.title,
          profiles: List.unmodifiable(items),
          subscription: group.subscription,
          manualGroupName: group.isManualGroup ? group.title : null,
        ),
      );
    }
    return sections;
  }

  int _selectedCountForSection(_ProfileSection section) => section.profiles
      .where((profile) => _selectedProfileIds.contains(profile.id))
      .length;

  _ProfileSelectionScope _scopeForSection(_ProfileSection section) =>
      section.subscription == null
          ? _ProfileSelectionScope.servers
          : _ProfileSelectionScope.subscriptions;

  void _toggleSectionSelection(_ProfileSection section) {
    final scope = _scopeForSection(section);
    if (_selectionScope != null && _selectionScope != scope) return;
    final ids = section.profiles.map((profile) => profile.id).toSet();
    setState(() {
      _selectionScope ??= scope;
      final fullySelected = ids.every(_selectedProfileIds.contains);
      if (fullySelected) {
        _selectedProfileIds.removeAll(ids);
      } else {
        _selectedProfileIds.addAll(ids);
      }
      if (_selectedProfileIds.isEmpty) _selectionScope = null;
    });
  }

  void _enterSectionSelection(_ProfileSection section) {
    final scope = _scopeForSection(section);
    if (_selectionScope != null && _selectionScope != scope) return;
    setState(() {
      _selectionScope = scope;
      _selectedProfileIds.addAll(
        section.profiles.map((profile) => profile.id),
      );
    });
  }

  bool _sectionExpanded(_ProfileSection section, String? activeId) {
    if (_expandedSectionKeys.contains(section.key)) return true;
    if (_collapsedSectionKeys.contains(section.key)) return false;
    if (section.subscription != null) {
      return activeId != null &&
          section.profiles.any((profile) => profile.id == activeId);
    }
    return true;
  }

  void _toggleSection(_ProfileSection section, String? activeId) {
    final expanded = _sectionExpanded(section, activeId);
    setState(() {
      if (expanded) {
        _expandedSectionKeys.remove(section.key);
        _collapsedSectionKeys.add(section.key);
      } else {
        _collapsedSectionKeys.remove(section.key);
        _expandedSectionKeys.add(section.key);
      }
    });
  }

  Future<String?> _requestGroupName(
    BuildContext context, {
    String initialValue = '',
    String title = 'Новая группа',
  }) async {
    final controller = TextEditingController(text: initialValue);
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 80,
            decoration: const InputDecoration(hintText: 'Например, Работа'),
            onSubmitted: (value) {
              final normalized = value.trim();
              if (normalized.isNotEmpty) {
                Navigator.of(dialogContext).pop(normalized);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final normalized = controller.text.trim();
                if (normalized.isNotEmpty) {
                  Navigator.of(dialogContext).pop(normalized);
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _assignToGroup(
    BuildContext context,
    Iterable<String> profileIds,
  ) async {
    final ids = profileIds.toSet();
    final manualIds = ids
        .where((id) => !profiles.isSubscriptionProfile(id))
        .toSet();
    if (manualIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Серверы подписки автоматически сгруппированы'),
        ),
      );
      return;
    }

    const createGroup = '__create_group__';
    const clearGroup = '__clear_group__';
    final action = await showOrexChoiceSheet<String>(
      context,
      title: 'Переместить в группу',
      options: [
        const OrexChoiceSheetOption<String>(
          value: clearGroup,
          icon: Icons.folder_off_outlined,
          title: 'Серверы',
        ),
        for (final name in profiles.manualGroupNames)
          OrexChoiceSheetOption<String>(
            value: name,
            icon: Icons.folder_outlined,
            title: name,
          ),
        const OrexChoiceSheetOption<String>(
          value: createGroup,
          icon: Icons.create_new_folder_outlined,
          title: 'Новая группа',
        ),
      ],
    );
    if (action == null || !context.mounted) return;

    String? targetGroup;
    if (action == createGroup) {
      targetGroup = await _requestGroupName(context);
      if (targetGroup == null || !context.mounted) return;
    } else if (action != clearGroup) {
      targetGroup = action;
    }

    final changed = await profiles.setProfilesGroup(manualIds, targetGroup);
    if (!context.mounted) return;
    if (ids.length != manualIds.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Перемещено $changed; серверы подписок оставлены в своих группах',
          ),
        ),
      );
    }
  }

  Future<void> _renameManualGroup(BuildContext context, String name) async {
    final next = await _requestGroupName(
      context,
      initialValue: name,
      title: 'Переименовать группу',
    );
    if (next == null || next == name || !mounted) return;
    await profiles.renameProfileGroup(name, next);
  }

  Future<void> _deleteManualGroup(BuildContext context, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Расформировать группу?'),
        content: Text(
          'Профили из группы «$name» останутся в разделе «Серверы».',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Расформировать'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await profiles.deleteProfileGroup(name);
  }

  Future<void> _openSubscriptionUrl(
    BuildContext context,
    String url,
  ) async {
    try {
      await ExternalUrlLauncher.open(url);
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть ссылку: $error')),
      );
    }
  }

  Future<void> _copySubscriptionUrl(
    BuildContext context,
    ProxySubscription subscription,
  ) async {
    await Clipboard.setData(ClipboardData(text: subscription.url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ссылка подписки скопирована')),
    );
  }

  Future<void> _exportSubscriptionServers(
    BuildContext context,
    ProxySubscription subscription,
  ) async {
    if (subscription.profileIds.isEmpty) return;
    await widget.owner._showXrayJsonExportMenu(
      context,
      profileIds: subscription.profileIds.toSet(),
      suggestedBaseName: subscription.name,
    );
  }

  Future<void> _selectFromProfiles(String id) async {
    if (!tunnel.canChangeTarget) return;
    await tunnel.selectTarget(id);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([profiles, tunnel.egressChanges]),
      builder: (context, _) {
        final currentProfiles = profiles.profiles;
        final validIds = currentProfiles.map((profile) => profile.id).toSet();
        _selectedProfileIds.removeWhere((id) => !validIds.contains(id));
        if (_selectedProfileIds.isEmpty) _selectionScope = null;
        final activeTarget = profiles.selectedTarget;
        final manualSections = _buildProfileSections(
          currentProfiles,
          subscriptions: false,
        );
        final subscriptionSections = _buildProfileSections(
          currentProfiles,
          subscriptions: true,
        );
        final subscriptionSectionsById = <String, _ProfileSection>{
          for (final section in subscriptionSections)
            if (section.subscription case final subscription?)
              subscription.id: section,
        };
        final manualProfileCount = manualSections.fold<int>(
          0,
          (count, section) => count + section.profiles.length,
        );
        final manualSelectedCount = manualSections.fold<int>(
          0,
          (count, section) => count + _selectedCountForSection(section),
        );
        final hasManualGroups =
            manualSections.any((section) => section.manualGroupName != null);
        final groupedManualView = manualSections.length > 1 || hasManualGroups;
        final selectedSubscriptions = _selectedSubscriptions;
        final selectedSubscriptionCount = selectedSubscriptions.length;
        final canGroupSelected = _selectingServers && _selectedProfileIds.isNotEmpty;

        Widget buildProfileCard(
          TunnelProfile profile,
          int localIndex,
          _ProfileSection section, {
          bool allowReorder = true,
          bool nested = false,
        }) {
          final serverSelectionEnabled =
              section.subscription == null && _selectingServers;
          final card = _ProfileCard(
            profile: profile,
            identity: tunnel.egressIdentityFor(profile.id),
            selected: activeTarget?.id == profile.id,
            multiSelected: serverSelectionEnabled &&
                _selectedProfileIds.contains(profile.id),
            selectionMode: serverSelectionEnabled,
            dragging: _draggingProfileId == profile.id,
            onSelect: () {
              if (_selectingServers && section.subscription == null) {
                _toggleSelection(profile.id);
              } else if (!_selectionMode) {
                unawaited(_selectFromProfiles(profile.id));
              }
            },
            onLongPress: _selectionScope == null && section.subscription == null
                ? () => _enterSelection(profile.id)
                : null,
            latencyMs: profile.latencyMs,
            onRefreshPing: tunnel.canRefreshTargetLatency(profile.id)
                ? () => tunnel.refreshProfileLatency(profile.id)
                : null,
            onEdit: () => widget.owner._showEditProfileDialog(context, profile),
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
            onGroup: section.subscription == null
                ? () => _assignToGroup(context, {profile.id})
                : null,
          );
          return Padding(
            key: ValueKey(profile.id),
            padding: EdgeInsets.only(bottom: nested ? 4 : 12),
            child: _selectingServers && allowReorder
                ? ReorderableDelayedDragStartListener(
                    index: localIndex,
                    child: card,
                  )
                : card,
          );
        }

        Widget buildManualGroupHeader(_ProfileSection section) {
          final selectedCount = _selectedCountForSection(section);
          return _ProfileGroupHeader(
            title: section.title,
            count: section.profiles.length,
            selectedCount: selectedCount,
            selectionMode: _selectingServers,
            expanded: _sectionExpanded(section, activeTarget?.id),
            onToggle: () => _selectingServers
                ? _toggleSectionSelection(section)
                : _toggleSection(section, activeTarget?.id),
            onLongPress: _selectionScope == null
                ? () => _enterSectionSelection(section)
                : null,
            onExpandToggle: () => _toggleSection(section, activeTarget?.id),
            onRename: section.manualGroupName == null
                ? null
                : () => _renameManualGroup(
                      context,
                      section.manualGroupName!,
                    ),
            onDelete: section.manualGroupName == null
                ? null
                : () => _deleteManualGroup(
                      context,
                      section.manualGroupName!,
                    ),
          );
        }


        final slivers = <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(
              child: AnimatedBuilder(
                animation: tunnel.profileUiChanges,
                builder: (context, _) => _ProfilesHeader(
                  refreshingLatency: tunnel.refreshingLatency,
                  canRefreshLatency: currentProfiles.isNotEmpty,
                  selectionMode: _selectionMode,
                  selectionScope: _selectionScope,
                  allSelected: switch (_selectionScope) {
                    _ProfileSelectionScope.servers => manualProfileCount > 0 &&
                        manualSelectedCount == manualProfileCount,
                    _ProfileSelectionScope.subscriptions =>
                      profiles.subscriptions.isNotEmpty &&
                          selectedSubscriptionCount == profiles.subscriptions.length,
                    null => false,
                  },
                  onOpenProfileMenu: () => widget.owner._showProfileMenu(context),
                  onRefreshLatency: tunnel.refreshAllLatencies,
                  onCloseSelection: _clearSelection,
                  onSelectAll: _selectAll,
                  onPingSelected: _pingSelected,
                  onExportSelected: () => _exportSelected(context),
                  onDeleteSelected: () => _deleteSelected(context),
                  onGroupSelected: () =>
                      _assignToGroup(context, _selectedProfileIds),
                  canGroupSelected: canGroupSelected,
                ),
              ),
            ),
          ),
          if (profiles.subscriptions.isNotEmpty) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              sliver: SliverToBoxAdapter(
                child: _SectionTitle(
                  title: 'Подписки',
                  count: profiles.subscriptions.length,
                  selectedCount:
                      _selectingSubscriptions ? selectedSubscriptionCount : null,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverReorderableList(
                itemCount: profiles.subscriptions.length,
                itemBuilder: (context, index) {
                  final subscription = profiles.subscriptions[index];
                  final section = subscriptionSectionsById[subscription.id];
                  final selectedCount = section == null
                      ? 0
                      : _selectedCountForSection(section);
                  final fullySelected = section != null &&
                      section.profiles.isNotEmpty &&
                      selectedCount == section.profiles.length;
                  final expanded = section != null &&
                      _sectionExpanded(section, activeTarget?.id);
                  final card = _SubscriptionCard(
                    subscription: subscription,
                    refreshing: profiles.subscriptionRefreshing(subscription.id),
                    expanded: expanded,
                    selectedCount: selectedCount,
                    selectionMode: _selectingSubscriptions,
                    onToggle: section == null
                        ? null
                        : () => _selectingSubscriptions
                            ? _toggleSectionSelection(section)
                            : _toggleSection(section, activeTarget?.id),
                    onLongPress: section == null || _selectionScope != null
                        ? null
                        : () => _enterSectionSelection(section),
                    onExpandToggle: section == null
                        ? null
                        : () => _toggleSection(section, activeTarget?.id),
                    onRefresh: () => widget.owner._refreshSubscription(
                      context,
                      subscription,
                    ),
                    onDelete: () => widget.owner._deleteSubscription(
                      context,
                      subscription,
                    ),
                    onCopyUrl: () => _copySubscriptionUrl(
                      context,
                      subscription,
                    ),
                    onExportServers: () => _exportSubscriptionServers(
                      context,
                      subscription,
                    ),
                    onOpenSupport: subscription.supportUrl.isEmpty
                        ? null
                        : () => _openSubscriptionUrl(
                              context,
                              subscription.supportUrl,
                            ),
                    onOpenWebPage: subscription.webPageUrl.isEmpty
                        ? null
                        : () => _openSubscriptionUrl(
                              context,
                              subscription.webPageUrl,
                            ),
                  );
                  final header = _selectingSubscriptions &&
                          fullySelected &&
                          profiles.subscriptions.length > 1
                      ? ReorderableDelayedDragStartListener(
                          index: index,
                          child: card,
                        )
                      : card;
                  return Column(
                    key: ValueKey('subscription-section-${subscription.id}'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header,
                      if (expanded)
                        _NestedGroupChildren(
                          child: Column(
                            children: [
                              for (var profileIndex = 0;
                                  profileIndex < section.profiles.length;
                                  profileIndex++)
                                buildProfileCard(
                                  section.profiles[profileIndex],
                                  profileIndex,
                                  section,
                                  allowReorder: false,
                                  nested: true,
                                ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 4),
                    ],
                  );
                },
                onReorderItem: (oldIndex, newIndex) {
                  if (newIndex == oldIndex) return;
                  unawaited(
                    profiles.reorderSubscriptions(oldIndex, newIndex),
                  );
                },
                proxyDecorator: (child, index, animation) => AnimatedBuilder(
                  animation: animation,
                  child: child,
                  builder: (context, child) {
                    final scale = Tween<double>(begin: 1, end: 1.012).evaluate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                        reverseCurve: Curves.easeInCubic,
                      ),
                    );
                    return Transform.scale(scale: scale, child: child);
                  },
                ),
              ),
            ),
          ],
          if (manualProfileCount > 0) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              sliver: SliverToBoxAdapter(
                child: _SectionTitle(
                  title: 'Серверы',
                  count: manualProfileCount,
                  selectedCount:
                      _selectingServers ? manualSelectedCount : null,
                ),
              ),
            ),
            if (groupedManualView)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverReorderableList(
                  itemCount: manualSections.length,
                  itemBuilder: (context, groupIndex) {
                    final section = manualSections[groupIndex];
                    final selectedCount = _selectedCountForSection(section);
                    final fullySelected = selectedCount == section.profiles.length;
                    final expanded = _sectionExpanded(section, activeTarget?.id);
                    final groupHeader = buildManualGroupHeader(section);
                    final draggableHeader = _selectingServers &&
                            fullySelected &&
                            manualSections.length > 1
                        ? ReorderableDelayedDragStartListener(
                            index: groupIndex,
                            child: groupHeader,
                          )
                        : groupHeader;
                    return Column(
                      key: ValueKey('manual-section-${section.key}'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        draggableHeader,
                        if (expanded)
                          _NestedGroupChildren(
                            child: ReorderableListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              buildDefaultDragHandles: false,
                              itemCount: section.profiles.length,
                              itemBuilder: (context, index) => buildProfileCard(
                                section.profiles[index],
                                index,
                                section,
                                nested: true,
                              ),
                              onReorderStart: (index) {
                                if (!mounted ||
                                    index < 0 ||
                                    index >= section.profiles.length) {
                                  return;
                                }
                                setState(
                                  () => _draggingProfileId =
                                      section.profiles[index].id,
                                );
                              },
                              onReorderEnd: (_) {
                                if (mounted && _draggingProfileId != null) {
                                  setState(() => _draggingProfileId = null);
                                }
                              },
                              proxyDecorator: (child, index, animation) =>
                                  AnimatedBuilder(
                                animation: animation,
                                child: child,
                                builder: (context, child) {
                                  final scale = Tween<double>(
                                    begin: 1,
                                    end: 1.015,
                                  ).evaluate(
                                    CurvedAnimation(
                                      parent: animation,
                                      curve: Curves.easeOutCubic,
                                      reverseCurve: Curves.easeInCubic,
                                    ),
                                  );
                                  return Transform.scale(
                                    scale: scale,
                                    child: child,
                                  );
                                },
                              ),
                              onReorderItem: (oldIndex, newIndex) {
                                if (newIndex == oldIndex) return;
                                unawaited(
                                  profiles.reorderProfilesInScope(
                                    section.profiles
                                        .map((profile) => profile.id)
                                        .toList(growable: false),
                                    oldIndex,
                                    newIndex,
                                  ),
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 4),
                      ],
                    );
                  },
                  onReorderItem: (oldIndex, newIndex) {
                    if (newIndex == oldIndex) return;
                    unawaited(
                      profiles.reorderProfileGroups(
                        manualSections.map((item) => item.key).toList(),
                        oldIndex,
                        newIndex,
                      ),
                    );
                  },
                  proxyDecorator: (child, index, animation) => AnimatedBuilder(
                    animation: animation,
                    child: child,
                    builder: (context, child) {
                      final scale = Tween<double>(begin: 1, end: 1.012).evaluate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                          reverseCurve: Curves.easeInCubic,
                        ),
                      );
                      return Transform.scale(scale: scale, child: child);
                    },
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverReorderableList(
                  itemCount: manualSections.single.profiles.length,
                  itemBuilder: (context, index) => buildProfileCard(
                    manualSections.single.profiles[index],
                    index,
                    manualSections.single,
                  ),
                  onReorderStart: (index) {
                    if (!mounted ||
                        index < 0 ||
                        index >= manualSections.single.profiles.length) {
                      return;
                    }
                    setState(
                      () => _draggingProfileId =
                          manualSections.single.profiles[index].id,
                    );
                  },
                  onReorderEnd: (_) {
                    if (mounted && _draggingProfileId != null) {
                      setState(() => _draggingProfileId = null);
                    }
                  },
                  proxyDecorator: (child, index, animation) => AnimatedBuilder(
                    animation: animation,
                    child: child,
                    builder: (context, child) {
                      final scale = Tween<double>(begin: 1, end: 1.015).evaluate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                          reverseCurve: Curves.easeInCubic,
                        ),
                      );
                      return Transform.scale(scale: scale, child: child);
                    },
                  ),
                  onReorderItem: (oldIndex, newIndex) {
                    unawaited(
                      profiles.reorderProfilesInScope(
                        manualSections.single.profiles
                            .map((profile) => profile.id)
                            .toList(growable: false),
                        oldIndex,
                        newIndex,
                      ),
                    );
                  },
                ),
              ),
          ],
          if (profiles.balancers.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                          members: profiles.effectiveBalancerMembers(balancer),
                          selected: activeTarget?.id == balancer.id,
                          latencyMs: profiles.targetById(balancer.id)?.latencyMs,
                          onRefreshPing:
                              tunnel.canRefreshTargetLatency(balancer.id)
                                  ? () => tunnel.refreshTargetLatency(balancer.id)
                                  : null,
                          onSelect: () => _selectFromProfiles(balancer.id),
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
                ),
              ),
            ),
          if (currentProfiles.isEmpty &&
              profiles.subscriptions.isEmpty &&
              profiles.balancers.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              sliver: SliverToBoxAdapter(
                child: _EmptyProfiles(
                  onImport: () => widget.owner._showProfileMenu(context),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ];

        return CustomScrollView(slivers: slivers);
      },
    );
  }
}

class _ProfilesHeader extends StatelessWidget {
  const _ProfilesHeader({
    required this.refreshingLatency,
    required this.canRefreshLatency,
    required this.selectionMode,
    required this.selectionScope,
    required this.allSelected,
    required this.onOpenProfileMenu,
    required this.onRefreshLatency,
    required this.onCloseSelection,
    required this.onSelectAll,
    required this.onPingSelected,
    required this.onExportSelected,
    required this.onDeleteSelected,
    required this.onGroupSelected,
    required this.canGroupSelected,
  });

  final bool refreshingLatency;
  final bool canRefreshLatency;
  final bool selectionMode;
  final _ProfileSelectionScope? selectionScope;
  final bool allSelected;
  final VoidCallback onOpenProfileMenu;
  final Future<void> Function() onRefreshLatency;
  final VoidCallback onCloseSelection;
  final VoidCallback onSelectAll;
  final Future<void> Function() onPingSelected;
  final VoidCallback onExportSelected;
  final VoidCallback onDeleteSelected;
  final VoidCallback onGroupSelected;
  final bool canGroupSelected;

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

    final actions = selectionMode
        ? _AdaptiveSelectionActions(
            scope: selectionScope!,
            refreshingLatency: refreshingLatency,
            allSelected: allSelected,
            canGroupSelected: canGroupSelected,
            onPingSelected: onPingSelected,
            onExportSelected: onExportSelected,
            onGroupSelected: onGroupSelected,
            onDeleteSelected: onDeleteSelected,
            onSelectAll: onSelectAll,
            onCloseSelection: onCloseSelection,
          )
        : Wrap(
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
                onPressed: refreshingLatency || !canRefreshLatency
                    ? null
                    : onRefreshLatency,
                icon: const Icon(Icons.network_ping_rounded),
                label: const Text('Проверить пинг'),
              ),
            ],
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final rowBreakpoint = selectionMode ? 920.0 : 700.0;
        if (constraints.maxWidth >= rowBreakpoint) {
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

class _AdaptiveSelectionActions extends StatelessWidget {
  const _AdaptiveSelectionActions({
    required this.scope,
    required this.refreshingLatency,
    required this.allSelected,
    required this.canGroupSelected,
    required this.onPingSelected,
    required this.onExportSelected,
    required this.onGroupSelected,
    required this.onDeleteSelected,
    required this.onSelectAll,
    required this.onCloseSelection,
  });

  final _ProfileSelectionScope scope;
  final bool refreshingLatency;
  final bool allSelected;
  final bool canGroupSelected;
  final Future<void> Function() onPingSelected;
  final VoidCallback onExportSelected;
  final VoidCallback onGroupSelected;
  final VoidCallback onDeleteSelected;
  final VoidCallback onSelectAll;
  final VoidCallback onCloseSelection;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final finite = width.isFinite;
        final serverScope = scope == _ProfileSelectionScope.servers;
        // Keep every action on one line whenever possible. Labels disappear
        // from the end first: Export, then Ping. Icon-only actions retain the
        // same pill height/style as the normal profile actions.
        final compactExport = finite && width < (serverScope ? 500 : 315);
        final compactPing = finite && width < 410;

        final children = <Widget>[];
        if (serverScope) {
          children.add(
            compactPing
                ? _HeaderIconActionButton(
                    tooltip: 'Пинг',
                    onPressed: refreshingLatency ? null : () => onPingSelected(),
                    icon: Icons.network_ping_rounded,
                  )
                : OutlinedButton.icon(
                    onPressed: refreshingLatency ? null : () => onPingSelected(),
                    icon: const Icon(Icons.network_ping_rounded),
                    label: const Text('Пинг'),
                  ),
          );
        }
        children.add(
          compactExport
              ? _HeaderIconActionButton(
                  tooltip: 'Экспорт',
                  onPressed: onExportSelected,
                  icon: Icons.ios_share_rounded,
                )
              : OutlinedButton.icon(
                  onPressed: onExportSelected,
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Экспорт'),
                ),
        );
        if (serverScope) {
          children.add(
            _HeaderIconActionButton(
              tooltip: 'Группа',
              onPressed: canGroupSelected ? onGroupSelected : null,
              icon: Icons.folder_outlined,
            ),
          );
        }
        children.addAll([
          _HeaderIconActionButton(
            tooltip: scope == _ProfileSelectionScope.subscriptions
                ? 'Удалить подписки'
                : 'Удалить',
            onPressed: onDeleteSelected,
            color: OrexColors.danger,
            icon: Icons.delete_outline_rounded,
          ),
          _HeaderIconActionButton(
            tooltip: 'Выбрать все',
            onPressed: allSelected ? null : onSelectAll,
            icon: Icons.select_all_rounded,
          ),
          _HeaderIconActionButton(
            tooltip: 'Готово',
            onPressed: onCloseSelection,
            icon: Icons.check_rounded,
          ),
        ]);
        final minimumOneRowWidth = serverScope ? 362.0 : 238.0;
        if (!finite || width >= minimumOneRowWidth) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0) const SizedBox(width: 10),
                children[index],
              ],
            ],
          );
        }
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: children,
        );
      },
    );
  }
}

class _HeaderIconActionButton extends StatelessWidget {
  const _HeaderIconActionButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.color,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: color,
          shape: const StadiumBorder(),
        ),
        child: Icon(icon),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.count,
    this.selectedCount,
  });

  final String title;
  final int count;
  final int? selectedCount;

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
        if (selectedCount case final selected?) ...[
          const SizedBox(width: 14),
          Text(
            'ВЫДЕЛЕНО',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: OrexColors.copper,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                ),
          ),
          const SizedBox(width: 8),
          Text('$selected', style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}

class _NestedGroupChildren extends StatelessWidget {
  const _NestedGroupChildren({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 10),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: OrexColors.copper.withValues(alpha: 0.34),
            width: 2,
          ),
        ),
      ),
      child: child,
    );
  }
}

class _NestedGroupChild extends StatelessWidget {
  const _NestedGroupChild({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _NestedGroupChildren(child: child);
  }
}

class _ProfileGroupHeader extends StatelessWidget {
  const _ProfileGroupHeader({
    required this.title,
    required this.count,
    required this.selectedCount,
    required this.selectionMode,
    required this.expanded,
    required this.onToggle,
    required this.onExpandToggle,
    required this.onLongPress,
    this.onRename,
    this.onDelete,
  });

  final String title;
  final int count;
  final int selectedCount;
  final bool selectionMode;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onExpandToggle;
  final VoidCallback? onLongPress;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final partiallySelected = selectedCount > 0 && selectedCount < count;
    final fullySelected = count > 0 && selectedCount == count;
    return Padding(
      padding: EdgeInsets.only(bottom: expanded ? 4 : 10),
      child: GlassPanel(
        borderRadius: 18,
        blur: 14,
        tint: selectedCount > 0 ? OrexColors.copper : null,
        opacity: selectedCount > 0 ? 0.24 : 0.34,
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          onTap: onToggle,
          onLongPress: onLongPress,
          leading: const Icon(
            Icons.folder_outlined,
            color: OrexColors.copper,
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text('$count серверов'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selectionMode)
                Checkbox(
                  tristate: true,
                  value: partiallySelected ? null : fullySelected,
                  onChanged: (_) => onToggle(),
                )
              else if (onRename != null || onDelete != null)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'rename') onRename?.call();
                    if (value == 'delete') onDelete?.call();
                  },
                  itemBuilder: (context) => [
                    if (onRename != null)
                      const PopupMenuItem(
                        value: 'rename',
                        child: Text('Переименовать'),
                      ),
                    if (onDelete != null)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Расформировать группу'),
                      ),
                  ],
                ),
              IconButton(
                tooltip: expanded ? 'Свернуть' : 'Развернуть',
                onPressed: onExpandToggle,
                icon: Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                ),
              ),
            ],
          ),
        ),
      ),
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
            'Импортируйте ссылку, подписку или JSON Xray с одним или несколькими профилями.',
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

class _ImportSubscriptionDialog extends StatefulWidget {
  const _ImportSubscriptionDialog({required this.profiles});

  final ProfilesController profiles;

  @override
  State<_ImportSubscriptionDialog> createState() =>
      _ImportSubscriptionDialogState();
}

class _ImportSubscriptionDialogState extends State<_ImportSubscriptionDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Вставь URL подписки');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.profiles.importSubscription(value);
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message.toString());
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось добавить подписку: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Добавить подписку'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Поддерживаются обычные HTTP/HTTPS подписки: '
              'список ссылок, Base64-список и JSON Xray.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              enabled: !_loading,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'URL подписки',
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Добавить'),
        ),
      ],
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({
    required this.subscription,
    required this.refreshing,
    required this.expanded,
    required this.selectedCount,
    required this.selectionMode,
    required this.onToggle,
    required this.onExpandToggle,
    required this.onLongPress,
    required this.onRefresh,
    required this.onDelete,
    required this.onCopyUrl,
    required this.onExportServers,
    required this.onOpenSupport,
    required this.onOpenWebPage,
  });

  final ProxySubscription subscription;
  final bool refreshing;
  final bool expanded;
  final int selectedCount;
  final bool selectionMode;
  final VoidCallback? onToggle;
  final VoidCallback? onExpandToggle;
  final VoidCallback? onLongPress;
  final VoidCallback onRefresh;
  final VoidCallback onDelete;
  final VoidCallback onCopyUrl;
  final VoidCallback onExportServers;
  final VoidCallback? onOpenSupport;
  final VoidCallback? onOpenWebPage;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(subscription.url);
    final host = uri?.host ?? subscription.url;
    final count = subscription.profileIds.length;
    final partiallySelected = selectedCount > 0 && selectedCount < count;
    final fullySelected = count > 0 && selectedCount == count;
    final userInfo = subscription.parsedUserInfo;
    final rawNotices = subscription.notices.take(3).toList(growable: false);
    final summaryLine = [
      '$count серверов',
      host,
      if (subscription.lastUpdatedEpochMs case final updated?)
        _relativeSubscriptionUpdate(updated),
    ].join(' · ');
    final rawInfoLine = rawNotices.join(' · ');
    final hasMetadata = userInfo != null ||
        subscription.announce.isNotEmpty ||
        onOpenSupport != null ||
        onOpenWebPage != null;

    return Padding(
      padding: EdgeInsets.only(bottom: expanded ? 4 : 10),
      child: GlassPanel(
        borderRadius: 18,
        blur: 16,
        tint: selectedCount > 0 ? OrexColors.copper : null,
        opacity: selectedCount > 0 ? 0.24 : 0.42,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              onTap: onToggle,
              onLongPress: onLongPress,
              leading: const Icon(
                Icons.cloud_sync_outlined,
                color: OrexColors.copper,
              ),
              title: Text(
                subscription.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                rawInfoLine.isEmpty
                    ? summaryLine
                    : '$summaryLine\n$rawInfoLine',
                maxLines: rawInfoLine.isEmpty ? 2 : 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selectionMode)
                    Checkbox(
                      tristate: true,
                      value: partiallySelected ? null : fullySelected,
                      onChanged: onToggle == null ? null : (_) => onToggle!(),
                    )
                  else ...[
                    IconButton(
                      tooltip: 'Обновить подписку',
                      onPressed: refreshing ? null : onRefresh,
                      icon: refreshing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Действия подписки',
                      enabled: !refreshing,
                      onSelected: (value) {
                        if (value == 'copy-url') onCopyUrl();
                        if (value == 'export-json') onExportServers();
                        if (value == 'delete') onDelete();
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'copy-url',
                          child: Text('Скопировать исходную ссылку'),
                        ),
                        PopupMenuItem(
                          value: 'export-json',
                          child: Text('Экспорт серверов JSON Xray'),
                        ),
                        PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Удалить подписку'),
                        ),
                      ],
                    ),
                  ],
                  IconButton(
                    tooltip: expanded ? 'Свернуть' : 'Развернуть',
                    onPressed: onExpandToggle,
                    icon: Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                    ),
                  ),
                ],
              ),
            ),
            if (hasMetadata)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: _SubscriptionMetadataPanel(
                  subscription: subscription,
                  userInfo: userInfo,
                  onOpenSupport: onOpenSupport,
                  onOpenWebPage: onOpenWebPage,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SubscriptionMetadataPanel extends StatelessWidget {
  const _SubscriptionMetadataPanel({
    required this.subscription,
    required this.userInfo,
    required this.onOpenSupport,
    required this.onOpenWebPage,
  });

  final ProxySubscription subscription;
  final SubscriptionUserInfo? userInfo;
  final VoidCallback? onOpenSupport;
  final VoidCallback? onOpenWebPage;

  @override
  Widget build(BuildContext context) {
    final info = userInfo;
    final total = info?.totalBytes;
    final expiry = info?.expiresAt;
    final usageFraction = info?.usageFraction;
    final remaining = info?.remainingBytes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (subscription.announce.isNotEmpty) ...[
          Text(
            subscription.announce,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: OrexColors.copper,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
        ],
        if (info != null && total != null) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Использовано ${_formatSubscriptionBytes(info.usedBytes)} / '
                  '${_formatSubscriptionBytes(total)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (remaining != null)
                Text(
                  'Осталось ${_formatSubscriptionBytes(remaining)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: OrexColors.copper,
                        fontWeight: FontWeight.w600,
                      ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: usageFraction,
              backgroundColor:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.10),
              color: OrexColors.copper,
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (expiry != null) ...[
          Text(
            _formatSubscriptionExpiry(expiry),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
        ],
        if (onOpenWebPage != null || onOpenSupport != null) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onOpenWebPage != null)
                OutlinedButton.icon(
                  onPressed: onOpenWebPage,
                  icon: const Icon(Icons.account_circle_outlined, size: 18),
                  label: const Text('Кабинет'),
                ),
              if (onOpenSupport != null)
                OutlinedButton.icon(
                  onPressed: onOpenSupport,
                  icon: const Icon(Icons.support_agent_rounded, size: 18),
                  label: const Text('Поддержка'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

String _formatSubscriptionBytes(int bytes) {
  const units = <String>['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  final digits = unit <= 1 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

String _formatSubscriptionExpiry(DateTime expiry) {
  final now = DateTime.now();
  final difference = expiry.difference(now);
  if (difference <= Duration.zero) return 'Срок действия истёк';
  final days = (difference.inSeconds / Duration.secondsPerDay).ceil();
  return 'До ${_formatSubscriptionDate(expiry)} · ${_daysLabel(days)}';
}

String _formatSubscriptionDate(DateTime date) {
  const months = <String>[
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  return '${date.day} ${months[date.month - 1]}';
}

String _daysLabel(int days) {
  final mod100 = days % 100;
  final mod10 = days % 10;
  if (mod100 >= 11 && mod100 <= 14) return '$days дней';
  if (mod10 == 1) return '$days день';
  if (mod10 >= 2 && mod10 <= 4) return '$days дня';
  return '$days дней';
}

String _relativeSubscriptionUpdate(int epochMs) {
  final elapsed = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(epochMs),
  );
  if (elapsed.isNegative || elapsed.inMinutes < 1) return 'серверы обновлены сейчас';
  if (elapsed.inHours < 1) return 'серверы обновлены ${elapsed.inMinutes} мин назад';
  if (elapsed.inDays < 1) return 'серверы обновлены ${elapsed.inHours} ч назад';
  return 'серверы обновлены ${_daysLabel(elapsed.inDays)} назад';
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.identity,
    required this.selected,
    required this.multiSelected,
    required this.selectionMode,
    required this.dragging,
    required this.onSelect,
    required this.onLongPress,
    required this.latencyMs,
    required this.onRefreshPing,
    required this.onEdit,
    required this.onExport,
    required this.onDelete,
    this.onGroup,
  });

  final TunnelProfile profile;
  final EgressIdentity? identity;
  final bool selected;
  final bool multiSelected;
  final bool selectionMode;
  final bool dragging;
  final VoidCallback onSelect;
  final VoidCallback? onLongPress;
  final int? latencyMs;
  final VoidCallback? onRefreshPing;
  final VoidCallback onEdit;
  final VoidCallback onExport;
  final VoidCallback onDelete;
  final VoidCallback? onGroup;

  @override
  Widget build(BuildContext context) {
    final card = RepaintBoundary(
      child: GlassPanel(
        borderRadius: 22,
        blur: dragging ? 0 : 18,
        tint: multiSelected ? OrexColors.copper : null,
        opacity: dragging
            ? 0.88
            : multiSelected
                ? 0.24
                : 0.50,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          onTap: onSelect,
          onLongPress: onLongPress,
          leading: EgressAvatar(
            identity: identity,
            selected: selected,
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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
          trailing: selectionMode
              ? Checkbox(
                  value: multiSelected,
                  onChanged: (_) => onSelect(),
                )
              : PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') onEdit();
                        if (value == 'ping') onRefreshPing?.call();
                        if (value == 'export') onExport();
                        if (value == 'group') onGroup?.call();
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
                        if (onGroup != null)
                          const PopupMenuItem(
                            value: 'group',
                            child: Text('Группа…'),
                          ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Удалить'),
                        ),
                      ],
                    ),
        ),
      ),
    );
    return card;
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
          latency == null ? '- мс' : '$latency мс',
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
      opacity: 0.50,
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
              'из нескольких конфигов и HTTP/HTTPS ссылка с JSON. '
              'Для обновляемого списка серверов используйте «Подписка».',
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
    required this.memberGroupKeys,
    required this.strategy,
    required this.probeIntervalSeconds,
    required this.fallbackTarget,
  });

  final String name;
  final List<String> memberIds;
  final List<String> memberGroupKeys;
  final BalancerStrategy strategy;
  final int probeIntervalSeconds;
  final String? fallbackTarget;
}

class _BalancerDialog extends StatefulWidget {
  const _BalancerDialog({
    required this.profiles,
    required this.groups,
    required this.probeUrl,
    this.existing,
  });

  final List<TunnelProfile> profiles;
  final List<ProfileGroupInfo> groups;
  final String probeUrl;
  final BalancerProfile? existing;

  @override
  State<_BalancerDialog> createState() => _BalancerDialogState();
}

class _BalancerDialogState extends State<_BalancerDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _interval = TextEditingController(
    text: '${widget.existing?.probeIntervalSeconds ?? 30}',
  );
  late final Set<String> _members =
      widget.existing?.memberIds.toSet() ?? <String>{};
  late final Set<String> _memberGroups =
      widget.existing?.memberGroupKeys.toSet() ?? <String>{};
  late BalancerStrategy _strategy =
      widget.existing?.strategy ?? BalancerStrategy.random;
  final Set<String> _expandedGroups = <String>{};
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
    for (final group in widget.groups) {
      if (_memberGroups.contains(group.key) ||
          group.profileIds.any(_members.contains)) {
        _expandedGroups.add(group.key);
      }
    }
    if (_expandedGroups.isEmpty && widget.groups.isNotEmpty) {
      _expandedGroups.add(widget.groups.first.key);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _interval.dispose();
    super.dispose();
  }

  List<ProfileGroupInfo> get _selectableGroups => widget.groups
      .where((group) => group.isManualGroup || group.isSubscription)
      .toList(growable: false);

  bool _canSelectWholeGroup(ProfileGroupInfo group) =>
      group.isManualGroup || group.isSubscription;

  Set<String> get _groupMemberIds => {
        for (final group in _selectableGroups)
          if (_memberGroups.contains(group.key)) ...group.profileIds,
      };

  TunnelProfile? _profileForId(String id) {
    for (final profile in widget.profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  Set<String> get _effectiveMemberIds => <String>{
        ..._members,
        ..._groupMemberIds,
      };

  void _submit() {
    final interval = int.tryParse(_interval.text.trim()) ?? 30;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Укажи имя балансировщика');
      return;
    }
    if (_effectiveMemberIds.isEmpty) {
      setState(() => _error = 'Выбери хотя бы один сервер или папку');
      return;
    }
    Navigator.pop(
      context,
      _BalancerDraft(
        name: _name.text.trim(),
        memberIds: _members.toList(growable: false),
        memberGroupKeys: _memberGroups.toList(growable: false),
        strategy: _strategy,
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
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Адрес проверки задержки',
                  ),
                  child: Text(
                    widget.probeUrl,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Используется общий адрес из «Сеть → Проверка задержки».',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _interval,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Интервал проверки, секунд'),
                ),
              ],
              const SizedBox(height: 16),
              Text('Маршруты', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Можно выбрать папку целиком или раскрыть её и отметить '
                'отдельные серверы. Выбранная папка остаётся динамической: '
                'новые серверы в ней попадут в балансировщик автоматически.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final group in widget.groups) ...[
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    group.isSubscription
                        ? Icons.cloud_sync_outlined
                        : group.isManualGroup
                            ? Icons.folder_outlined
                            : Icons.folder_open_outlined,
                    color: OrexColors.copper,
                  ),
                  title: Text(
                    group.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('${group.profileIds.length} серверов'),
                  onTap: () => setState(() {
                    if (!_expandedGroups.add(group.key)) {
                      _expandedGroups.remove(group.key);
                    }
                  }),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_canSelectWholeGroup(group))
                        Checkbox(
                          value: _memberGroups.contains(group.key),
                          onChanged: (value) {
                            setState(() {
                              if (value == true) {
                                _memberGroups.add(group.key);
                                _members.removeAll(group.profileIds);
                                _expandedGroups.add(group.key);
                              } else {
                                _memberGroups.remove(group.key);
                              }
                            });
                          },
                        ),
                      Icon(
                        _expandedGroups.contains(group.key)
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                      ),
                    ],
                  ),
                ),
                if (_expandedGroups.contains(group.key))
                  for (final id in group.profileIds)
                    if (_profileForId(id) case final profile?)
                      Builder(
                        builder: (context) {
                          final inherited = _memberGroups.contains(group.key);
                          return _NestedGroupChild(
                            child: CheckboxListTile(
                              dense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              value: inherited || _members.contains(profile.id),
                              onChanged: inherited
                                  ? null
                                  : (value) {
                                      setState(() {
                                        if (value == true) {
                                          _members.add(profile.id);
                                        } else {
                                          _members.remove(profile.id);
                                        }
                                      });
                                    },
                              title: Text(
                                profile.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                inherited
                                    ? 'Включён через группу · ${profile.endpoint}'
                                    : '${profile.endpoint} · '
                                        '${profile.latencyMs == null ? '- мс' : '${profile.latencyMs} мс'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );
                        },
                      ),
                if (group != widget.groups.last) const Divider(height: 1),
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
}
