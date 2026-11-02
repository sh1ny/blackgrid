import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _t(String hms) {
  final [h, m, s] = hms.split(':').map(int.parse).toList();
  return DateTime(2026, 10, 28, h, m, s);
}

const _saleId = LogRecordId('f1', LogFile.pushNotifications, 7);

FleaSale _sale(String at, {int count = 2, int? roubles = 45000}) =>
    FleaSale(_saleId, _t(at), 'item-a', count, roubles);

RaidLifecycleState _after(Iterable<GameLogEvent> events) {
  var state = RaidLifecycleState.initial;
  for (final event in events) {
    state = reduce(state, event).$1;
  }
  return state;
}

void main() {
  test('sale publishes one flea-sale transition with the session mode', () {
    final state = _after([
      SessionModeChanged(
        const LogRecordId('f1', LogFile.application, 1),
        _t('19:30:00'),
        GameMode.pve,
      ),
      ProfileSelected(
        const LogRecordId('f1', LogFile.application, 2),
        _t('19:30:05'),
      ),
    ]);

    final (next, published) = reduce(state, _sale('19:31:00'));

    final sold = published.single as FleaSoldTransition;
    expect(sold.id, _saleId);
    expect(sold.time, _t('19:31:00'));
    expect(sold.itemId, 'item-a');
    expect(sold.count, 2);
    expect(sold.roubles, 45000);
    expect(sold.mode, GameMode.pve);
    expect(next.phase, state.phase);
    expect(next.phase, RaidPhase.inMenus);
  });

  test('sale before any mode has no mode', () {
    final (_, published) = reduce(
      RaidLifecycleState.initial,
      _sale('19:31:00'),
    );

    expect((published.single as FleaSoldTransition).mode, isNull);
  });

  test('sale without roubles publishes no payout', () {
    final (_, published) = reduce(
      RaidLifecycleState.initial,
      _sale('19:31:00', roubles: null),
    );

    expect((published.single as FleaSoldTransition).roubles, isNull);
  });

  test('sale in raid leaves phase and raid unchanged', () {
    final state = _after([
      ProfileSelected(
        const LogRecordId('f1', LogFile.application, 1),
        _t('19:30:00'),
      ),
      RaidStarted(
        const LogRecordId('f1', LogFile.application, 2),
        _t('19:41:06'),
      ),
    ]);
    expect(state.phase, RaidPhase.inRaid);

    final (next, published) = reduce(state, _sale('19:45:00'));

    expect(published.single, isA<FleaSoldTransition>());
    expect(next.phase, RaidPhase.inRaid);
    expect(next.raid, same(state.raid));
    expect(next.currentRaid, same(state.currentRaid));
  });
}
