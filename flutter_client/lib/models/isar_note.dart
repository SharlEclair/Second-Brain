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
}
