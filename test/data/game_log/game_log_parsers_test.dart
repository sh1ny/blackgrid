import 'dart:convert';

import 'package:blackgrid/data/game_log/game_log_parsers.dart';
import 'package:blackgrid/data/game_log/game_locations.dart';
import 'package:blackgrid/data/game_log/log_file_tail.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';
import 'package:test/test.dart';

const _app = '2026-10-28 19:41:06.991|1.2.5.0.48146|Info|application|';
const _backend = '2026-10-28 19:41:07.250|1.2.5.0.48146|Info|backend|';
const _push = '2026-10-28 19:41:08.100|1.2.5.0.48146|Info|push-notifications|';
const _roubles = '5449016a4bdc2d6f028b456f';
const _folder = 'log_2026.10.28_19-40-00_1.2.5.0.48146';

ParseResult _parse(LogFile file, String text, {int offset = 7}) =>
    parseGameLogRecord(_folder, file, TailRecord(offset, text));

RecordedGameLogEvent? _event(LogFile file, String text) =>
    switch (_parse(file, text)) {
      ParsedEvent(:final event) => event,
      _ => null,
    };

String _pushRecord(Object body) =>
    '${_push}Got notification | ChatMessageReceived\n'
    '${body is String ? body : const JsonEncoder.withIndent('  ').convert(body)}';

Map<String, Object?> _message(
  int type, {
  String? templateId,
  Map<String, Object?>? systemData,
  List<Object?>? items,
}) => {
  'type': 'new_message',
  'eventId': 'aaaaaaaaaaaaaaaaaaaaaaaa',
  'dialogId': 'bbbbbbbbbbbbbbbbbbbbbbbb',
  'message': {
    '_id': 'cccccccccccccccccccccccc',
    'uid': 'dddddddddddddddddddddddd',
    'type': type,
    'dt': 1761680000,
    'templateId': ?templateId,
    'systemData': ?systemData,
    if (items != null) 'items': {'data': items},
  },
};

