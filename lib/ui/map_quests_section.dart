import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../application/manual_progress_controller.dart';
import '../application/quest_checklist.dart';
import 'ember/ember_tokens.dart';
import 'ember/theme_access.dart';

/// The started quests of the effective mode with their objectives.
///
/// Each task lists its objectives in catalog order with a tick, +/- controls
/// for counters and Undo or Redo of the objective's last manual entry. Tasks
/// and objectives on the current map are marked from [markerTaskIds] and
/// [markerObjectiveIds]. While progress is not usable, or the mode has no
/// task catalog, the section shows the reason and offers no controls.
///
/// The section attaches [controller] while mounted, so it reads the
/// projection even where nothing else does. The list is a plain column: it
/// lives inside the inspector's single scrolling list, and a started-task
/// list is bounded by the catalog.
class QuestsSection extends StatefulWidget {
  /// Creates the section over [controller].
  const QuestsSection({
    super.key,
    required this.controller,
    this.markerTaskIds = const {},
    this.markerObjectiveIds = const {},
  });

  /// The shared projection and actions for local manual progress.
  final ManualProgressController controller;

  /// The task IDs carried by the current map's quest markers.
  final Set<String> markerTaskIds;

  /// The objective IDs carried by the current map's quest markers.
  final Set<String> markerObjectiveIds;

  @override
  State<QuestsSection> createState() => _QuestsSectionState();
}

class _QuestsSectionState extends State<QuestsSection> {
  @override
  void initState() {
    super.initState();
    _attach(widget.controller);
  }

  void _attach(ManualProgressController controller) {
    controller.addListener(_changed);
    controller.attach();
  }

  void _detach(ManualProgressController controller) {
    controller.removeListener(_changed);
    controller.detach();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant QuestsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detach(oldWidget.controller);
      _attach(widget.controller);
    }
  }

  @override
  void dispose() {
    _detach(widget.controller);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final ember = context.ember;
    final note = EmberType.body.copyWith(color: ember.inkSecondary);
    if (controller.disabledReason case final reason?) {
      return Text(reason, style: note);
    }
    if (controller.progressCatalog == null) {
      return Text('Quest data is not available yet.', style: note);
    }
    final checklist = controller.questChecklist(
      markerTaskIds: widget.markerTaskIds,
      markerObjectiveIds: widget.markerObjectiveIds,
    );
    if (checklist.tasks.isEmpty) {
      return Text(
        controller.loading
            ? 'Loading local progress…'
            : 'No quest is started. Accept one in game, or set it in '
                  'Settings, Your progress.',
        style: note,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, task) in checklist.tasks.indexed)
          _TaskBlock(
            key: ValueKey('quest-task-${task.id}'),
            controller: controller,
            task: task,
            first: index == 0,
          ),
      ],
    );
  }
}

class _TaskBlock extends StatelessWidget {
  const _TaskBlock({
    super.key,
    required this.controller,
    required this.task,
    required this.first,
  });

  final ManualProgressController controller;
  final QuestTask task;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final ember = context.ember;
    final trader = task.traderName;
    return Container(
      padding: EdgeInsets.only(
        top: first ? 0 : EmberSpace.md,
        bottom: EmberSpace.xs,
      ),
      decoration: first
          ? null
          : BoxDecoration(
              border: Border(top: BorderSide(color: ember.hairline)),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.name,
            style: EmberType.uiHeading.copyWith(color: ember.ink),
          ),
          if (trader != null)
            Text(
              trader,
              style: EmberType.label.copyWith(color: ember.inkTertiary),
            ),
          const SizedBox(height: EmberSpace.xs),
          for (final objective in task.objectives)
            _ObjectiveRow(
              key: ValueKey('quest-objective-${task.id}-${objective.id}'),
              controller: controller,
              taskId: task.id,
              objective: objective,
            ),
        ],
      ),
    );
  }
}

class _ObjectiveRow extends StatelessWidget {
  const _ObjectiveRow({
    super.key,
    required this.controller,
    required this.taskId,
    required this.objective,
  });

  final ManualProgressController controller;
  final String taskId;
  final QuestObjective objective;

  String get _suffix => '$taskId-${objective.id}';

  @override
  Widget build(BuildContext context) {
    final ember = context.ember;
    final label = EmberType.label.copyWith(color: ember.inkTertiary);
    final target = controller.objectiveTarget(objective.id);
    final pending = target != null && controller.pending(target);
    final ready =
        target != null && !pending && controller.disabledReason == null;
    final done = objective.done;
    final goal = objective.target;
    final action = target == null ? null : controller.actionLabel(target);
    final failure = target == null ? null : controller.failure(target);
    final shared = objective.sharedWith;
    final id = objective.id;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          key: ValueKey('quest-tick-$_suffix'),
          tooltip: goal != null
              ? 'Set to $goal'
              : done
              ? 'Mark not done'
              : 'Mark done',
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          onPressed: ready && !(goal != null && done)
              ? () => unawaited(controller.setObjectiveComplete(id, !done))
              : null,
          icon: Icon(
            done ? Icons.check_box : Icons.check_box_outline_blank,
            color: done ? ember.ok : ember.inkSecondary,
          ),
        ),
        const SizedBox(width: EmberSpace.xs),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: EmberSpace.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  objective.description,
                  style: EmberType.body.copyWith(
                    color: done ? ember.inkSecondary : ember.ink,
                  ),
                ),
                Wrap(
                  spacing: EmberSpace.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (goal != null) ...[
                      _StepButton(
                        key: ValueKey('quest-minus-$_suffix'),
                        icon: Icons.remove,
                        tooltip: 'One less',
                        onPressed: controller.canStepObjective(id, -1)
                            ? () => unawaited(
                                controller.stepObjectiveCount(id, -1),
                              )
                            : null,
                      ),
                      Text(
                        '${objective.count}/$goal',
                        style: EmberType.body.copyWith(color: ember.ink),
                      ),
                      _StepButton(
                        key: ValueKey('quest-plus-$_suffix'),
                        icon: Icons.add,
                        tooltip: 'One more',
                        onPressed: controller.canStepObjective(id, 1)
                            ? () => unawaited(
                                controller.stepObjectiveCount(id, 1),
                              )
                            : null,
                      ),
                    ],
                    if (objective.optional) Text('Optional', style: label),
                    if (objective.onThisMap)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 12,
                            color: ember.inkSecondary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            'On this map',
                            style: label.copyWith(color: ember.inkSecondary),
                          ),
                        ],
                      ),
                    if (pending) Text('Saving…', style: label),
                    if (action != null && target != null)
                      TextButton(
                        key: ValueKey('quest-undo-$_suffix'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          minimumSize: const Size(0, EmberSize.control),
                          padding: const EdgeInsets.symmetric(
                            horizontal: EmberSpace.sm,
                          ),
                        ),
                        onPressed: ready
                            ? () => unawaited(controller.undoOrRedo(target))
                            : null,
                        child: Text(action),
                      ),
                  ],
                ),
                if (shared.isNotEmpty)
                  Text(
                    'Shared with ${shared.map((task) => task.name).join(', ')}',
                    style: label,
                  ),
                if (failure != null)
                  Text(
                    failure,
                    style: EmberType.label.copyWith(color: ember.errInk),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    iconSize: 16,
    onPressed: onPressed,
    icon: Icon(icon),
  );
}
