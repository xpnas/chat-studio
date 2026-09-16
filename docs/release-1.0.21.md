# Chat Studio 1.0.21（22）

## 本次交付

- 聊天内容左右外边距从 20 减为 10；气泡内边距从水平 14 / 垂直 10 改为 11 / 8，圆角从 20 改为 16。保留淡色背景与宽屏最大宽度约束，为手机正文释放横向空间。
- 用户与 AI 普通正文共享字号 **14.5 → 15.5**，行高保持 1.48；系统字体缩放和 Markdown 标题、粗体、代码层级保持。
- 修复长模型列表上滑时，「当前使用」高亮进入固定标题/搜索框的问题：每个惰性条目有独立且裁剪的 Material，选中背景及 ink 只在该条目绘制，不再依赖整个弹层 Material。
- 保留选中语义、文字标记、勾选、当前模型优先、按提供商分组、折叠和搜索，不通过取消高亮或取消选中状态掩盖问题。

实现与复现细节见 [模型高亮与聊天空间](model-highlight.md)。README 仅更新当前功能和截图，不添加版本迭代列表。

## 验证

- **270 项单元/Widget 测试通过，11 项按环境跳过**（10 项真实协议、1 项截图测试单独执行）。新增 6 项覆盖 100 模型长列表浅深主题滚动、固定区域像素、按压 ink、分组/搜索、边距与 1.8 倍字体。
- 旧实现曾临时回放，浅深主题的两个滚动像素测试均失败；恢复修复后通过。保证测试能检出截图所示越界，而非只检查参数。
- **10 项隔离真实 Studio HTTP/Socket.IO 契约全部通过**，包括远程工作区、可用 Agent、任务计划、断线恢复、队列、多会话、附件和 STT/TTS。
- `flutter analyze --fatal-infos` 无问题，格式、应用身份门禁与 diff 检查通过。
- 字体预览 **1 项通过，23 张 PNG**；重新生成聊天图片，新增 `models-scrolled.png` 与 `models-scrolled-dark.png`，人工查看聊天空间与滚动后固定标题区。
- Windows 已串行构建最终 APK/AAB。未进行 Android 真机/模拟器端到端、iOS 本地编译、真实外部 Agent CLI 或远端 Actions 验证。像素与触摸验证来自 Flutter 组件，不等于已在用户手机上验收。

## Android 产物

- versionName **1.0.21** / versionCode **22**；应用 ID `ai.chatstudio.app`，启动类 `ai.chatstudio.app.MainActivity`。
- minSdk 24 / targetSdk 36，包含 arm64-v8a / armeabi-v7a / x86_64。
- APK v2 签名验证通过，非 debuggable，包含 Dart AOT，无 debug kernel；APK/AAB 内置版本均与 pubspec 对应。
- 签名证书不变：SHA-256 `51b8f4a1a78f7cb5689601fc762606790c2006b4001658baf5c1480dfc64ff28`，可覆盖同包名、同签名的前一版本。
- AAB `bundletool validate` 与 `jarsigner -verify` 成功；仍有自签名证书、无时间戳、ZIP/JAR 流读取差异等既有警告，不代表已通过商店审核。

```text
dist/chatstudio-1.0.21-android-release.apk
dist/chatstudio-1.0.21-android-release.aab
dist/chatstudio-1.0.21-SHA256SUMS.txt
```

SHA-256：

```text
1faaa0fc97d1e910d0c05437f7354e54351cb290c49182db83c2689ab1f01692  chatstudio-1.0.21-android-release.apk
00fc2439bf4b4688ad1730673e404d969378c1f4e8bb40aebeef085292fc287d  chatstudio-1.0.21-android-release.aab
```

源码及文档本地 Git 提交，未推送远端。旧版本 dist 文件不覆盖；密钥、包文件与私有诊断不提交。
