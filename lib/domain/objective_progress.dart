import 'package:blackgrid_progress/blackgrid_progress.dart';

/// The target count of a counter objective, or `null` when it is not one.
///
/// A counter is an objective whose catalog count is a whole number over 1.
int? objectiveCounterTarget(TaskObjective objective) {
  final count = objective.count;
  if (count == null || count <= 1 || count != count.truncate()) return null;
  return count.toInt();
}

/// Whether [objective] is done, given its recorded completion and count.
///
/// An objective is done when it is recorded [complete], or when it is a
/// counter (see [objectiveCounterTarget]) whose recorded [count] reached its
/// target. The quest checklist records a counter's completion only in its
/// count, so both are read. [count] is ignored for an objective that is not a
/// counter.
bool objectiveDone(
  TaskObjective objective, {
  required bool complete,
  required int count,
}) {
  if (complete) return true;
  final target = objectiveCounterTarget(objective);
  return target != null && count >= target;
}
