import 'package:flutter/material.dart';

import '../../shared/theme/glass.dart';
import '../../shared/theme/orex_palette.dart';
import '../../shared/widgets/responsive_motion.dart';
import '../../shared/l10n/orex_l10n.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({
    super.key,
    required this.onOpenApps,
    required this.onOpenNetwork,
    required this.onOpenGeoData,
    required this.onOpenBackground,
    required this.onOpenAppearance,
    required this.onOpenDiagnostics,
    required this.onOpenAbout,
    this.showApps = true,
  });

  final VoidCallback onOpenApps;
  final VoidCallback onOpenNetwork;
  final VoidCallback onOpenGeoData;
  final VoidCallback onOpenBackground;
  final VoidCallback onOpenAppearance;
  final VoidCallback onOpenDiagnostics;
  final VoidCallback onOpenAbout;
  final bool showApps;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AnimatedSize(
          duration: OrexMotion.duration(context),
          curve: OrexMotion.curve,
          alignment: Alignment.topLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('More'.tr, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                showApps
                    ? 'Apps, network, GeoData and OrexRay behavior'.tr
                    : 'Network, GeoData and OrexRay behavior'.tr,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (showApps) ...[
          _MoreTile(
            icon: Icons.apps_rounded,
            title: 'Apps'.tr,
            subtitle: 'Split tunneling and Android exclusions'.tr,
            onTap: onOpenApps,
          ),
          const SizedBox(height: 12),
        ],
        _MoreTile(
          icon: Icons.public_rounded,
          title: 'Network'.tr,
          subtitle: 'DNS, routing and logs'.tr,
          onTap: onOpenNetwork,
        ),
        const SizedBox(height: 12),
        _MoreTile(
          icon: Icons.travel_explore_rounded,
          title: 'GeoData',
          subtitle: 'GeoIP, GeoSite and updates'.tr,
          onTap: onOpenGeoData,
        ),
        const SizedBox(height: 12),
        _MoreTile(
          icon: Icons.battery_saver_rounded,
          title: 'Background operation'.tr,
          subtitle: 'Notification, speed and power consumption'.tr,
          onTap: onOpenBackground,
        ),
        const SizedBox(height: 12),
        _MoreTile(
          icon: Icons.palette_outlined,
          title: 'Interface'.tr,
          subtitle: 'Theme and Orex brand style'.tr,
          onTap: onOpenAppearance,
        ),
        const SizedBox(height: 12),
        _MoreTile(
          icon: Icons.monitor_heart_outlined,
          title: 'Diagnostics'.tr,
          subtitle: 'Xray, watchdog, ports and safe report'.tr,
          onTap: onOpenDiagnostics,
        ),
        const SizedBox(height: 12),
        _MoreTile(
          icon: Icons.info_outline_rounded,
          title: 'About'.tr,
          subtitle: 'Version, engine and diagnostics'.tr,
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
    return AnimatedSize(
      duration: OrexMotion.duration(context),
      curve: OrexMotion.curve,
      alignment: Alignment.topLeft,
      child: GlassPanel(
        borderRadius: 20,
        child: ListTile(
          leading: Icon(icon, color: OrexPalette.of(context).accent),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
          mouseCursor: SystemMouseCursors.click,
          onTap: onTap,
        ),
      ),
    );
  }
}
