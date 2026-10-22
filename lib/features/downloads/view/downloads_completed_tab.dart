import 'package:hazuki/shared/text/chinese_conversion_scope.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hazuki/l10n/l10n.dart';
import 'package:hazuki/services/manga_download/manga_download_models.dart';
import 'package:hazuki/services/download_groups/download_group.dart';
import 'package:hazuki/features/search/view/search_bar_shell.dart';
import 'downloads_cover_widgets.dart';
import 'downloads_completed_status_widgets.dart';
import 'downloads_shell_widgets.dart';
import '../state/downloads_completed_list_controller.dart';

part 'downloads_completed/downloads_completed_buttons.dart';
part 'downloads_completed/downloads_completed_category.dart';
part 'downloads_completed/downloads_completed_comic_card.dart';
part 'downloads_completed/downloads_completed_search.dart';

@immutable
class DownloadsCompletedTabModel {
  const DownloadsCompletedTabModel({
    required this.comics,
    required this.active,
    required this.selectionMode,
    required this.scanning,
    required this.selectedCount,
    required this.selectedComicIds,
    required this.comicsWithIntegrityIssues,
    required this.groups,
    required this.selectedGroupId,
    required this.selectedGroupName,
    required this.selectedGroupComicCount,
    required this.groupComicCounts,
    this.searchQuery = '',
    this.deleting = false,
    this.batchBusy = false,
  });

  final List<DownloadedMangaComic> comics;
  final bool active;
  final bool selectionMode;
  final bool scanning;
  final int selectedCount;
  final Set<String> selectedComicIds;
  final Set<String> comicsWithIntegrityIssues;
  final List<DownloadGroup> groups;
  final String selectedGroupId;
  final String selectedGroupName;
  final int selectedGroupComicCount;
  final Map<String, int> groupComicCounts;

  /// 当前检索关键字（空串表示未检索）。
  final String searchQuery;

  /// 批量删除进行中，用于禁用按钮并显示进度。
  final bool deleting;

  /// 任意批量操作（删除/移动）进行中，用于禁用其它批量入口防重复提交。
  final bool batchBusy;
}

@immutable
class DownloadsCompletedTabActions {
  const DownloadsCompletedTabActions({
    required this.onToggleSelection,
    required this.onDeleteSelected,
    required this.onScanDownloaded,
    required this.onOpenComic,
    required this.onDeleteComic,
    required this.onSelectGroup,
    required this.onCreateGroup,
    required this.onRenameGroup,
    required this.onReorderGroups,
    required this.onDeleteGroup,
    required this.onShowComicMenu,
    required this.onBatchGroup,
    required this.onSearchQueryChanged,
    required this.onEnterSelection,
  });

  final ValueChanged<String> onToggleSelection;

  /// 长按卡片进入多选并选中该项。
  final ValueChanged<String> onEnterSelection;
  final VoidCallback onDeleteSelected;
  final VoidCallback onScanDownloaded;
  final ValueChanged<DownloadedMangaComic> onOpenComic;
  final ValueChanged<DownloadedMangaComic> onDeleteComic;
  final ValueChanged<String> onSelectGroup;
  final Future<DownloadGroup> Function(String name) onCreateGroup;
  final Future<DownloadGroup> Function(String groupId, String name)
  onRenameGroup;
  final Future<void> Function(List<String> orderedGroupIds) onReorderGroups;
  final Future<void> Function(String groupId) onDeleteGroup;
  final Future<void> Function(
    DownloadedMangaComic comic,
    Offset globalPosition,
    BuildContext itemContext,
  )
  onShowComicMenu;
  final VoidCallback onBatchGroup;

  /// 检索关键字变化回调（空串表示清空检索）。
  final ValueChanged<String> onSearchQueryChanged;
}

class DownloadsCompletedTab extends StatefulWidget {
  const DownloadsCompletedTab({
    super.key,
    required this.model,
    required this.actions,
  });

  final DownloadsCompletedTabModel model;
  final DownloadsCompletedTabActions actions;

