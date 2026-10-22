import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:hazuki/l10n/l10n.dart';
import 'package:hazuki/services/source/source_capabilities.dart';
import 'package:hazuki/services/manga_download/manga_download_library.dart';
import 'package:hazuki/services/download_groups/download_groups_repository.dart';
import '../support/downloads_actions.dart';

class UpdateComicGroupsResult {
  const UpdateComicGroupsResult({
    required this.changed,
    this.addedGroupIds = const {},
    this.removedGroupIds = const {},
  });

  final bool changed;
  final Set<String> addedGroupIds;
  final Set<String> removedGroupIds;
}

class UpdateSelectedComicGroupsResult {
  const UpdateSelectedComicGroupsResult({
    required this.comicCount,
    required this.changedGroupCount,
  });

  final int comicCount;
  final int changedGroupCount;
}

/// 批量删除的结果，用于给出「删了几部 / 几部没删掉」的反馈。
class DownloadsBatchDeleteResult {
  const DownloadsBatchDeleteResult({
    required this.requested,
    required this.failed,
  });

  final int requested;
  final int failed;

  int get deleted => requested - failed;
  bool get hasFailure => failed > 0;
}

/// 正在执行的批量操作类型，用来区分「删除中」和「移动中」的 UI 表现。
enum _BatchBusyKind { delete, move }

class DownloadsPageController extends ChangeNotifier {
  DownloadsPageController({
    required MangaDownloadLibrary downloadService,
    required DownloadGroupsRepository downloadGroupsService,
  }) : _downloadService = downloadService,
       _downloadGroupsService = downloadGroupsService {
    _downloadService.addListener(_handleDownloadsChanged);
    _downloadGroupsService.addListener(_handleGroupsChanged);
  }

  final MangaDownloadLibrary _downloadService;
  final DownloadGroupsRepository _downloadGroupsService;
  String _selectedGroupId = DownloadGroup.defaultGroupId;
  String _searchQuery = '';
  bool _reconcilingGroups = false;

  List<MangaDownloadTask> get tasks =>
      List.unmodifiable(_downloadService.tasks);
  List<DownloadGroup> get groups => _downloadGroupsService.groups;
  String get selectedGroupId => _selectedGroupId;
  DownloadGroup get selectedGroup => groups.firstWhere(
    (group) => group.id == _selectedGroupId,
    orElse: () => const DownloadGroup(
      id: DownloadGroup.defaultGroupId,
      name: DownloadGroup.defaultGroupName,
      createdAtMs: 0,
    ),
  );
  String get searchQuery => _searchQuery;

  void setSearchQuery(String query) {
    final next = query.trim();
    if (_searchQuery == next) return;
    _searchQuery = next;
    _notify();
  }

  /// 已下载 key 集合缓存：页面每次重建都会为「每个分组」算一次计数，旧实现
  /// 每次都要 `.map(...).toSet()` 重建集合（N+1 次 O(M)）。现在只在下载
  /// 状态变化时重建一次。
  Set<String>? _downloadedKeysCache;
  int _downloadedKeysStamp = -1;
  int _downloadsRevision = 0;

  Set<String> get _downloadedKeys {
    final cached = _downloadedKeysCache;
    if (cached != null && _downloadedKeysStamp == _downloadsRevision) {
      return cached;
    }
    final keys = <String>{
      for (final comic in _downloadService.downloadedComics) comic.storageKey,
    };
    _downloadedKeysCache = keys;
    _downloadedKeysStamp = _downloadsRevision;
    return keys;
  }

  int comicCountForGroup(String groupId) {
    final downloadedKeys = _downloadedKeys;
    return _downloadGroupsService
        .comicKeysForGroup(groupId)
        .where(downloadedKeys.contains)
        .length;
  }

  /// 分组 → 漫画数量（分类面板一次性用到全部计数）。
  Map<String, int> get groupComicCounts => {
    for (final group in groups) group.id: comicCountForGroup(group.id),
  };

  /// Group the comic currently belongs to; a comic is only ever in one group.
  String? groupIdForComic(DownloadedMangaComic comic) =>
      _downloadGroupsService.primaryGroupIdForComic(comic.storageKey);

