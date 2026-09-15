# 1.0.6（7）聊天输入、流畅性与自动化

- 顶部显示聊天名称，模型选择移入输入框，支持官方 v1.0.3 引擎对应的 `/` 命令候选及回执。
- 命令选择仅补全草稿；技能/Bundle 使用当前 Profile 的服务端目录。
- 流式刷新不再重建整个 MaterialApp 和主题；历史列表 key 索引使用映射，未变化 Markdown 避免重复分段。
- GitHub Mobile CI 加入可复用隔离服务端联调门禁，并检查 Profile APK、Release APK/AAB 编译。正式签名仍要求 release Environment Secrets。
- 本地采用 Linux、Flutter 3.44.9、Dart 3.12.2、JDK 17、Android SDK 36。

## 已验证

- 静态分析无问题；本地单元/Widget 测试 132 项通过、6 项默认跳过。
- 本地隔离官方服务端真实 HTTP/Socket.IO 测试 5 项通过（含命令回执、改名、清屏及历史清理）。模型/语音使用本地确定性夹具，不调用收费模型。
- 上游认证回归 57 项通过。
- actionlint 检查三个 GitHub workflow 通过。未据此宣称远端 Actions 已运行。

## 签名与安装注意

本机未找到之前版本的发布签名，生成了专用本地 Release RSA 3072 签名（非 debug key）。密钥和凭据仅在被 Git 忽略的 `.local/signing`，不得上传到 Git 或附在产物中。

如果已安装的旧版使用不同签名，本包不能直接覆盖更新。优先使用原签名重新出包；不要在未备份所需数据时卸载旧版。后续 CI 要连续覆盖安装，应在受保护的 release Environment 使用同一套签名。

## 真机性能复现

已提供 `integration_test/chat_performance_test.dart` 和 `test_driver/performance_driver.dart`：1000 条历史滚动、命令输入、连续流式输出。使用真实设备执行：

```sh
flutter drive --profile -d DEVICE_ID \
  --driver=test_driver/performance_driver.dart \
  --target=integration_test/chat_performance_test.dart
```

报告由 integration_test driver 写出，包括 history_scroll / composer_stream 的帧统计。用目标设备的刷新率预算判断结果（60 Hz 为 16.67 ms），检查 build/raster P90/P99 和超预算帧比例；目前没有连接真机，因此不报告虚构的帧率、P99 或能耗。

本机没有 Xcode，不能编译签名 iOS IPA；GitHub macOS 构建仍待远端实跑和 Apple 签名材料。


## 本地 Release 出包结果

- 通用 APK：58,776,831 bytes，versionName 1.0.6 / versionCode 7，minSdk 24 / targetSdk 36，arm64-v8a / armeabi-v7a / x86_64。
- APK：apksigner v2 签名验证通过；非 debuggable，存在 Dart AOT libapp.so，不含 debug kernel。
- AAB：Release 编译成功，bundletool 1.18.3 结构验证通过。jarsigner 验证有自签名证书、无时间戳及 ZIP 流读取差异警告；未上传 Play Console，不能据此宣称商店已验收。
- APK SHA-256：`3bb435765924ac617985aa00f665118f61cb71ee48840104d62cf05d6001b5e3`
- AAB SHA-256：`1455ab4e0ed24bed62f06919cb1ed98fc5679e5c03cb655acc7bedef8fb53987`
