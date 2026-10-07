import 'package:xml/xml.dart';

List<String> svgLayerOrder(String source, Set<String> layerIds) => [
  for (final element in XmlDocument.parse(source).descendantElements)
    if (layerIds.contains(element.getAttribute('id')))
      element.getAttribute('id')!,
];

/// Binds every direct source floor and publisher-declared attachment to the
/// authored selection contract before splitting pictures.
void validateSvgFloorInventory(
  String source,
  List<Map<String, Object?>> floors,
) {
  final root = XmlDocument.parse(source).rootElement;
  final expectedRoots = <String>{
    for (final floor in floors) floor['id'] as String,
    for (final floor in floors)
      ...(floor['attachedIds'] as List).cast<String>(),
  };
  final actualRoots = <String>{};
  for (final group in root.childElements.where(
    (element) => element.name.local == 'g',
  )) {
    final id = group.getAttribute('id');
    if (id == null || !actualRoots.add(id)) {
      throw const FormatException('Anonymous or duplicated source floor group');
    }
  }
  if (actualRoots.length != expectedRoots.length ||
      !actualRoots.containsAll(expectedRoots)) {
    throw FormatException(
      'SVG floor closure changed; missing ${expectedRoots.difference(actualRoots)}, '
      'unowned ${actualRoots.difference(expectedRoots)}',
    );
  }
  final expectedAttachments = <String, String>{
    for (final floor in floors)
      for (final id in (floor['attachedIds'] as List).cast<String>())
        id: floor['id'] as String,
  };
  final actualAttachments = <String, String>{};
  for (final element in root.descendantElements) {
    final owner = element.getAttribute('data-keep-with-group');
    if (owner == null) continue;
    final id = element.getAttribute('id');
    if (id == null || id.isEmpty || actualAttachments.containsKey(id)) {
      throw const FormatException('Anonymous or duplicated attached layer');
    }
    actualAttachments[id] = owner;
  }
  if (actualAttachments.length != expectedAttachments.length ||
      expectedAttachments.entries.any(
        (entry) => actualAttachments[entry.key] != entry.value,
      )) {
    throw const FormatException('SVG attached layer ownership changed');
  }
}

/// Deleted publisher symbols whose dangling `<use>` references are dropped:
/// Customs `path493` (two uses) and Streets stairs (ten uses).
const droppedStaleSvgUseTargets = {
  'path493',
  'stairs-85',
  'stairs-86',
  'stairs-87',
  'stairs-90',
  'stairs-92',
};

