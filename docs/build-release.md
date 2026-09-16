# 构建、签名与 GitHub 自动出包

## 工具链

固定 Flutter 3.44.9（Dart 3.12.2），提交 pubspec.lock。版本以 `pubspec.yaml` 的 `version` 为准；本地 Gradle 堆上限 3 GB、metaspace 1 GB、worker 上限 2，避免低内存构建机过度并行。Android 使用 JDK 17、SDK 36，Flutter 插件按项目配置自动安装所需 NDK。iOS 使用 macOS-15 runner 与项目默认 Swift Package Manager 集成，不需要手写 Podfile。

`Mobile CI` 在 Linux 检查格式、静态分析、单元/组件测试，再自动架设固定上游 SHA 的一次性 Studio 做真实契约测试，全部通过后分别构建 Android 和 iOS。Android 同时上传 Debug APK、arm64 Profile APK（debug 签名，性能验收用）以及未签名 Release APK/AAB（编译验收用）。正式分发使用 Signed packages。Actions 会安装工具链、解析锁定依赖，无需提交本地 SDK 和生成目录。

工作流目前使用主版本固定的官方 actions / subosito action，以及固定 Flutter 版本；若需供应链强化，可审计后进一步将 action 引用固定到 commit SHA。未配置从不可信 PR 自动发布的逻辑。

## 应用标识与安装

- Dart 包名：`chatstudio`；Android applicationId / namespace、iOS Bundle ID：`ai.chatstudio.app`。
- Android 启动类：`ai.chatstudio.app.MainActivity`；两端文件导出通道：`ai.chatstudio.app/file_export`。
- **这是新的应用身份，不能覆盖旧包安装，也不能读取旧包私有存储。** 安装后重新添加服务器并登录，服务端聊天历史不受影响；草稿、偏好和服务器列表不会自动跨应用迁移。确认新应用可用后再自行卸载旧应用。
- 签名证书沿用已有材料；无需因为重命名而改密钥/alias。iOS 需要为新 Bundle ID 配置匹配的 App ID / provisioning profile，旧 profile 不能直接使用。
- 本地和 CI 都运行 `python scripts/verify-app-identity.py`，防止包名、原生通道或旧客户端命名回归。

## Android

### 本地签名

1.0.6 本地 Linux 环境没有找到旧版签名，已新生成专用 RSA 3072 Release 密钥。**它不保证与先前 Windows 版本同签名；不同签名不能覆盖安装。** 材料仅存放在：

- `.local/signing/chatstudio-upload.jks`
- `.local/signing/credentials.json`
- `android/key.properties`

不要把这些文件发送到聊天、提交仓库或放进构建 artifact。请用密码管理器/离线介质备份。丢失原签名可能导致无法覆盖更新已有安装。

也可以自行用 JDK keytool 创建密钥，之后写 `android/key.properties`（Java Properties 格式；Windows 路径用 `/`）：

```properties
storeFile=/absolute/path/to/upload.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=YOUR_ALIAS
keyPassword=YOUR_KEY_PASSWORD
```

```sh
flutter build apk --release
flutter build appbundle --release
# 只需要 arm64 小包时：
flutter build apk --release --target-platform android-arm64
```

未提供签名文件时产物未签名。不会将 debug key 当生产签名。普通 CI 单独输出 debug APK，用于方便试装；评估性能应使用 profile / release，而非 debug。

### 本地交付目录与命名

Flutter 的 `build/app/outputs/` 是编译输出，不是最终交付目录。每次功能修复出包先递增 `pubspec.yaml` 中的版本号与构建号，完成 APK / AAB 构建和签名/manifest 校验后，复制到：

```text
dist/chatstudio-{version}-android-release.apk
dist/chatstudio-{version}-android-release.aab
dist/chatstudio-{version}-SHA256SUMS.txt
```

`{version}` 是 `+` 前的 versionName；内置 versionCode 使用 `+` 后的数字。校验清单基于 dist 中的最终文件生成；发布记录保存对应哈希，不将私钥、日志、二进制加入 Git。不要继续复用同一文件名覆盖不同修复版本，也不要仅提供 Flutter 的默认 `app-release.apk` 作为交付。

### GitHub 签名

