import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class FileMeta {
  final String hash;
  final DateTime modTime;
  final int size;

  FileMeta({required this.hash, required this.modTime, required this.size});

  factory FileMeta.fromJson(Map<String, dynamic> json) => FileMeta(
        hash: json['hash'] as String,
        modTime: DateTime.parse(json['mod_time'] as String),
        size: (json['size'] as num).toInt(),
      );
}

class BackupResult {
  final int uploaded;
  final int skipped;
  final int failed;
  final List<String> errors;

  BackupResult({
    required this.uploaded,
    required this.skipped,
    required this.failed,
    required this.errors,
  });
}

class BackupService {
  final String serverUrl;

  BackupService({required this.serverUrl});

  /// Fetch list of available destinations from server
  Future<List<String>> fetchDestinations() async {
    final uri = Uri.parse('$serverUrl/destinations');
    final resp = await http.get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw Exception('Server error: ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = data['destinations'] as List<dynamic>? ?? [];
    return list.map((e) => e.toString()).toList();
  }

  /// Fetch current file meta from server for a destination
  Future<Map<String, FileMeta>> fetchMeta(String dest) async {
    final uri = Uri.parse('$serverUrl/meta?dest=${Uri.encodeComponent(dest)}');
    final resp = await http.get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw Exception('Server error fetching meta: ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final files = data['files'] as Map<String, dynamic>? ?? {};
    return files.map((k, v) => MapEntry(
          k,
          FileMeta.fromJson(v as Map<String, dynamic>),
        ));
  }

  /// Hash a local file using SHA-256
  Future<String> hashFile(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  /// Perform backup of a local folder to the given destination
  Future<BackupResult> backup(
    String localPath,
    String dest, {
    void Function(String msg)? onProgress,
  }) async {
    final dir = Directory(localPath);
    if (!await dir.exists()) {
      throw Exception('Local path does not exist: $localPath');
    }

    onProgress?.call('正在获取服务器元数据...');
    final serverMeta = await fetchMeta(dest);

    final files = await dir
        .list(recursive: true, followLinks: false)
        .where((e) => e is File)
        .cast<File>()
        .toList();

    int uploaded = 0;
    int skipped = 0;
    int failed = 0;
    final errors = <String>[];

    for (final file in files) {
      final relPath = p.relative(file.path, from: localPath);
      final stat = await file.stat();
      final modTime = stat.modified;
      final size = stat.size;

      final serverFileMeta = serverMeta[relPath];

      // Check if file needs uploading
      if (serverFileMeta != null) {
        // Compare mod time first (fast check)
        final modChanged =
            modTime.difference(serverFileMeta.modTime).abs().inSeconds > 1;
        if (!modChanged && size == serverFileMeta.size) {
          skipped++;
          onProgress?.call('跳过: $relPath');
          continue;
        }
        // Mod time changed: verify hash
        final hash = await hashFile(file.path);
        if (hash == serverFileMeta.hash) {
          skipped++;
          onProgress?.call('跳过(哈希相同): $relPath');
          continue;
        }
        // Hash different: upload
        onProgress?.call('上传中: $relPath');
        try {
          await _uploadFile(file, relPath, dest, hash, modTime, size);
          uploaded++;
        } catch (e) {
          failed++;
          errors.add('$relPath: $e');
          onProgress?.call('失败: $relPath - $e');
        }
      } else {
        // New file
        final hash = await hashFile(file.path);
        onProgress?.call('上传新文件: $relPath');
        try {
          await _uploadFile(file, relPath, dest, hash, modTime, size);
          uploaded++;
        } catch (e) {
          failed++;
          errors.add('$relPath: $e');
          onProgress?.call('失败: $relPath - $e');
        }
      }
    }

    return BackupResult(
      uploaded: uploaded,
      skipped: skipped,
      failed: failed,
      errors: errors,
    );
  }

  Future<void> _uploadFile(
    File file,
    String relPath,
    String dest,
    String hash,
    DateTime modTime,
    int size,
  ) async {
    final uri = Uri.parse('$serverUrl/upload');
    final request = http.MultipartRequest('POST', uri);
    request.fields['dest'] = dest;
    request.fields['path'] = relPath;
    request.fields['hash'] = hash;
    request.fields['mod_time'] = modTime.toUtc().toIso8601String();
    request.fields['size'] = size.toString();
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamedResp =
        await request.send().timeout(const Duration(minutes: 5));
    final resp = await http.Response.fromStream(streamedResp);
    if (resp.statusCode != 200) {
      throw Exception('Upload failed: ${resp.statusCode} ${resp.body}');
    }
  }
}
