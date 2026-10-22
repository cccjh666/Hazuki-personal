import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hazuki/services/manga_download/manga_download_models.dart';

class AnimatedDownloadedComicEntry {
  const AnimatedDownloadedComicEntry({
    required this.comic,
    this.entering = false,
    this.exiting = false,
  });

  final DownloadedMangaComic comic;
  final bool entering;
  final bool exiting;

  AnimatedDownloadedComicEntry copyWith({
    DownloadedMangaComic? comic,
    bool? entering,
    bool? exiting,
  }) => AnimatedDownloadedComicEntry(
    comic: comic ?? this.comic,
    entering: entering ?? this.entering,
    exiting: exiting ?? this.exiting,
  );
}

/// Owns list-diff and enter/exit timing independently from the widget tree.
class DownloadsCompletedListController extends ChangeNotifier {
  DownloadsCompletedListController({
    required List<DownloadedMangaComic> comics,
    required this.transitionDuration,
  }) : _currentComics = List.unmodifiable(comics),
       _entries = comics
           .map((comic) => AnimatedDownloadedComicEntry(comic: comic))
           .toList(growable: false);

  final Duration transitionDuration;
  List<DownloadedMangaComic> _currentComics;
  List<AnimatedDownloadedComicEntry> _entries;

  /// 上一次 [sync] 传入的列表实例（可能是控制器里的缓存列表）。
  List<DownloadedMangaComic>? _lastSyncedSource;
  bool _disposed = false;

  /// Enter/exit animations are flushed in batches, one timer for the whole
  /// batch. Scheduling one timer per item meant N timers each rebuilding an
  /// O(N) list, i.e. O(n^2) work after every bulk change.
  final Set<String> _pendingEnterKeys = <String>{};
  final Set<String> _pendingRemovalKeys = <String>{};
  Timer? _enterTimer;
  Timer? _removalTimer;

  List<AnimatedDownloadedComicEntry> get entries => _entries;

  /// Replaces the visible list.
  ///
  /// Pass `animateExits: false` for context switches (another group, another
  /// search keyword). The list is replaced wholesale there, so animating
  /// hundreds of exits costs a frame budget the user never sees; it was the
  /// main reason switching a large group stuttered.
  void sync(List<DownloadedMangaComic> comics, {bool animateExits = true}) {
    // 多选时每次点选都会重建整页，而列表本身常常是同一个缓存实例。
    // 这种情况下 diff 完全是白做，直接返回。
    if (identical(comics, _lastSyncedSource)) return;
    _lastSyncedSource = comics;
    _currentComics = List.unmodifiable(comics);
    if (!animateExits) {
      _pendingEnterKeys.clear();
      _pendingRemovalKeys.clear();
      _enterTimer?.cancel();
      _enterTimer = null;
      _removalTimer?.cancel();
      _removalTimer = null;
      _replaceIfChanged(
        comics
            .map((comic) => AnimatedDownloadedComicEntry(comic: comic))
            .toList(growable: false),
      );
      return;
    }
    final nextById = <String, DownloadedMangaComic>{
      for (final comic in comics) comic.storageKey: comic,
    };
    final currentById = <String, AnimatedDownloadedComicEntry>{
      for (final entry in _entries) entry.comic.storageKey: entry,
    };
    final exitingEntries =
        <({int index, AnimatedDownloadedComicEntry entry})>[];
    final nextVisible = <AnimatedDownloadedComicEntry>[];

    for (var index = 0; index < _entries.length; index++) {
      final entry = _entries[index];
      if (!nextById.containsKey(entry.comic.storageKey)) {
        exitingEntries.add((
          index: index,
          entry: entry.copyWith(exiting: true, entering: false),
        ));
        if (!entry.exiting) _pendingRemovalKeys.add(entry.comic.storageKey);
      }
    }

    for (final comic in comics) {
      final currentEntry = currentById[comic.storageKey];
      if (currentEntry == null) {
        nextVisible.add(
          AnimatedDownloadedComicEntry(comic: comic, entering: true),
        );
        _pendingEnterKeys.add(comic.storageKey);
      } else {
        nextVisible.add(
          AnimatedDownloadedComicEntry(
            comic: comic,
            entering: currentEntry.entering,
          ),
        );
      }
    }

    for (final exiting in exitingEntries) {
      nextVisible.insert(
        exiting.index.clamp(0, nextVisible.length),
        exiting.entry,
      );
    }
    _replaceIfChanged(nextVisible);
    _scheduleEnterFlush();
    _scheduleRemovalFlush();
  }

  void _scheduleEnterFlush() {
    if (_pendingEnterKeys.isEmpty) return;
    _enterTimer?.cancel();
    _enterTimer = Timer(transitionDuration, _flushEntering);
  }

  void _scheduleRemovalFlush() {
    if (_pendingRemovalKeys.isEmpty) return;
    _removalTimer?.cancel();
    _removalTimer = Timer(transitionDuration, _flushRemovals);
  }

  void _flushEntering() {
    _enterTimer = null;
    if (_disposed || _pendingEnterKeys.isEmpty) return;
    final keys = Set<String>.of(_pendingEnterKeys);
    _pendingEnterKeys.clear();
    _replaceIfChanged(
      _entries
          .map(
            (entry) =>
                keys.contains(entry.comic.storageKey) && !entry.exiting
                ? entry.copyWith(entering: false)
                : entry,
          )
          .toList(growable: false),
    );
  }

  void _flushRemovals() {
    _removalTimer = null;
    if (_disposed || _pendingRemovalKeys.isEmpty) return;
    final keys = Set<String>.of(_pendingRemovalKeys);
    _pendingRemovalKeys.clear();
    // A comic that came back before the timer fired stays in the list.
    final currentKeys = <String>{
      for (final comic in _currentComics) comic.storageKey,
    };
    keys.removeAll(currentKeys);
    if (keys.isEmpty) return;
    _replaceIfChanged(
      _entries
          .where((entry) => !keys.contains(entry.comic.storageKey))
          .toList(growable: false),
    );
  }

  void _replaceIfChanged(List<AnimatedDownloadedComicEntry> next) {
    if (_sameEntries(_entries, next)) return;
    _entries = next;
    notifyListeners();
  }

  bool _sameEntries(
    List<AnimatedDownloadedComicEntry> current,
    List<AnimatedDownloadedComicEntry> next,
  ) {
    if (current.length != next.length) return false;
    for (var index = 0; index < current.length; index++) {
      final a = current[index];
      final b = next[index];
      if (a.comic != b.comic ||
          a.exiting != b.exiting ||
          a.entering != b.entering) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _enterTimer?.cancel();
    _enterTimer = null;
    _removalTimer?.cancel();
    _removalTimer = null;
    _pendingEnterKeys.clear();
    _pendingRemovalKeys.clear();
    super.dispose();
  }
}
