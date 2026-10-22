part of '../downloads_completed_tab.dart';

/// 已下载列表顶部的检索框。
///
/// 与分组筛选叠加生效：先按分组过滤，再按关键字过滤。
class DownloadsCompletedSearchBar extends StatelessWidget {
  const DownloadsCompletedSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
    required this.onSubmit,
  });

  /// 检索框可视高度，列表顶部留白依赖该常量。
  static const double height = 40;

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SizedBox(
            height: height,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                return SearchBarShell(
                  controller: controller,
                  focusNode: focusNode,
                  clearKey: 'downloads_search_clear',
                  submitKey: 'downloads_search_submit',
                  compact: true,
                  hintText: l10n(context).downloadsSearchHint,
                  onChanged: onChanged,
                  onClear: onClear,
                  onSubmit: onSubmit,
                  onSubmitted: (_) => onSubmit(),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
