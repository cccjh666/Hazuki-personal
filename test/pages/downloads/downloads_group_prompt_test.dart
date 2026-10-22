import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hazuki/features/downloads/state/downloads_page_controller.dart';
import 'package:hazuki/l10n/app_localizations.dart';
import 'package:hazuki/l10n/app_localizations_zh.dart';
import 'package:hazuki/services/download_groups_service.dart';
import 'package:hazuki/services/manga_download/manga_download_service.dart';
import 'package:hazuki/services/storage/hazuki_database.dart';

void main() {
  test('single comic move reports the groups it left', () async {
    final database = HazukiDatabase.memory();
    final groups = DownloadGroupsService(database: database);
    final downloads = MangaDownloadService();
    final controller = DownloadsPageController(
      downloadService: downloads,
      downloadGroupsService: groups,
    );
    const comic = DownloadedMangaComic(
      comicId: 'comic-a',
      title: 'Comic A',
      subTitle: '',
      description: '',
      coverUrl: '',
      localCoverPath: null,
      chapters: [],
      updatedAtMillis: 0,
    );

    await groups.initialize([comic.storageKey]);
    final first = await groups.createGroup('First');
    final second = await groups.createGroup('Second');
    await groups.addComicToGroups(comic.storageKey, {first.id, second.id});

    final result = await controller.updateComicGroups(comic, second.id);

    expect(result.changed, isTrue);
    expect(result.removedGroupIds, {
      DownloadGroupsService.defaultGroupId,
      first.id,
    });
    expect(groups.groupIdsForComic(comic.storageKey), {second.id});

    await groups.addComicToGroup(comic.storageKey, first.id);
    controller.toggleSelection(comic.storageKey);
    final bulkResult = await controller.updateSelectedComicsGroups(first.id);

    expect(bulkResult.comicCount, 1);
    expect(bulkResult.changedGroupCount, 1);
    expect(groups.groupIdsForComic(comic.storageKey), {first.id});

    controller.dispose();
    downloads.dispose();
    groups.dispose();
    await database.close();
  });

  test('Chinese group prompts distinguish one and multiple groups', () {
    final strings = AppLocalizationsZh();

    expect(strings.downloadsComicRemovedFromGroup('收藏组'), '该漫画已从收藏组移出');
    expect(strings.downloadsComicRemovedFromGroups(2), '已将该漫画从2个组中移出');
    expect(strings.downloadsBatchAddedToGroup(3, '收藏组'), '已将3部漫画添加到收藏组');
    expect(strings.downloadsBatchAddedToGroups(3, 2), '已将3部漫画添加到2个组中');
    expect(strings.downloadsBatchMovedToGroup(3, '收藏组'), '已将3部漫画移动到收藏组');
    expect(strings.downloadsBatchMovedToGroups(3, 2), '已将3部漫画移动到2个组中');
    expect(strings.downloadsBatchRemovedFromGroup(3, '收藏组'), '已将3部漫画从收藏组移出');
    expect(strings.downloadsBatchRemovedFromGroups(3, 2), '已将3部漫画从2个组中移出');
  });

  test('a single comic can be sent back to the default group', () async {
    final database = HazukiDatabase.memory();
    final groups = DownloadGroupsService(database: database);
    final downloads = MangaDownloadService();
    final controller = DownloadsPageController(
      downloadService: downloads,
      downloadGroupsService: groups,
    );
    const comic = DownloadedMangaComic(
      comicId: 'comic-a',
      title: 'Comic A',
      subTitle: '',
      description: '',
      coverUrl: '',
      localCoverPath: null,
      chapters: [],
      updatedAtMillis: 0,
    );

    await groups.initialize([comic.storageKey]);
    final customGroup = await groups.createGroup('Custom');
    await groups.moveComicToGroup(comic.storageKey, customGroup.id);
    controller.selectGroup(customGroup.id);

    // There is no dedicated "remove from group" action any more: the default
    // group is just another pick, and it lands the comic back on the default.
    final moved = await controller.updateComicGroups(
      comic,
      DownloadGroupsService.defaultGroupId,
    );
    expect(moved.changed, isTrue);
    expect(groups.groupIdsForComic(comic.storageKey), {
      DownloadGroupsService.defaultGroupId,
    });

    // Re-picking the group it already lives in changes nothing.
    final again = await controller.updateComicGroups(
      comic,
      DownloadGroupsService.defaultGroupId,
    );
    expect(again.changed, isFalse);

    controller.dispose();
    downloads.dispose();
    groups.dispose();
    await database.close();
  });

  test('batch group update moves the whole selection into one group', () async {
    final database = HazukiDatabase.memory();
    final groups = DownloadGroupsService(database: database);
    final downloads = MangaDownloadService();
    final controller = DownloadsPageController(
      downloadService: downloads,
      downloadGroupsService: groups,
    );
    await groups.initialize(const ['comic-a', 'comic-b']);
    final first = await groups.createGroup('First');
    final second = await groups.createGroup('Second');
    final third = await groups.createGroup('Third');
    await groups.moveComicToGroup('comic-a', first.id);
    await groups.moveComicToGroup('comic-b', second.id);
    controller.toggleSelection('comic-a');
    controller.toggleSelection('comic-b');
    // The selection spans two groups, so no single group is pre-selected.
    expect(controller.commonSelectedGroupId, isNull);

    final result = await controller.updateSelectedComicsGroups(third.id);

    expect(result.comicCount, 2);
    expect(result.changedGroupCount, 2);
    expect(groups.groupIdsForComic('comic-a'), {third.id});
    expect(groups.groupIdsForComic('comic-b'), {third.id});
    expect(controller.selectedCount, 0);

    controller.dispose();
    downloads.dispose();
    groups.dispose();
    await database.close();
  });

  test('batch group update skips comics already in the target group', () async {
    final database = HazukiDatabase.memory();
    final groups = DownloadGroupsService(database: database);
    final downloads = MangaDownloadService();
    final controller = DownloadsPageController(
      downloadService: downloads,
      downloadGroupsService: groups,
    );
    await groups.initialize(const ['comic-a', 'comic-b']);
    final first = await groups.createGroup('First');
    await groups.moveComicToGroup('comic-a', first.id);
    controller.toggleSelection('comic-a');
    controller.toggleSelection('comic-b');
    expect(controller.commonSelectedGroupId, isNull);

    final result = await controller.updateSelectedComicsGroups(first.id);

    expect(result.comicCount, 2);
    // Only comic-b actually moves; comic-a stays untouched and is not rewritten.
    expect(result.changedGroupCount, 1);
    expect(groups.groupIdsForComic('comic-a'), {first.id});
    expect(groups.groupIdsForComic('comic-b'), {first.id});

    controller.dispose();
    downloads.dispose();
    groups.dispose();
    await database.close();
  });

  testWidgets('deleting a local download preserves synced group memberships', (
    tester,
  ) async {
    final database = HazukiDatabase.memory();
    final groups = DownloadGroupsService(database: database);
    final downloads = _DeleteTrackingDownloadService();
    final controller = DownloadsPageController(
      downloadService: downloads,
      downloadGroupsService: groups,
    );
    const comic = DownloadedMangaComic(
      comicId: 'comic-a',
      title: 'Comic A',
      subTitle: '',
      description: '',
      coverUrl: '',
      localCoverPath: null,
      chapters: [],
      updatedAtMillis: 0,
    );
    await groups.initialize([comic.storageKey]);
    final customGroup = await groups.createGroup('Custom');
    await groups.moveComicToGroup(comic.storageKey, customGroup.id);

    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final deletion = controller.deleteSingleComic(context, comic);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await deletion;

    expect(downloads.deletedKeys, {comic.storageKey});
    expect(groups.groupIdsForComic(comic.storageKey), {customGroup.id});

    controller.dispose();
    downloads.dispose();
    groups.dispose();
    await database.close();
  });
}

class _DeleteTrackingDownloadService extends MangaDownloadService {
  final Set<String> deletedKeys = {};

  @override
  Future<void> deleteDownloadedComics(Iterable<String> comicIds) async {
    deletedKeys.addAll(comicIds);
    notifyListeners();
  }
}
