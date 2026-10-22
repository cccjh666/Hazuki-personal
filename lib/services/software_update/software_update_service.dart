import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/preferences/hazuki_preference_keys.dart';
import '../../shared/preferences/software_update_source.dart';

export '../../shared/preferences/software_update_source.dart';

/// 更新源偏好访问器。
///
/// 本 fork **移除了应用自身的更新检查**：不再请求 `update.json` / GitHub
/// releases，也不再有下载 APK 或拉起安装器的能力。原因是被改包的签名与官方
/// 版本不同，任何「引导更新」都只会装上一个无法与本地数据共存的新包。
///
/// 这里只保留「更新源」（jsDelivr / GitHub / ghproxy）这一个偏好项，因为插件
/// 市场索引、插件配置地址与公告拉取仍然共用它来决定走哪条线路。
class SoftwareUpdateService {
  SoftwareUpdateService();

  Future<SoftwareUpdateSource> loadUpdateSource() {
    return loadSoftwareUpdateSourcePreference();
  }

  Future<void> setUpdateSource(SoftwareUpdateSource source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      hazukiSoftwareUpdateSourcePreferenceKey,
      source.preferenceValue,
    );
  }
}
