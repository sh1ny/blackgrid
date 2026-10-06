import 'dart:convert';

Map<String, dynamic> decodeWireObject(String text) {
  final decoded = jsonDecode(text);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Invalid wire object');
  }
  // jsonDecode validates syntax but silently overwrites duplicate object keys.
  // Walk strings and container boundaries without allocating value substrings.
  final keys = <Set<String>?>[];
  final expectingKey = <bool>[];
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c == 123 || c == 91) {
      keys.add(c == 123 ? <String>{} : null);
      expectingKey.add(c == 123);
    } else if (c == 125 || c == 93) {
      keys.removeLast();
      expectingKey.removeLast();
    } else if (c == 44) {
      if (keys.isNotEmpty && keys.last != null) {
        expectingKey[expectingKey.length - 1] = true;
      }
    } else if (c == 34) {
      final start = i;
      var escaped = false;
      for (i++; i < text.length; i++) {
        final value = text.codeUnitAt(i);
        if (value == 92) {
          escaped = true;
          i++;
        } else if (value == 34) {
          break;
        }
      }
      if (keys.isNotEmpty && expectingKey.last) {
        final key = escaped
            ? jsonDecode(text.substring(start, i + 1)) as String
            : text.substring(start + 1, i);
        if (!keys.last!.add(key)) {
          throw const FormatException('Duplicate wire identity');
        }
        expectingKey[expectingKey.length - 1] = false;
      }
    }
  }
  return decoded;
}
