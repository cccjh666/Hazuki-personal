import 'package:flutter_test/flutter_test.dart';
import 'package:hazuki/features/downloads/state/downloads_completed_list_controller.dart';
import 'package:hazuki/services/manga_download/manga_download_service.dart';

void main() {
  test('list controller owns enter and exit transitions', () async {
    final controller = DownloadsCompletedListController(
      comics: const [_comic1],
      transitionDuration: Duration.zero,
    );

    controller.sync(const [_comic2]);

    expect(controller.entries.map((entry) => entry.comic.comicId), [
      'comic-1',
      'comic-2',
    ]);
    expect(controller.entries.first.exiting, isTrue);
    expect(controller.entries.last.entering, isTrue);

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(controller.entries, hasLength(1));
    expect(controller.entries.single.comic.comicId, 'comic-2');
    expect(controller.entries.single.entering, isFalse);
    controller.dispose();
  });

  const transition = Duration(milliseconds: 40);
  const settle = Duration(milliseconds: 90);

  DownloadsCompletedListController buildController(List<String> comicIds) {
    final controller = DownloadsCompletedListController(
      comics: [for (final id in comicIds) _buildComic(id)],
      transitionDuration: transition,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  List<String> visibleIds(DownloadsCompletedListController controller) => [
    for (final entry in controller.entries) entry.comic.comicId,
  ];

  test('switching context replaces entries without exit animations', () {
    final controller = buildController(['a', 'b', 'c']);

    controller.sync([_buildComic('d'), _buildComic('e')], animateExits: false);

    // 换分组/换检索词是整屏替换：不留出场项，也不逐条加入场动画。
    expect(visibleIds(controller), ['d', 'e']);
    expect(controller.entries.any((entry) => entry.exiting), isFalse);
    expect(controller.entries.any((entry) => entry.entering), isFalse);
  });

  test('removals are flushed in one batch after the transition', () async {
    final controller = buildController(['a', 'b', 'c']);
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.sync([_buildComic('d')]);

    // 旧的 3 项先挂出场态，新的 1 项挂入场态。
    expect(visibleIds(controller), ['a', 'b', 'c', 'd']);
    expect(controller.entries.where((entry) => entry.exiting).length, 3);

    await Future<void>.delayed(settle);

    // 一批定时器一次性清掉出场项，而不是每项各触发一次列表重建。
    expect(visibleIds(controller), ['d']);
    expect(controller.entries.single.entering, isFalse);
    expect(notifications, lessThanOrEqualTo(3));
  });

  test('a comic deleted and re-added before the timer survives', () async {
    final controller = buildController(['a']);

    controller.sync(const []);
    expect(controller.entries.single.exiting, isTrue);

    controller.sync([_buildComic('a')]);
    await Future<void>.delayed(settle);

    expect(visibleIds(controller), ['a']);
    expect(controller.entries.single.exiting, isFalse);
  });

  test('no notification is emitted when the list is unchanged', () {
    final controller = buildController(['a', 'b']);
    final comics = [for (final entry in controller.entries) entry.comic];
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.sync(comics);

    expect(notifications, 0);
  });
}

DownloadedMangaComic _buildComic(String id) => DownloadedMangaComic(
  comicId: id,
  title: 'Comic $id',
  subTitle: '',
  description: '',
  coverUrl: '',
  localCoverPath: null,
  chapters: const [],
  updatedAtMillis: 0,
);

const _comic1 = DownloadedMangaComic(
  comicId: 'comic-1',
  title: 'One',
  subTitle: '',
  description: '',
  coverUrl: '',
  localCoverPath: null,
  chapters: [],
  updatedAtMillis: 1,
);

const _comic2 = DownloadedMangaComic(
  comicId: 'comic-2',
  title: 'Two',
  subTitle: '',
  description: '',
  coverUrl: '',
  localCoverPath: null,
  chapters: [],
  updatedAtMillis: 2,
);
