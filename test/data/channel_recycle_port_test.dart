import 'package:blackgrid/application/recycle_port.dart';
import 'package:blackgrid/data/channel_recycle_port.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('blackgrid/recycle');

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall) answer;

  setUp(() {
    calls = [];
    answer = (_) async => null;
    messenger.setMockMethodCallHandler(_channel, (call) {
      calls.add(call);
      return answer(call);
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  test(
    'recycle sends folder and names and maps every status in request order',
    () async {
      final names = ['a.png', 'b.png', 'c.png', 'd.png', 'e.png', 'f.png'];
      answer = (_) async => [
        {'name': 'f.png', 'status': 'cancelled'},
        {'name': 'e.png', 'status': 'failed'},
        {'name': 'd.png', 'status': 'rejected'},
        {'name': 'c.png', 'status': 'notRecyclable'},
        {'name': 'b.png', 'status': 'missing'},
        {'name': 'a.png', 'status': 'moved'},
      ];

      final result = await ChannelRecyclePort().recycle(r'C:\screens', names);

      expect(calls.single.method, 'recycle');
      expect(calls.single.arguments, {'folder': r'C:\screens', 'names': names});
      expect(result, isA<RecycleStatuses>());
      final statuses = (result as RecycleStatuses).statuses;
      expect(statuses.keys.toList(), names);
      expect(statuses['a.png'], isA<RecycleMoved>());
      expect(statuses['b.png'], isA<RecycleMissing>());
      expect(statuses['c.png'], isA<RecycleNotRecyclable>());
      expect(statuses['d.png'], isA<RecycleRejected>());
      expect(statuses['e.png'], isA<RecycleFailed>());
      expect(statuses['f.png'], isA<RecycleCancelled>());
    },
  );

  test('cancel sends no arguments', () async {
    await ChannelRecyclePort().cancel();
    expect(calls.single.method, 'cancel');
    expect(calls.single.arguments, isNull);
  });

  test('accepts the maximum batch of 64 names', () async {
    final names = List.generate(64, (i) => '$i.png');
    answer = (_) async => [
      for (final name in names) {'name': name, 'status': 'missing'},
    ];
    final result = await ChannelRecyclePort().recycle('folder', names);
    expect(result, isA<RecycleStatuses>());
    expect((result as RecycleStatuses).statuses.length, 64);
    expect(calls.single.method, 'recycle');
  });

  test('rejects batches over 64 without invoking the channel', () async {
    final names = List.generate(65, (i) => '$i.png');
    expect(
      await ChannelRecyclePort().recycle('folder', names),
      isA<RecycleCallFailure>(),
    );
    expect(calls, isEmpty);
  });

  group('malformed replies fail the whole call', () {
    final invalidReplies = <String, Object?>{
      'null': null,
      'non-list': 'moved',
      'non-map entry': ['moved'],
      'missing name': [
        <String, Object?>{'status': 'moved'},
      ],
      'missing status': [
        <String, Object?>{'name': 'a.png'},
      ],
      'non-string name': [
        <String, Object?>{'name': 1, 'status': 'moved'},
      ],
      'non-string status': [
        <String, Object?>{'name': 'a.png', 'status': 1},
      ],
      'unknown status': [
        <String, Object?>{'name': 'a.png', 'status': 'other'},
      ],
      'unknown name': [
        <String, Object?>{'name': 'other.png', 'status': 'moved'},
      ],
      'missing entry': <Object?>[],
      'duplicate entry': [
        <String, Object?>{'name': 'a.png', 'status': 'moved'},
        <String, Object?>{'name': 'a.png', 'status': 'missing'},
      ],
    };
    for (final entry in invalidReplies.entries) {
      test(entry.key, () async {
        answer = (_) async => entry.value;
        expect(
          await ChannelRecyclePort().recycle('folder', ['a.png']),
          isA<RecycleCallFailure>(),
        );
      });
    }
  });

  test('platform exception becomes call failure', () async {
    answer = (_) async => throw PlatformException(code: 'busy');
    expect(
      await ChannelRecyclePort().recycle('folder', ['a.png']),
      isA<RecycleCallFailure>(),
    );
  });

  test('missing plugin becomes call failure', () async {
    messenger.setMockMethodCallHandler(_channel, null);
    expect(
      await ChannelRecyclePort().recycle('folder', ['a.png']),
      isA<RecycleCallFailure>(),
    );
  });
}
