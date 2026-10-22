import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hazuki/services/manga_download/download_group_folders.dart';

void main() {
  const folders = DownloadGroupFolders();
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hazuki-group-folders-');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  Directory dir(String name) => Directory('${root.path}/$name');

  Future<void> writeFile(String dirName, String fileName) async {
    final file = File('${root.path}/$dirName/$fileName');
    await file.parent.create(recursive: true);
    await file.writeAsString('x');
  }

  group('deleteIfEmpty', () {
    test('removes an empty folder so no stray group folder is left', () async {
      final folder = dir('Group_Reading');
      await folder.create();

      expect(await folders.deleteIfEmpty(folder), isTrue);
      expect(await folder.exists(), isFalse);
    });

    test('treats a missing folder as already cleaned', () async {
      expect(await folders.deleteIfEmpty(dir('Group_Missing')), isTrue);
    });

    test('keeps a non-empty folder instead of dropping user data', () async {
      await writeFile('Group_Reading', 'keep.txt');
      final folder = dir('Group_Reading');

      expect(await folders.deleteIfEmpty(folder), isFalse);
      expect(await folder.exists(), isTrue);
      expect(
        await File('${folder.path}/keep.txt').exists(),
        isTrue,
      );
    });
  });

  group('moveContents', () {
    test('renames the whole folder when the target does not exist', () async {
      await writeFile('Group_Old', 'comic/chapter.png');
      final moved = await folders.moveContents(
        dir('Group_Old'),
        dir('Group_New'),
      );

      expect(moved, isEmpty, reason: '整体重命名时没有逐个移动的条目');
      expect(await dir('Group_Old').exists(), isFalse);
      expect(
        await File('${dir('Group_New').path}/comic/chapter.png').exists(),
        isTrue,
      );
    });

    test('replaces an empty leftover target before renaming', () async {
      await writeFile('Group_Old', 'comic/chapter.png');
      await dir('Group_New').create();

      await folders.moveContents(dir('Group_Old'), dir('Group_New'));

      expect(await dir('Group_Old').exists(), isFalse);
      expect(
        await File('${dir('Group_New').path}/comic/chapter.png').exists(),
        isTrue,
      );
    });

    test('merges missing entries without overwriting existing ones', () async {
      await writeFile('Group_Old', 'kept/chapter.png');
      await writeFile('Group_Old', 'conflict/old.png');
      await writeFile('Group_New', 'conflict/new.png');

      final moved = await folders.moveContents(
        dir('Group_Old'),
        dir('Group_New'),
      );

      expect(moved, {'kept'});
      expect(
        await File('${dir('Group_New').path}/kept/chapter.png').exists(),
        isTrue,
      );
      // 同名目录留在原处，绝不覆盖另一组的数据
      expect(
        await File('${dir('Group_New').path}/conflict/new.png').exists(),
        isTrue,
      );
      expect(
        await File('${dir('Group_Old').path}/conflict/old.png').exists(),
        isTrue,
      );
    });

    test('does nothing when the source is already gone', () async {
      final moved = await folders.moveContents(
        dir('Group_Missing'),
        dir('Group_New'),
      );

      expect(moved, isEmpty);
      expect(await dir('Group_New').exists(), isFalse);
    });
  });
}