  List<DownloadedMangaComic> get comics => model.comics;
  bool get active => model.active;
  bool get selectionMode => model.selectionMode;
  bool get scanning => model.scanning;
  int get selectedCount => model.selectedCount;
  Set<String> get selectedComicIds => model.selectedComicIds;
  Set<String> get comicsWithIntegrityIssues => model.comicsWithIntegrityIssues;
  List<DownloadGroup> get groups => model.groups;
  String get selectedGroupId => model.selectedGroupId;
  String get selectedGroupName => model.selectedGroupName;
  int get selectedGroupComicCount => model.selectedGroupComicCount;
  Map<String, int> get groupComicCounts => model.groupComicCounts;
  String get searchQuery => model.searchQuery;
  bool get deleting => model.deleting;
  bool get batchBusy => model.batchBusy;
  ValueChanged<String> get onToggleSelection => actions.onToggleSelection;
  ValueChanged<String> get onEnterSelection => actions.onEnterSelection;
  VoidCallback get onDeleteSelected => actions.onDeleteSelected;
  VoidCallback get onScanDownloaded => actions.onScanDownloaded;
  ValueChanged<DownloadedMangaComic> get onOpenComic => actions.onOpenComic;
  ValueChanged<DownloadedMangaComic> get onDeleteComic => actions.onDeleteComic;
  ValueChanged<String> get onSelectGroup => actions.onSelectGroup;
  Future<DownloadGroup> Function(String name) get onCreateGroup =>
      actions.onCreateGroup;
  Future<DownloadGroup> Function(String groupId, String name)
  get onRenameGroup => actions.onRenameGroup;
  Future<void> Function(List<String> orderedGroupIds) get onReorderGroups =>
      actions.onReorderGroups;
  Future<void> Function(String groupId) get onDeleteGroup =>
      actions.onDeleteGroup;
  Future<void> Function(
    DownloadedMangaComic comic,
    Offset globalPosition,
    BuildContext itemContext,
  )
  get onShowComicMenu => actions.onShowComicMenu;
  VoidCallback get onBatchGroup => actions.onBatchGroup;
  ValueChanged<String> get onSearchQueryChanged => actions.onSearchQueryChanged;

  static const Duration dismissDuration = Duration(milliseconds: 320);

  /// 检索输入的防抖时长：短到「几乎即时」，长到能让连续输入合并成一次过滤。
  static const Duration searchDebounce = Duration(milliseconds: 200);

  @override
  State<DownloadsCompletedTab> createState() => _DownloadsCompletedTabState();
}

class _DownloadsCompletedTabState extends State<DownloadsCompletedTab> {
  static const double _backToTopThreshold = 280;
  static const double _categoryLauncherTopSpace =
      DownloadsCategoryMorphLauncher.height + 22;

  /// 搜索框高度 + 与上方分类启动器的间距。
  static const double _searchBarSpace = DownloadsCompletedSearchBar.height + 12;

