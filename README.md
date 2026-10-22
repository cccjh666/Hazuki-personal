> **本项目是基于 [LuckyLxi/Hazuki](https://github.com/LuckyLxi/Hazuki) v1.2.0 的个人改版（非官方）**
>
> - 已**移除应用内自动更新 / 检查更新 / 安装器拉起**，避免被官方版本覆盖安装
> - 下载页新增检索、分组独立文件夹、批量操作等改进（详见 [MODIFICATIONS.md](MODIFICATIONS.md)）
> - 采用 GPL-3.0 授权，改版内容同样遵循 GPL-3.0
> - `main` 分支为上游 v1.2.0 原始代码，改版代码在 `fork-no-auto-update` 分支

## 界面预览

<table>
  <tr>
    <th>首页</th>
    <th>漫画详情</th>
    <th>评论</th>
    <th>收藏</th>
  </tr>
  <tr>
    <td><img src="screenshots/discover.jpg" width="200" alt="Hazuki 首页：推荐与热门漫画"></td>
    <td><img src="screenshots/detail.jpg" width="200" alt="Hazuki 漫画详情页：简介、作者与标签"></td>
    <td><img src="screenshots/comments.jpg" width="200" alt="Hazuki 评论页：浏览和发表评论"></td>
    <td><img src="screenshots/favorite.jpg" width="200" alt="Hazuki 收藏页：收藏夹与漫画列表"></td>
  </tr>
</table>

## 下载

前往 [GitHub Releases](https://github.com/LuckyLxi/Hazuki/releases) 下载 Android APK。

## 本地开发

环境要求：Flutter `>=3.47.0`、Dart `^3.11.1`、`JDK 21`

```sh
flutter pub get
flutter gen-l10n
flutter run
flutter build apk --debug
```

## 致谢

- [Venera](https://github.com/venera-app/venera) — 参考了部分实现。
- [venera-configs](https://github.com/venera-app/venera-configs) — 使用了漫画源脚本。
- [Animeko](https://github.com/open-ani/animeko) — 参考了部分 UI 设计。

## 许可证

本项目采用 [GPL-3.0](LICENSE) 许可证。
