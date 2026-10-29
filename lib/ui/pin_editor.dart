import 'package:flutter/material.dart';

import '../application/app_services.dart';
import '../domain/map_coordinates.dart';
import '../domain/settings.dart';
import 'theme.dart';

Future<void> showPinEditor(
  BuildContext context,
  AppServices services, {
  CustomPin? pin,
  MapPinCoordinates? coordinates,
}) => showDialog<void>(
  context: context,
  builder: (context) =>
      PinEditor(services: services, pin: pin, coordinates: coordinates),
);

class PinEditor extends StatefulWidget {
  const PinEditor({
    super.key,
    required this.services,
    this.pin,
    this.coordinates,
  });
  final AppServices services;
  final CustomPin? pin;
  final MapPinCoordinates? coordinates;
  @override
  State<PinEditor> createState() => _PinEditorState();
}

class _PinEditorState extends State<PinEditor> {
  late final TextEditingController label = TextEditingController(
    text: widget.pin?.label ?? '',
  );
  late final TextEditingController x = TextEditingController(
    text: (widget.pin?.x ?? widget.coordinates?.point.x)?.toString() ?? '',
  );
  late final TextEditingController y = TextEditingController(
    text: (widget.pin?.y ?? widget.coordinates?.point.y)?.toString() ?? '',
  );
  String? error;
  bool saving = false;
  @override
  void dispose() {
    label.dispose();
    x.dispose();
    y.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final nx = double.tryParse(x.text), ny = double.tryParse(y.text);
    if (nx == null ||
        ny == null ||
        !nx.isFinite ||
        !ny.isFinite ||
        label.text.trim().isEmpty) {
      setState(
        () => error = 'Enter a label and a number for each position. Points outside the map are allowed.',
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final map =
        widget.pin?.mapId ??
        widget.coordinates?.mapId ??
        widget.services.settings.settings.selectedMap;
    final pin = CustomPin(
      id: widget.pin?.id ?? 'pin-${DateTime.now().microsecondsSinceEpoch}',
      mapId: map,
      x: nx,
      y: ny,
      frame:
          widget.pin?.frame ??
          widget.coordinates?.frame.wireName ??
          (map == 'thelab'
              ? MapCoordinateFrame.labsNativeNormalized.wireName
              : MapCoordinateFrame.legacyNormalized.wireName),
      frameRevision:
          widget.pin?.frameRevision ??
          widget.coordinates?.frame.revision ??
          (map == 'thelab' ? 1 : 0),
      label: label.text.trim(),
      updatedAt: DateTime.now().toUtc(),
    );
    final success = await widget.services.settings.savePin(pin);
    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
    } else {
      setState(() {
        saving = false;
        error = widget.services.settings.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.pin == null ? 'Add pin' : 'Edit pin'),
    content: SizedBox(
      width: 430,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Map: ${mapLabel(widget.pin?.mapId ?? widget.coordinates?.mapId ?? widget.services.settings.settings.selectedMap)}',
            ),
            const SizedBox(height: 8),
            const Text(
              'Positions run from 0 to 1 across the whole map. Points outside the map are allowed.',
              style: TextStyle(color: GridColors.muted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: label,
              decoration: const InputDecoration(labelText: 'Pin label'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: x,
              decoration: const InputDecoration(
                labelText: 'Position across (0–1)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: y,
              decoration: const InputDecoration(
                labelText: 'Position down (0–1)',
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: Text(saving ? 'Saving…' : 'Save pin'),
      ),
    ],
  );
}
