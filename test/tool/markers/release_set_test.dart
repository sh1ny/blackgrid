import 'package:flutter_test/flutter_test.dart';

import '../../../tool/markers/icon_set.dart';

void main() {
  test('assets/map_markers manifest is a valid release set', () {
    final result = checkIconSet('assets/map_markers/manifest.json');

    switch (result) {
      case IconSetValid(:final set):
        expect(set.scope, IconSetScope.release);
        expect(set.icons.map((icon) => icon.key), unorderedEquals(iconKeys));
      case IconSetInvalid(:final failures):
        fail(failures.map(formatFailure).join('\n'));
    }
  });
}
