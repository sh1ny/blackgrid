import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../data/item_icon_client.dart';

/// What a lease shows.
sealed class ItemIconView {
  const ItemIconView();
}

/// The generic placeholder: no icon is available for the item.
final class GenericItemIcon extends ItemIconView {
  const GenericItemIcon();

  @override
  bool operator ==(Object other) => other is GenericItemIcon;

  @override
  int get hashCode => 0;
}

/// A complete icon file inside the cache folder.
final class ReadyItemIcon extends ItemIconView {
  const ReadyItemIcon(this.file);

  /// The stored icon. It is always a direct child of the cache folder.
  final File file;

  @override
  bool operator ==(Object other) =>
      other is ReadyItemIcon && other.file.path == file.path;

  @override
  int get hashCode => file.path.hashCode;
}

/// A hold on one item's icon. Release it when the item is no longer shown.
abstract interface class ItemIconLease
    implements ValueListenable<ItemIconView> {
  /// The item this lease holds.
  String get itemId;

  /// Gives the hold back. Calling it again does nothing.
  void release();
}

/// How long after a revalidation a shown icon is revalidated again.
const _revalidateAfter = Duration(days: 30);

/// How long a failed item and link are left alone.
const _failureWait = Duration(hours: 24);

/// A stored `lastShownAt` older than this is refreshed on the next show.
const _touchAfter = Duration(hours: 1);

final _storedName = RegExp(r'^[0-9a-f]{16}-[0-9a-f]{16}\.(webp|png|jpg)$');

/// Downloads item icons for the items being shown and keeps them on disk.
///
/// The cache is the only writer of its folder and of the `ItemIconRecords`
/// table, and the only caller of the icon client. Consumers call [acquire]
/// and read the returned lease; the cache shares one request per item,
/// cancels it when nothing holds the item, waits 24 hours after a failure,
/// revalidates shown icons every 30 days and stays within its byte budget.
class ItemIconCache {
  /// Creates a cache that stores icons in [directory].
  ///
  /// [clock] defaults to [DateTime.now]. The cache evicts the least recently
  /// shown icons when the stored bytes exceed [budgetBytes], and runs at most
  /// [maxConcurrent] requests at once.
  ItemIconCache({
    required BlackgridDatabase this._database,
    required ItemIconClient this._client,
    required Directory this._directory,
    DateTime Function()? clock,
    this._budgetBytes = 64 * 1024 * 1024,
    this._maxConcurrent = 4,
  }) : _clock = clock ?? DateTime.now,
       _enabled = true;

  /// Creates a cache that always shows the generic icon and sends nothing.
  ///
  /// [open] and [dispose] do nothing.
  ItemIconCache.disabled()
    : _database = null,
      _client = null,
      _directory = null,
      _clock = DateTime.now,
      _budgetBytes = 0,
      _maxConcurrent = 0,
      _enabled = false;

  final BlackgridDatabase? _database;
  final ItemIconClient? _client;
  final Directory? _directory;
  final DateTime Function() _clock;
  final int _budgetBytes;
  final int _maxConcurrent;
  final bool _enabled;

  final Map<String, ItemIconRecord> _rows = {};
  final Map<String, _Item> _items = {};
  final Queue<_Op> _queue = Queue();
  final List<Completer<void>> _idleWaiters = [];
  final Set<Future<void>> _fetches = {};
  Future<void> _writes = Future.value();
  int _running = 0;
  int _pendingWrites = 0;
  bool _opened = false;
  bool _disposed = false;

  /// Loads the index and removes stray files before any acquire is admitted.
  ///
  /// An acquire before this completes gives the generic icon and sends
  /// nothing. When the index or the folder cannot be read, this completes
  /// normally and the cache stays generic, so icons never stop start-up.
  Future<void> open() async {
    if (!_enabled || _opened || _disposed) return;
    try {
      await _load();
    } on Object catch (error) {
      debugPrint('Item icons disabled: cannot open the cache ($error)');
      _rows.clear();
      return;
    }
    if (_disposed) return;
    _opened = true;
  }

