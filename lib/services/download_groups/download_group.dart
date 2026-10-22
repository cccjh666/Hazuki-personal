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

  /// 磁盘目录名。默认组不使用子目录（文件直接放下载根目录）；
  /// 自定义组用固定前缀 + 去重的组名生成，保证跨重命名稳定。
  String get folderName {
    if (isDefault) return '';
    final sanitized = name.trim().replaceAll(
      RegExp(r'[\\/:*?"<>|\r\n\t]'),
      '_',
    );
    return 'Group_$sanitized';
  }
}
