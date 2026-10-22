class DownloadGroup {
  const DownloadGroup({
    required this.id,
    required this.name,
    required this.createdAtMs,
    this.sortOrder = 0,
  });

  static const String defaultGroupId = 'default';
  static const String defaultGroupName = 'Default';

  final String id;
  final String name;
  final int createdAtMs;
  final int sortOrder;

  bool get isDefault => id == defaultGroupId;

  /// 由组名推导磁盘目录名。
  ///
  /// 非法文件名字符统一替换成下划线，因此「a:b」与「a_b」会落到同一个
  /// 目录——调用方判重时必须比较目录名而不是原始组名。
  static String folderNameForName(String name) {
    final sanitized = name.trim().replaceAll(
      RegExp(r'[\\/:*?"<>|\r\n\t]'),
      '_',
    );
    return 'Group_$sanitized';
  }

  /// 磁盘目录名。默认组不使用子目录（文件直接放下载根目录）；
  /// 自定义组用固定前缀 + 组名生成。
  String get folderName {
    if (isDefault) return '';
    return folderNameForName(name);
  }
}

/// 新建或重命名分组时，目标组名会与已有分组共用同一个磁盘目录。
///
/// 自定义分组的磁盘目录由组名派生（`Group_<组名>`），同名或清洗后同名的
/// 两个分组会落到同一个目录，导致两组漫画混在一起、删除其中一组时还会
/// 波及另一组。因此这类重名必须被拒绝。
class DuplicateDownloadGroupNameException implements Exception {
  const DuplicateDownloadGroupNameException({
    required this.requestedName,
    required this.existingName,
  });

  /// 用户本次输入的名称。
  final String requestedName;

  /// 已存在的、会造成目录冲突的分组名称。
  final String existingName;

  @override
  String toString() =>
      'DuplicateDownloadGroupNameException($requestedName conflicts with $existingName)';
}
