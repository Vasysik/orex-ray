import 'package:flutter/material.dart';

import '../../shared/theme/glass.dart';
import '../../shared/theme/orex_theme.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({
    super.key,
    required this.onOpenNetwork,
    required this.onOpenAppearance,
    required this.onOpenAbout,
  });

  final VoidCallback onOpenNetwork;
  final VoidCallback onOpenAppearance;
  final VoidCallback onOpenAbout;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Ещё', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Сеть, интерфейс и информация о приложении',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        _MoreTile(
          icon: Icons.public_rounded,
          title: 'Сеть',
          subtitle: 'DNS, маршрутизация и логи',
          onTap: onOpenNetwork,
        ),
        const SizedBox(height: 12),
        _MoreTile(
          icon: Icons.palette_outlined,
          title: 'Интерфейс',
          subtitle: 'Тема и фирменный стиль Orex',
          onTap: onOpenAppearance,
        ),
        const SizedBox(height: 12),
        _MoreTile(
          icon: Icons.info_outline_rounded,
          title: 'О приложении',
          subtitle: 'Версия, движок и диагностика',
          onTap: onOpenAbout,
        ),
      ],
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 20,
      child: ListTile(
        leading: Icon(icon, color: OrexColors.copper),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
