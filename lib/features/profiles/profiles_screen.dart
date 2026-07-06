import 'package:flutter/material.dart';

import '../../core/profiles/profiles_controller.dart';
import '../../core/profiles/vless_link_parser.dart';
import '../../core/tunnel/tunnel_models.dart';
import '../../shared/theme/glass.dart';
import '../../shared/theme/orex_theme.dart';
import '../../shared/widgets/squirrel_mascot.dart';

class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key, required this.profiles});

  final ProfilesController profiles;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: profiles,
      builder: (context, _) {
        final selected = profiles.selectedTarget;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 360,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Профили', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text(
                        'Серверы, ping и балансировщики Xray',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: profiles.profiles.length < 2
                      ? null
                      : () => _showBalancerDialog(context),
                  icon: const Icon(Icons.hub_rounded),
                  label: const Text('Балансировщик'),
                ),
                OutlinedButton.icon(
                  onPressed: profiles.refreshingLatency || profiles.profiles.isEmpty
                      ? null
                      : profiles.refreshAllLatencies,
                  icon: profiles.refreshingLatency
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_ping_rounded),
                  label: const Text('Проверить ping'),
                ),
                FilledButton.icon(
                  onPressed: () => _showImportDialog(context),
                  icon: const Icon(Icons.add_link_rounded),
                  label: const Text('Импорт'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (profiles.profiles.isEmpty)
              _EmptyProfiles(onImport: () => _showImportDialog(context))
            else ...[
              _SectionTitle(
                title: 'Серверы',
                count: profiles.profiles.length,
              ),
              const SizedBox(height: 10),
              for (final profile in profiles.profiles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ProfileCard(
                    profile: profile,
                    selected: selected?.id == profile.id,
                    onSelect: () => profiles.select(profile.id),
                    onRefreshPing: () => profiles.refreshLatency(profile.id),
                    onEdit: () => _showEditProfileDialog(context, profile),
                    onDelete: () => _deleteTarget(context, profile.id, profile.name),
                  ),
                ),
              if (profiles.balancers.isNotEmpty) ...[
                const SizedBox(height: 10),
                _SectionTitle(
                  title: 'Балансировщики',
                  count: profiles.balancers.length,
                ),
                const SizedBox(height: 10),
                for (final balancer in profiles.balancers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _BalancerCard(
                      balancer: balancer,
                      members: [
                        for (final id in balancer.memberIds)
                          ...profiles.profiles.where((item) => item.id == id),
                      ],
                      selected: selected?.id == balancer.id,
                      onSelect: () => profiles.select(balancer.id),
                      onEdit: () => _showBalancerDialog(context, existing: balancer),
                      onDelete: () => _deleteTarget(context, balancer.id, balancer.name),
                    ),
                  ),
              ],
            ],
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title.toUpperCase(), style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
          Text('Белочка ждёт сервер', style: Theme.of(context).textTheme.titleLarge),
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
    required this.onRefreshPing,
    required this.onEdit,
    required this.onDelete,
  });

  final TunnelProfile profile;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onRefreshPing;
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
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: selected ? OrexColors.copperGradient : null,
            color: selected ? null : OrexColors.copper.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(
            selected ? Icons.check_rounded : Icons.public_rounded,
            color: selected ? OrexColors.cream : OrexColors.copper,
          ),
        ),
        title: Row(
          children: [
            Expanded(child: Text(profile.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
            _PingBadge(latencyMs: profile.latencyMs, onTap: onRefreshPing),
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
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') onEdit();
            if (value == 'ping') onRefreshPing();
            if (value == 'delete') onDelete();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'edit', child: Text('Редактировать')),
            PopupMenuItem(value: 'ping', child: Text('Проверить ping')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'delete', child: Text('Удалить')),
          ],
        ),
      ),
    );
  }
}

class _PingBadge extends StatelessWidget {
  const _PingBadge({required this.latencyMs, required this.onTap});

