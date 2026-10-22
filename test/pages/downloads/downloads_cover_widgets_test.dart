import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hazuki/features/downloads/downloads.dart';
import 'package:hazuki/services/manga_download/manga_download_service.dart';
import 'package:hazuki/widgets/widgets.dart';
import '../../support/test_service_locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    await ensureTestServiceLocator();
  });

  group('DownloadedComicCover', () {
    testWidgets('does not load network cover when no local path is provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithMaterialApp(
          DownloadedComicCover(
            comic: _comic(
              localCoverPath: '   ',
              coverUrl: 'https://example.com/cover.jpg',
            ),
          ),
        ),
      );

      expect(find.byType(HazukiCachedImage), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('downloaded_cover_placeholder')),
        findsOneWidget,
      );
    });

    testWidgets(
      'shows fallback icon when local path is set but file is missing',
      (tester) async {
        await tester.pumpWidget(
          _wrapWithMaterialApp(
            DownloadedComicCover(
              comic: _comic(localCoverPath: 'Z:/missing-cover.png'),
            ),
          ),
        );

        expect(find.byType(HazukiCachedImage), findsNothing);
        expect(
          find.byKey(const ValueKey<String>('downloaded_cover_placeholder')),
          findsOneWidget,
        );
      },
    );

    testWidgets('wraps content with hero and handles taps', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        _wrapWithMaterialApp(
          DownloadedComicCover(
            comic: _comic(coverUrl: 'https://example.com/cover.jpg'),
            heroTag: 'download-cover-hero',
            onTap: () => tapped = true,
          ),
        ),
      );

      expect(find.byType(Hero), findsOneWidget);
      expect(find.byType(InkWell), findsOneWidget);

      await tester.tap(find.byType(InkWell));
      expect(tapped, isTrue);
    });

    testWidgets('decodes the local cover at the display size', (tester) async {
      // 必须在 fake-async 环境里用同步 IO，否则异步文件操作会一直挂起。
      final directory = Directory.systemTemp.createTempSync('hazuki-cover');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/cover.png')
        ..writeAsBytesSync(_tinyPng);
      DownloadedComicCover.debugResetCoverFileCache();

      await tester.pumpWidget(
        _wrapWithMaterialApp(
          DownloadedComicCover(comic: _comic(localCoverPath: file.path)),
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      final provider = image.image;
      // 不按显示尺寸解码会把整张封面读进内存（掉帧主因之一）。
      expect(provider, isA<ResizeImage>());
      expect(
        (provider as ResizeImage).width,
        (84 * MediaQuery.of(tester.element(find.byType(Image))).devicePixelRatio)
            .round(),
      );
      expect((provider).height, isNull);
    });
  });

  group('DownloadedComicCoverPreviewPage', () {
    testWidgets('shows bundled placeholder when cover is unavailable', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithMaterialApp(
          DownloadedComicCoverPreviewPage(
            comic: _comic(localCoverPath: null, coverUrl: '   '),
            heroTag: 'preview-hero',
          ),
        ),
      );

      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>('downloaded_cover_preview_placeholder'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('uses the full preview area as the zoom canvas', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DownloadedComicCoverPreviewPage(
            comic: _comic(localCoverPath: null, coverUrl: '   '),
            heroTag: 'preview-hero',
          ),
        ),
      );

      final viewerFinder = find.byKey(
        const ValueKey<String>('downloaded_cover_viewer'),
      );
      final viewer = tester.widget<InteractiveViewer>(viewerFinder);
      final viewerSize = tester.getSize(viewerFinder);

      expect(viewer.clipBehavior, Clip.none);
      expect(viewer.boundaryMargin, EdgeInsets.zero);
      expect(viewerSize.width, greaterThan(700));
      expect(viewerSize.height, greaterThan(500));
    });

    testWidgets('keeps the cover fixed while it is not zoomed', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DownloadedComicCoverPreviewPage(
            comic: _comic(localCoverPath: null, coverUrl: '   '),
            heroTag: 'preview-hero',
          ),
        ),
      );

      final coverFinder = find.byKey(
        const ValueKey<String>('downloaded_cover_preview_placeholder'),
      );
      final originalCenter = tester.getCenter(coverFinder);

      await tester.drag(coverFinder, const Offset(140, 100));
      await tester.pumpAndSettle();

      final draggedCenter = tester.getCenter(coverFinder);
      expect(draggedCenter.dx, closeTo(originalCenter.dx, 0.01));
      expect(draggedCenter.dy, closeTo(originalCenter.dy, 0.01));
    });

    testWidgets('tapping preview pops the route', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => DownloadedComicCoverPreviewPage(
                            comic: _comic(localCoverPath: null, coverUrl: ''),
                            heroTag: 'preview-hero',
                          ),
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(DownloadedComicCoverPreviewPage), findsOneWidget);

      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();
      expect(find.byType(DownloadedComicCoverPreviewPage), findsNothing);
    });
  });
}

Widget _wrapWithMaterialApp(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}

/// 1x1 透明 PNG，用于验证本地封面按显示尺寸解码。
const _tinyPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82,
];

DownloadedMangaComic _comic({String? localCoverPath, String coverUrl = ''}) {
  return DownloadedMangaComic(
    comicId: 'comic-1',
    title: 'Test Comic',
    subTitle: 'Subtitle',
    description: 'Description',
    coverUrl: coverUrl,
    localCoverPath: localCoverPath,
    chapters: const [],
    updatedAtMillis: 0,
  );
}
