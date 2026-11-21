import '../domain/alert_rules.dart' show QuestObjectiveRef;
import 'prepared_map.dart' show PreparedMarker;

/// The quest objectives carried by [markers].
///
/// Only markers of category `questObjectives` count, and a marker whose
/// details lack a task or objective ID is skipped.
List<QuestObjectiveRef> questObjectiveRefs(Iterable<PreparedMarker> markers) =>
    [
      for (final marker in markers)
        if (marker.category == 'questObjectives')
          if (marker.details case {
            'id': final String objectiveId,
            'quest': {'id': final String taskId},
          })
            QuestObjectiveRef(taskId, objectiveId),
    ];
