import 'catalog.dart';
import 'progress.dart';

enum FirState { unknown, yes, no }

class InspectionContext {
  const InspectionContext({
    required this.mode,
    required this.now,
    this.catalog,
    this.progress,
    this.fir = FirState.unknown,
    this.catalogStale = false,
    this.progressStale = false,
  });
  final GameMode mode;
  final DateTime now;
  final CatalogSnapshot? catalog;
  final ProgressSnapshot? progress;
  final FirState fir;
  final bool catalogStale, progressStale;
}
