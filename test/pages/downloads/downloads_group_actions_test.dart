import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hazuki/features/downloads/support/downloads_group_actions.dart';
import 'package:hazuki/l10n/app_localizations.dart';
import 'package:hazuki/services/download_groups_service.dart';

void main() {
  testWidgets('upward long press menu anchors to the comic top edge', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Builder(
                builder: (itemContext) => SizedBox(
                  key: const ValueKey<String>('comic_item'),
                  height: 80,
                  width: 300,
                  child: FilledButton(
                    onPressed: () {
                      showDownloadsComicMenu(
                        context: context,
                        itemContext: itemContext,
                        globalPosition: const Offset(200, 580),
                      );
                    },
                    child: const Text('Open menu'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open menu'));
    await tester.pumpAndSettle();

    final cardRect = tester.getRect(
      find.byKey(const ValueKey<String>('comic_item')),
    );
    final menuRect = tester.getRect(
      find.byKey(const ValueKey<String>('downloads_comic_long_press_menu')),
    );
    expect(menuRect.bottom, closeTo(cardRect.top - 8, 0.1));
    expect(find.text('Move to group'), findsOneWidget);
    // A comic lives in exactly one group, so the redundant "remove" entry is
    // gone: moving back to the default group is just another group pick.
    expect(find.text('Remove from this group'), findsNothing);
    expect(find.text('Add to group'), findsNothing);
  });

  testWidgets('group picker keeps exactly one group selected', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await showDownloadGroupPicker(
                  context: context,
                  groups: const [
                    DownloadGroup(
                      id: DownloadGroupsService.defaultGroupId,
                      name: DownloadGroupsService.defaultGroupName,
                      createdAtMs: 0,
                    ),
                    DownloadGroup(id: 'a', name: 'A', createdAtMs: 1),
                    DownloadGroup(id: 'b', name: 'B', createdAtMs: 2),
                  ],
                  initiallySelectedGroupId:
                      DownloadGroupsService.defaultGroupId,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final listView = tester.widget<ListView>(find.byType(ListView));
    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(listView.padding, EdgeInsets.zero);
    expect(
      dialog.insetPadding,
      const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
    );
    expect(find.byType(CheckboxListTile), findsNothing);

    double checkOpacity(String groupId) => tester
        .widget<AnimatedOpacity>(
          find.descendant(
            of: find.byKey(ValueKey<String>('downloads_pick_group_$groupId')),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;

    // The current group starts selected and nothing else is.
    expect(checkOpacity(DownloadGroupsService.defaultGroupId), 1);
    expect(checkOpacity('a'), 0);
    expect(checkOpacity('b'), 0);

    await tester.tap(find.byKey(const ValueKey<String>('downloads_pick_group_a')));
    await tester.pumpAndSettle();
    expect(checkOpacity('a'), 1);
    expect(checkOpacity(DownloadGroupsService.defaultGroupId), 0);
    expect(checkOpacity('b'), 0);

    await tester.tap(find.byKey(const ValueKey<String>('downloads_pick_group_b')));
    await tester.pumpAndSettle();
    expect(checkOpacity('b'), 1);
    expect(checkOpacity('a'), 0);
    expect(checkOpacity(DownloadGroupsService.defaultGroupId), 0);

    // Re-selecting the same group changes nothing (no flicker, same result).
    await tester.tap(find.byKey(const ValueKey<String>('downloads_pick_group_b')));
    await tester.pumpAndSettle();
    expect(checkOpacity('b'), 1);
    expect(checkOpacity('a'), 0);

    await tester.tap(find.widgetWithText(FilledButton, 'Move'));
    await tester.pumpAndSettle();

    expect(result, 'b');
  });

  testWidgets('long press menu keeps delete as the only destructive entry', (
    tester,
  ) async {
    DownloadsComicMenuAction? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Builder(
              builder: (itemContext) => FilledButton(
                onPressed: () async {
                  result = await showDownloadsComicMenu(
                    context: context,
                    itemContext: itemContext,
                    globalPosition: const Offset(200, 200),
                  );
                },
                child: const Text('Open menu'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open menu'));
    await tester.pumpAndSettle();

    expect(find.text('Remove from this group'), findsNothing);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(result, DownloadsComicMenuAction.delete);
  });

  testWidgets('group picker only warns after saving without a group', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () {
                showDownloadGroupPicker(
                  context: context,
                  groups: const [
                    DownloadGroup(id: 'a', name: 'A', createdAtMs: 1),
                  ],
                  initiallySelectedGroupId: null,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Select one group'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Move'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Move'));
    await tester.pumpAndSettle();

    expect(find.text('Select one group'), findsOneWidget);
    final cancelCenter = tester.getCenter(
      find.widgetWithText(TextButton, 'Cancel'),
    );
    final moveCenter = tester.getCenter(
      find.widgetWithText(FilledButton, 'Move'),
    );
    expect(cancelCenter.dy, closeTo(moveCenter.dy, 0.1));
  });

  testWidgets('bulk group dialog opens straight on the group list', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () {
                showDownloadsBulkGroupDialog(
                  context: context,
                  groups: const [
                    DownloadGroup(id: 'a', name: 'A', createdAtMs: 1),
                    DownloadGroup(id: 'b', name: 'B', createdAtMs: 2),
                  ],
                  selectedComicCount: 2,
                  initialGroupId: null,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final dialog = find.byKey(
      const ValueKey<String>('downloads_bulk_group_dialog'),
    );
    expect(tester.getSize(dialog), const Size(420, 500));
    // No intermediate "move / remove" stage any more.
    expect(
      find.byKey(const ValueKey<String>('downloads_bulk_action_stage')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('downloads_bulk_group_stage')),
      findsOneWidget,
    );
    expect(find.text('Remove from this group'), findsNothing);
    expect(find.text('2 comics selected'), findsOneWidget);
  });

  testWidgets('bulk dialog moves the whole selection into one group', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await showDownloadsBulkGroupDialog(
                  context: context,
                  groups: const [
                    DownloadGroup(id: 'a', name: 'A', createdAtMs: 1),
                    DownloadGroup(id: 'b', name: 'B', createdAtMs: 2),
                  ],
                  selectedComicCount: 2,
                  initialGroupId: 'a',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('2 comics selected'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('downloads_bulk_group_stage')),
      findsOneWidget,
    );
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.widgetWithText(TextButton, 'View'), findsNothing);

    double checkOpacity(String groupId) => tester
        .widget<AnimatedOpacity>(
          find.descendant(
            of: find.byKey(ValueKey<String>('downloads_bulk_group_$groupId')),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;

    // The group shared by the selection starts checked, the other one does not.
    expect(checkOpacity('a'), 1);
    expect(checkOpacity('b'), 0);

    await tester.tap(
      find.byKey(const ValueKey<String>('downloads_bulk_group_b')),
    );
    await tester.pumpAndSettle();
    expect(checkOpacity('b'), 1);
    expect(checkOpacity('a'), 0);
    expect(find.text('Select one group'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Move'));
    await tester.pumpAndSettle();

    expect(result, 'b');
  });
}
