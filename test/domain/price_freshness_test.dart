import 'package:flutter_test/flutter_test.dart';
import 'package:blackgrid/domain/price_freshness.dart';

void main() {
  final now = DateTime.utc(2026, 11, 8, 11, 40);

  test('price within an hour is fresh', () {
    final quote = now.subtract(const Duration(minutes: 32));
    final result = priceFreshness(quote, now, fleaEligible: true);
    expect(result, isA<PriceFresh>());
    expect((result as PriceFresh).time, quote);
    // Exactly at the limit is still fresh, like the engine.
    expect(
      priceFreshness(
        now.subtract(priceFreshnessLimit),
        now,
        fleaEligible: null,
      ),
      isA<PriceFresh>(),
    );
  });

  test('stale age in hours then days', () {
    PriceStale stale(Duration age) =>
        priceFreshness(now.subtract(age), now, fleaEligible: true)
            as PriceStale;
    final threeHours = stale(const Duration(hours: 3, minutes: 10));
    expect((threeHours.amount, threeHours.unit), (3, PriceAgeUnit.hours));
    final justOver = stale(const Duration(hours: 1, minutes: 1));
    expect((justOver.amount, justOver.unit), (1, PriceAgeUnit.hours));
    final lastHours = stale(const Duration(hours: 47, minutes: 59));
    expect((lastHours.amount, lastHours.unit), (47, PriceAgeUnit.hours));
    final twoDays = stale(const Duration(hours: 48));
    expect((twoDays.amount, twoDays.unit), (2, PriceAgeUnit.days));
    final manyDays = stale(const Duration(days: 5, hours: 20));
    expect((manyDays.amount, manyDays.unit), (5, PriceAgeUnit.days));
  });

  test('missing or future price time is unknown', () {
    expect(priceFreshness(null, now, fleaEligible: true), isA<PriceUnknown>());
    expect(priceFreshness(null, now, fleaEligible: null), isA<PriceUnknown>());
    expect(
      priceFreshness(
        now.add(const Duration(seconds: 1)),
        now,
        fleaEligible: true,
      ),
      isA<PriceUnknown>(),
    );
  });

  test('hidden when not Flea-sellable', () {
    expect(priceFreshness(null, now, fleaEligible: false), isA<PriceHidden>());
    expect(
      priceFreshness(
        now.subtract(const Duration(days: 3)),
        now,
        fleaEligible: false,
      ),
      isA<PriceHidden>(),
    );
  });
}