  /// The single group shared by every selected comic, or `null` when the
  /// selection spans multiple groups (so no radio can be pre-checked).
  String? get commonSelectedGroupId {
    String? common;
    var first = true;
    for (final key in _selectedComicIds) {
      final groupId = _downloadGroupsService.primaryGroupIdForComic(key);
      if (first) {
        common = groupId;
        first = false;
        continue;
      }
      if (common != groupId) return null;
    }
    return common;
  }

  List<DownloadedMangaComic> get selectedDownloadedComics {
    return _downloadService.downloadedComics
        .where((comic) => _selectedComicIds.contains(comic.storageKey))
        .toList(growable: false);
  }

  /// 检索用小写索引缓存：旧实现每次过滤都要对标题/作者/标签逐个
  /// `toLowerCase()`，分组切换与每次输入都会重跑一遍。这里按
  /// （storageKey, updatedAtMillis）缓存拼好的小写干草堆。
  final Map<String, _ComicSearchIndex> _searchIndexCache = {};
  static const int _searchIndexCacheLimit = 4096;

  String _searchHaystackFor(DownloadedMangaComic comic) {
    final cached = _searchIndexCache[comic.storageKey];
    if (cached != null && cached.stamp == comic.updatedAtMillis) {
      return cached.haystack;
    }
    final buffer = StringBuffer()
      ..write(comic.title.toLowerCase())
      ..write('\u0001')
      ..write(comic.subTitle.toLowerCase())
      ..write('\u0001')
      ..write(comic.uploader.toLowerCase());
    for (final entry in comic.tags.entries) {
      buffer
        ..write('\u0001')
        ..write(entry.key.toLowerCase());
      for (final value in entry.value) {
        buffer
          ..write('\u0001')
          ..write(value.toLowerCase());
      }
    }
    final haystack = buffer.toString();
    if (_searchIndexCache.length >= _searchIndexCacheLimit) {
      _searchIndexCache.clear();
    }
    _searchIndexCache[comic.storageKey] = _ComicSearchIndex(
      stamp: comic.updatedAtMillis,
      haystack: haystack,
    );
    return haystack;
  }

  List<DownloadedMangaComic> get filteredDownloadedComics {
    final keys = _downloadGroupsService.comicKeysForGroup(_selectedGroupId);
    final query = _searchQuery.toLowerCase();
    return _downloadService.downloadedComics
        .where((comic) {
          if (!keys.contains(comic.storageKey)) return false;
          if (query.isEmpty) return true;
          return _searchHaystackFor(comic).contains(query);
        })
        .toList(growable: false);
  }

  final Set<String> _selectedComicIds = <String>{};
  bool _selectionEnabled = false;
  bool _scanningDownloaded = false;
  bool _checkingIntegrity = false;
  bool _batchBusy = false;
  _BatchBusyKind? _batchBusyKind;
  bool _disposed = false;
  Set<String> _comicsWithIntegrityIssues = const {};

  /// 只读视图，不复制集合。卡片在列表里逐项判断选中状态，
  /// 旧实现每次调用都 `Set.unmodifiable` 复制一份（O(选中数) × 可见卡片数）。
  Set<String> get selectedComicIds => UnmodifiableSetView(_selectedComicIds);
  int get selectedCount => _selectedComicIds.length;
  bool get scanningDownloaded => _scanningDownloaded;

  /// 批量操作进行中（删除/移动），用于禁用按钮防止重复触发。
  bool get batchBusy => _batchBusy;

  /// 是否正在批量删除（决定删除按钮要不要显示进度圈，移动分组时不该显示）。
  bool get deletingSelection => _batchBusyKind == _BatchBusyKind.delete;
  Set<String> get comicsWithIntegrityIssues =>
      Set<String>.unmodifiable(_comicsWithIntegrityIssues);

  Future<void> initialize() async {
    await _downloadService.ensureInitialized();
    await _downloadGroupsService.initialize(
      _downloadService.downloadedComics.map((comic) => comic.storageKey),
      migratedComicKeys: _legacyComicKeyMigrations,
    );
  }

