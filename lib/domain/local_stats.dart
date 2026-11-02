import 'catalog.dart';
import 'raid_lifecycle.dart';

/// How long after a stored raid started a reconnect on the same map is still
/// taken for that same raid.
///
/// Changing it never rewrites stored rows; it only changes later decisions.
const reconnectSameRaidWindow = Duration(hours: 2);

/// One stored raid start, as the local stats keep it.
final class RaidStatRow {
  /// Creates a stored raid row.
  const RaidStatRow({
    required this.id,
    required this.mode,
    required this.mapId,
    required this.start,
    required this.entry,
  });

  /// The log record that announced the raid.
  final LogRecordId id;

  /// The game mode, or `null` when it was not known.
  final GameMode? mode;

  /// The map id, or `null` when the map was not known.
  final String? mapId;

  /// When the raid started.
  final DateTime start;

  /// How the player came to enter the raid.
  final RaidEntry entry;
}

/// One stored flea-market sale, as the local stats keep it.
final class FleaSaleRow {
  /// Creates a stored sale row.
  const FleaSaleRow({
    required this.id,
    required this.mode,
    required this.time,
    required this.itemId,
    required this.count,
    required this.roubles,
  });

  /// The log record that announced the sale.
  final LogRecordId id;

  /// The game mode, or `null` when it was not known.
  final GameMode? mode;

  /// When the sale happened.
  final DateTime time;

  /// The id of the item sold.
  final String itemId;

  /// How many items the sale covered.
  final int count;

  /// The roubles received, or `null` when the sale was paid in another
  /// currency.
  final int? roubles;
}

/// Decides whether [candidate] counts as a new raid.
///
/// Only a reconnect entry can be suppressed. It is suppressed when [previous],
/// the newest stored raid of the same mode that started strictly before it, is
/// on the same map and started at most [reconnectSameRaidWindow] earlier. A
/// [previous] of another mode, or one that does not start before [candidate],
/// never suppresses a count, so a replay decides the same way.
bool countsReconnect(RaidStatRow? previous, RaidStatRow candidate) {
  if (candidate.entry != RaidEntry.reconnect || previous == null) return true;
  if (previous.mode != candidate.mode) return true;
  if (previous.mapId != candidate.mapId) return true;
  final elapsed = candidate.start.difference(previous.start);
  if (elapsed <= Duration.zero) return true;
  return elapsed > reconnectSameRaidWindow;
}

/// Totals shown by the local stats.
final class LocalStatsTotals {
  /// Creates totals; [raidsByMap] is re-ordered by count, then by map key.
  LocalStatsTotals({
    required Map<String?, int> raidsByMap,
    required this.raidTotal,
    required this.sales,
    required this.items,
    required this.roubles,
    required this.salesNotInRoubles,
  }) : raidsByMap = Map.unmodifiable(_ordered(raidsByMap));

  /// Totals with nothing counted.
  static final empty = LocalStatsTotals(
    raidsByMap: const {},
    raidTotal: 0,
    sales: 0,
    items: 0,
    roubles: 0,
    salesNotInRoubles: 0,
  );

  /// Raids per map id, most raids first and ties by map key; a `null` key is
  /// the unknown map.
  final Map<String?, int> raidsByMap;

  /// All raids counted.
  final int raidTotal;

  /// Flea sales counted.
  final int sales;

  /// Items sold across all sales.
  final int items;

  /// Roubles received across the sales paid in roubles.
  final int roubles;

  /// Sales paid in another currency, left out of [roubles].
  final int salesNotInRoubles;

  /// Whether nothing at all has been counted.
  bool get isEmpty => raidTotal == 0 && sales == 0 && raidsByMap.isEmpty;

  static Map<String?, int> _ordered(Map<String?, int> source) {
    final entries = source.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : (a.key ?? '').compareTo(b.key ?? '');
      });
    return {for (final MapEntry(:key, :value) in entries) key: value};
  }
}
