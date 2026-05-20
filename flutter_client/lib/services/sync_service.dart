import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/isar_note.dart';
import 'api_service.dart';
import 'debug_logger.dart';

class SyncService {
  static Isar? _isar;
  final ApiService _apiService = ApiService();

  static Future<Isar> get isar async {
    if (_isar != null) return _isar!;
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [IsarNoteSchema],
      directory: dir.path,
    );
    return _isar!;
  }

  Future<void> syncDown() async {
    try {
      final isarDb = await isar;
      final remoteNotes = await _apiService.fetchNotes();
      
      // Get all local fileNames to check for deletions later
      final localNotes = await isarDb.isarNotes.where().findAll();
      final localFileNames = localNotes.map((n) => n.fileName).toSet();
      final remoteFileNames = <String>{};

      for (final note in remoteNotes) {
        final fileName = note['fileName'] as String?;
        if (fileName == null) continue;
        remoteFileNames.add(fileName);

        final title = note['title'] as String? ?? fileName.replaceAll('.md', '');
        final category = note['category'] as String? ?? 'General';
        final dateStr = note['date'] as String? ?? '';
        final lastModified = DateTime.tryParse(dateStr) ?? DateTime.now();

        // Check if cached note needs update
        final cached = await isarDb.isarNotes.filter().fileNameEqualTo(fileName).findFirst();
        if (cached == null || cached.lastModified.isBefore(lastModified)) {
          try {
            final content = await _apiService.fetchNoteContent(fileName);
            final newNote = IsarNote()
              ..fileName = fileName
              ..title = title
              ..category = category
              ..content = content
              ..lastModified = lastModified;
            
            await isarDb.writeTxn(() async {
              await isarDb.isarNotes.put(newNote);
            });
            DebugLogger.log('Synced note down: $fileName', type: 'SYNC');
          } catch (e) {
            DebugLogger.log('Failed to sync content for $fileName: $e', type: 'ERROR');
          }
        }
      }

      // Sync Master Index and Category Indexes for complete offline navigation tree
      try {
        final masterIndexContent = await _apiService.fetchNoteContent('_master-index.md');
        final masterNote = IsarNote()
          ..fileName = '_master-index.md'
          ..title = 'Master Index'
          ..category = 'System'
          ..content = masterIndexContent
          ..lastModified = DateTime.now();
        await isarDb.writeTxn(() async {
          await isarDb.isarNotes.put(masterNote);
        });
        remoteFileNames.add('_master-index.md');

        // Parse category indexes to sync down
        final lines = masterIndexContent.split('\n');
        final categoryRegExp = RegExp(r'-\s*\*\*\[\[([^/|\]]+)/_index\|([^\]]+)\]\]\*\*(?::\s*(\d+)\s*articles)?');
        for (final line in lines) {
          final match = categoryRegExp.firstMatch(line.trim());
          if (match != null) {
            final path = match.group(1)!;
            final catIndexName = '$path/_index.md';
            remoteFileNames.add(catIndexName);
            try {
              final catIndexContent = await _apiService.fetchNoteContent(catIndexName);
              final catNote = IsarNote()
                ..fileName = catIndexName
                ..title = '${match.group(2)} Index'
                ..category = 'System'
                ..content = catIndexContent
                ..lastModified = DateTime.now();
              await isarDb.writeTxn(() async {
                await isarDb.isarNotes.put(catNote);
              });
            } catch (e) {
              DebugLogger.log('Failed to sync category index $catIndexName: $e', type: 'ERROR');
            }
          }
        }
      } catch (e) {
        DebugLogger.log('Failed to sync directory tree metadata: $e', type: 'ERROR');
      }

      // Handle deletions: local notes that are no longer present remotely
      final toDelete = localFileNames.difference(remoteFileNames);
      if (toDelete.isNotEmpty) {
        await isarDb.writeTxn(() async {
          for (final fileName in toDelete) {
            await isarDb.isarNotes.filter().fileNameEqualTo(fileName).deleteAll();
            DebugLogger.log('Deleted obsolete note from cache: $fileName', type: 'SYNC');
          }
        });
      }
    } catch (e) {
      DebugLogger.log('Downward sync failed: $e', type: 'ERROR');
      rethrow;
    }
  }

  Future<List<IsarNote>> getCachedNotes() async {
    final isarDb = await isar;
    return isarDb.isarNotes.filter().not().categoryEqualTo('System').findAll();
  }

  Future<IsarNote?> getCachedNote(String fileName) async {
    final isarDb = await isar;
    return isarDb.isarNotes.filter().fileNameEqualTo(fileName).findFirst();
  }
}