/// Keeps the original root, defs, styles and ancestor tree. Excluded floors
/// referenced by a retained `<use>` remain as non-rendering definitions.
String normalizeSvgFloor(
  String source,
  Set<String> selected,
  Set<String> allFloors,
) {
  if (source.contains('<!DOCTYPE') || source.contains('<!ENTITY')) {
    throw const FormatException(
      'SVG entities and external doctypes are unsupported',
    );
  }
  final document = XmlDocument.parse(source);
  final root = document.rootElement;
  if (root.name.local != 'svg') {
    throw const FormatException('Expected SVG root');
  }
  final elements = [root, ...root.descendantElements];
  final ids = <String, XmlElement>{};
  for (final element in elements) {
    final id = element.getAttribute('id');
    if (id != null && ids.containsKey(id)) {
      throw FormatException('Duplicate SVG id $id');
    }
    if (id != null) ids[id] = element;
    if ([
      'image',
      'script',
      'foreignObject',
      'filter',
    ].contains(element.name.local)) {
      throw FormatException('Unsupported vector element ${element.name.local}');
    }
    for (final attribute in element.attributes) {
      if (attribute.name.local == 'href' && !attribute.value.startsWith('#')) {
        throw FormatException('Unsafe external SVG href ${attribute.value}');
      }
      if (attribute.name.local.startsWith('on')) {
        throw const FormatException('SVG event handlers are unsupported');
      }
    }
  }
  for (final id in selected) {
    if (!ids.containsKey(id)) {
      throw FormatException('Missing required SVG floor $id');
    }
  }
  // A <use> whose local target is absent renders nothing in browsers. The
  // publisher's Streets and Customs artwork ship stale references to these
  // deleted symbols, and the reference WebView rendering omits them. Drop only
  // these known ids so any other lost symbol still fails dependency closure.
  for (final element in elements.toList()) {
    if (element.name.local != 'use') continue;
    final href = element.attributes
        .where((attribute) => attribute.name.local == 'href')
        .map((attribute) => attribute.value)
        .toList();
    if (href.length != 1) continue;
    final target = href.single.substring(1);
    if (!ids.containsKey(target) &&
        droppedStaleSvgUseTargets.contains(target)) {
      element.parent!.children.remove(element);
      elements.remove(element);
      ids.remove(element.getAttribute('id'));
    }
  }
  final references = <String>{};
  final localUrl = RegExp(r'''url\(\s*['"]?(#[\w:.-]+)['"]?\s*\)''');
  for (final element in elements) {
    for (final attribute in element.attributes) {
      if (attribute.name.local == 'href') {
        references.add(attribute.value.substring(1));
      }
      if (attribute.value.contains('url(')) {
        final matches = localUrl.allMatches(attribute.value).toList();
        if (matches.isEmpty ||
            matches.length !=
                RegExp(r'url\s*\(').allMatches(attribute.value).length) {
          throw FormatException('Unsafe SVG resource ${attribute.value}');
        }
        for (final match in matches) {
          references.add(match.group(1)!.substring(1));
        }
      }
    }
  }
  for (final id in references) {
    if (!ids.containsKey(id)) {
      throw FormatException('Missing SVG dependency #$id');
    }
  }
  final rules = <({String selector, Map<String, String> declarations})>[];
  for (final style in elements.where((e) => e.name.local == 'style')) {
    final css = style.innerText.replaceAll(
      RegExp(r'/\*.*?\*/', dotAll: true),
      '',
    );
    final matches = RegExp(r'([^{}]+)\{([^{}]*)\}').allMatches(css).toList();
    final remainder = css
        .replaceAll(RegExp(r'([^{}]+)\{([^{}]*)\}'), '')
        .trim();
    if (remainder.isNotEmpty) {
      throw FormatException('Unsupported CSS $remainder');
    }
    for (final match in matches) {
      for (final selector in match.group(1)!.split(',')) {
        final clean = selector.trim();
        if (!RegExp(r'^\.[\w-]+$').hasMatch(clean)) {
          throw FormatException('Unsupported CSS selector $clean');
        }
        rules.add((
          selector: clean.substring(1),
          declarations: _declarations(match.group(2)!),
        ));
      }
    }
  }
  for (final element in elements) {
    final classes = (element.getAttribute('class') ?? '')
        .split(RegExp(r'\s+'))
        .toSet();
    final declarations = <String, String>{};
    for (final rule in rules) {
      if (classes.contains(rule.selector)) {
        declarations.addAll(rule.declarations);
      }
    }
    // CSS beats presentation attributes; inline style beats the simple class
    // selectors present in the pinned source. Reject unsupported selectors.
    declarations.addAll(_declarations(element.getAttribute('style') ?? ''));
    for (final entry in declarations.entries) {
      if (entry.key == 'filter') {
        if (entry.value != 'drop-shadow(0 0 2px #000)') {
          throw FormatException(
            'Unsupported essential SVG filter ${entry.value}',
          );
        }
      }
      if (entry.value.contains('url')) {
        final matches = localUrl.allMatches(entry.value).toList();
        if (matches.isEmpty ||
            matches.length !=
                RegExp(r'url\s*\(').allMatches(entry.value).length) {
          throw FormatException('Unsafe CSS resource ${entry.value}');
        }
        for (final match in matches) {
          final dependency = match.group(1)!.substring(1);
          if (!ids.containsKey(dependency)) {
            throw FormatException('Missing CSS dependency #$dependency');
          }
          references.add(dependency);
        }
      }
      element.setAttribute(entry.key, entry.value);
    }
    element.removeAttribute('style');
  }
  for (final id in allFloors.difference(selected)) {
    final floor = ids[id];
    if (floor == null) continue;
    // A referenced group is a complete dependency: pruning independently
    // listed components beneath it would silently empty a retained <use>.
    if (floor.ancestors.whereType<XmlElement>().any(
      (ancestor) => references.contains(ancestor.getAttribute('id')),
    )) {
      continue;
    }
    // A selected feature component keeps its floor ancestor's inherited
    // transform/paint context. Only its sibling components are excluded.
    if (floor.descendantElements.any(
      (e) => selected.contains(e.getAttribute('id')),
    )) {
      continue;
    }
    final floorIds = {
      id,
      for (final e in floor.descendantElements)
        if (e.getAttribute('id') != null) e.getAttribute('id')!,
    };
    if (references.intersection(floorIds).isEmpty) {
      floor.parent!.children.remove(floor);
    } else {
      final parent = floor.parent!;
      final index = parent.children.indexOf(floor);
      parent.children.remove(floor);
      parent.children.insert(index, XmlElement(XmlName('defs'), [], [floor]));
    }
  }
  // Source floor toggles are replaced by explicit component selection.
  for (final id in selected) {
    final component = ids[id]!;
    for (final element in [
      component,
      ...component.ancestors.whereType<XmlElement>(),
    ]) {
      if (selected.contains(element.getAttribute('id')) ||
          allFloors.contains(element.getAttribute('id'))) {
        element.removeAttribute('display');
        element.removeAttribute('visibility');
      }
    }
  }
  return document.toXmlString();
}