void main() {
  group('application log', () {
    test('session mode and profile selected', () {
      final mode = _event(
        LogFile.application,
        '${_app}Session mode: PvpSeason',
      );
      expect(mode, isA<SessionModeChanged>());
      expect((mode! as SessionModeChanged).mode, GameMode.seasonal);
      expect(mode.id, const LogRecordId(_folder, LogFile.application, 7));
      expect(mode.time, DateTime(2026, 10, 28, 19, 41, 6, 991));
      expect(
        _event(
          LogFile.application,
          '${_app}PrepareSelectedProfileLocally ProfileId:0123456789abcdef01234567 AccountId:1234567',
        ),
        isA<ProfileSelected>(),
      );
    });

    test('transit reconnect line becomes raid rejoined', () {
      final event = _event(
        LogFile.application,
        '${_app}Transit reconnect status:MatchWait raidMode:Online '
        'location:bigmap settingsLocal:False',
      );
      expect(event, isA<RaidRejoined>());
      final rejoined = event! as RaidRejoined;
      expect(rejoined.status, 'MatchWait');
      expect(rejoined.location, 'bigmap');
      expect(rejoined.mapId, 'customs');
    });

    test('full raid lines in order', () {
      final lines = [
        '${_app}Matching with group id: 6601208',
        '${_app}scene preset path:maps/lighthouse_preset.bundle '
            'rcid:lighthouse.scenespreset.asset',
        '${_app}MatchingCompleted:89.19 real:97.16 diff:7.97',
        '${_app}GameStarting:150.37(26.13) real:164.48(26.56) diff:14.11',
        '${_app}GameStarted:161.35(10.98) real:176.48(12) diff:15.12',
      ];
      final events = [
        for (final line in lines) _event(LogFile.application, line),
      ];
      expect(events[0], isA<QueueEntered>());
      expect(events[1], isA<SceneLoaded>());
      expect((events[1]! as SceneLoaded).mapId, 'lighthouse');
      expect(events[2], isA<MatchFound>());
      expect(events[3], isA<RaidStarting>());
      expect(events[4], isA<RaidStarted>());
    });

    test('matching cancelled line', () {
      expect(
        _event(LogFile.application, '${_app}Network game matching cancelled.'),
        isA<MatchingAborted>(),
      );
    });

    test('unknown scene has no map', () {
      final event = _event(
        LogFile.application,
        '${_app}scene preset path:maps/unknown_place.bundle '
        'rcid:unknown.scenespreset.asset',
      );
      expect(event, isA<SceneLoaded>());
      expect((event! as SceneLoaded).mapId, isNull);
    });

    test('event presets map to Factory and The Lab', () {
      String? mapOf(String preset) =>
          (_event(
                    LogFile.application,
                    '${_app}scene preset path:maps/$preset.bundle rcid:x',
                  )!
                  as SceneLoaded)
              .mapId;
      expect(mapOf('factory_event_preset'), 'factory');
      expect(mapOf('laboratory_event_preset'), 'thelab');
    });

    test('rejoin locations are case-insensitive and cover every map', () {
      const expected = {
        'bigmap': 'customs',
        'TarkovStreets': 'streetsoftarkov',
        'Shoreline': 'shoreline',
        'RezervBase': 'reserve',
        'Lighthouse': 'lighthouse',
        'laboratory': 'thelab',
        'laboratory_event': 'thelab',
        'Interchange': 'interchange',
        'Woods': 'woods',
        'Sandbox': 'groundzero',
        'Sandbox_high': 'groundzero',
        'factory4_day': 'factory',
        'factory4_night': 'factory',
        'factory_event': 'factory',
        'Icebreaker': 'icebreaker',
        'BIGMAP': 'customs',
      };
      for (final MapEntry(:key, :value) in expected.entries) {
        expect(rejoinLocationMapId(key), value, reason: key);
      }
      expect(rejoinLocationMapId('nowhere'), isNull);
    });

    test('unrelated line produces nothing', () {
      final result = _parse(
        LogFile.application,
        '${_app}Reason:PacketsQueue, Position:(62.883, 10.690, -947.049), '
        'SpeedLimit:1.0595',
      );
      expect(result, isA<ParsedNothing>());
    });
  });

  group('backend log', () {
    String line(String payload) =>
        '${_backend}WebSocketSharp - binary message received: '
        'type=Notification, trackingId=abcdef0123456789, '
        'payloadType=$payload, payloadLength=393';

    test('userMatchOver line becomes raid exit', () {
      final event = _event(LogFile.backend, line('userMatchOver'));
      expect(event, isA<RaidExit>());
      expect((event! as RaidExit).time, DateTime(2026, 10, 28, 19, 41, 7, 250));
    });

    test('other payload types produce nothing', () {
      expect(
        _parse(LogFile.backend, line('groupMatchRaidReady')),
        isA<ParsedNothing>(),
      );
    });
  });

  group('push notifications', () {
    test('type 4 sale with roubles', () {
      final event = _event(
        LogFile.pushNotifications,
        _pushRecord(
          _message(
            4,
            systemData: {
              'soldItem': '5c94bbff86f7747ee735c08f',
              'itemCount': 2,
            },
            items: [
              {
                '_id': 'eeeeeeeeeeeeeeeeeeeeeeee',
                '_tpl': _roubles,
                'upd': {'StackObjectsCount': 206792},
              },
            ],
          ),
        ),
      );
      expect(event, isA<FleaSale>());
      final sale = event! as FleaSale;
      expect(sale.itemId, '5c94bbff86f7747ee735c08f');
      expect(sale.count, 2);
      expect(sale.roubles, 206792);
      expect(sale.time, DateTime(2026, 10, 28, 19, 41, 8, 100));
    });

    test('sale in another currency has no rouble amount', () {
      final event = _event(
        LogFile.pushNotifications,
        _pushRecord(
          _message(
            4,
            systemData: {
              'soldItem': '5c94bbff86f7747ee735c08f',
              'itemCount': 1,
            },
            items: [
              {
                '_id': 'eeeeeeeeeeeeeeeeeeeeeeee',
                '_tpl': '5696686a4bdc2da3298b456a',
                'upd': {'StackObjectsCount': 150},
              },
            ],
          ),
        ),
      );
      expect(event, isA<FleaSale>());
      expect((event! as FleaSale).roubles, isNull);
    });

    test('type 10, 11 and 12 task messages', () {
      const task = '5936d90786f7742b1420ba5b';
      final started = _event(
        LogFile.pushNotifications,
        _pushRecord(_message(10, templateId: '$task description')),
      );
      final failed = _event(
        LogFile.pushNotifications,
        _pushRecord(_message(11, templateId: '$task failMessageText')),
      );
      final finished = _event(
        LogFile.pushNotifications,
        _pushRecord(_message(12, templateId: '$task successMessageText')),
      );
      expect(failed, isA<TaskFailed>());
      expect((failed! as TaskFailed).taskId, task);
      expect(started, isA<TaskStarted>());
      expect((started! as TaskStarted).taskId, task);
      expect(finished, isA<TaskFinished>());
      expect((finished! as TaskFinished).taskId, task);
    });

    test('task message without an ID is rejected', () {
      final result = _parse(
        LogFile.pushNotifications,
        _pushRecord(_message(10, templateId: '')),
      );
      expect(result, isA<ParseRejected>());
      expect((result as ParseRejected).reason, GameLogRejection.missingTaskId);
    });

    test('invalid JSON body is rejected and later records parse', () {
      final bad = _parse(
        LogFile.pushNotifications,
        _pushRecord('{"type": "new_message", "message": '),
      );
      expect(bad, isA<ParseRejected>());
      expect((bad as ParseRejected).reason, GameLogRejection.invalidJson);
      final good = _parse(
        LogFile.pushNotifications,
        _pushRecord(
          _message(
            12,
            templateId: '5936d90786f7742b1420ba5b successMessageText',
          ),
        ),
        offset: 900,
      );
      expect(good, isA<ParsedEvent>());
    });

    test('Cyrillic text in a push body parses', () {
      final body = _message(
        12,
        templateId: '5936d90786f7742b1420ba5b successMessageText',
      );
      (body['message']! as Map<String, Object?>)['text'] = 'Сёма';
      final event = _event(LogFile.pushNotifications, _pushRecord(body));
      expect(event, isA<TaskFinished>());
    });

    test('other message types and notifications produce nothing', () {
      expect(
        _parse(LogFile.pushNotifications, _pushRecord(_message(1))),
        isA<ParsedNothing>(),
      );
      expect(
        _parse(
          LogFile.pushNotifications,
          '${_push}Got notification | UserConfirmed\n{}',
        ),
        isA<ParsedNothing>(),
      );
    });
  });
}
