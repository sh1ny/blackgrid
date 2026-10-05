import 'dart:convert';
import 'dart:io';

import 'contracts.dart';

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.length < 2) {
      throw const ContractException(
        'Usage: m0.dart validate RECORD [--freeze-id SHA256] [--source-root ROOT] | hash-lock LOCK [--write]',
      );
    }
    final command = arguments[0];
    final path = arguments[1];
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
            if (expectedFreezeId != null)
              throw const ContractException('Repeated --freeze-id');
            expectedFreezeId = value;
          } else {
            if (sourceRoot != null)
              throw const ContractException('Repeated --source-root');
            sourceRoot = value;
          }
        }
        validateRecord(decoded, expectedFreezeId: expectedFreezeId);
        if (sourceRoot != null)
          await verifySourceIntegrity(decoded, sourceRoot);
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
          await File(path).writeAsString('${canonicalJson(decoded)}\n');
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
