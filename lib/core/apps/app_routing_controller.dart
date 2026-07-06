import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppRoutingMode {
  all,
  excludeSelected,
  onlySelected;

  String get storageValue => switch (this) {
        AppRoutingMode.all => 'all',
        AppRoutingMode.excludeSelected => 'exclude_selected',
        AppRoutingMode.onlySelected => 'only_selected',
      };

  String get title => switch (this) {
        AppRoutingMode.all => 'Все приложения',
        AppRoutingMode.excludeSelected => 'Кроме выбранных',
        AppRoutingMode.onlySelected => 'Только выбранные',
      };

  String get description => switch (this) {
        AppRoutingMode.all => 'Весь трафик приложений проходит через VPN',
        AppRoutingMode.excludeSelected => 'Выбранные приложения обходят VPN',
        AppRoutingMode.onlySelected => 'Только выбранные приложения используют VPN',
      };

  static AppRoutingMode fromStorageValue(String? value) => switch (value) {
        'exclude_selected' => AppRoutingMode.excludeSelected,
        'only_selected' => AppRoutingMode.onlySelected,
        _ => AppRoutingMode.all,
      };
}

class AndroidAppInfo {
  const AndroidAppInfo({
    required this.packageName,
    required this.label,
    required this.isSystem,
    required this.hasLauncher,
    this.iconBytes,
  });

  final String packageName;
  final String label;
  final bool isSystem;
  final bool hasLauncher;
  final Uint8List? iconBytes;
}

class AppRoutingController extends ChangeNotifier {
  AppRoutingController._({
    required SharedPreferences preferences,
    required AppRoutingMode mode,
    required Set<String> selectedPackages,
    required bool showSystemApps,
  })  : _preferences = preferences,
        _mode = mode,
        _selectedPackages = selectedPackages,
        _showSystemApps = showSystemApps;

  static const _channel = MethodChannel('ru.orex.ray/tunnel');
  static const _modeKey = 'orex_ray_app_routing_mode_v1';
  static const _packagesKey = 'orex_ray_app_routing_packages_v1';
  static const _showSystemAppsKey = 'orex_ray_show_system_apps_v1';

  final SharedPreferences _preferences;
  AppRoutingMode _mode;
  final Set<String> _selectedPackages;
  bool _showSystemApps;
  List<AndroidAppInfo> _apps = const [];
  bool _loading = false;
  String? _error;

  static Future<AppRoutingController> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppRoutingController._(
      preferences: prefs,
      mode: AppRoutingMode.fromStorageValue(prefs.getString(_modeKey)),
      selectedPackages: prefs.getStringList(_packagesKey)?.toSet() ?? <String>{},
      showSystemApps: prefs.getBool(_showSystemAppsKey) ?? false,
    );
  }

  AppRoutingMode get mode => _mode;
  Set<String> get selectedPackages => Set.unmodifiable(_selectedPackages);
  List<AndroidAppInfo> get apps => List.unmodifiable(_apps);
  bool get showSystemApps => _showSystemApps;
  bool get loading => _loading;
  String? get error => _error;
  bool get supported => Platform.isAndroid;

  Future<void> setMode(AppRoutingMode value) async {
    if (_mode == value) return;
    _mode = value;
    await _preferences.setString(_modeKey, value.storageValue);
    notifyListeners();
  }

  Future<void> setShowSystemApps(bool value) async {
    if (_showSystemApps == value) return;
    _showSystemApps = value;
    await _preferences.setBool(_showSystemAppsKey, value);
    notifyListeners();
  }

  Future<void> togglePackage(String packageName) async {
    if (_selectedPackages.contains(packageName)) {
      _selectedPackages.remove(packageName);
    } else {
      _selectedPackages.add(packageName);
    }
    await _preferences.setStringList(
      _packagesKey,
      _selectedPackages.toList()..sort(),
    );
    notifyListeners();
  }

  Future<void> loadApps({bool force = false}) async {
    if (!Platform.isAndroid || _loading || (_apps.isNotEmpty && !force)) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final raw = await _channel.invokeListMethod<dynamic>('listApps') ?? const [];
      final apps = <AndroidAppInfo>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final packageName = (map['packageName'] as String? ?? '').trim();
        final label = (map['label'] as String? ?? packageName).trim();
        if (packageName.isEmpty) continue;
        Uint8List? iconBytes;
        final rawIcon = map['iconBase64'];
        if (rawIcon is String && rawIcon.isNotEmpty) {
          try {
            iconBytes = base64Decode(rawIcon);
          } on FormatException {
            iconBytes = null;
          }
        }
        apps.add(AndroidAppInfo(
          packageName: packageName,
          label: label.isEmpty ? packageName : label,
          isSystem: map['isSystem'] == true,
          hasLauncher: map['hasLauncher'] == true,
          iconBytes: iconBytes,
        ));
      }
      apps.sort((a, b) {
        final byLabel = a.label.toLowerCase().compareTo(b.label.toLowerCase());
        return byLabel == 0 ? a.packageName.compareTo(b.packageName) : byLabel;
      });
      _apps = apps;
    } on PlatformException catch (error) {
      _error = error.message ?? error.code;
    } on Object catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
