import 'catalog.dart';

/// The name a need goes by in the app.
///
/// A hideout need with a known level reads as the station name, then "level", then the level number; every
/// other need reads as its source name, such as the task name.
String needTitle(ItemRequirement requirement) {
  final level = requirement.stationLevel;
  if (requirement.kind == RequirementKind.hideout && level != null) {
    return '${requirement.sourceName} level $level';
  }
  return requirement.sourceName;
}
