import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hazuki/features/settings/view/about_page.dart';
import 'package:hazuki/features/settings/view/about_page_content.dart';
import 'package:hazuki/l10n/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';

Widget _app(
  Widget page, {
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.purple,
      brightness: brightness,
    ),
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: page,
);

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 200);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Hazuki',
      packageName: 'com.example.hazuki',
      version: '1.1.9',
      buildNumber: '20',
      buildSignature: '',
    );
  });

  Widget page() => const AboutPage();

  for (final scenario in [
    (width: 320.0, scale: 1.0, locale: 'en', brightness: Brightness.light),
    (width: 320.0, scale: 2.0, locale: 'en', brightness: Brightness.dark),
    (width: 390.0, scale: 2.0, locale: 'zh', brightness: Brightness.light),
    (width: 1280.0, scale: 1.0, locale: 'zh', brightness: Brightness.dark),
  ]) {
    testWidgets(
      'about fits ${scenario.width}px, ${scenario.scale}x text, ${scenario.locale}, ${scenario.brightness.name}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(scenario.width, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          _app(
            page(),
            locale: Locale(scenario.locale),
            brightness: scenario.brightness,
            textScale: scenario.scale,
          ),
        );
        await tester.pumpAndSettle();
        final strings = AppLocalizations.of(
          tester.element(find.byType(AboutPage)),
        )!;
        expect(find.text(strings.aboutVersion('1.1.9')), findsOneWidget);
        expect(find.text('GPL-3.0'), findsOneWidget);
        expect(find.byType(FlutterLogo), findsNothing);
        expect(tester.takeException(), isNull);

        for (final label in [
          strings.aboutProjectTitle,
          strings.aboutFeedbackTitle,
          strings.aboutDisclaimerTitle,
          strings.aboutThirdPartyLicensesTitle,
        ]) {
          await _scrollTo(tester, find.text(label));
          expect(find.text(label).hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  // 这个 fork 移除了应用自身的更新检查：关于页不应再出现任何「检查更新」入口，
  // 否则用户可能被引导去装官方签名的新包，覆盖掉本地修改版。
  testWidgets('about page has no update entry point', (tester) async {
    await tester.pumpWidget(_app(page()));
    await tester.pumpAndSettle();
    final strings = AppLocalizations.of(
      tester.element(find.byType(AboutPage)),
    )!;

    expect(find.text(strings.aboutCheckUpdateTitle), findsNothing);
    expect(find.text(strings.aboutCheckSoftwareUpdateSubtitle), findsNothing);
    expect(find.byIcon(Icons.system_update_alt_rounded), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disclaimer opens, closes, and licenses show the real version', (
    tester,
  ) async {
    await tester.pumpWidget(_app(page()));
    await tester.pumpAndSettle();
    final strings = AppLocalizations.of(
      tester.element(find.byType(AboutPage)),
    )!;
    await _scrollTo(tester, find.text(strings.aboutDisclaimerTitle));
    await tester.tap(find.text(strings.aboutDisclaimerTitle));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(strings.aboutDisclaimerContent), findsOneWidget);
    await tester.tap(find.text(strings.commonClose));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    await _scrollTo(tester, find.text(strings.aboutThirdPartyLicensesTitle));
    await tester.tap(find.text(strings.aboutThirdPartyLicensesTitle));
    await tester.pumpAndSettle();
    final licensePage = tester.widget<LicensePage>(find.byType(LicensePage));
    expect(licensePage.applicationName, 'Hazuki');
    expect(licensePage.applicationVersion, '1.1.9');
    expect(find.byType(FlutterLogo), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('project and feedback entries invoke their own actions', (
    tester,
  ) async {
    var projects = 0;
    var feedback = 0;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: AboutPageContent(
            currentVersion: '1.1.9',
            onOpenProject: () => projects++,
            onOpenFeedback: () => feedback++,
            onOpenDisclaimer: () {},
            onOpenLicenses: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final strings = AppLocalizations.of(
      tester.element(find.byType(AboutPageContent)),
    )!;
    await _scrollTo(tester, find.text(strings.aboutProjectTitle));
    await tester.tap(find.text(strings.aboutProjectTitle));
    await _scrollTo(tester, find.text(strings.aboutFeedbackTitle));
    await tester.tap(find.text(strings.aboutFeedbackTitle));
    expect(projects, 1);
    expect(feedback, 1);
  });
}