  Future<void> _load() async {
    final database = _database!;
    final directory = _directory!;
    final stored = await database.readItemIcons();
    await directory.create(recursive: true);
    final named = <String>{};
    for (final row in stored) {
      final name = row.fileName;
      if (name != null && !_storedName.hasMatch(name)) {
        _rows[row.itemId] = row.copyWith(
          fileName: const Value(null),
          byteSize: 0,
        );
        continue;
      }
      if (name != null) named.add(name);
      _rows[row.itemId] = row;
    }
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name.endsWith('.tmp') || !named.contains(name)) {
        await _delete(entity);
      }
    }
  }

  /// Holds the icon of [itemId] for [iconLink] until the lease is released.
  ///
  /// The lease shows the generic icon until a stored file exists for exactly
  /// this link. A null or unusable [iconLink], a cache that is not open, and a
  /// disposed or disabled cache all give a lease that stays generic.
  ItemIconLease acquire(String itemId, String? iconLink) {
    final uri = iconLink == null ? null : Uri.tryParse(iconLink);
    if (!_enabled ||
        !_opened ||
        _disposed ||
        iconLink == null ||
        uri == null ||
        !uri.isScheme('https') ||
        uri.host.isEmpty) {
      return _InertLease(itemId);
    }
    final item = _items.putIfAbsent(itemId, () => _Item(itemId));
    final lease = _Lease(this, item, iconLink);
    item.leases.add(lease);
    item.lastLink = iconLink;
    _checkFile(itemId, iconLink);
    _touch(itemId);
    _drive(item);
    return lease;
  }

  /// Cancels every request, then waits for the cancelled fetches to unwind and
  /// the queued writes to finish.
  ///
  /// Afterwards [acquire] gives the generic icon and nothing is sent. Leases
  /// still held may be released safely.
  Future<void> dispose() async {
    if (!_enabled || _disposed) return;
    _disposed = true;
    for (final item in _items.values) {
      _cancelOp(item);
    }
    _queue.clear();
    // The abort reaches the client only when each fetch has unwound, and the
    // caller closes the shared client right after this returns.
    await Future.wait(_fetches.toList());
    await _writes;
    _notifyIdle();
  }

  // ---- decisions ----

  String _currentLink(_Item item) =>
      item.leases.isEmpty ? item.lastLink : item.leases.last.link;

  bool _waiting(ItemIconRecord? row, String link) =>
      row != null &&
      row.failedLink == link &&
      row.failedUntil != null &&
      _clock().isBefore(row.failedUntil!);

  bool _revalidationDue(ItemIconRecord row) {
    final validated = row.validatedAt;
    return validated == null ||
        _clock().difference(validated) >= _revalidateAfter;
  }

  ItemIconView _viewFor(ItemIconRecord? row, String link) {
    final name = row?.fileName;
    if (row == null || name == null || row.iconLink != link) {
      return const GenericItemIcon();
    }
    return ReadyItemIcon(_fileFor(name));
  }

  void _publish(_Item item) {
    if (_disposed) return;
    final row = _rows[item.id];
    for (final lease in List.of(item.leases)) {
      lease._set(_viewFor(row, lease.link));
    }
  }

  /// Brings the item's work in line with its leases and stored state.
  void _drive(_Item item) {
    if (_disposed) return;
    _publish(item);
    if (item.leases.isEmpty) {
      _cancelOp(item);
      _forget(item);
      return;
    }
    final link = _currentLink(item);
    final op = item.op;
    if (op != null) {
      if (op.link == link || op.settling) return;
      if (item.leases.any((l) => l.link == op.link)) return;
      _cancelOp(item);
    }
    final row = _rows[item.id];
    if (_waiting(row, link)) return;
    if (row == null || row.fileName == null || row.iconLink != link) {
      _startOp(item, link, null);
    } else if (_revalidationDue(row)) {
      _startOp(item, link, row.etag);
    }
  }

  void _forget(_Item item) {
    if (item.leases.isEmpty &&
        item.op == null &&
        identical(_items[item.id], item)) {
      _items.remove(item.id);
    }
  }

  /// Resets a row whose file has vanished, so the item downloads again.
  void _checkFile(String itemId, String link) {
    final row = _rows[itemId];
    final name = row?.fileName;
    if (row == null || name == null || row.iconLink != link) return;
    if (_fileFor(name).existsSync()) return;
    _rows[itemId] = row.copyWith(
      fileName: const Value(null),
      byteSize: 0,
      etag: const Value(null),
      validatedAt: const Value(null),
    );
    _enqueue(() => _persist(itemId));
  }

  /// Refreshes `lastShownAt` at most once an hour per item.
  void _touch(String itemId) {
    final row = _rows[itemId];
    if (row == null || row.fileName == null) return;
    final now = _clock();
    if (now.difference(row.lastShownAt) <= _touchAfter) return;
    _rows[itemId] = row.copyWith(lastShownAt: now);
    _enqueue(() => _database!.touchItemIcon(itemId, now));
  }

  // ---- network operations ----

  void _startOp(_Item item, String link, String? etag) {
    final op = _Op(item, link, etag);
    item.op = op;
    _queue.add(op);
    _pump();
  }

  void _pump() {
    while (!_disposed && _running < _maxConcurrent && _queue.isNotEmpty) {
      final op = _queue.removeFirst();
      op.running = true;
      _running++;
      late final Future<void> fetch;
      fetch = _run(op).whenComplete(() => _fetches.remove(fetch));
      _fetches.add(fetch);
    }
  }

  Future<void> _run(_Op op) async {
    ItemIconFetchResult result;
    try {
      result = await _client!.fetch(
        Uri.parse(op.link),
        etag: op.etag,
        cancel: op.cancel.future,
      );
    } on Object {
      result = const IconFailed(IconFailureKind.transport);
    }
    _onResult(op, result);
  }

  /// Frees the op's slot, which a cancelled op holds until its fetch returns.
  void _onResult(_Op op, ItemIconFetchResult result) {
    op.running = false;
    _running--;
    if (op.cancelled) {
      _pump();
      _notifyIdle();
      return;
    }
    final item = op.item;
    if (_disposed) {
      if (identical(item.op, op)) item.op = null;
      _notifyIdle();
      return;
    }
    switch (result) {
      case IconFailed():
        item.op = null;
        _recordFailure(item.id, op.link);
        _enqueue(() => _persist(item.id));
        _drive(item);
      case IconCancelled():
        item.op = null;
        _drive(item);
      case IconFetched() || IconNotModified():
        op.settling = true;
        _enqueue(() => _settle(op, result));
    }
    _pump();
    _notifyIdle();
  }

  void _cancelOp(_Item item) {
    final op = item.op;
    if (op == null || op.settling) return;
    item.op = null;
    op.cancelled = true;
    if (op.running) {
      // The slot stays taken until the fetch unwinds; see [_onResult].
      if (!op.cancel.isCompleted) op.cancel.complete();
    } else {
      _queue.remove(op);
    }
    _pump();
    _notifyIdle();
  }

  void _release(_Lease lease) {
    final item = lease.item;
    item.leases.remove(lease);
    if (_disposed) return;
    _drive(item);
  }

  // ---- writes ----

  void _enqueue(Future<void> Function() task) {
    _pendingWrites++;
    _writes = _writes.then((_) async {
      try {
        await task();
      } on Object {
        // Icons are cosmetic: a failed write never reaches the user.
      } finally {
        _pendingWrites--;
        _notifyIdle();
      }
    });
  }

  void _notifyIdle() {
    if (_running != 0 || _pendingWrites != 0) return;
    for (final waiter in _idleWaiters.toList()) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _idleWaiters.clear();
  }

  Future<void> _idle() {
    if (_running == 0 && _pendingWrites == 0) return Future.value();
    final waiter = Completer<void>();
    _idleWaiters.add(waiter);
    return waiter.future;
  }

  /// Persists the in-memory row of [itemId] as it is when the write runs.
  Future<void> _persist(String itemId) async {
    final row = _rows[itemId];
    if (row == null) return;
    await _database!.upsertItemIcon(row.toCompanion(false));
  }

  /// Records the failure wait in memory first, before any database write.
  void _recordFailure(String itemId, String link) {
    final now = _clock();
    final base =
        _rows[itemId] ??
        ItemIconRecord(
          itemId: itemId,
          iconLink: link,
          byteSize: 0,
          lastShownAt: now,
        );
    _rows[itemId] = base.copyWith(
      failedUntil: Value(now.add(_failureWait)),
      failedLink: Value(link),
    );
  }

  Future<void> _settle(_Op op, ItemIconFetchResult result) async {
    final item = op.item;
    try {
      if (op.cancelled || op.link != _currentLink(item)) return;
      switch (result) {
        case IconFetched():
          await _store(item.id, op.link, result);
        case IconNotModified():
          await _validated(item.id, op.link);
        default:
          break;
      }
    } finally {
      if (identical(item.op, op)) item.op = null;
      if (!_disposed) _drive(item);
      _forget(item);
    }
  }

  /// A 304: refreshes the validation time without touching the file.
  ///
  /// A 304 is never a failure. When the file it confirms has gone meanwhile,
  /// this records nothing, and the caller's drive sends a plain GET.
  Future<void> _validated(String itemId, String link) async {
    final row = _rows[itemId];
    if (row == null || row.fileName == null || row.iconLink != link) return;
    final updated = row.copyWith(
      validatedAt: Value(_clock()),
      failedUntil: const Value(null),
      failedLink: const Value(null),
    );
    try {
      await _database!.upsertItemIcon(updated.toCompanion(false));
      _rows[itemId] = updated;
    } on Object {
      _recordFailure(itemId, link);
    }
  }

  Future<void> _store(String itemId, String link, IconFetched fetched) async {
    final now = _clock();
    final old = _rows[itemId];
    final name = _nameFor(itemId, fetched.bytes, fetched.format);
    final keep = old?.fileName == name && await _fileFor(name).exists();
    var wrote = false;
    try {
      if (!keep) {
        await _writeFile(name, fetched.bytes);
        wrote = true;
      }
      final row = ItemIconRecord(
        itemId: itemId,
        iconLink: link,
        fileName: name,
        byteSize: fetched.bytes.length,
        etag: fetched.etag,
        validatedAt: now,
        lastShownAt: now,
      );
      await _database!.upsertItemIcon(row.toCompanion(false));
      _rows[itemId] = row;
    } on Object {
      if (wrote) await _delete(_fileFor(name));
      _recordFailure(itemId, link);
      try {
        await _persist(itemId);
      } on Object {
        // The wait stays in memory for this process.
      }
      return;
    }
    final superseded = old?.fileName;
    if (superseded != null && superseded != name) {
      await _delete(_fileFor(superseded));
    }
    await _evict(itemId);
  }

  /// Removes the least recently shown icons until the budget holds.
  ///
  /// Never removes [keepId]. Items with a live lease go last.
  Future<void> _evict(String keepId) async {
    final stored = _rows.values.where((r) => r.fileName != null).toList();
    var total = stored.fold<int>(0, (sum, r) => sum + r.byteSize);
    if (total <= _budgetBytes) return;
    bool leased(ItemIconRecord r) =>
        _items[r.itemId]?.leases.isNotEmpty ?? false;
    final candidates = stored.where((r) => r.itemId != keepId).toList()
      ..sort((a, b) {
        final byLease = (leased(a) ? 1 : 0).compareTo(leased(b) ? 1 : 0);
        if (byLease != 0) return byLease;
        final byShown = a.lastShownAt.compareTo(b.lastShownAt);
        return byShown != 0 ? byShown : a.itemId.compareTo(b.itemId);
      });
    final victims = <ItemIconRecord>[];
    for (final row in candidates) {
      if (total <= _budgetBytes) break;
      victims.add(row);
      total -= row.byteSize;
    }
    if (victims.isEmpty) return;
    try {
      await _database!.deleteItemIcons(victims.map((r) => r.itemId));
    } on Object {
      return;
    }
    for (final row in victims) {
      _rows.remove(row.itemId);
      await _delete(_fileFor(row.fileName!));
      final item = _items[row.itemId];
      if (item != null) _publish(item);
    }
  }

  // ---- files ----

  File _fileFor(String name) =>
      File('${_directory!.path}${Platform.pathSeparator}$name');

  String _nameFor(String itemId, Uint8List bytes, IconFormat format) {
    String short(List<int> data) =>
        sha256.convert(data).toString().substring(0, 16);
    return '${short(utf8.encode(itemId))}-${short(bytes)}.${format.extension}';
  }

  /// Writes through a temporary file: write, flush, then rename.
  Future<void> _writeFile(String name, Uint8List bytes) async {
    final target = _fileFor(name);
    final tmp = _fileFor('$name.tmp');
    try {
      final handle = await tmp.open(mode: FileMode.write);
      try {
        await handle.writeFrom(bytes);
        await handle.flush();
      } finally {
        await handle.close();
      }
      await tmp.rename(target.path);
    } on Object {
      await _delete(tmp);
      rethrow;
    }
  }

  Future<void> _delete(FileSystemEntity entity) async {
    try {
      await entity.delete();
    } on Object {
      // A file that stays is removed by the next start-up sweep.
    }
  }
}