在仓库 Settings → Environments 新建 `release`，设置审核/分支限制，并添加：

| Secret | 内容 |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | JKS 文件完整 Base64，无换行 |
| `ANDROID_STORE_PASSWORD` | store password |
| `ANDROID_KEY_PASSWORD` | key password |
| `ANDROID_KEY_ALIAS` | 现有 keystore 中的真实 alias；更改应用包名不要求更换签名密钥或 alias |

运行 Actions → Signed packages → Run workflow → android。脚本只在 runner 临时目录解码密钥；缺项直接失败，不降级签名。结束时清除文件，上传 APK/AAB，不上传密钥。

`github.run_number` 用作 CI versionCode；正式上架前应确保它高于已有商店版本，必要时调整构建编号策略。不同工作流编号不能作为全局单调版本源。

## iOS

### 无 Apple 证书

`Mobile CI` 先构建模拟器 `.app`，再构建 `--no-codesign` 的设备 `.app`。二者用途不同：

- 模拟器 app：解压后可在兼容架构的 iOS Simulator 中安装。
- 设备未签名 app：用于编译检查，**不能直接在 iPhone 安装**。

不要简单把未签名 app 压成 Payload.zip 并宣称可用 IPA。

### IPA

当前 Bundle ID：`ai.chatstudio.app`。Android appId 为 `ai.chatstudio.app`。正式发布前应换成你控制的标识，并生成匹配的 Apple App ID / profile。

`release` Environment Secrets：

| Secret | 内容 |
|---|---|
| `IOS_CERTIFICATE_BASE64` | Apple Distribution 证书 + 私钥导出的 `.p12` Base64 |
| `IOS_CERTIFICATE_PASSWORD` | p12 密码 |
| `IOS_PROFILE_BASE64` | 与 Runner Bundle ID 完全匹配的 `.mobileprovision` Base64 |
| `IOS_TEAM_ID` | Apple Team ID |

手动工作流选 ios / both。`ios_method`：

- `app-store-connect`：匹配 App Store distribution profile；IPA 提交 App Store Connect / TestFlight。
- `release-testing`：匹配 Ad Hoc profile；仅 profile 已注册的设备可安装。

脚本校验 Team、App ID、profile 期限，建立临时 Keychain，仅给 Runner 设置手动签名，archive 后 export IPA，并在退出时删除敏感临时文件。尚未在本地 Windows 验证这一 Apple 签名链路，首次运行应审阅 Xcode 日志。

## 故障排查

- Windows Kotlin incremental cache 报跨盘不同 root：项目已关闭 Kotlin incremental 并使用 in-process 编译；不影响 Dart hot reload。
- Maven TLS / 下载失败：确认网络，重试；不要全局禁用 TLS 验证。
- iOS Profile mismatch：检查 Team、Bundle ID、证书是否包含私钥及 profile 的分发方式。
- GitHub 未启动：先把本地提交推送至 GitHub，并确认 Actions 已启用。默认流程没有 SSH 到你的服务器、公开部署服务或发布到商店的权限。


## 1.0.1 更新说明

版本号 `1.0.1+2`，沿用 1.0.0 的签名密钥以便覆盖安装。新增 Android 麦克风权限与 iOS 麦克风/相册用途说明，原生插件版本锁定在 `pubspec.lock`。不得把本地 `.local/signing`、`android/key.properties` 提交到 Git。

在同一工作目录内串行执行 `flutter test` 与 `flutter build`：它们会重新生成插件注册表，并发执行可能让 release 编译错误引用仅测试使用的 integration_test 插件。CI 原有分 Job 隔离不受影响。


### 测试后 Release 构建的插件注册表

Flutter 3.44.9 在运行测试后可能留下含 integration_test 的 GeneratedPluginRegistrant；Release 构建会排除该 dev 插件。测试之后不要使用 `flutter build ... --no-pub` 跳过插件刷新：先 `flutter pub get --enforce-lockfile`，再正常执行 `flutter build apk --release`。不要把手工编辑生成的注册表当成修复。测试与构建保持串行。

签名 Release APK 可用以下脚本检查签名、非 debuggable、Dart AOT 与 SHA-256：

```sh
bash scripts/verify-android-release.sh build/app/outputs/flutter-apk/app-release.apk
```
