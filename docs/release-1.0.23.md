# Chat Studio 1.0.23（24）

本次交付聚焦图片预览体验：图片预览改为真正的边到边全屏画布，移除图片标题和画布内缩进；下载、关闭改为与 Chat Studio 主界面一致的放大线性图标按钮，采用浮空胶囊底座并遵守系统安全区域。保留双指缩放、轻点图片关闭、系统保存位置、下载进度/取消、失败重试和 Android 返回关闭。

## 验证

- Flutter 静态分析：`flutter analyze --fatal-infos` 通过。
- 完整 Flutter 测试套件：278 项通过、11 项按环境跳过；新增图片预览回归覆盖浅色/深色、竖屏/横屏安全区、全屏画布几何、放大图标按钮、缩放不误关闭、下载失败重试、保存中关闭安全性。
- 预览截图测试重新渲染当前 UI，使用本地字体测试环境运行；未将字体文件纳入仓库。
- Android Release APK/AAB 已构建并校验；未进行 iOS 本地编译、真机安装或远端 GitHub Actions 执行。

## 产物

应用 ID `ai.chatstudio.app`，versionName `1.0.23` / versionCode `24`，沿用现有签名，可覆盖同包名、同签名旧版本。

```text
dist/chatstudio-1.0.23-android-release.apk
dist/chatstudio-1.0.23-android-release.aab
dist/chatstudio-1.0.23-SHA256SUMS.txt
```

SHA-256：`20f085f9a614cdbe093ced1badf7b37ec9a13c120e9c12aef4dcffd4782dacb9`（APK），`f8dc316b5bccdd33a0aee2224f5207edde68351fba75a07bdd551c75b645f0b8`（AAB）。仅提交源码、测试和文档，不提交包文件、日志或签名密钥。
