import 'package:blackgrid_progress/blackgrid_progress.dart';

Map<String, dynamic> taskWire(
  String id, [
  Map<String, dynamic> fields = const {},
]) => {
  'id': id,
  'name': '$id name',
  'normalizedName': 'normalized-$id',
  'trader': 'trader-a',
  'minPlayerLevel': 1,
  'factionName': 'Any',
  'taskRequirements': <Object?>[],
  'traderRequirements': <Object?>[],
  'failConditions': <Object?>[],
  'objectives': <Object?>[],
  ...fields,
};

Map<String, dynamic> stationWire(
  String id, [
  Map<String, dynamic> fields = const {},
]) => {
  'id': id,
  'name': '$id name',
  'normalizedName': 'normalized-$id',
  'levels': <Object?>[],
  ...fields,
};

Map<String, dynamic> levelWire(
  String id,
  int number, [
  Map<String, dynamic> fields = const {},
]) => {
  'id': id,
  'level': number,
  'constructionTime': 60,
  'stationLevelRequirements': <Object?>[],
  'traderRequirements': <Object?>[],
  'skillRequirements': <Object?>[],
  ...fields,
};

ProgressCatalog parseWire({
  List<Map<String, dynamic>>? tasks,
  List<Map<String, dynamic>>? stations,
  Set<String> traderIds = const {'trader-a', 'trader-b'},
  Map<String, dynamic>? taskDictionary,
  Map<String, dynamic>? hideoutDictionary,
}) => parseProgressCatalog(
  {
    'tasks': {
      for (final task in tasks ?? [taskWire('task-a')])
        task['id'] as String: task,
    },
  },
  {
    for (final station in stations ?? <Map<String, dynamic>>[])
      station['id'] as String: station,
  },
  traderIds,
  taskDictionary,
  hideoutDictionary,
);