  final int? latencyMs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final latency = latencyMs;
    final color = latency == null
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : latency < 100
            ? OrexColors.online
            : latency < 250
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
          latency == null ? 'ping —' : '$latency ms',
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _BalancerCard extends StatelessWidget {
  const _BalancerCard({
    required this.balancer,
    required this.members,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  final BalancerProfile balancer;
  final List<TunnelProfile> members;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final latencies = members.map((item) => item.latencyMs).whereType<int>().toList()..sort();
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
            color: selected ? null : OrexColors.copper.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(
            Icons.hub_rounded,
            color: selected ? OrexColors.cream : OrexColors.copper,
          ),
        ),
        title: Row(
          children: [
            Expanded(child: Text(balancer.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
            _PingBadge(
              latencyMs: latencies.isEmpty ? null : latencies.first,
              onTap: onEdit,
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
      if (mounted) Navigator.of(context).pop(profile);
    } on VlessLinkFormatException catch (error) {
      if (mounted) setState(() { _importing = false; _error = error.message; });
    } catch (error) {
      if (mounted) setState(() { _importing = false; _error = 'Не удалось импортировать: $error'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Импорт VLESS'),
      content: SizedBox(
        width: 560,
        child: TextField(
          controller: _controller,
          minLines: 4,
          maxLines: 8,
          autofocus: true,
          enabled: !_importing,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            hintText: 'vless://uuid@server:443?...',
            errorText: _error,
          ),
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

class _EditProfileDialog extends StatefulWidget {
  const _EditProfileDialog({required this.profile});

  final TunnelProfile profile;

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.profile.name);
  late final TextEditingController _address = TextEditingController(text: widget.profile.address);
  late final TextEditingController _port = TextEditingController(text: '${widget.profile.port}');
  late final TextEditingController _uuid = TextEditingController(text: widget.profile.userId);
  late final TextEditingController _serverName = TextEditingController(text: widget.profile.serverName);
  late final TextEditingController _fingerprint = TextEditingController(text: widget.profile.fingerprint);
  late final TextEditingController _password = TextEditingController(text: widget.profile.realityPassword);
  late final TextEditingController _shortId = TextEditingController(text: widget.profile.shortId);
  late final TextEditingController _path = TextEditingController(text: widget.profile.path);
  late final TextEditingController _host = TextEditingController(text: widget.profile.host);
  late final TextEditingController _serviceName = TextEditingController(text: widget.profile.serviceName);
  late final TextEditingController _flow = TextEditingController(text: widget.profile.flow);
  late String _security = widget.profile.security;
  late String _transport = widget.profile.transport;
  bool _allowInsecure = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _allowInsecure = widget.profile.allowInsecure;
  }

  @override
  void dispose() {
    for (final controller in [
      _name, _address, _port, _uuid, _serverName, _fingerprint,
      _password, _shortId, _path, _host, _serviceName, _flow,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final port = int.tryParse(_port.text.trim());
    if (_name.text.trim().isEmpty || _address.text.trim().isEmpty || _uuid.text.trim().isEmpty) {
      setState(() => _error = 'Имя, адрес и UUID обязательны');
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
        flow: _flow.text.trim(),
        security: _security,
        transport: _transport,
        serverName: _serverName.text.trim(),
        fingerprint: _fingerprint.text.trim().isEmpty ? 'chrome' : _fingerprint.text.trim(),
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
      title: const Text('Редактировать профиль'),
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
              Row(children: [
                Expanded(flex: 3, child: _field(_address, 'Адрес')),
                const SizedBox(width: 10),
                Expanded(child: _field(_port, 'Порт', number: true)),
              ]),
              _field(_uuid, 'UUID'),
              _field(_flow, 'Flow (например xtls-rprx-vision)'),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _security,
                    decoration: const InputDecoration(labelText: 'Security'),
                    items: const [
                      DropdownMenuItem(value: 'none', child: Text('None')),
                      DropdownMenuItem(value: 'tls', child: Text('TLS')),
                      DropdownMenuItem(value: 'reality', child: Text('REALITY')),
                    ],
                    onChanged: (value) => setState(() => _security = value ?? 'none'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _transport,
                    decoration: const InputDecoration(labelText: 'Transport'),
                    items: const [
                      DropdownMenuItem(value: 'raw', child: Text('RAW / TCP')),
                      DropdownMenuItem(value: 'websocket', child: Text('WebSocket')),
                      DropdownMenuItem(value: 'grpc', child: Text('gRPC')),
                      DropdownMenuItem(value: 'xhttp', child: Text('XHTTP')),
                      DropdownMenuItem(value: 'httpupgrade', child: Text('HTTPUpgrade')),
                    ],
                    onChanged: (value) => setState(() => _transport = value ?? 'raw'),
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
                  onChanged: (value) => setState(() => _allowInsecure = value),
                ),
              if (_transport == 'websocket' || _transport == 'xhttp' || _transport == 'httpupgrade') ...[
                _field(_path, 'Path'),
                _field(_host, 'Host'),
              ],
              if (_transport == 'grpc') _field(_serviceName, 'gRPC service name'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: _submit, child: const Text('Сохранить')),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label, {bool number = false}) {
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
  });

  final String name;
  final List<String> memberIds;
  final BalancerStrategy strategy;
  final String probeUrl;
  final int probeIntervalSeconds;
}

class _BalancerDialog extends StatefulWidget {
  const _BalancerDialog({required this.profiles, this.existing});

  final List<TunnelProfile> profiles;
  final BalancerProfile? existing;

  @override
  State<_BalancerDialog> createState() => _BalancerDialogState();
}

class _BalancerDialogState extends State<_BalancerDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _probeUrl = TextEditingController(
    text: widget.existing?.probeUrl ?? 'https://www.gstatic.com/generate_204',
  );
  late final TextEditingController _interval = TextEditingController(
    text: '${widget.existing?.probeIntervalSeconds ?? 30}',
  );
  late final Set<String> _members = widget.existing?.memberIds.toSet() ?? <String>{};
  late BalancerStrategy _strategy = widget.existing?.strategy ?? BalancerStrategy.random;
  String? _error;

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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Новый балансировщик' : 'Редактировать балансировщик'),
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
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Имя')),
              const SizedBox(height: 12),
              DropdownButtonFormField<BalancerStrategy>(
                value: _strategy,
                decoration: const InputDecoration(labelText: 'Стратегия'),
                items: [
                  for (final strategy in BalancerStrategy.values)
                    DropdownMenuItem(value: strategy, child: Text(strategy.title)),
                ],
                onChanged: (value) => setState(() => _strategy = value ?? BalancerStrategy.random),
              ),
              if (_strategy == BalancerStrategy.leastPing) ...[
                const SizedBox(height: 12),
                TextField(controller: _probeUrl, decoration: const InputDecoration(labelText: 'URL проверки')),
                const SizedBox(height: 12),
                TextField(
                  controller: _interval,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Интервал проверки, секунд'),
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
                  subtitle: Text('${profile.endpoint} · ${profile.latencyMs == null ? 'ping —' : '${profile.latencyMs} ms'}'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: _submit, child: const Text('Сохранить')),
      ],
    );
  }
}