Map<String, String> _declarations(String text) {
  final result = <String, String>{};
  for (final declaration in text.split(';')) {
    if (declaration.trim().isEmpty) continue;
    final separator = declaration.indexOf(':');
    if (separator < 1) {
      throw FormatException('Invalid SVG CSS declaration $declaration');
    }
    final key = declaration.substring(0, separator).trim();
    final value = declaration.substring(separator + 1).trim();
    if (value.contains('!important')) {
      throw const FormatException(
        'CSS important declarations need qualification',
      );
    }
    result[key] = value;
  }
  return result;
}

/// Transfers only the source's exact, floor-scoped drop-shadow to the native
/// renderer. Everything else stays vector; no blur is silently discarded.
({String xml, List<Map<String, Object?>> effects}) compilerSvg(
  String normalized,
  String componentId,
) {
  final document = XmlDocument.parse(normalized);
  final effects = <Map<String, Object?>>[];
  for (final element in document.descendantElements.toList()) {
    // The strict compiler handles paired definitions but rejects <defs/>.
    // Keep the definition tree and identities unchanged.
    if (element.name.local == 'defs') element.isSelfClosing = false;
    if (element.name.local == 'style') {
      element.parent!.children.remove(element);
      continue;
    }
    final filter = element.getAttribute('filter');
    if (filter != null) {
      if (element.getAttribute('id') != componentId ||
          filter != 'drop-shadow(0 0 2px #000)') {
        // Filters within non-rendering definitions still matter if referenced.
        throw FormatException(
          'Essential filter outside qualified component $componentId',
        );
      }
      effects.add({
        'type': 'drop-shadow',
        'dx': 0,
        'dy': 0,
        'sigma': 2,
        'color': '#000000',
        'sourceDeclaration': filter,
      });
      element.removeAttribute('filter');
    }
  }
  return (xml: document.toXmlString(), effects: effects);
}

Map<String, Object?> svgFrame(String source) {
  final root = XmlDocument.parse(source).rootElement;
  final viewBox = (root.getAttribute('viewBox') ?? '')
      .split(RegExp(r'[\s,]+'))
      .map(double.tryParse)
      .toList();
  if (viewBox.length != 4 ||
      viewBox.any((v) => v == null || !v.isFinite) ||
      viewBox[2]! <= 0 ||
      viewBox[3]! <= 0) {
    throw const FormatException('Missing valid SVG viewBox');
  }
  return {'width': viewBox[2], 'height': viewBox[3], 'viewBox': viewBox};
}
