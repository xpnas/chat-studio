# Chat Studio 1.0.20（21）

## 本次修复

1. **聊天区域横滑**：修复此前只能边缘打开且可选文字拦截水平手势的问题。新建页和正文阅读区右滑打开记录、左滑打开服务器工作区；输入框、长按、多指、纵向阅读与子控件横向滚动不触发。保留按钮入口。
2. **服务器工作区**：选择提交 `fullPath`，不再提交相对 `path`；显示文件接口返回的 `absolutePath`，不再读取不存在的 `current`。工作区刷新按钮不再误调全局配置刷新。支持服务器子目录浏览、返回根目录、分层选择和本地面板重试。
3. **错误与并发隔离**：ENOENT/无权限只在工作区面板提示，不覆盖聊天正文顶部；目录/文件状态按会话隔离，旧请求、旧会话、退出后的结果不写入当前页面。运行时、只读自动化会话不能切换目录，保存期间不发送新消息。
4. **统一正文**：用户和 AI 使用共享的 14.5 字号、1.48 行高。Markdown 标题/粗体/代码保留语义差异，普通列表、引用和表格正文使用同一基准。
5. **回归补修**：完整测试发现上一轮模型列表当前提供商被强制展开、无法折叠，已修正；当前项置顶仍保留。

说明：这里始终是 Agent 服务器上的文件系统，不是手机目录。若旧版本已保存错误的相对路径，请在新包中重新选择一次有效服务器文件夹；新客户端不会猜测路径或自动创建/删除服务器目录。新建对话首次发送后建立会话，再允许选择工作目录。详见 [协议和交互说明](workspace-navigation.md)。

## 验证

- **264 项单元/Widget 测试通过，11 项环境默认跳过**；新增 15 项包含中央慢滑、正文触摸、远程路径参数、迟到结果隔离与字体一致性。
- **10 项隔离真实 Studio HTTP/Socket.IO 契约通过**。新增工作区测试经真实 REST 创建目录、读取选项、保存绝对路径、检查数据库会话字段、写入文件并重新列出；非本地状态模拟。
- `flutter analyze --fatal-infos` 无问题，Dart 格式、命名门禁、PowerShell/Bash 语法与 Git diff 检查通过。
- 字体预览测试 **1 项通过、21 张 PNG**；README 与截图说明同步，新增工作区/目录选择图，未添加 README 迭代列表。
- Windows 串行完成 APK / AAB Release 构建；没有 Android 真机/模拟器端到端、iOS 编译、真实外部 Agent CLI 或远端 GitHub Actions 执行。触摸验证来自真实 Flutter 组件测试，不能代替手机系统手势体验验收。

## Android 交付

采用新版本 **1.0.20+21**，不再以相同版本名覆盖此前修复包。应用 ID `ai.chatstudio.app`，启动类 `ai.chatstudio.app.MainActivity`；minSdk 24 / targetSdk 36，ABI：arm64-v8a / armeabi-v7a / x86_64。

```text
dist/chatstudio-1.0.20-android-release.apk
dist/chatstudio-1.0.20-android-release.aab
dist/chatstudio-1.0.20-SHA256SUMS.txt
```

- APK v2 签名通过、非 debuggable，Dart AOT 且无 debug kernel，核对内置 versionName/versionCode 与 pubspec 一致后才复制到 dist。
- 沿用现有签名，证书 SHA-256：`51b8f4a1a78f7cb5689601fc762606790c2006b4001658baf5c1480dfc64ff28`，可覆盖同包名、同签名版本。
- AAB `bundletool validate` 和 `jarsigner -verify` 通过，manifest 包名和版本一致；自签名证书、无时间戳及既有 ZIP/JAR 流读取差异警告仍存在，不代表已通过 Play Console 审核。

SHA-256：

```text
77ddad65443cf2bb848ff812292d1e541cc028b7bc1265bbfbc01e40edaa862d  chatstudio-1.0.20-android-release.apk
4d1b14c797979739390453d68706afcf4009fbf28038d722fbe647d33a4ec06d  chatstudio-1.0.20-android-release.aab
```

仅本地 Git 提交，未推送。二进制、私钥、诊断日志与本地工具索引不作为本次源码变更提交。
