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
  const AndroidAppInfo({required this.packageName, required this.label});

  final String packageName;
  final String label;
}

class AppRoutingController extends ChangeNotifier {
  AppRoutingController._({
    required SharedPreferences preferences,
    required AppRoutingMode mode,
    required Set<String> selectedPackages,
  })  : _preferences = preferences,
        _mode = mode,
        _selectedPackages = selectedPackages;

  static const _channel = MethodChannel('ru.orex.ray/tunnel');
  static const _modeKey = 'orex_ray_app_routing_mode_v1';
  static const _packagesKey = 'orex_ray_app_routing_packages_v1';

  final SharedPreferences _preferences;
  AppRoutingMode _mode;
  final Set<String> _selectedPackages;
  List<AndroidAppInfo> _apps = const [];
  bool _loading = false;
  String? _error;

  static Future<AppRoutingController> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppRoutingController._(
      preferences: prefs,
      mode: AppRoutingMode.fromStorageValue(prefs.getString(_modeKey)),
      selectedPackages: prefs.getStringList(_packagesKey)?.toSet() ?? <String>{},
    );
  }

  AppRoutingMode get mode => _mode;
  Set<String> get selectedPackages => Set.unmodifiable(_selectedPackages);
  List<AndroidAppInfo> get apps => List.unmodifiable(_apps);
  bool get loading => _loading;
  String? get error => _error;
  bool get supported => Platform.isAndroid;

  Future<void> setMode(AppRoutingMode value) async {
    if (_mode == value) return;
    _mode = value;
    await _preferences.setString(_modeKey, value.storageValue);
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
        apps.add(AndroidAppInfo(packageName: packageName, label: label));
      }
      apps.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
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
