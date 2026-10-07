import 'package:blackgrid/application/launch_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> calls;
  late int? exitCode;

  Future<void> dispatch(List<String> args, {int selfCheckResult = 0}) =>
      dispatchLaunch(
        args,
        runUi: () => calls.add('ui'),
        selfCheck: (selfCheckArgs) async {
          calls.add('selfCheck:${selfCheckArgs.join(' ')}');
          return selfCheckResult;
        },
        exitProcess: (code) => exitCode = code,
      );

  setUp(() {
    calls = [];
    exitCode = null;
  });

  test('no arguments selects UI mode and never constructs runtime', () async {
    expect(resolveLaunchMode(const []), LaunchMode.ui);
    await dispatch(const []);
    expect(calls, ['ui']);
    expect(exitCode, isNull);
  });

  test(
    'unknown argument selects UI mode and never constructs runtime',
    () async {
      expect(resolveLaunchMode(const ['--other', 'x']), LaunchMode.ui);
      await dispatch(const ['--other', 'x']);
      expect(calls, ['ui']);
      expect(exitCode, isNull);
    },
  );

  test(
    'self-check flag selects self-check mode and exits with its code',
    () async {
      const args = ['--vision-self-check', r'C:\temp\vision.json'];
      expect(resolveLaunchMode(args), LaunchMode.visionSelfCheck);
      await dispatch(args, selfCheckResult: 3);
      expect(calls, [r'selfCheck:--vision-self-check C:\temp\vision.json']);
      expect(exitCode, 3);
    },
  );
}
