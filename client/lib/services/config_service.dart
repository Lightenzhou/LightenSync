import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/backup_config.dart';

class ConfigService {
  static const _configsKey = 'backup_configs';
  static const _serverUrlKey = 'server_url';

  final SharedPreferences prefs;

  ConfigService({required this.prefs});

  String get serverUrl {
    final raw = prefs.getString(_serverUrlKey) ?? '';
    if (raw.isEmpty) return 'http://192.168.1.100:8080';
    // 自动补全 http:// 前缀
    if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
      return 'http://$raw';
    }
    return raw;
  }

  Future<void> setServerUrl(String url) async {
    var clean = url.trim();
    if (clean.isNotEmpty &&
        !clean.startsWith('http://') &&
        !clean.startsWith('https://')) {
      clean = 'http://$clean';
    }
    await prefs.setString(_serverUrlKey, clean);
  }

  List<BackupConfig> loadConfigs() {
    final raw = prefs.getStringList(_configsKey) ?? [];
    return raw.map((s) {
      final json = jsonDecode(s) as Map<String, dynamic>;
      return BackupConfig.fromJson(json);
    }).toList();
  }

  Future<void> saveConfigs(List<BackupConfig> configs) async {
    final raw = configs.map((c) => jsonEncode(c.toJson())).toList();
    await prefs.setStringList(_configsKey, raw);
  }
}
