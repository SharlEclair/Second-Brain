import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'debug_logger.dart';

class LocalNote {
  final String title;
  final String fileName;
  final String content;
  final DateTime savedAt;

  LocalNote({
    required this.title,
    required this.fileName,
    required this.content,
    required this.savedAt,
  });
}

class StorageService {
  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    final vaultDir = Directory('${directory.path}/vault');
    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }
    return vaultDir.path;
  }

  Future<File> _getLocalFile(String fileName) async {
    final path = await _localPath;
    return File('$path/$fileName');
  }

  Future<void> saveNote(String fileName, String content) async {
    try {
      final file = await _getLocalFile(fileName);
      await file.writeAsString(content);
      DebugLogger.log('Saved note locally: $fileName', type: 'STORAGE');
    } catch (e) {
      DebugLogger.log('Failed to save note locally: $e', type: 'ERROR');
    }
  }

  Future<String?> readNote(String fileName) async {
    try {
      final file = await _getLocalFile(fileName);
      if (await file.exists()) {
        return await file.readAsString();
      }
      return null;
    } catch (e) {
      DebugLogger.log('Failed to read note locally: $e', type: 'ERROR');
      return null;
    }
  }

  Future<List<FileSystemEntity>> listLocalNotes() async {
    try {
      final path = await _localPath;
      final dir = Directory(path);
      return dir.listSync().where((entity) => entity.path.endsWith('.md')).toList();
    } catch (e) {
      DebugLogger.log('Failed to list local notes: $e', type: 'ERROR');
      return [];
    }
  }

  Future<void> deleteNote(String fileName) async {
    try {
      final file = await _getLocalFile(fileName);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      DebugLogger.log('Failed to delete note locally: $e', type: 'ERROR');
    }
  }
}
