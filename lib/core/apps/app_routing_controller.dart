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
  });

  final String packageName;
  final String label;
  final bool isSystem;
  final bool hasLauncher;
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
  static const _maxCachedIcons = 192;

  final SharedPreferences _preferences;
  AppRoutingMode _mode;
  final Set<String> _selectedPackages;
  bool _showSystemApps;
  List<AndroidAppInfo> _apps = const [];
  bool _loading = false;
  String? _error;
  bool _disposed = false;

  final Map<String, ValueNotifier<Uint8List?>> _iconNotifiers = {};
  final Set<String> _iconLoads = {};
  final Set<String> _missingIcons = {};

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

  ValueListenable<Uint8List?> iconListenableFor(String packageName) =>
      _iconNotifiers.putIfAbsent(packageName, () => ValueNotifier(null));

  Future<void> setMode(AppRoutingMode value) async {
    if (_mode == value || _disposed) return;
    _mode = value;
    await _preferences.setString(_modeKey, value.storageValue);
    _notifyListeners();
  }

  Future<void> setShowSystemApps(bool value) async {
    if (_showSystemApps == value || _disposed) return;
    _showSystemApps = value;
    await _preferences.setBool(_showSystemAppsKey, value);
    _notifyListeners();
  }

  Future<void> togglePackage(String packageName) async {
    if (_disposed) return;
    if (_selectedPackages.contains(packageName)) {
      _selectedPackages.remove(packageName);
    } else {
      _selectedPackages.add(packageName);
    }
    await _preferences.setStringList(
      _packagesKey,
      _selectedPackages.toList()..sort(),
    );
    _notifyListeners();
  }

  Future<void> loadApps({bool force = false}) async {
    if (!Platform.isAndroid || _disposed || _loading) return;
    if (_apps.isNotEmpty && !force) return;

    _loading = true;
    _error = null;
    _notifyListeners();
    try {
      final raw = await _channel.invokeListMethod<dynamic>('listApps') ?? const [];
      if (_disposed) return;

      final apps = <AndroidAppInfo>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final packageName = (map['packageName'] as String? ?? '').trim();
        final label = (map['label'] as String? ?? packageName).trim();
        if (packageName.isEmpty) continue;
        apps.add(AndroidAppInfo(
          packageName: packageName,
          label: label.isEmpty ? packageName : label,
          isSystem: map['isSystem'] == true,
          hasLauncher: map['hasLauncher'] == true,
        ));
      }
      apps.sort((a, b) {
        final byLabel = a.label.toLowerCase().compareTo(b.label.toLowerCase());
        return byLabel == 0 ? a.packageName.compareTo(b.packageName) : byLabel;
      });
      _apps = apps;

      final installed = apps.map((app) => app.packageName).toSet();
      final selectedBefore = _selectedPackages.length;
      _selectedPackages.removeWhere((packageName) => !installed.contains(packageName));
      if (_selectedPackages.length != selectedBefore) {
        await _preferences.setStringList(
          _packagesKey,
          _selectedPackages.toList()..sort(),
        );
      }
      final stale = _iconNotifiers.keys.where((key) => !installed.contains(key)).toList();
      for (final key in stale) {
        _iconNotifiers.remove(key)?.dispose();
        _iconLoads.remove(key);
        _missingIcons.remove(key);
      }
    } on PlatformException catch (error) {
      if (!_disposed) _error = error.message ?? error.code;
    } on Object catch (error) {
      if (!_disposed) _error = error.toString();
    } finally {
      if (!_disposed) {
        _loading = false;
        _notifyListeners();
      }
    }
  }

  Future<void> loadIcon(String packageName) async {
    if (!Platform.isAndroid || _disposed) return;
    final notifier = _iconNotifiers.putIfAbsent(
      packageName,
      () => ValueNotifier<Uint8List?>(null),
    );
    if (notifier.value != null ||
        _iconLoads.contains(packageName) ||
        _missingIcons.contains(packageName)) {
      return;
    }

    _iconLoads.add(packageName);
    try {
      final raw = await _channel.invokeMethod<String>(
        'loadAppIcon',
        {'packageName': packageName},
      );
      if (_disposed) return;
      if (raw == null || raw.isEmpty) {
        _missingIcons.add(packageName);
        return;
      }

      final bytes = base64Decode(raw);
      if (bytes.isEmpty) {
        _missingIcons.add(packageName);
        return;
      }

      _evictOldIconIfNeeded(except: packageName);
      notifier.value = bytes;
    } on FormatException {
      if (!_disposed) _missingIcons.add(packageName);
    } on PlatformException {
      if (!_disposed) _missingIcons.add(packageName);
    } finally {
      _iconLoads.remove(packageName);
    }
  }

  void _evictOldIconIfNeeded({required String except}) {
    final loaded = _iconNotifiers.entries
        .where((entry) => entry.key != except && entry.value.value != null)
        .toList(growable: false);
    if (loaded.length < _maxCachedIcons) return;
    loaded.first.value.value = null;
  }

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final notifier in _iconNotifiers.values) {
      notifier.dispose();
    }
    _iconNotifiers.clear();
    _iconLoads.clear();
    _missingIcons.clear();
    super.dispose();
  }
}