/// Completes when the cache has no running fetch and no queued write.
@visibleForTesting
Future<void> itemIconCacheIdle(ItemIconCache cache) => cache._idle();

/// The cache's state for one item.
class _Item {
  _Item(this.id);
  final String id;
  final LinkedHashSet<_Lease> leases = LinkedHashSet();
  String lastLink = '';
  _Op? op;
}

/// One queued, running or settling request.
class _Op {
  _Op(this.item, this.link, this.etag);
  final _Item item;
  final String link;
  final String? etag;
  final Completer<void> cancel = Completer();
  bool running = false;
  bool cancelled = false;
  bool settling = false;
}

/// A listenable that never asserts, so a release during a notification is safe.
class _Lease implements ItemIconLease {
  _Lease(this._cache, this.item, this.link);

  final ItemIconCache _cache;
  final _Item item;
  final String link;
  final List<VoidCallback> _listeners = [];
  ItemIconView _view = const GenericItemIcon();
  bool _released = false;

  @override
  String get itemId => item.id;

  @override
  ItemIconView get value => _view;

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  @override
  void release() {
    if (_released) return;
    _released = true;
    _cache._release(this);
  }

  void _set(ItemIconView view) {
    if (_released || view == _view) return;
    _view = view;
    for (final listener in List.of(_listeners)) {
      if (_listeners.contains(listener)) listener();
    }
  }
}

/// A lease that stays generic and holds nothing.
class _InertLease implements ItemIconLease {
  _InertLease(this.itemId);

  @override
  final String itemId;

  @override
  ItemIconView get value => const GenericItemIcon();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  void release() {}
}
