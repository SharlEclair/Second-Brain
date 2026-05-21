import 'package:isar/isar.dart';

part 'isar_api_request.g.dart';

@collection
class ApiRequest {
  Id id = Isar.autoIncrement;

  late String type;
  late String payload;
  late DateTime createdAt;

  int retryCount = 0;
  bool isFailed = false;
}