  Map<String, String> get _legacyComicKeyMigrations => {
    for (final comic in _downloadService.downloadedComics)
      if (isHazukiJmSourceKey(comic.sourceKey)) comic.comicId: comic.storageKey,
  };

  void selectGroup(String groupId) {
    if (_selectedGroupId == groupId) return;
    _selectedGroupId = groupId;
    _clearSelection(notify: false);
    _notify();
  }

  Future<DownloadGroup> createGroup(String name) =>
      _downloadGroupsService.createGroup(name);

  Future<DownloadGroup> renameGroup(String groupId, String name) async {
    final previous = groups.firstWhere(
      (group) => group.id == groupId,
      orElse: () => selectedGroup,
    );
    final previousFolder = previous.isDefault ? null : previous.folderName;
    final renamed = await _downloadGroupsService.renameGroup(groupId, name);
    if (previousFolder != null && renamed.folderName != previousFolder) {
      await _downloadService.renameGroupFolder(
        previousFolder,
        renamed.folderName,
      );
    }
    return renamed;
  }

  Future<void> reorderGroups(List<String> orderedGroupIds) =>
      _downloadGroupsService.reorderGroups(orderedGroupIds);

  Future<void> deleteGroup(String groupId) async {
    // 删除前先记下磁盘目录名：删除后 groups 里已经没有这个组了。
    DownloadGroup? deletingGroup;
    for (final group in groups) {
      if (group.id == groupId) {
        deletingGroup = group;
        break;
      }
    }
    final folderName = (deletingGroup == null || deletingGroup.isDefault)
        ? null
        : deletingGroup.folderName;

    final affectedKeys = _downloadGroupsService.comicKeysForGroup(groupId);
    await _downloadGroupsService.deleteGroup(groupId);
    if (_selectedGroupId == groupId) {
      _selectedGroupId = DownloadGroup.defaultGroupId;
    }
    for (final storageKey in affectedKeys) {
      await _syncComicDiskLocation(storageKey);
    }
    // 成员搬回默认组之后再删组目录，否则目录非空删不掉。目录里若仍有
    // 搬迁失败的漫画或用户手动放入的文件，会被保留而不是一并删除。
    if (folderName != null) {
      await _downloadService.removeGroupFolder(folderName);
    }
    _notify();
  }

  String? _groupFolderNameFor(String? groupId) {
    if (groupId == null) return null;
    for (final group in groups) {
      if (group.isDefault) continue;
      if (group.id == groupId) return group.folderName;
    }
    return null;
  }

  Future<void> _syncComicDiskLocation(String storageKey) async {
    await _downloadService.moveDownloadedComicToGroup(
      storageKey,
      _groupFolderNameFor(
        _downloadGroupsService.primaryGroupIdForComic(storageKey),
      ),
    );
  }

  /// Moves [comic] into [groupId], replacing any previous membership.
  ///
  /// A comic lives in exactly one group, so the move is a full replacement and
  /// the on-disk folder is relocated instead of copied (no duplicate files).
  Future<UpdateComicGroupsResult> updateComicGroups(
    DownloadedMangaComic comic,
    String groupId,
  ) async {
    final current = _downloadGroupsService.groupIdsForComic(comic.storageKey);
    if (current.length == 1 && current.single == groupId) {
      return const UpdateComicGroupsResult(changed: false);
    }
    final added = current.contains(groupId) ? const <String>{} : {groupId};
    final removed = current.difference({groupId});
    await _downloadGroupsService.moveComicToGroups(comic.storageKey, [groupId]);
    await _syncComicDiskLocation(comic.storageKey);
    return UpdateComicGroupsResult(
      changed: true,
      addedGroupIds: added,
      removedGroupIds: removed,
    );
  }

