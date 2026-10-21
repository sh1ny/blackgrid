import 'dart:convert';

import 'package:blackgrid/application/item_icon_cache.dart';
import 'package:flutter/foundation.dart';

/// A 1x1 lossless WebP.
final Uint8List tinyWebp = base64Decode(
  'UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA==',
);

/// A 1x1 PNG.
final Uint8List tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

/// A lease the test drives by hand.
class FakeLease extends ChangeNotifier implements ItemIconLease {
  /// Creates a generic lease for [itemId].
  FakeLease(this.itemId);

  @override
  final String itemId;

  ItemIconView _view = const GenericItemIcon();

  /// Whether [release] was called.
  bool released = false;

  @override
  ItemIconView get value => _view;

  set value(ItemIconView view) {
    _view = view;
    notifyListeners();
  }

  @override
  void release() => released = true;
}

/// An [ItemIconCache] that records every acquire and hands out [FakeLease]s.
class FakeItemIconCache implements ItemIconCache {
  /// Every lease handed out, in order.
  final List<FakeLease> leases = [];

  /// Every `(itemId, iconLink)` pair that was acquired, in order.
  final List<(String, String?)> acquires = [];

  /// Runs inside [acquire], before the new lease is returned, like the real
  /// cache publishing to the item's other leases.
  void Function(String itemId)? onAcquire;

  /// The leases handed out for [itemId].
  List<FakeLease> leasesFor(String itemId) =>
      leases.where((l) => l.itemId == itemId).toList();

  @override
  ItemIconLease acquire(String itemId, String? iconLink) {
    acquires.add((itemId, iconLink));
    onAcquire?.call(itemId);
    final lease = FakeLease(itemId);
    leases.add(lease);
    return lease;
  }

  @override
  Future<void> open() async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
