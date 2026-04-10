import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../models/backup_config.dart';
import '../services/backup_service.dart';
import '../services/config_service.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final SharedPreferences prefs;

  const HomeScreen({super.key, required this.prefs});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late ConfigService _configService;
  late BackupService _backupService;

  List<BackupConfig> _configs = [];
  List<String> _availableDestinations = [];
  bool _isBackingUp = false;
  String _statusMessage = '';
  final List<String> _logLines = [];

  @override
  void initState() {
    super.initState();
    _configService = ConfigService(prefs: widget.prefs);
    _backupService = BackupService(serverUrl: _configService.serverUrl);
    _configs = _configService.loadConfigs();
    _fetchDestinations();
  }

  Future<void> _fetchDestinations() async {
    try {
      final dests = await _backupService.fetchDestinations();
      setState(() => _availableDestinations = dests);
    } catch (e) {
      setState(() => _statusMessage = '无法连接到服务器: $e');
    }
  }

  Future<void> _addConfig() async {
    if (_availableDestinations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先确保服务器连接正常并配置存储目标')),
      );
      return;
    }

    // Pick folder
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择存档文件夹',
    );
    if (result == null) return;

    String? selectedDest = _availableDestinations.first;
    String label = result.split('/').last;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _AddConfigDialog(
        localPath: result,
        destinations: _availableDestinations,
        initialDest: selectedDest!,
        initialLabel: label,
        onConfirm: (dest, lbl) {
          selectedDest = dest;
          label = lbl;
        },
      ),
    );

    if (confirmed != true) return;

    final config = BackupConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      localPath: result,
      destination: selectedDest!,
      label: label,
    );

    setState(() {
      _configs.add(config);
    });
    await _configService.saveConfigs(_configs);
  }

  Future<void> _removeConfig(String id) async {
    setState(() {
      _configs.removeWhere((c) => c.id == id);
    });
    await _configService.saveConfigs(_configs);
  }

  Future<void> _startBackup() async {
    if (_isBackingUp) return;
    if (_configs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先添加备份配置')),
      );
      return;
    }

    setState(() {
      _isBackingUp = true;
      _logLines.clear();
      _statusMessage = '正在备份...';
    });

    int totalUploaded = 0;
    int totalSkipped = 0;
    int totalFailed = 0;

    for (final config in _configs) {
      _addLog('=== 开始备份: ${config.label} → ${config.destination} ===');
      try {
        final result = await _backupService.backup(
          config.localPath,
          config.destination,
          onProgress: (msg) {
            _addLog(msg);
          },
        );
        totalUploaded += result.uploaded;
        totalSkipped += result.skipped;
        totalFailed += result.failed;
        _addLog(
            '完成: 上传 ${result.uploaded}, 跳过 ${result.skipped}, 失败 ${result.failed}');
      } catch (e) {
        _addLog('错误: $e');
        totalFailed++;
      }
    }

    setState(() {
      _isBackingUp = false;
      _statusMessage =
          '备份完成 — 上传: $totalUploaded, 跳过: $totalSkipped, 失败: $totalFailed';
    });
  }

  void _addLog(String msg) {
    setState(() {
      _logLines.add(msg);
      if (_logLines.length > 200) _logLines.removeAt(0);
    });
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          prefs: widget.prefs,
          onSaved: () {
            _backupService =
                BackupService(serverUrl: _configService.serverUrl);
            _fetchDestinations();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('存档备份'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchDestinations,
          ),
        ],
      ),
      body: Column(
        children: [
          // Backup list
          Expanded(
            flex: 3,
            child: _configs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.folder_open,
                            size: 64, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(
                          '暂无备份配置',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _addConfig,
                          icon: const Icon(Icons.add),
                          label: const Text('添加备份路径'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _configs.length,
                    itemBuilder: (ctx, i) {
                      final c = _configs[i];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.folder),
                          title: Text(c.label),
                          subtitle: Text(
                            '${c.localPath}\n→ ${c.destination}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _removeConfig(c.id),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Backup button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isBackingUp
                      ? Colors.grey
                      : Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: _isBackingUp ? null : _startBackup,
                icon: _isBackingUp
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.backup),
                label: Text(_isBackingUp ? '备份中...' : '开始备份'),
              ),
            ),
          ),

          // Status
          if (_statusMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _statusMessage,
                style: TextStyle(
                  color: _statusMessage.contains('失败')
                      ? Colors.red
                      : Colors.green,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

          // Log output
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: _logLines.isEmpty
                  ? const Center(
                      child: Text('日志将在此显示',
                          style: TextStyle(color: Colors.grey)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _logLines.length,
                      itemBuilder: (ctx, i) => Text(
                        _logLines[i],
                        style:
                            const TextStyle(color: Colors.green, fontSize: 12),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
      floatingActionButton: _configs.isNotEmpty
          ? FloatingActionButton(
              onPressed: _addConfig,
              tooltip: '添加备份路径',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class _AddConfigDialog extends StatefulWidget {
  final String localPath;
  final List<String> destinations;
  final String initialDest;
  final String initialLabel;
  final void Function(String dest, String label) onConfirm;

  const _AddConfigDialog({
    required this.localPath,
    required this.destinations,
    required this.initialDest,
    required this.initialLabel,
    required this.onConfirm,
  });

  @override
  State<_AddConfigDialog> createState() => _AddConfigDialogState();
}

class _AddConfigDialogState extends State<_AddConfigDialog> {
  late String _selectedDest;
  late TextEditingController _labelCtrl;

  @override
  void initState() {
    super.initState();
    _selectedDest = widget.initialDest;
    _labelCtrl = TextEditingController(text: widget.initialLabel);
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加备份配置'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '本地路径:',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          Text(
            widget.localPath,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _labelCtrl,
            decoration: const InputDecoration(
              labelText: '备份名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _selectedDest,
            decoration: const InputDecoration(
              labelText: '服务器存储位置',
              border: OutlineInputBorder(),
            ),
            items: widget.destinations
                .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                .toList(),
            onChanged: (v) => setState(() => _selectedDest = v!),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onConfirm(_selectedDest, _labelCtrl.text.trim());
            Navigator.pop(context, true);
          },
          child: const Text('确认'),
        ),
      ],
    );
  }
}