  /// Moves every selected comic into [groupId], replacing their memberships.
  ///
  /// 已有批量操作在跑时直接返回空结果，避免重复点击导致的二次搬迁。
  Future<UpdateSelectedComicGroupsResult> updateSelectedComicsGroups(
    String groupId,
  ) async {
    if (_batchBusy) {
      return const UpdateSelectedComicGroupsResult(
        comicCount: 0,
        changedGroupCount: 0,
      );
    }
    final keys = Set<String>.of(_selectedComicIds);
    final movedKeys = <String>{};
    for (final key in keys) {
      final current = _downloadGroupsService.groupIdsForComic(key);
      if (current.length == 1 && current.single == groupId) continue;
      movedKeys.add(key);
    }
    _batchBusy = true;
    _batchBusyKind = _BatchBusyKind.move;
    _notify();
    try {
      if (movedKeys.isNotEmpty) {
        await _downloadGroupsService.moveComicsToGroups(movedKeys, [groupId]);
        for (final storageKey in movedKeys) {
          await _syncComicDiskLocation(storageKey);
        }
      }
    } finally {
      _batchBusy = false;
      _batchBusyKind = null;
    }
    _clearSelection(notify: true);
    return UpdateSelectedComicGroupsResult(
      comicCount: keys.length,
      changedGroupCount: movedKeys.length,
    );
  }

  bool selectionModeForTab(int tabIndex) =>
      tabIndex == 1 && (_selectionEnabled || _selectedComicIds.isNotEmpty);

  void handleTabChanged({
    required int tabIndex,
    required bool indexIsChanging,
  }) {
    if (indexIsChanging || tabIndex == 1) {
      return;
    }
    _clearSelection(notify: true);
  }

  void toggleSelection(String comicId) {
    if (_selectedComicIds.contains(comicId)) {
      _selectedComicIds.remove(comicId);
    } else {
      _selectedComicIds.add(comicId);
    }
    _notify();
  }

  /// 长按卡片进入多选，并把该卡片一并选中。
  ///
  /// 重复长按同一张卡片不会清零已选内容，只会保证它在选中集合里。
  void enterSelectionModeWith(String comicId) {
    final alreadySelected =
        _selectionEnabled && _selectedComicIds.contains(comicId);
    if (alreadySelected) return;
    _selectionEnabled = true;
    _selectedComicIds.add(comicId);
    _notify();
  }

  /// 切换全选状态：当前已全选则取消全选，否则全选指定范围内的漫画
  void toggleSelectAll(Iterable<String> comicKeys) {
    final keys = comicKeys.toList();
    // 判断是否已全选：所有 key 都在已选集合里
    final isAllSelected =
        keys.isNotEmpty && keys.every(_selectedComicIds.contains);
    if (isAllSelected) {
      // 已全选 → 取消全选
      _selectedComicIds.removeAll(keys);
    } else {
      // 未全选 → 全选
      _selectedComicIds.addAll(keys);
    }
    _notify();
  }

  void toggleSelectionMode(int tabIndex) {
    if (selectionModeForTab(tabIndex)) {
      exitSelectionMode(tabIndex);
      return;
    }
    _selectionEnabled = true;
    _notify();
  }

  bool exitSelectionMode(int tabIndex) {
    if (!selectionModeForTab(tabIndex)) {
      return false;
    }
    _clearSelection(notify: true);
    return true;
  }

  /// 批量删除选中的漫画。
  ///
  /// 返回 null 表示用户取消或当前已有批量操作在跑（防止重复触发）；
  /// 返回结果里带「请求数 / 失败数」，调用方据此给出结果或部分失败提示。
  Future<DownloadsBatchDeleteResult?> deleteSelected(BuildContext context) async {
    if (_selectedComicIds.isEmpty || _batchBusy) {
      return null;
    }
    final strings = l10n(context);
    final requestedKeys = Set<String>.of(_selectedComicIds);
    final confirmed = await showDownloadsDeleteDialog(
      context,
      title: strings.downloadsDeleteSelectedTitle,
      content: strings.downloadsDeleteSelectedContent('${requestedKeys.length}'),
    );
    if (confirmed != true) {
      return null;
    }
    _batchBusy = true;
    _batchBusyKind = _BatchBusyKind.delete;
    _notify();
    try {
      await _downloadService.deleteDownloadedComics(requestedKeys);
    } finally {
      _batchBusy = false;
      _batchBusyKind = null;
    }
    // 删除失败时服务会静默跳过，靠「删除后仍存在」来判断失败条数。
    final remaining = <String>{
      for (final comic in _downloadService.downloadedComics)
        if (requestedKeys.contains(comic.storageKey)) comic.storageKey,
    };
    _clearSelection(notify: false);
    _notify();
    return DownloadsBatchDeleteResult(
      requested: requestedKeys.length,
      failed: remaining.length,
    );
  }

