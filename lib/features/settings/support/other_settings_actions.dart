import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hazuki/shared/preferences/hazuki_preference_keys.dart';
import 'package:hazuki/shared/window/window_title_bar_control.dart';
import 'package:hazuki/l10n/app_localizations.dart';
import 'package:hazuki/services/discover_daily_recommendation_service.dart';
import 'package:hazuki/services/manga_download/manga_download_service.dart';
import 'package:hazuki/services/manga_download/manga_download_storage_support.dart';
import 'package:hazuki/widgets/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OtherSettingsSnapshot {
  const OtherSettingsSnapshot({
    required this.autoCheckInEnabled,
    required this.autoSourceUpdateCheckEnabled,
    required this.aggregateSearchEnabled,
    required this.comicIdSearchEnhanceEnabled,
    required this.discoverDailyRecommendationEnabled,
    required this.useSystemTitleBar,
    required this.mangaDownloadsRootPath,
    required this.loading,
  });

  final bool autoCheckInEnabled;
  final bool autoSourceUpdateCheckEnabled;
  final bool aggregateSearchEnabled;
  final bool comicIdSearchEnhanceEnabled;
  final bool discoverDailyRecommendationEnabled;
  final bool useSystemTitleBar;
  final String mangaDownloadsRootPath;
  final bool loading;

  OtherSettingsSnapshot copyWith({
    bool? autoCheckInEnabled,
    bool? autoSourceUpdateCheckEnabled,
    bool? aggregateSearchEnabled,
    bool? comicIdSearchEnhanceEnabled,
    bool? discoverDailyRecommendationEnabled,
    bool? useSystemTitleBar,
    String? mangaDownloadsRootPath,
    bool? loading,
  }) {
    return OtherSettingsSnapshot(
      autoCheckInEnabled: autoCheckInEnabled ?? this.autoCheckInEnabled,
      autoSourceUpdateCheckEnabled:
          autoSourceUpdateCheckEnabled ?? this.autoSourceUpdateCheckEnabled,
      aggregateSearchEnabled:
          aggregateSearchEnabled ?? this.aggregateSearchEnabled,
      comicIdSearchEnhanceEnabled:
          comicIdSearchEnhanceEnabled ?? this.comicIdSearchEnhanceEnabled,
      discoverDailyRecommendationEnabled:
          discoverDailyRecommendationEnabled ??
          this.discoverDailyRecommendationEnabled,
      useSystemTitleBar: useSystemTitleBar ?? this.useSystemTitleBar,
      mangaDownloadsRootPath:
          mangaDownloadsRootPath ?? this.mangaDownloadsRootPath,
      loading: loading ?? this.loading,
    );
  }

  static OtherSettingsSnapshot initial({required bool useSystemTitleBar}) {
    return OtherSettingsSnapshot(
      autoCheckInEnabled: false,
      autoSourceUpdateCheckEnabled: true,
      aggregateSearchEnabled: false,
      comicIdSearchEnhanceEnabled: false,
      discoverDailyRecommendationEnabled: false,
      useSystemTitleBar: useSystemTitleBar,
      mangaDownloadsRootPath: MangaDownloadAccess.defaultDownloadsRootPath,
      loading: true,
    );
  }
}

class OtherSettingsActions {
  const OtherSettingsActions._();

  static Future<bool> loadUpdateCheckSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(hazukiAutoSourceUpdateCheckEnabledPreferenceKey) ??
        true;
  }

  static Future<OtherSettingsSnapshot> loadSettings({
    required bool initialUseSystemTitleBar,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final updateChecks = await loadUpdateCheckSettings();
    final mangaDownloadsRootPath =
        await MangaDownloadAccess.loadDownloadsRootPath(prefs: prefs);
    return OtherSettingsSnapshot(
      autoCheckInEnabled:
          prefs.getBool(hazukiAutoCheckInEnabledPreferenceKey) ?? false,
      autoSourceUpdateCheckEnabled: updateChecks,
      aggregateSearchEnabled:
          prefs.getBool(hazukiAggregateSearchEnabledPreferenceKey) ?? false,
      comicIdSearchEnhanceEnabled:
          prefs.getBool(hazukiComicIdSearchEnhancePreferenceKey) ?? false,
      discoverDailyRecommendationEnabled:
          prefs.getBool(
            hazukiDiscoverDailyRecommendationEnabledPreferenceKey,
          ) ??
          false,
      useSystemTitleBar: initialUseSystemTitleBar,
      mangaDownloadsRootPath: mangaDownloadsRootPath,
      loading: false,
    );
  }

  static bool resolveUseSystemTitleBarFromScope(
    BuildContext context, {
    required bool fallbackValue,
  }) {
    if (Theme.of(context).platform != TargetPlatform.windows) {
      return fallbackValue;
    }
    return HazukiWindowsTitleBarScope.of(context).useSystemTitleBar;
  }

  static Future<void> toggleAutoCheckIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(hazukiAutoCheckInEnabledPreferenceKey, value);
  }

  static Future<void> toggleAggregateSearch(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(hazukiAggregateSearchEnabledPreferenceKey, value);
  }

  static Future<void> toggleComicIdSearchEnhance(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(hazukiComicIdSearchEnhancePreferenceKey, value);
  }

  static Future<void> toggleAutoSourceUpdateCheck(
    BuildContext context,
    bool value,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(hazukiAutoSourceUpdateCheckEnabledPreferenceKey, value);
    if (!context.mounted) {
      return;
    }
    await showHazukiPrompt(
      context,
      AppLocalizations.of(context)!.otherAutoUpdateUpdated,
    );
  }

  static Future<void> toggleDiscoverDailyRecommendation(
    DiscoverDailyRecommendationService service,
    bool value,
  ) {
    return service.setEnabled(value);
  }

  static Future<String?> editMangaDownloadPath(
    BuildContext context, {
    required String currentPath,
    required MangaDownloadService downloadService,
  }) async {
    final strings = AppLocalizations.of(context)!;
    String? result;
    try {
      result = await MangaDownloadAccess.pickDownloadsRootPath(
        currentPath: currentPath,
      );
    } on PlatformException catch (error) {
      if (!context.mounted) {
        return null;
      }
      await showHazukiPrompt(
        context,
        strings.otherMangaDownloadPathPickFailed(error.message ?? error.code),
      );
      return null;
    } catch (error) {
      if (!context.mounted) {
        return null;
      }
      await showHazukiPrompt(
        context,
        strings.otherMangaDownloadPathPickFailed(error.toString()),
      );
      return null;
    }
    if (!context.mounted || result == null) {
      return null;
    }

    final normalized = MangaDownloadAccess.normalizeDownloadsRootPath(result);
    await MangaDownloadAccess.saveDownloadsRootPath(normalized);
    await MangaDownloadAccess.ensureNoMediaMarkerForPath(normalized);
    await downloadService.handleRootPathChanged();
    if (!context.mounted) {
      return null;
    }
    await showHazukiPrompt(context, strings.otherMangaDownloadPathSaved);
    return normalized;
  }
}
