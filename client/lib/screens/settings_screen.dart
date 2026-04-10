import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/config_service.dart';

class SettingsScreen extends StatefulWidget {
  final SharedPreferences prefs;
  final VoidCallback onSaved;

  const SettingsScreen({
    super.key,
    required this.prefs,
    required this.onSaved,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late ConfigService _configService;
  late TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    _configService = ConfigService(prefs: widget.prefs);
    _urlCtrl = TextEditingController(text: _configService.serverUrl);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('服务器地址不能为空')),
      );
      return;
    }
    await _configService.setServerUrl(url);
    widget.onSaved();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '服务器配置',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: 'http://192.168.1.100:8080',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.dns),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