  Future<void> deleteSingleComic(
    BuildContext context,
    DownloadedMangaComic comic,
  ) async {
    final strings = l10n(context);
    final confirmed = await showDownloadsDeleteDialog(
      context,
      title: strings.downloadsDeleteSelectedTitle,
      content: strings.downloadsDeleteSelectedContent('1'),
    );
    if (confirmed != true) {
      return;
    }
    await _downloadService.deleteDownloadedComics([comic.storageKey]);
  }

  Future<void> pauseTask(String comicId) async {
    await _downloadService.pauseTask(comicId);
  }

  Future<void> resumeTask(String comicId) async {
    await _downloadService.resumeTask(comicId);
  }

  /// 暂停所有下载任务
  Future<void> pauseAllTasks() async {
    await _downloadService.pauseAllTasks();
  }

  /// 恢复所有暂停或失败的下载任务
  Future<void> resumeAllTasks() async {
    await _downloadService.resumeAllTasks();
  }

  Future<void> deleteTask(BuildContext context, String comicId) async {
    final strings = l10n(context);
    final confirmed = await showDownloadsDeleteDialog(
      context,
      title: strings.comicDetailDelete,
      content: strings.downloadsDeleteSelectedContent('1'),
    );
    if (confirmed != true) {
      return;
    }
    await _downloadService.deleteTask(comicId);
  }

  Future<void> runIntegrityCheck() async {
    if (_checkingIntegrity) return;
    _checkingIntegrity = true;
    try {
      _comicsWithIntegrityIssues = await _downloadService
          .checkDownloadedIntegrity();
      _notify();
    } finally {
      _checkingIntegrity = false;
    }
  }

  Future<void> scanDownloadedComics(BuildContext context) async {
    if (_scanningDownloaded) {
      return;
    }
    _scanningDownloaded = true;
    _notify();
    try {
      final result = await _downloadService.scanDownloadedComics();
      if (!context.mounted) {
        return;
      }
      await showDownloadsScanResultPrompt(context, result);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      await showDownloadsScanErrorPrompt(context, error);
    } finally {
      _scanningDownloaded = false;
      _notify();
    }
  }

  void _clearSelection({required bool notify}) {
    final hadSelection = _selectionEnabled || _selectedComicIds.isNotEmpty;
    _selectionEnabled = false;
    _selectedComicIds.clear();
    if (notify && hadSelection) {
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _handleDownloadsChanged() {
    _downloadsRevision++;
    _downloadedKeysCache = null;
    if (!_reconcilingGroups) {
      _reconcilingGroups = true;
      _downloadGroupsService
          .reconcileDownloadedComics(
            _downloadService.downloadedComics.map((comic) => comic.storageKey),
            migratedComicKeys: _legacyComicKeyMigrations,
          )
          .whenComplete(() => _reconcilingGroups = false);
    }
    _notify();
  }

  void _handleGroupsChanged() {
    // 成员关系变化后已下载集合虽然没变，但计数依赖的是分组查询，无需失效
    // key 缓存；这里仅转发通知。
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchIndexCache.clear();
    _downloadedKeysCache = null;
    _downloadService.removeListener(_handleDownloadsChanged);
    _downloadGroupsService.removeListener(_handleGroupsChanged);
    super.dispose();
  }
}

/// 单部漫画的检索干草堆（小写拼接），按 updatedAtMillis 失效。
class _ComicSearchIndex {
  const _ComicSearchIndex({required this.stamp, required this.haystack});

  final int stamp;
  final String haystack;
}
