import 'catalog.dart';
import 'progress_facts.dart';

enum FirState { unknown, yes, no }

class InspectionContext {
  const InspectionContext({
    required this.mode,
    required this.now,
    this.catalog,
    this.progress,
    this.fir = FirState.unknown,
    this.catalogStale = false,
  });
  final GameMode mode;
  final DateTime now;
  final CatalogSnapshot? catalog;

  /// The effective mode's local progress, or `null` when it cannot be read.
  final ProgressFacts? progress;
  final FirState fir;
  final bool catalogStale;
}
