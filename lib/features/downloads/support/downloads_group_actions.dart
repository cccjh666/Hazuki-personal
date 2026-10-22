import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:hazuki/l10n/l10n.dart';
import 'package:hazuki/services/download_groups/download_group.dart';

/// One of the remaining actions of the downloaded comic menu.
///
/// A comic belongs to exactly one group, so there is no "remove from this
/// group" entry: moving back to the default group is a plain group pick.
enum DownloadsComicMenuAction { updateGroups, delete }

Future<DownloadsComicMenuAction?> showDownloadsComicMenu({
  required BuildContext context,
  required BuildContext itemContext,
  required Offset globalPosition,
}) async {
  final overlay =
      Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
  final cardBox = itemContext.findRenderObject() as RenderBox?;
  if (overlay == null || cardBox == null) return null;

  const width = 212.0;
  const height = 113.0;
  const gap = 8.0;
  final padding = MediaQuery.paddingOf(context);
  final finger = overlay.globalToLocal(globalPosition);
  final cardTop = cardBox.localToGlobal(Offset.zero, ancestor: overlay).dy;
  final cardBottom = cardTop + cardBox.size.height;
  final left = (finger.dx - width / 2).clamp(
    8.0,
    overlay.size.width - width - 8,
  );
  final showBelow =
      cardBottom + gap + height <= overlay.size.height - padding.bottom - 8;
  final top = showBelow
      ? (cardBottom + gap).clamp(
          8 + padding.top,
          overlay.size.height - height - 8,
        )
      : (cardTop - gap - height).clamp(
          8 + padding.top,
          overlay.size.height - height - 8,
        );
  final upwardBottom = overlay.size.height - cardTop + gap;
  final strings = l10n(context);

  return showGeneralDialog<DownloadsComicMenuAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: strings.commonClose,
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 280),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
      );
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          alignment: Alignment(
            ((finger.dx - left) / width * 2 - 1).clamp(-1, 1),
            showBelow ? -1 : 1,
          ),
          scale: Tween<double>(begin: 0.86, end: 1).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final scheme = Theme.of(context).colorScheme;
      return Stack(
        children: [
          Positioned(
            left: left,
            top: showBelow ? top : null,
            bottom: showBelow ? null : upwardBottom,
            width: width,
            child: ClipRRect(
              key: const ValueKey<String>('downloads_comic_long_press_menu'),
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Material(
                  color: scheme.surfaceContainerHigh.withValues(alpha: 0.78),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MenuItem(
                        icon: Icons.drive_file_move_outline,
                        label: strings.downloadsMoveToGroup,
                        onTap: () => Navigator.pop(
                          dialogContext,
                          DownloadsComicMenuAction.updateGroups,
                        ),
                      ),
                      Divider(height: 1, color: scheme.outlineVariant),
                      _MenuItem(
                        icon: Icons.delete_outline,
                        label: strings.comicDetailDelete,
                        danger: true,
                        onTap: () => Navigator.pop(
                          dialogContext,
                          DownloadsComicMenuAction.delete,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// Lets the user choose the single group a comic belongs to.
///
/// Selection is exclusive: tapping a group that is not selected replaces the
/// previous choice in place (200ms background/border cross-fade plus a scaling
/// check), so the two groups never appear checked at the same time.
Future<String?> showDownloadGroupPicker({
  required BuildContext context,
  required List<DownloadGroup> groups,
  String? initiallySelectedGroupId,
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: l10n(context).commonClose,
    transitionDuration: const Duration(milliseconds: 240),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return _DownloadGroupPickerDialog(
        groups: groups,
        initiallySelectedGroupId: initiallySelectedGroupId,
      );
    },
  );
}

/// Opens the batch grouping dialog and returns the chosen group id.
///
/// The dialog starts directly on the group list: a comic can only live in one
/// group, so there is no intermediate "move / remove" step, and "remove from
/// this group" would only ever mean "move to the default group", which the list
/// itself already expresses.
Future<String?> showDownloadsBulkGroupDialog({
  required BuildContext context,
  required List<DownloadGroup> groups,
  required int selectedComicCount,
  required String? initialGroupId,
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: l10n(context).commonClose,
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 280),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (dialogContext, animation, secondaryAnimation) =>
        _DownloadsBulkGroupDialog(
          groups: groups,
          selectedComicCount: selectedComicCount,
          initialGroupId: initialGroupId,
        ),
  );
}

class _DownloadsBulkGroupDialog extends StatefulWidget {
  const _DownloadsBulkGroupDialog({
    required this.groups,
    required this.selectedComicCount,
    required this.initialGroupId,
  });

  final List<DownloadGroup> groups;
  final int selectedComicCount;
  final String? initialGroupId;

  @override
  State<_DownloadsBulkGroupDialog> createState() =>
      _DownloadsBulkGroupDialogState();
}

class _DownloadsBulkGroupDialogState extends State<_DownloadsBulkGroupDialog> {
  String? _selectedGroupId;
  bool _showSelectionRequired = false;

  @override
  void initState() {
    super.initState();
    _selectedGroupId = widget.initialGroupId;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Center(
        child: SizedBox(
          key: const ValueKey<String>('downloads_bulk_group_dialog'),
          width: 420,
          height: 500,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            elevation: 8,
            borderRadius: BorderRadius.circular(28),
            clipBehavior: Clip.antiAlias,
            child: _buildGroupSelection(context),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupSelection(BuildContext context) {
    final strings = l10n(context);
    return Padding(
      key: const ValueKey<String>('downloads_bulk_group_stage'),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.downloadsChooseGroup,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            strings.downloadsSelectedComicCount(widget.selectedComicCount),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: widget.groups.length,
              itemBuilder: (context, index) {
                final group = widget.groups[index];
                return _GroupChoiceTile(
                  key: ValueKey<String>('downloads_bulk_group_${group.id}'),
                  label: group.isDefault
                      ? strings.downloadsDefaultGroup
                      : group.name,
                  selected: _selectedGroupId == group.id,
                  onTap: () => _selectGroup(group.id),
                );
              },
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _showSelectionRequired && _selectedGroupId == null
                ? Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      strings.downloadsSelectOneGroup,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(strings.commonCancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _submit,
                child: Text(strings.downloadsMoveAction),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _selectGroup(String groupId) {
    if (_selectedGroupId == groupId) return;
    setState(() {
      _selectedGroupId = groupId;
      _showSelectionRequired = false;
    });
  }

  void _submit() {
    final groupId = _selectedGroupId;
    if (groupId == null) {
      setState(() => _showSelectionRequired = true);
      return;
    }
    Navigator.pop(context, groupId);
  }
}

class _DownloadGroupPickerDialog extends StatefulWidget {
  const _DownloadGroupPickerDialog({
    required this.groups,
    required this.initiallySelectedGroupId,
  });

  final List<DownloadGroup> groups;
  final String? initiallySelectedGroupId;

  @override
  State<_DownloadGroupPickerDialog> createState() =>
      _DownloadGroupPickerDialogState();
}

class _DownloadGroupPickerDialogState
    extends State<_DownloadGroupPickerDialog> {
  String? _selected;
  bool _showSelectionRequired = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initiallySelectedGroupId;
  }

  @override
  Widget build(BuildContext context) {
    final strings = l10n(context);
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
      title: Text(strings.downloadsChooseGroup),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: widget.groups.length,
                  itemBuilder: (context, index) {
                    final group = widget.groups[index];
                    return _GroupChoiceTile(
                      key: ValueKey<String>('downloads_pick_group_${group.id}'),
                      label: group.isDefault
                          ? strings.downloadsDefaultGroup
                          : group.name,
                      selected: _selected == group.id,
                      onTap: () => setState(() {
                        _selected = group.id;
                        _showSelectionRequired = false;
                      }),
                    );
                  },
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _showSelectionRequired && _selected == null
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        strings.downloadsSelectOneGroup,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.commonCancel),
        ),
        FilledButton(
          onPressed: () {
            final groupId = _selected;
            if (groupId == null) {
              setState(() => _showSelectionRequired = true);
              return;
            }
            Navigator.pop(context, groupId);
          },
          child: Text(strings.downloadsMoveAction),
        ),
      ],
    );
  }
}

/// Exclusive single-choice row used by both the picker and the batch dialog.
///
/// The trailing indicator has a fixed 22x22 box and the row height is driven by
/// padding only, so switching the selection never reflows the list; only the
/// background, border, text weight and the check mark animate.
class _GroupChoiceTile extends StatelessWidget {
  const _GroupChoiceTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: selected ? scheme.primaryContainer : Colors.transparent,
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: Icon(
                    selected ? Icons.folder_rounded : Icons.folder_outlined,
                    key: ValueKey<bool>(selected),
                    size: 20,
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    style: (textTheme.bodyMedium ?? const TextStyle()).copyWith(
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _GroupChoiceIndicator(selected: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupChoiceIndicator extends StatelessWidget {
  const _GroupChoiceIndicator({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 22,
      height: 22,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? scheme.primary : Colors.transparent,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outline,
            width: 1.6,
          ),
        ),
        child: AnimatedOpacity(
          opacity: selected ? 1 : 0,
          duration: const Duration(milliseconds: 140),
          child: AnimatedScale(
            scale: selected ? 1 : 0.4,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutBack,
            child: Icon(Icons.check_rounded, size: 14, color: scheme.onPrimary),
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: color, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
