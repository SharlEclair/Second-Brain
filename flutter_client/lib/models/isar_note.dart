import 'package:isar/isar.dart';

part 'isar_note.g.dart';

@collection
class IsarNote {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String fileName;

  late String title;
  late String content;
  late String category;
  late DateTime lastModified;

  /// Deterministic FNV-1a hash for fileName → stable Isar Id.
  /// Ensures `put()` overwrites rather than duplicating.
  static int fastHash(String string) {
    var hash = 0xcbf29ce484222325;
    var i = 0;
    while (i < string.length) {
      final codeUnit = string.codeUnitAt(i++);
      hash ^= codeUnit >> 8;
      hash *= 0x100000001b3;
      hash ^= codeUnit & 0xFF;
      hash *= 0x100000001b3;
    }
    return hash;
  }
}
