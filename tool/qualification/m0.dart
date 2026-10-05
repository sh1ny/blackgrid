import 'dart:convert';
import 'dart:io';

import 'contracts.dart';
import 'report.dart';

Future<void> _assertRegularLock(File target) async {
  var path = target.path;
  var first = true;
  while (true) {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.link ||
        (first && type != FileSystemEntityType.file)) {
      throw const ContractException(
        'Lock replacement requires a regular file without linked ancestry.',
      );
    }
    final parent = FileSystemEntity.parentOf(path);
    if (parent == path) {
      return;
    }
    path = parent;
    first = false;
  }
}

Future<void> _replaceLock(String path, String content) async {
  final target = File(path).absolute;
  await _assertRegularLock(target);
  final temporary = await target.parent.createTemp('.m0-lock-');
  try {
    final replacement = File('${temporary.path}/record.json');
    await replacement.writeAsString(content, flush: true);
    await _assertRegularLock(target);
    // The sibling stays on the same volume. Dart's Windows implementation uses
    // MoveFileExW with REPLACE_EXISTING; failure leaves the original in place.
    await replacement.rename(target.path);
  } finally {
    await temporary.delete(recursive: true);
  }
}

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.length < 2) {
      throw const ContractException(
        'Usage: m0.dart validate RECORD [--freeze-id SHA256] [--source-root ROOT] | hash-lock LOCK [--write] | report REQUEST --input-root ROOT --output-root NEW_DIRECTORY',
      );
    }
    final command = arguments[0];
    final path = arguments[1];
    if (command == 'report') {
      final options = <String, String>{};
      for (var index = 2; index < arguments.length; index += 2) {
        final option = arguments[index];
        if (!['--input-root', '--output-root'].contains(option) ||
            index + 1 >= arguments.length ||
            options.containsKey(option)) {
          throw ContractException('Invalid or repeated report option: $option');
        }
        options[option] = arguments[index + 1];
      }
      if (options.length != 2) {
        throw const ContractException(
          'Usage: report REQUEST --input-root ROOT --output-root NEW_DIRECTORY',
        );
      }
      await generateDossier(
        path,
        inputRoot: options['--input-root']!,
        outputRoot: options['--output-root']!,
      );
      stdout.writeln(canonicalJson({'generated': true}));
      return;
    }
    final decoded = jsonDecode(await File(path).readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const ContractException('Record must be a JSON object');
    }
    switch (command) {
      case 'validate':
        String? expectedFreezeId;
        String? sourceRoot;
        for (var index = 2; index < arguments.length; index++) {
          final option = arguments[index];
          if (!['--freeze-id', '--source-root'].contains(option) ||
              index + 1 >= arguments.length) {
            throw ContractException('Invalid validate option: $option');
          }
          final value = arguments[++index];
          if (option == '--freeze-id') {
            if (expectedFreezeId != null) {
              throw const ContractException('Repeated --freeze-id');
            }
            expectedFreezeId = value;
          } else {
            if (sourceRoot != null) {
              throw const ContractException('Repeated --source-root');
            }
            sourceRoot = value;
          }
        }
        validateRecord(decoded, expectedFreezeId: expectedFreezeId);
        if (sourceRoot != null) {
          await verifySourceIntegrity(decoded, sourceRoot);
        }
        stdout.writeln(
          canonicalJson({
            'valid': true,
            'id': decoded['id'],
            'record_type': decoded['record_type'],
            'integrity_checked': sourceRoot != null,
          }),
        );
      case 'hash-lock':
        if (arguments.length > 3 ||
            (arguments.length == 3 && arguments[2] != '--write')) {
          throw const ContractException('Usage: hash-lock LOCK [--write]');
        }
        final identity = sourceFreezeId(decoded);
        if (arguments.length == 3) {
          decoded['freeze_id'] = identity;
          validateRecord(decoded);
          await _replaceLock(path, '${canonicalJson(decoded)}\n');
        }
        stdout.writeln(identity);
      default:
        throw ContractException('Unknown command: $command');
    }
  } on ContractException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  } on FormatException catch (error) {
    stderr.writeln('Invalid JSON: ${error.message}');
    exitCode = 1;
  } on FileSystemException catch (error) {
    stderr.writeln(
      'Cannot read or write qualification record: ${error.message}',
    );
    exitCode = 1;
  }
}
