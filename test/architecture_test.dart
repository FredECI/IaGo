import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CA-R2: o domínio é Dart puro e o SDK de IA fica num lugar só.
List<File> _dartFiles(String dir) => [
  for (final e in Directory(dir).listSync(recursive: true))
    if (e is File && e.path.endsWith('.dart')) e,
];

String _norm(String path) => path.replaceAll(r'\', '/');

final _import = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

void main() {
  test('lib/domain não importa Flutter, material_ui nem firebase_*', () {
    final forbidden = RegExp(
      r'^(package:(flutter|flutter_riverpod|material_ui|firebase_[a-z_]+|'
      r'cloud_firestore)/|dart:(ui|html|js|js_interop))',
    );
    final violations = <String>[];
    final files = _dartFiles('lib/domain');
    expect(files, isNotEmpty);
    for (final f in files) {
      for (final m in _import.allMatches(f.readAsStringSync())) {
        final uri = m.group(1)!;
        if (forbidden.hasMatch(uri) ||
            uri.contains('/data/') ||
            uri.contains('/features/')) {
          violations.add('${_norm(f.path)} importa $uri');
        }
      }
    }
    expect(violations, isEmpty);
  });

  test('firebase_ai só aparece em lib/data/ai/gemini/', () {
    final violations = <String>[];
    for (final f in _dartFiles('lib')) {
      final path = _norm(f.path);
      if (path.contains('lib/data/ai/gemini/')) continue;
      for (final m in _import.allMatches(f.readAsStringSync())) {
        if (m.group(1)!.startsWith('package:firebase_ai/')) {
          violations.add('$path importa ${m.group(1)}');
        }
      }
    }
    expect(violations, isEmpty);
  });
}
