import 'package:hazuki/shared/text/chinese_conversion_scope.dart';
import 'package:flutter/material.dart';
import 'package:hazuki/l10n/l10n.dart';
import 'package:hazuki/services/manga_download/manga_download_models.dart';

import 'downloads_cover_widgets.dart';

class DownloadedComicOverviewCard extends StatelessWidget {
  const DownloadedComicOverviewCard({
    super.key,
    required this.comic,
    required this.imageCount,
    required this.coverHeroTag,
    required this.onCoverTap,
    required this.onCopyId,
  });

  final DownloadedMangaComic comic;
  final int imageCount;
  final String coverHeroTag;
  final VoidCallback onCoverTap;
  final VoidCallback onCopyId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cover = DownloadedComicCover(
      comic: comic,
      heroTag: coverHeroTag,
      width: 116,
      height: 162,
      borderRadius: 14,
      onTap: onCoverTap,
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          convertChineseText(context, comic.title),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        if (comic.subTitle.trim().isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            comic.subTitle.trim(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 5,
          children: [
            _DownloadedComicStatChip(
              icon: Icons.library_books_outlined,
              label: l10n(
                context,
              ).downloadsChapterCount('${comic.chapters.length}'),
            ),
            _DownloadedComicStatChip(
              icon: Icons.image_outlined,
              label: l10n(
                context,
              ).downloadsCurrentProgress('$imageCount', '$imageCount'),
            ),
            if (comic.pageCount.trim().isNotEmpty)
              _DownloadedComicStatChip(
                icon: Icons.auto_stories_outlined,
                label: l10n(context).comicDetailPagesCount(comic.pageCount),
              ),
          ],
        ),
        const SizedBox(height: 8),
        InkWell(
          key: const ValueKey<String>('downloaded_comic_copy_id'),
          borderRadius: BorderRadius.circular(6),
          onTap: onCopyId,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    'ID: ${comic.comicId}',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Icon(
                  Icons.copy_all_outlined,
                  size: 14,
                  color: colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
        if (comic.updateTime.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            l10n(context).comicDetailUpdatedAt(comic.updateTime.trim()),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cover,
          const SizedBox(width: 12),
          Expanded(child: details),
        ],
      ),
    );
  }
}

class DownloadedComicSectionCard extends StatelessWidget {
  const DownloadedComicSectionCard({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class DownloadedComicMetadata extends StatelessWidget {
  const DownloadedComicMetadata({
    super.key,
    required this.tags,
    required this.uploader,
    this.onCopyValue,
  });

  final Map<String, List<String>> tags;
  final String uploader;

  /// 点击作者/上传者时回调（用于复制到剪贴板）；为 null 时这些值不可点。
  final ValueChanged<String>? onCopyValue;

  /// 作者类标签名：不同源可能用不同写法，命中即允许复制。
  static const Set<String> _authorLikeLabels = <String>{
    '作者',
    '著者',
    '作者名',
    '上传者',
    '上傳者',
    'author',
    'authors',
    'uploader',
  };

  static bool _isAuthorLikeLabel(String label) =>
      _authorLikeLabels.contains(label.trim().toLowerCase());

  @override
  Widget build(BuildContext context) {
    final rows = <({String label, List<String> values, bool copyable})>[
      for (final entry in tags.entries)
        (
          label: entry.key,
          values: entry.value,
          copyable: _isAuthorLikeLabel(entry.key),
        ),
      if (uploader.trim().isNotEmpty)
        (
          label: l10n(context).comicDetailUploader,
          values: <String>[uploader.trim()],
          copyable: true,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          if (row.values.any((value) => value.trim().isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _DownloadedComicMetadataRow(
                label: row.label,
                values: row.values,
                // 只有作者类行支持复制，避免点普通标签时误触。
                onCopyValue: row.copyable ? onCopyValue : null,
              ),
            ),
      ],
    );
  }
}

class _DownloadedComicStatChip extends StatelessWidget {
  const _DownloadedComicStatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colorScheme.onSecondaryContainer),
          const SizedBox(width: 3),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadedComicMetadataRow extends StatelessWidget {
  const _DownloadedComicMetadataRow({
    required this.label,
    required this.values,
    this.onCopyValue,
  });

  final String label;
  final List<String> values;

  /// 非 null 时每个值都可点击复制，并在标签右侧显示复制图标。
  final ValueChanged<String>? onCopyValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final normalizedValues = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 58,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Wrap(
            spacing: 5,
            runSpacing: 4,
            children: normalizedValues
                .map((value) => _buildValueChip(theme, colorScheme, value))
                .toList(growable: false),
          ),
        ),
      ],
    );
  }

  Widget _buildValueChip(
    ThemeData theme,
    ColorScheme colorScheme,
    String value,
  ) {
    final copyHandler = onCopyValue;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onTertiaryContainer,
            ),
          ),
          if (copyHandler != null) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.copy_all_outlined,
              size: 12,
              color: colorScheme.onTertiaryContainer.withValues(alpha: 0.7),
            ),
          ],
        ],
      ),
    );
    if (copyHandler == null) return chip;
    return Semantics(
      button: true,
      // 让读屏播报「作者：xxx」而不是重复播报内部文本。
      label: '$label：$value',
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey<String>('downloaded_metadata_copy_$label'),
        borderRadius: BorderRadius.circular(999),
        onTap: () => copyHandler(value),
        child: chip,
      ),
    );
  }
}

class DownloadedComicExpandableDescription extends StatefulWidget {
  const DownloadedComicExpandableDescription({super.key, required this.text});

  final String text;

  @override
  State<DownloadedComicExpandableDescription> createState() =>
      _DownloadedComicExpandableDescriptionState();
}

class _DownloadedComicExpandableDescriptionState
    extends State<DownloadedComicExpandableDescription> {
  static const int _collapsedMaxLines = 4;
  static const Duration _animationDuration = Duration(milliseconds: 280);

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final text = convertChineseText(context, widget.text);
    final theme = Theme.of(context);
    final textStyle =
        theme.textTheme.bodyMedium ??
        const TextStyle(fontSize: 14, height: 1.5);
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: text, style: textStyle),
          maxLines: _collapsedMaxLines,
          textDirection: textDirection,
          textScaler: textScaler,
        )..layout(maxWidth: constraints.maxWidth);

        final isOverflowing = textPainter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedSize(
              key: const ValueKey<String>('downloaded_description_size'),
              duration: _animationDuration,
              reverseDuration: _animationDuration,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              clipBehavior: Clip.hardEdge,
              child: Text(
                key: const ValueKey<String>('downloaded_description_text'),
                text,
                style: textStyle,
                maxLines: _expanded ? null : _collapsedMaxLines,
                overflow: _expanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
              ),
            ),
            if (isOverflowing)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    key: const ValueKey<String>(
                      'downloaded_description_toggle',
                    ),
                    borderRadius: BorderRadius.circular(999),
                    onTap: () {
                      setState(() {
                        _expanded = !_expanded;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _expanded
                                ? l10n(context).comicDetailCollapse
                                : l10n(context).comicDetailExpand,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 2),
                          AnimatedRotation(
                            turns: _expanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            child: Icon(
                              Icons.keyboard_arrow_down,
                              size: 18,
                              color: theme.colorScheme.primary,
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
}
