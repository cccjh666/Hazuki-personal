import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/hazuki_models.dart';
import '../source/source_capabilities.dart';
import 'manga_download_commands.dart';
import 'manga_download_library.dart';
import 'download_group_folders.dart';
import 'manga_download_lifecycle_coordinator.dart';
import 'manga_download_state.dart';
import 'manga_download_files.dart';
import 'manga_download_queue_support.dart';
import 'manga_download_recovery_support.dart';
import 'manga_download_storage_support.dart';

export 'manga_download_models.dart';

class MangaDownloadService extends ChangeNotifier
    implements MangaDownloadCommands, MangaDownloadLibrary {
  MangaDownloadService({SourceReaderGateway? sourceReader}) {
    _stateStore = MangaDownloadStateStore(logScan: _logScan);
    _access = MangaDownloadAccess(logScan: _logScan);
    _files = MangaDownloadFiles(sourceReader: sourceReader, logScan: _logScan);
    _recoveryScanner = MangaDownloadRecoveryScanner(
      logScan: _logScan,
      taskByComicId: _state.taskByComicId,
      chapterDirForTarget: _files.chapterDirForTarget,
      writeMetadataFile: _files.writeMetadataFile,
    );
    _lifecycle = MangaDownloadLifecycleCoordinator(
      isAndroid: Platform.isAndroid,
      hasActiveDownloads: _hasActiveDownloads,
      startForegroundService: _access.startDownloadForegroundService,
      stopForegroundService: _access.stopDownloadForegroundService,
      processQueue: () => _queueExecutor.processQueue(),
    );
    _queueExecutor = MangaDownloadQueueExecutor(
      logDownload: _logScan,
      state: _state,
      files: _files,
      access: _access,
      flushState: _flushState,
      shouldSuspendDownloads: () => _lifecycle.shouldSuspendDownloads,
      shouldRecoverTransientNetworkError: () =>
          _lifecycle.shouldRecoverTransientNetworkError,
      sourceReader: sourceReader,
    );
  }

  SharedPreferences? _prefs;
  Future<void>? _initFuture;
  final MangaDownloadState _state = MangaDownloadState();
  late final MangaDownloadFiles _files;
  static const DownloadGroupFolders _groupFolders = DownloadGroupFolders();
  List<MangaDownloadTask> get _tasks => _state.tasks;
  List<DownloadedMangaComic> get _downloaded => _state.downloadedComics;
  late final MangaDownloadStateStore _stateStore;
  late final MangaDownloadAccess _access;
  late final MangaDownloadRecoveryScanner _recoveryScanner;
  late final MangaDownloadQueueExecutor _queueExecutor;
  late final MangaDownloadLifecycleCoordinator _lifecycle;

  @override
  List<MangaDownloadTask> get tasks => _state.tasks;
  @override
  List<DownloadedMangaComic> get downloadedComics => _state.downloadedComics;

  // 下载扫描日志已禁用，不再写入应用日志
  // ignore: unused_element
  void _logScan(String title, {Object? content, String level = 'info'}) {}

  void handleAppLifecycleState(AppLifecycleState state) {
    _lifecycle.handleAppLifecycleState(state);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  bool _hasActiveDownloads() => _tasks.any(
    (t) =>
        t.status == MangaDownloadTaskStatus.queued ||
        t.status == MangaDownloadTaskStatus.downloading,
  );

  @override
  Future<Set<String>> checkDownloadedIntegrity() async {
    final issueIds = <String>{};
    for (final comic in _downloaded) {
      bool hasIssue = false;
      outer:
      for (final chapter in comic.chapters) {
        for (final imagePath in chapter.imagePaths) {
          if (!await File(imagePath).exists()) {
            hasIssue = true;
            break outer;
          }
        }
      }
      if (hasIssue) {
        issueIds.add(comic.storageKey);
      }
    }
    return issueIds;
  }

  @override
  Future<void> ensureInitialized() async {
    final inFlight = _initFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final future = _init();
    _initFuture = future;
    await future;
  }

  @override
  Future<MangaDownloadedScanResult> scanDownloadedComics() async {
    await ensureInitialized();
    final hasAccess = await _ensureAndroidDownloadsAccess();
    if (!hasAccess) {
      return const MangaDownloadedScanResult(
        permissionGranted: false,
        scannedDirectories: 0,
        recoveredComics: 0,
      );
    }

    final rootDir = await _ensureRootDir();
    final result = await _recoveryScanner.scanDownloadedFromDisk(rootDir);
    _state.replaceDownloaded(result.comics);
    await _persistState();
    notifyListeners();
    return MangaDownloadedScanResult(
      permissionGranted: true,
      scannedDirectories: result.scannedDirectories,
      recoveredComics: result.recoveredComics,
    );
  }

  DownloadedMangaComic? downloadedComicById(String comicId) {
    return downloadedComicByIdForSource(comicId, sourceKey: '');
  }

  DownloadedMangaComic? downloadedComicByIdForSource(
    String comicId, {
    required String sourceKey,
  }) => _state.downloadedComicByIdForSource(comicId, sourceKey: sourceKey);

  MangaDownloadTask? taskByComicId(String comicId) =>
      _state.taskByComicId(comicId);

  @override
  Future<MangaDownloadConflict> checkDownloadTaskConflict({
    required ComicDetailsData details,
    required List<MangaChapterDownloadTarget> chapters,
  }) async {
    await ensureInitialized();
    final task = _state.taskByStorageKey(details.scopedId.storageKey);
    return MangaDownloadConflict(
      comicTitle: details.title,
      existingChapters: task == null
          ? const <MangaChapterDownloadTarget>[]
          : chapters
                .where(
                  (target) =>
                      task.targets.any((item) => item.epId == target.epId),
                )
                .toList(growable: false),
    );
  }

  @override
  Future<MangaDownloadConflict> checkDownloadConflict({
    required ComicDetailsData details,
    required List<MangaChapterDownloadTarget> chapters,
  }) async {
    await ensureInitialized();
    final downloaded = downloadedComicByIdForSource(
      details.id,
      sourceKey: details.sourceKey.trim(),
    );
    return MangaDownloadConflict(
      comicTitle: details.title,
      existingChapters: downloaded == null
          ? const <MangaChapterDownloadTarget>[]
          : chapters
                .where(
                  (target) => downloaded.chapters.any(
                    (chapter) => MangaDownloadState.chapterMatchesTarget(
                      chapter,
                      target,
                    ),
                  ),
                )
                .toList(growable: false),
    );
  }

  @override
  Future<MangaDownloadEnqueueResult> enqueueDownload({
    required ComicDetailsData details,
    required String coverUrl,
    required String description,
    required List<MangaChapterDownloadTarget> chapters,
    bool redownloadExisting = false,
  }) async {
    if (chapters.isEmpty) {
      return MangaDownloadEnqueueResult.nothingToQueue;
    }

    await ensureInitialized();
    if (redownloadExisting) {
      await _removeDownloadedChaptersForRedownload(
        details: details,
        chapters: chapters,
      );
    }
    final result = _state.enqueue(
      details: details,
      coverUrl: coverUrl,
      description: description,
      chapters: chapters,
    );
    if (result != MangaDownloadEnqueueResult.queued) return result;

    await _persistState();
    notifyListeners();
    unawaited(_queueExecutor.processQueue());
    return MangaDownloadEnqueueResult.queued;
  }

  Future<void> _removeDownloadedChaptersForRedownload({
    required ComicDetailsData details,
    required List<MangaChapterDownloadTarget> chapters,
  }) async {
    final downloaded = downloadedComicByIdForSource(
      details.id,
      sourceKey: details.sourceKey.trim(),
    );
    if (downloaded == null) {
      return;
    }

    final chaptersToRemove = downloaded.chapters
        .where(
          (chapter) => chapters.any(
            (target) =>
                MangaDownloadState.chapterMatchesTarget(chapter, target),
          ),
        )
        .toList(growable: false);
    if (chaptersToRemove.isEmpty) {
      return;
    }

    if (!await _ensureAndroidDownloadsAccess()) {
      throw FileSystemException('Android downloads access not granted');
    }
    final rootDir = await _ensureRootDir();
    final comicDir = _files.comicDirForDownloadedComic(downloaded, rootDir);
    final chapterDirectories = <String>{};
    for (final chapter in chaptersToRemove) {
      final directory = await _recoveryScanner.resolveChapterDirForEpId(
        comicDir: comicDir,
        epId: chapter.epId,
        targets: chapters,
        downloadedComic: downloaded,
      );
      if (directory != null && _isPathWithin(directory, comicDir)) {
        chapterDirectories.add(directory.path);
      }
    }
    for (final path in chapterDirectories) {
      final directory = Directory(path);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }

    final remainingChapters = downloaded.chapters
        .where(
          (chapter) => !chapters.any(
            (target) =>
                MangaDownloadState.chapterMatchesTarget(chapter, target),
          ),
        )
        .toList(growable: false);
    if (remainingChapters.isEmpty) {
      _state.removeDownloaded({downloaded.storageKey});
      await _files.deleteMetadataFiles(comicDir);
    } else {
      final updated = downloaded.copyWith(chapters: remainingChapters);
      _state.upsertDownloadedComic(updated);
      await _files.writeMetadataFile(comicDir, updated);
    }
    await _persistState();
    notifyListeners();
  }

  bool _isPathWithin(Directory child, Directory parent) {
    String normalize(String path) {
      final absolute = Directory(path).absolute.path.replaceAll('\\', '/');
      final trimmed = absolute.endsWith('/')
          ? absolute.substring(0, absolute.length - 1)
          : absolute;
      return Platform.isWindows ? trimmed.toLowerCase() : trimmed;
    }

    final childPath = normalize(child.path);
    final parentPath = normalize(parent.path);
    return childPath.startsWith('$parentPath/');
  }

  @override
  Future<void> deleteDownloadedComics(Iterable<String> comicIds) async {
    await ensureInitialized();
    final ids = comicIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (ids.isEmpty) {
      return;
    }

    final hasAccess = await _ensureAndroidDownloadsAccess();
    if (!hasAccess) {
      return;
    }

    final rootDir = await _ensureRootDir();
    for (final storageKey in ids) {
      try {
        final comic = _state.downloadedComicByStorageKey(storageKey);
        final scopedId = SourceScopedComicId.fromStorageKey(storageKey);
        final removesLegacyDirectory =
            scopedId.sourceKey.isEmpty ||
            isHazukiJmSourceKey(scopedId.sourceKey);
        final dirNames = <String>{
          comic?.downloadDirName ?? scopedId.downloadDirName,
          scopedId.downloadDirName,
          // Downloads created before source-scoped IDs used the raw comic ID
          // as their directory name. Keep deleting that legacy directory so a
          // migrated download does not remain on disk after deletion.
          if (removesLegacyDirectory && comic != null) comic.comicId,
          if (removesLegacyDirectory) scopedId.comicId,
        };
        final directories = <Directory>{
          for (final dirName in dirNames) Directory('${rootDir.path}/$dirName'),
          if (comic != null) _files.comicDirForDownloadedComic(comic, rootDir),
        };
        for (final dir in directories) {
          if (_isPathWithin(dir, rootDir) && await dir.exists()) {
            await dir.delete(recursive: true);
            // 漫画在分组子目录里时，删完可能留下一个空的组目录。
            await _pruneEmptyContainer(dir, rootDir);
          }
        }
      } catch (_) {}
    }
    _state.removeDownloaded(ids);
    await _persistState();
    notifyListeners();
  }

  /// 将某部已下载漫画的磁盘目录移动到指定组子目录（或扁平根目录）下。
  @override
  Future<void> moveDownloadedComicToGroup(
    String storageKey,
    String? groupFolderName,
  ) async {
    final comic = _state.downloadedComicByStorageKey(storageKey);
    if (comic == null) return;
    if (!await _ensureAndroidDownloadsAccess()) return;
    final rootDir = await _ensureRootDir();

    final currentDir = _files.comicDirForDownloadedComic(comic, rootDir);
    final targetDir = _resolveComicTargetDir(comic, rootDir, groupFolderName);
    if (_sameDirectoryPath(currentDir, targetDir)) return;

    await _relocateComicDirectory(comic, currentDir, targetDir);
  }

  /// 组重命名时，同步重命名对应的磁盘目录。
  ///
  /// 目标目录已存在时不再静默放弃（否则元数据改名成功、磁盘目录却仍是旧的）：
  /// 空目录先清理再重命名，非空则把源目录的子项逐个合并过去，同名一律不覆盖。
  @override
  Future<void> renameGroupFolder(
    String oldFolderName,
    String newFolderName,
  ) async {
    final oldName = oldFolderName.trim();
    final newName = newFolderName.trim();
    if (oldName.isEmpty || newName.isEmpty || oldName == newName) return;
    if (!await _ensureAndroidDownloadsAccess()) return;
    final rootDir = await _ensureRootDir();
    final oldDir = Directory('${rootDir.path}/$oldName');
    final newDir = Directory('${rootDir.path}/$newName');
    if (!await oldDir.exists() || !_isPathWithin(oldDir, rootDir)) return;

    // 移动之前先确定受影响的记录：移动完成后就判断不出旧前缀了。
    final affected = [
      for (final comic in _downloaded)
        if (_comicUnderDirectory(comic, oldDir.path)) comic,
    ];

    // 目标目录可能已存在（上次删除分组残留的空目录，或人工建的同名目录）。
    // 统一交给 moveContents：空目录先清理再整体重命名，非空则合并缺失项，
    // 同名一律不覆盖——避免出现「元数据已改名、磁盘目录还是旧的」。
    final movedDirNames = await _groupFolders.moveContents(oldDir, newDir);
    // 合并后源目录可能还有同名残留，空的就顺手删掉。
    await _groupFolders.deleteIfEmpty(oldDir);

    final relocated = <DownloadedMangaComic>[];
    for (final comic in affected) {
      if (movedDirNames.isNotEmpty &&
          !movedDirNames.contains(comic.downloadDirName)) {
        // 同名冲突导致该目录留在原处，记录保持旧路径才与磁盘一致。
        continue;
      }
      relocated.add(_rewriteComicPaths(comic, oldDir.path, newDir.path));
    }
    for (final comic in relocated) {
      _state.upsertDownloadedComic(comic);
      await _files.writeMetadataFile(
        _files.comicDirForDownloadedComic(comic, rootDir),
        comic,
      );
    }
    await _persistState();
    notifyListeners();
  }

  /// 删除分组对应的磁盘目录（**仅当目录为空**）。
  ///
  /// 调用时机应在组内漫画搬回默认组之后。返回 true 表示目录已删除或本来
  /// 不存在；false 表示目录非空被保留——组内还有搬迁失败的漫画，或用户
  /// 手动放入的文件，此时宁留冗余也不删数据。
  @override
  Future<bool> removeGroupFolder(String folderName) async {
    final name = folderName.trim();
    if (name.isEmpty) return true;
    if (!await _ensureAndroidDownloadsAccess()) return false;
    final rootDir = await _ensureRootDir();
    final dir = Directory('${rootDir.path}/$name');
    if (!_isPathWithin(dir, rootDir)) return false;
    return _groupFolders.deleteIfEmpty(dir);
  }

  /// 漫画目录删除后，若其所在的组容器目录已经空了，一并清理。
  Future<void> _pruneEmptyContainer(Directory dir, Directory rootDir) async {
    final parent = dir.parent;
    if (_sameDirectoryPath(parent, rootDir)) return;
    if (!_isPathWithin(parent, rootDir)) return;
    await _groupFolders.deleteIfEmpty(parent);
  }

  Directory _resolveComicTargetDir(
    DownloadedMangaComic comic,
    Directory root,
    String? groupFolderName,
  ) {
    final name = groupFolderName?.trim();
    if (name == null || name.isEmpty) {
      return Directory('${root.path}/${comic.downloadDirName}');
    }
    return Directory('${root.path}/$name/${comic.downloadDirName}');
  }

  Future<void> _relocateComicDirectory(
    DownloadedMangaComic comic,
    Directory fromDir,
    Directory toDir,
  ) async {
    if (!await fromDir.exists()) return;
    // 目标已存在时不再静默放弃，否则会出现「分组记录已改、文件还留在旧位置」。
    // moveContents 会按「目标不存在→整体重命名 / 目标为空→先清理再重命名 /
    // 目标非空→合并缺失子项」处理，同名项一律不覆盖。
    await _groupFolders.moveContents(fromDir, toDir);
    await _groupFolders.deleteIfEmpty(fromDir);
    final updated = _rewriteComicPaths(comic, fromDir.path, toDir.path);
    _state.upsertDownloadedComic(updated);
    await _files.writeMetadataFile(toDir, updated);
    await _persistState();
    notifyListeners();
  }

  DownloadedMangaComic _rewriteComicPaths(
    DownloadedMangaComic comic,
    String fromPath,
    String toPath,
  ) {
    final fromNorm = _normalizePath(fromPath);
    final toNorm = _normalizePath(toPath);
    String rewrite(String path) {
      final normalized = _normalizePath(path);
      if (normalized.startsWith('$fromNorm/')) {
        return '$toNorm${normalized.substring(fromNorm.length)}';
      }
      return path;
    }

    final cover = comic.localCoverPath;
    return comic.copyWith(
      localCoverPath: cover == null ? null : rewrite(cover),
      updatedAtMillis: comic.updatedAtMillis,
      chapters: [
        for (final chapter in comic.chapters)
          DownloadedMangaChapter(
            epId: chapter.epId,
            title: chapter.title,
            index: chapter.index,
            directoryIndex: chapter.directoryIndex,
            groupId: chapter.groupId,
            groupTitle: chapter.groupTitle,
            imagePaths: [for (final p in chapter.imagePaths) rewrite(p)],
          ),
      ],
    );
  }

  bool _comicUnderDirectory(DownloadedMangaComic comic, String dirPath) {
    final dirNorm = _normalizePath(dirPath);
    final cover = comic.localCoverPath?.trim();
    if (cover != null && cover.isNotEmpty) {
      return _normalizePath(cover).startsWith('$dirNorm/');
    }
    for (final chapter in comic.chapters) {
      if (chapter.imagePaths.isNotEmpty) {
        return _normalizePath(chapter.imagePaths.first).startsWith('$dirNorm/');
      }
    }
    return false;
  }

  bool _sameDirectoryPath(Directory a, Directory b) {
    return _normalizePath(a.path) == _normalizePath(b.path);
  }

  String _normalizePath(String path) {
    var normalized = path.replaceAll('\\', '/');
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  @override
  Future<void> pauseTask(String storageKey) async {
    await ensureInitialized();
    if (!_state.pauseTask(storageKey)) return;
    await _persistState();
    notifyListeners();
  }

  @override
  Future<void> resumeTask(String storageKey) async {
    await ensureInitialized();
    if (!_state.resumeTask(storageKey)) return;
    await _persistState();
    notifyListeners();
    unawaited(_queueExecutor.processQueue());
  }

  @override
  Future<void> pauseAllTasks() async {
    await ensureInitialized();
    if (!_state.pauseAllTasks()) return;
    await _persistState();
    notifyListeners();
  }

  @override
  Future<void> resumeAllTasks() async {
    await ensureInitialized();
    if (!_state.resumeAllTasks()) return;
    await _persistState();
    notifyListeners();
    unawaited(_queueExecutor.processQueue());
  }

  @override
  Future<void> deleteTask(String storageKey) async {
    await ensureInitialized();
    if (_state.taskByStorageKey(storageKey) == null) {
      return;
    }

    final hasAccess = await _ensureAndroidDownloadsAccess();
    if (!hasAccess) {
      return;
    }

    final task = _state.removeTask(storageKey);
    if (task == null) return;
    final rootDir = await _ensureRootDir();
    final downloadedComic = _state.downloadedComicByStorageKey(task.storageKey);
    final comicDir = downloadedComic != null
        ? _files.comicDirForDownloadedComic(downloadedComic, rootDir)
        : Directory('${rootDir.path}/${task.downloadDirName}');
    if (task.currentChapterEpId?.isNotEmpty == true) {
      try {
        final chapterDir = await _recoveryScanner.resolveChapterDirForEpId(
          comicDir: comicDir,
          epId: task.currentChapterEpId!,
          targets: task.targets,
          downloadedComic: downloadedComic,
        );
        if (chapterDir != null && await chapterDir.exists()) {
          await chapterDir.delete(recursive: true);
        }
      } catch (_) {}
    }
    if (downloadedComic == null) {
      try {
        if (await comicDir.exists()) {
          await comicDir.delete(recursive: true);
        }
      } catch (_) {}
    }
    await _persistState();
    notifyListeners();
  }

  Future<void> handleRootPathChanged({bool rescan = true}) async {
    await ensureInitialized();
    _state.replaceDownloaded(const []);

    if (rescan) {
      final hasAccess = await _ensureAndroidDownloadsAccess();
      if (hasAccess) {
        final rootDir = await _ensureRootDir();
        final result = await _recoveryScanner.scanDownloadedFromDisk(rootDir);
        _state.replaceDownloaded(result.comics);
      }
    }

    await _persistState();
    notifyListeners();
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    final restored = await _stateStore.restore(_prefs);
    _state.restoreTasks(restored.tasks);
    _sanitizeRestoredDownloadedState(restored.downloaded);
    await _persistState();
  }

  Future<bool> _ensureAndroidDownloadsAccess() {
    return _access.ensureAndroidDownloadsAccess();
  }

  Future<Directory> _ensureRootDir() {
    return _access.ensureRootDir();
  }

  Future<void> _persistState() {
    return _stateStore.persist(
      prefs: _prefs,
      tasks: _tasks,
      downloaded: _downloaded,
    );
  }

  Future<void> _flushState() async {
    await _persistState();
    if (_tasks.isEmpty) {
      unawaited(_access.stopDownloadForegroundService());
    }
    notifyListeners();
  }

  void _sanitizeRestoredDownloadedState(Iterable<DownloadedMangaComic> comics) {
    final sanitized = <DownloadedMangaComic>[];
    final droppedIds = <String>[];
    for (final comic in comics) {
      final normalized = _recoveryScanner.sanitizeDownloadedComicState(comic);
      if (normalized != null) {
        sanitized.add(normalized);
      } else {
        droppedIds.add(comic.comicId);
      }
    }
    if (droppedIds.isNotEmpty) {
      _logScan(
        'Dropped invalid downloaded comic entries on restore',
        level: 'warning',
        content: {'droppedIds': droppedIds},
      );
    }
    _state.replaceDownloaded(sanitized);
  }
}