  final GlobalKey _stackKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  late final DownloadsCompletedListController _listController;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  _DownloadedComicSwipeReveal? _swipeReveal;
  Timer? _searchDebounce;
  bool _showBackToTop = false;
  bool _categoryShellOpen = false;
  int _categoryLauncherLandingVersion = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScrollChanged);
    _searchController = TextEditingController(text: widget.searchQuery);
    _searchFocusNode = FocusNode(debugLabel: 'downloads_search_field');
    _listController = DownloadsCompletedListController(
      comics: widget.comics,
      transitionDuration: DownloadsCompletedTab.dismissDuration,
    )..addListener(_handleListChanged);
  }

  @override
  void dispose() {
    _cancelSearchDebounce();
    _scrollController.removeListener(_handleScrollChanged);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _listController
      ..removeListener(_handleListChanged)
      ..dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DownloadsCompletedTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!widget.active && oldWidget.active) ||
        (widget.selectionMode && !oldWidget.selectionMode) ||
        (_swipeReveal != null &&
            !widget.comics.any(
              (comic) => comic.storageKey == _swipeReveal!.comic.storageKey,
            ))) {
      _swipeReveal = null;
    }
    if ((!widget.active || widget.comics.isEmpty) && _showBackToTop) {
      _showBackToTop = false;
    }
    // 外部检索状态变化（例如切换分组时清空）需同步到输入框，
    // 比较 trim 后的值，避免输入空格等场景反复重置光标位置。
    if (widget.searchQuery != oldWidget.searchQuery) {
      // 有外部改写时丢弃尚未结算的输入，否则防抖到期会用旧文本覆盖回去。
      _cancelSearchDebounce();
    }
    if (widget.searchQuery != _searchController.text.trim()) {
      _searchController.text = widget.searchQuery;
    }
    // 切换分组/改检索词属于「换一屏内容」，整表替换时不做逐条出场动画：
    // 大分组下逐条动画会排队数百个定时器并反复重建列表（O(n^2)），
    // 正是切换分组掉帧的主要来源。
    final contextChanged =
        oldWidget.selectedGroupId != widget.selectedGroupId ||
        oldWidget.searchQuery != widget.searchQuery;
    _listController.sync(widget.comics, animateExits: !contextChanged);
  }

  void _handleSearchChanged(String value) {
    // 每敲一个字都把整库过滤一遍（O(N) + 整页重建 + 列表 diff）在几千部
    // 漫画时会明显掉帧。这里做 200ms 防抖：输入框本身即时回显，过滤延后。
    _searchDebounce?.cancel();
    _searchDebounce = Timer(DownloadsCompletedTab.searchDebounce, () {
      _searchDebounce = null;
      if (!mounted) return;
      widget.onSearchQueryChanged(_searchController.text);
    });
  }

  void _handleSearchClear() {
    _cancelSearchDebounce();
    _searchController.clear();
    widget.onSearchQueryChanged('');
    _searchFocusNode.requestFocus();
  }

  void _handleSearchSubmit() {
    // 提交时立刻结算尚未生效的输入，避免「敲完就回车」要多等一次防抖。
    final pending = _searchDebounce;
    if (pending != null) {
      pending.cancel();
      _searchDebounce = null;
      widget.onSearchQueryChanged(_searchController.text);
    }
    _searchFocusNode.unfocus();
  }

  void _cancelSearchDebounce() {
    _searchDebounce?.cancel();
    _searchDebounce = null;
  }

  void _handleListChanged() {
    if (mounted) setState(() {});
  }

  void _handleScrollChanged() {
    final showBackToTop =
        widget.active && _scrollController.offset >= _backToTopThreshold;
    if (_showBackToTop == showBackToTop) {
      return;
    }
    setState(() {
      _showBackToTop = showBackToTop;
    });
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) {
      return;
    }
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  void _closeSwipeReveal() {
    if (_swipeReveal == null) {
      return;
    }
    setState(() {
      _swipeReveal = null;
    });
  }

  void _handleOpenComic(DownloadedMangaComic comic) {
    _closeSwipeReveal();
    widget.onOpenComic(comic);
  }

  void _handleDeleteComic(DownloadedMangaComic comic) {
    _closeSwipeReveal();
    widget.onDeleteComic(comic);
  }

  void _handleSwipeReveal(_DownloadedComicSwipeReveal reveal) {
    final activeStorageKey = _swipeReveal?.comic.storageKey;
    if (!reveal.claimActive &&
        activeStorageKey != null &&
        activeStorageKey != reveal.comic.storageKey) {
      return;
    }
    final nextReveal = reveal.progress <= precisionErrorTolerance
        ? null
        : reveal;
    setState(() {
      _swipeReveal = nextReveal;
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification && _swipeReveal != null) {
      setState(() {
        _swipeReveal = null;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final visibleComics = _listController.entries;
    // 只取一次：卡片逐项判断选中状态时不再重复包装集合。
    final selectedIds = widget.selectedComicIds;
    final searching = widget.searchQuery.isNotEmpty;
    final listContent = visibleComics.isEmpty
        ? Center(
            child: Text(
              searching
                  ? l10n(context).downloadsSearchEmpty
                  : l10n(context).downloadsEmptyDownloaded,
            ),
          )
        : NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: ListView.builder(
              key: const ValueKey<String>('downloaded_comics_list'),
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(
                16,
                _categoryLauncherTopSpace + _searchBarSpace + 12,
                16,
                96,
              ),
              itemCount: visibleComics.length,
              itemBuilder: (context, index) {
                final entry = visibleComics[index];
                return _AnimatedDownloadedComicCard(
                  key: ValueKey<String>('downloaded_${entry.comic.storageKey}'),
                  entry: entry,
                  bottomSpacing: index == visibleComics.length - 1 ? 0 : 12,
                  selectionMode: widget.selectionMode,
                  selected: selectedIds.contains(entry.comic.storageKey),
                  hasIntegrityIssue: widget.comicsWithIntegrityIssues.contains(
                    entry.comic.storageKey,
                  ),
                  activeSwipeStorageKey: _swipeReveal?.comic.storageKey,
                  swipeRevealStackKey: _stackKey,
                  onSwipeRevealChanged: _handleSwipeReveal,
                  onToggleSelection: widget.onToggleSelection,
                  onEnterSelection: widget.onEnterSelection,
                  onOpenComic: _handleOpenComic,
                  onShowComicMenu: widget.onShowComicMenu,
                );
              },
            ),
          );
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Stack(
      key: _stackKey,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: listContent),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DownloadsCategoryMorphLauncher(
                visible: !_categoryShellOpen,
                landingVersion: _categoryLauncherLandingVersion,
                label: widget.selectedGroupName,
                comicCount: widget.selectedGroupComicCount,
                onPressed: _showCategoryShell,
              ),
              // 分类面板展开时不保留检索框，避免与浮层输入框争抢焦点。
              if (!_categoryShellOpen)
                DownloadsCompletedSearchBar(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onChanged: _handleSearchChanged,
                  onClear: _handleSearchClear,
                  onSubmit: _handleSearchSubmit,
                ),
            ],
          ),
        ),
        if (_swipeReveal case final reveal?)
          Positioned(
            top: reveal.top,
            right:
                -_DownloadedComicEdgeDeleteButton.width * (1 - reveal.progress),
            height: reveal.height,
            child: _DownloadedComicEdgeDeleteButton(
              comic: reveal.comic,
              enabled: reveal.revealed,
              onDeleteComic: _handleDeleteComic,
            ),
          ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          right: widget.selectionMode || _showBackToTop ? 84 : 16,
          bottom: 16 + bottomInset,
          child: DownloadsScanButton(
            selectionMode: widget.selectionMode,
            scanning: widget.scanning,
            deleting: widget.deleting,
            selectedCount: widget.selectedCount,
            onDeleteSelected: widget.onDeleteSelected,
            onScanDownloaded: widget.onScanDownloaded,
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16 + bottomInset,
          child: DownloadsBatchGroupButton(
            visible: widget.selectionMode,
            enabled: widget.selectedCount > 0 && !widget.batchBusy,
            onPressed: widget.onBatchGroup,
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16 + bottomInset,
          child: DownloadsBackToTopButton(
            visible: _showBackToTop && !widget.selectionMode,
            onPressed: _scrollToTop,
          ),
        ),
      ],
    );
  }

  Future<void> _showCategoryShell() async {
    if (_categoryShellOpen) {
      return;
    }
    _closeSwipeReveal();
    setState(() {
      _categoryShellOpen = true;
    });
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.34),
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return DownloadsCategoryShellDialog(
          animation: animation,
          onDisposed: _restoreCategoryLauncher,
          groups: widget.groups,
          selectedGroupId: widget.selectedGroupId,
          groupComicCounts: widget.groupComicCounts,
          onSelectGroup: widget.onSelectGroup,
          onCreateGroup: widget.onCreateGroup,
          onRenameGroup: widget.onRenameGroup,
          onReorderGroups: widget.onReorderGroups,
          onDeleteGroup: widget.onDeleteGroup,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return child;
      },
    );
  }

  void _restoreCategoryLauncher() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _categoryShellOpen = false;
          _categoryLauncherLandingVersion++;
        });
      }
    });
  }
}
