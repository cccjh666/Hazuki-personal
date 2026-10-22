import 'dart:io';

/// 分组子目录的磁盘操作。
///
/// 全部方法遵守同一条底线：**不覆盖、不递归删除非空目录**。
/// 只有确认目录为空时才删除，其余情况一律保留，宁可留下冗余目录
/// 也不能丢用户的漫画文件。
class DownloadGroupFolders {
  const DownloadGroupFolders();

  /// 目录为空时删除它。
  ///
  /// 返回 true 表示已删除或本来就不存在；false 表示目录非空被保留
  /// （组内还有搬迁失败的漫画，或用户手动放入的文件）。
  Future<bool> deleteIfEmpty(Directory dir) async {
    try {
      if (!await dir.exists()) return true;
      if (!await dir.list().isEmpty) return false;
      await dir.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 把 [from] 的直接子项移动到 [to]，目标已存在的同名项跳过（不覆盖）。
  ///
  /// 返回实际移动成功的子项名。
  Future<Set<String>> mergeInto(Directory from, Directory to) async {
    final moved = <String>{};
    try {
      if (!await to.exists()) await to.create(recursive: true);
    } catch (_) {
      return moved;
    }
    try {
      await for (final entity in from.list()) {
        final name = baseName(entity.path);
        if (name.isEmpty) continue;
        final targetPath = '${to.path}/$name';
        try {
          final targetExists = entity is Directory
              ? await Directory(targetPath).exists()
              : await File(targetPath).exists();
          if (targetExists) continue;
          await entity.rename(targetPath);
          moved.add(name);
        } catch (_) {
          // rename 跨卷失败时退化为「复制 + 删源」。
          try {
            if (entity is Directory) {
              await copyDirectoryRecursive(entity, Directory(targetPath));
              await entity.delete(recursive: true);
            } else if (entity is File) {
              await entity.copy(targetPath);
              await entity.delete();
            } else {
              continue;
            }
            moved.add(name);
          } catch (_) {}
        }
      }
    } catch (_) {}
    return moved;
  }

  /// 让 [from] 的内容落到 [to]。
  ///
  /// - [to] 不存在：整体重命名，返回空集合（表示全部搬走）；
  /// - [to] 存在但为空：先删掉再重命名；
  /// - [to] 非空：合并缺失子项，返回实际移动的子项名。
  ///
  /// 返回空集合既可能是「整体搬走」，也可能是「一个都没搬成」，
  /// 调用方应结合 [Directory.exists] 判断残留。
  Future<Set<String>> moveContents(Directory from, Directory to) async {
    if (!await from.exists()) return <String>{};
    // 目标组目录可能还不存在（该组刚建、还没有漫画落盘），先把父目录建好，
    // 否则整体 rename 会失败并退化到逐个移动，多绕一步。
    try {
      await to.parent.create(recursive: true);
    } catch (_) {}
    if (!await to.exists()) {
      try {
        await from.rename(to.path);
        return <String>{};
      } catch (_) {
        // 跨卷等无法整体 rename 的场景，退化为逐个移动。
        return mergeInto(from, to);
      }
    }
    if (await deleteIfEmpty(to)) {
      try {
        await from.rename(to.path);
        return <String>{};
      } catch (_) {
        // 目标已删但 rename 仍失败，继续走合并分支。
      }
    }
    return mergeInto(from, to);
  }

  static String baseName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/').where((part) => part.isNotEmpty);
    return parts.isEmpty ? '' : parts.last;
  }

  /// 递归复制目录内容，用于 rename 无法跨卷的场景。
  static Future<void> copyDirectoryRecursive(
    Directory from,
    Directory to,
  ) async {
    if (!await to.exists()) await to.create(recursive: true);
    await for (final entity in from.list()) {
      final targetPath = '${to.path}/${baseName(entity.path)}';
      if (entity is Directory) {
        await copyDirectoryRecursive(entity, Directory(targetPath));
      } else if (entity is File) {
        await entity.copy(targetPath);
      }
    }
  }
}
