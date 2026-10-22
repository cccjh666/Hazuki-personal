import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hazuki/features/downloads/view/downloaded_comic_detail_widgets.dart';
import 'package:hazuki/l10n/app_localizations.dart';
import 'package:hazuki/services/manga_download/manga_download_models.dart';

void main() {
  testWidgets('description over four lines expands fully and collapses', (
    tester,
  ) async {
    const description = 'Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6';

    await tester.pumpWidget(_wrapDescription(description));

    final textFinder = find.byKey(
      const ValueKey<String>('downloaded_description_text'),
    );
    final sizeFinder = find.byKey(
      const ValueKey<String>('downloaded_description_size'),
    );
    final toggleFinder = find.byKey(
      const ValueKey<String>('downloaded_description_toggle'),
    );
    final collapsedHeight = tester.getSize(sizeFinder).height;
    var text = tester.widget<Text>(textFinder);

    expect(text.maxLines, 4);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(toggleFinder, findsOneWidget);

    await tester.tap(toggleFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));

    final expandingHeight = tester.getSize(sizeFinder).height;
    expect(expandingHeight, greaterThan(collapsedHeight));

    await tester.pumpAndSettle();
    text = tester.widget<Text>(textFinder);
    final expandedHeight = tester.getSize(sizeFinder).height;

    expect(text.data, description);
    expect(text.maxLines, isNull);
    expect(text.overflow, TextOverflow.visible);
    expect(expandedHeight, greaterThan(collapsedHeight));

    await tester.tap(toggleFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));

    expect(tester.getSize(sizeFinder).height, lessThan(expandedHeight));

    await tester.pumpAndSettle();
    text = tester.widget<Text>(textFinder);

    expect(text.maxLines, 4);
    expect(tester.getSize(sizeFinder).height, collapsedHeight);
  });

  testWidgets('description with four lines does not show a toggle', (
    tester,
  ) async {
    await tester.pumpWidget(_wrapDescription('Line 1\nLine 2\nLine 3\nLine 4'));

    expect(
      find.byKey(const ValueKey<String>('downloaded_description_toggle')),
      findsNothing,
    );
  });

  testWidgets('overview and metadata show offline comic details', (
    tester,
  ) async {
    const comic = DownloadedMangaComic(
      comicId: 'comic-123',
      sourceKey: 'jm',
      title: 'Hazuki',
      subTitle: 'Subtitle',
      description: '',
      coverUrl: '',
      tags: {
        '作者': ['Author A'],
        '标签': ['Tag A', 'Tag B'],
      },
      uploader: 'Uploader A',
      updateTime: '2026-06-14',
      pageCount: '128',
      localCoverPath: null,
      chapters: [],
      updatedAtMillis: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(
            children: [
              DownloadedComicOverviewCard(
                comic: comic,
                imageCount: 20,
                coverHeroTag: 'cover',
                onCoverTap: () {},
                onCopyId: () {},
              ),
              DownloadedComicMetadata(
                tags: comic.tags,
                uploader: comic.uploader,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('ID: comic-123'), findsOneWidget);
    expect(find.text('Author A'), findsOneWidget);
    expect(find.text('Tag A'), findsOneWidget);
    expect(find.text('Tag B'), findsOneWidget);
    expect(find.text('Uploader A'), findsOneWidget);
    expect(find.textContaining('2026-06-14'), findsOneWidget);
  });

  testWidgets('author and uploader chips copy their value, plain tags do not', (
    tester,
  ) async {
    final copied = <String>[];
    await tester.pumpWidget(
      _wrapMetadata(
        const DownloadedMangaComic(
          comicId: 'comic-1',
          sourceKey: 'jm',
          title: 'Hazuki',
          subTitle: '',
          description: '',
          coverUrl: '',
          tags: {
            '作者': ['Author A'],
            '标签': ['Tag A'],
          },
          uploader: 'Uploader A',
          localCoverPath: null,
          chapters: [],
          updatedAtMillis: 1,
        ),
        onCopyValue: copied.add,
      ),
    );

    // 「作者」标签行与「上传者」行都可点复制
    await _tapMetadataChip(tester, 'Author A');
    await _tapMetadataChip(tester, 'Uploader A');

    expect(copied, ['Author A', 'Uploader A']);

    // 普通标签不可点：没有可点击容器，点了也不产生回调
    await tester.tap(find.text('Tag A'));
    await tester.pump();
    expect(copied, hasLength(2));
    expect(
      find.ancestor(of: find.text('Tag A'), matching: find.byType(InkWell)),
      findsNothing,
    );
  });
}

/// 点击元数据里某个值（chip），用于验证复制行为。
Future<void> _tapMetadataChip(WidgetTester tester, String value) async {
  final chip = find.ancestor(
    of: find.text(value),
    matching: find.byType(InkWell),
  );
  expect(chip, findsWidgets, reason: '$value 应该是一个可点击复制的标签');
  await tester.tap(chip.first);
  await tester.pump();
}

Widget _wrapMetadata(
  DownloadedMangaComic comic, {
  ValueChanged<String>? onCopyValue,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: DownloadedComicMetadata(
        tags: comic.tags,
        uploader: comic.uploader,
        onCopyValue: onCopyValue,
      ),
    ),
  );
}

Widget _wrapDescription(String text) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 240,
          child: DownloadedComicExpandableDescription(text: text),
        ),
      ),
    ),
  );
}
