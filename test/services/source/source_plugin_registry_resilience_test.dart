import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hazuki/services/source/plugins/source_plugin_manager.dart';
import 'package:hazuki/services/source/plugins/source_plugin_repository.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('hazuki_plugin_registry_');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  SourcePluginManager buildManager() => SourcePluginManager(
    directory: () async => root,
    legacyDirectories: const [],
  );

  File registryFile() =>
      File(p.join(root.path, SourcePluginManager.installedPluginsFileName));

  List<File> quarantineFiles() => root
      .listSync()
      .whereType<File>()
      .where((file) => file.path.contains('.corrupt-'))
      .toList();

  Map<String, dynamic> goodRecord(String id) => {
    'manifest': {
      'id': id,
      'name': id.toUpperCase(),
      'version': '1.0.0',
      'apiVersion': 1,
      'entry': '$id.js',
    },
    'directory': '$id-1',
    'enabled': true,
  };

  test('a corrupt registry is quarantined instead of breaking startup', () async {
    registryFile().writeAsStringSync('{"schemaVersion": 1, "installed": [');

    final manager = buildManager();
    addTearDown(manager.dispose);
    await manager.initialize();

    expect(manager.installed, isEmpty);
    expect(quarantineFiles(), hasLength(1));
    expect(registryFile().existsSync(), isFalse);
    // 默认仓库仍然可用，插件页可以正常进入并重新安装。
    expect(manager.repositories, contains(sourcePluginsRepositoryUrl));
  });

  test('a registry with an unknown schema is quarantined too', () async {
    registryFile().writeAsStringSync('{"schemaVersion": 99}');

    final manager = buildManager();
    addTearDown(manager.dispose);
    await manager.initialize();

    expect(manager.installed, isEmpty);
    expect(quarantineFiles(), hasLength(1));
  });

  test('one damaged plugin record does not drop the healthy ones', () async {
    registryFile().writeAsStringSync(
      jsonEncode({
        'schemaVersion': 1,
        'installed': [
          goodRecord('jm'),
          // directory 非法：解析会抛 plugin_invalid_store。
          {
            'manifest': {
              'id': 'broken',
              'name': 'Broken',
              'version': '1.0.0',
              'entry': 'broken.js',
            },
            'directory': '../escape',
          },
          goodRecord('copy'),
        ],
        'repositories': <String>[],
        'plugins': <Map<String, dynamic>>[],
      }),
    );

    final manager = buildManager();
    addTearDown(manager.dispose);
    await manager.initialize();

    expect(
      manager.installed.map((plugin) => plugin.manifest.id),
      containsAll(<String>['jm', 'copy']),
    );
    expect(manager.errors['broken'], 'plugin_record_invalid');
    // 健康插件的脚本文件不存在，只应记 entry_missing，不影响安装记录。
    expect(manager.errors['jm'], 'plugin_entry_missing');
  });
}
