# Chat Studio 1.0.22（23）

## 调整

根据阅读效果反馈，将聊天内容两侧外边距从 10 调为 **15**。用户、AI 气泡及任务计划卡片的外边距同步；正文仍为 15.5 字号、1.48 行高，气泡内边距水平 11 / 垂直 8、圆角 16 保持不变。本次不改变手势、工作区或模型高亮逻辑。

README 当前布局描述、截图及几何断言同步更新；历史发布记录不改写。

## 验证

- 270 项单元/Widget 测试通过，11 项环境跳过；静态分析、Dart 格式及命名检查通过。
- 字体预览测试单独通过，重新生成 23 张 PNG，并查看 `chat.png` 的实际 Flutter 布局效果。
- 本次是纯间距调整，未重复真实 Studio 契约联调；10 项协议测试在 1.0.21 已通过。未进行 Android 真机、iOS 编译或远端 Actions 验证。
- Windows 已构建 APK / AAB Release；APK v2 签名、非调试/AOT、应用标识与版本校验通过，AAB bundletool validate / jarsigner verify 通过。
- AAB 仍有既有自签名证书、无时间戳和 ZIP/JAR 流读取差异警告，不代表已通过商店审核。

## 产物

应用 ID `ai.chatstudio.app`，versionName `1.0.22` / versionCode `23`，沿用原签名，可覆盖同包名、同签名的旧版。

```text
dist/chatstudio-1.0.22-android-release.apk
dist/chatstudio-1.0.22-android-release.aab
dist/chatstudio-1.0.22-SHA256SUMS.txt
```

SHA-256：

```text
061bdfb36c864559c313ff23d55c357b2d55198dc9076d9387ec3ab7b1ca4551  chatstudio-1.0.22-android-release.apk
3315cf3f454c20a2d60d536b73b743724c12e3e706b8db4eefed418b1afb00ce  chatstudio-1.0.22-android-release.aab
```

仅本地提交源码和文档，未推送远端；包文件、日志和签名密钥不提交。
