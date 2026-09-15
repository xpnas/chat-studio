# 验证记录与复现

## 当前验证（2026-09-15，1.0.18）

- `python scripts/verify-app-identity.py` 通过，检查 Dart / Android / iOS 标识、原生文件导出通道、存储键和客户端源码/路径命名；CI 已接入。
- 客户端全量测试：**219 项通过，8 项按环境默认跳过**；新增 7 项命名回归，覆盖安全存储、文件导出通道及上游 Agent 身份保持不变。
- 静态分析：`flutter analyze --fatal-infos` 无问题；格式门禁通过。
- 隔离官方 Studio v1.0.3：**7 项真实 HTTP / Socket.IO 联调通过**，包括断线恢复、多会话、附件上传、STT / TTS 等；测试环境变量与模型夹具已统一为 `CHATSTUDIO_*` / `chatstudio-test`。
- 截图测试：**1 项通过**，重新渲染 14 张实际 Flutter 组件预览，重命名不改变既有布局；[截图说明与复现](screenshots/README.md)。
- Android 构建、签名和校验信息见 [本次重构记录](release-1.0.18.md)。

原有后台重复内容回归继续通过，包括生成中实际断开并恢复 socket；桥接事件使用固定上游契约夹具，不代表运行了真实 Codex CLI / Hermes Python runtime。未做 Android 真机或模拟器端到端验收，也未本地编译 iOS；未推送远端或运行 GitHub Actions。

Windows 可复现隔离联调（要求上游已安装 Node 依赖，脚本核对固定 SHA）：

```powershell
./scripts/studio-contract.ps1 -StudioPath D:/code/hermes-studio-v1.0.3 -Flutter D:/code/toolchains/flutter/bin/flutter.bat
```

脚本只在空闲的 18647 / 18648 回环端口启动自己的进程；使用独立 HOME/Profile/数据库和随机密码，结束后终止所启动进程树、还原环境变量。私有诊断状态保留在被 Git 忽略的 `.local/contract-*`，不要上传或公开。Linux 使用 `scripts/studio-contract.sh`。

## 首轮交付记录（1.0.5，以下为历史验证）

| 项目 | 实际结果 |
|---|---|
| 格式检查 | `dart format`，格式与 CI 检查一致 |
| 静态分析 | `flutter analyze --fatal-infos`：无问题 |
| 客户端单元 / 组件测试 | **122 项通过**，默认跳过 4 项需真实服务的测试及 1 项需本地字体的预览测试 |
| 真实 v1.0.3 服务协议测试（1.0.5 已扩展） | **4 项通过**：实际 HTTP、Dart Socket.IO、多会话并行/任务快照/思考深度持久化、文件/图片上传和鉴权下载、STT 链路，非 FakeTransport |
| Flutter 设计预览 | 单独运行 **1 项通过**，生成登录、首页、聊天、分组模型选择、历史阅读模式及深色预览 |
| 上游认证回归（首轮交付已验证，本轮未重复运行） | `app-connections-auth.test.ts`、`user-auth.test.ts`：2 个文件 **57 项通过** |
| CodeGraph | 实际运行 orient / explore，JSON 存于 docs/analysis |
| Android Release APK | 实际编译成功，apksigner v2 签名验证通过，非 debug 包 |
| Android Release AAB | 实际编译成功，bundletool 1.18.3 validate 通过 |
| 自动化脚本 | actionlint 1.7.12 检查 3 个 workflow 通过；Bash / Python / plist 语法检查通过 |

当时 APK 元信息（旧应用标识，非当前包）：versionName `1.0.5`，versionCode `6`，minSdk 24，targetSdk 36，ABI 为 arm64-v8a / armeabi-v7a / x86_64。最终包与 SHA-256 在 `dist/`，被 Git 忽略。AAB 的 JAR 签名验证会提示自签名证书/无时间戳及 ZIP 流读取差异；bundletool 的结构验证已通过，尚未上传 Play Console 验证。

## 没有完成、不能混同为已验证

- 本机是 Windows，没有 Xcode；**没有本地编译/运行 iOS**，也未执行 Apple 证书签名或 TestFlight 上传。
- 未推送远端 / 未实际触发 GitHub Actions，提供并静态验证工作流不等于远端全部成功。
- `adb devices` 没有已连接手机/模拟器；未进行真机安装、键盘交互、安全存储插件运行验证或帧率/能耗测量。
- 没有运行 Docker 部署模板；实际服务联调采用 Node 源码启动。
- 本地 SSE Provider 是确定性夹具，不是付费真实模型；未验证 Hermes Python Runtime、任意供应商、全部工具权限及复杂工作流。
- Markdown、长列表和高频刷新做了性能设计，但没有用这代替真机性能数据。

## 常规检查

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test --coverage
flutter build apk --release
flutter build appbundle --release
```

覆盖率文件是 `coverage/lcov.info`。当前单元/组件测试覆盖地址策略、鉴权请求、重定向禁止、模型目录过滤、api_mode、消息分页、run 来源、Socket.IO recovery 参数解包、快照/replay、迟到事件、断线不重发、退出后的迟到 HTTP、权限确认及 320px / 1.8 倍字号布局。覆盖率并非全覆盖，也未设置掩盖缺口的虚假高阈值。

## 真实服务契约测试

**仅对一次性、可删除的隔离环境运行。测试会创建/删除会话、变更测试会话模型和标题；媒体测试还会配置/删除临时 STT 提供商并上传测试文件。切勿指向生产服务。**

最方便：推送后手动运行 `Studio contract`，它自动 checkout 固定上游 SHA、安装 Node 依赖、创建一次性目录、运行本地 Provider、旋转初始密码、执行 `test/live_contract_test.dart` 中的联调测试，最后停止子进程，不上传含凭据的服务端状态/日志。

本地复现步骤：

1. 获取并核对上游 v1.0.3 源码 SHA（见分析文档），执行 `npm ci --ignore-scripts --no-audit --no-fund`。
2. 创建全新的测试目录；把 `tools/mock-provider/config.yaml` 复制为测试 `HERMES_HOME/config.yaml`。
3. 独立终端运行 `node tools/mock-provider/server.mjs`（loopback 18648）。
4. 给源码服务设置隔离环境，启动 Node：

```powershell
# 在上游目录执行，示例路径均替换为本次新建的测试目录。
$env:HERMES_HOME='D:/temporary-chatstudio-contract/hermes'
$env:HERMES_WEB_UI_HOME='D:/temporary-chatstudio-contract/studio'
$env:HERMES_WEBUI_STATE_DIR=$env:HERMES_WEB_UI_HOME
$env:HERMES_RUNTIME_SOURCE='none'
$env:PORT='18647'
$env:TS_NODE_PROJECT='packages/server/tsconfig.json'
$env:TS_NODE_TRANSPILE_ONLY='true'
$env:TS_NODE_COMPILER_OPTIONS='{"rootDir":"../../"}'
node -r ts-node/register packages/server/src/index.ts
```

TS_NODE_COMPILER_OPTIONS 用于处理该 checkout 的 TypeScript 6 rootDir 推断变化。必须显式设置 `BIND_HOST=127.0.0.1` 使源码服务只监听回环地址；该版本使用的是 `BIND_HOST` 而非 `HOST`。新版 Linux/CI 脚本已自动设置。

5. 在移动端目录的另一终端设置随机测试密码，执行仅适用于新初始化账号的 bootstrap，再运行测试：

```powershell
$env:CHATSTUDIO_TEST_SERVER='http://127.0.0.1:18647'
# 用密码管理器/随机生成器提供 16 位以上随机值，不提交真实凭据。
$env:CHATSTUDIO_TEST_PASSWORD='<random-test-password>'
node tools/mock-provider/bootstrap.mjs
flutter test test/live_contract_test.dart --reporter expanded
```

bootstrap 会等待启动，用一次性的默认凭据登入，然后立即改为指定随机密码。测试结束后停止源码服务和 Provider。此次 Studio/Hermes 测试状态位于 `.local/`；上游 Ekko 也会在隔离 checkout 的 `packages/ekko-agent/.ekko` 创建运行数据。这些状态均未提交；两个测试监听已停止。

三项真实测试覆盖：

- 原生录音格式 WAV → 真实 Studio STT multipart → 本地识别夹具 → 文字；文件/图片 multipart → 内容块 run → 持久历史附件名称。音频夹具不验证实际语音识别准确率。

- AppController 登录 → run → 部分流式内容 → reconnect/resume → assistant 不重复 → abort。
- HTTP/Socket.IO 登录 → profiles/models → Ekko 新会话 → delta/completed → 持久历史 → rename/model/search → 完成快照 → 第二轮生成中断线恢复 → abort → delete。

## UI 预览

```powershell
$env:CHATSTUDIO_PREVIEW_FONT='C:/Windows/Fonts/msyh.ttc'
flutter test test/preview_test.dart
```

可换为你有权使用的 CJK 字体。字体文件不会打包进应用或仓库；这是确定性组件预览，不是 Android/iOS 真机截图。

## 下一轮真机验收建议

1. Android Release APK 安装/覆盖更新，冷启动、键盘、复制、深色模式、返回手势。
2. 登录后杀进程重启，验证 Keystore / Keychain 保存；撤销设备 token 后应退出。
3. 弱网、切 Wi-Fi/蜂窝、后台恢复、长回答与历史分页；确认不会重复发送。
4. 在 Android profile build / iOS 真机上测长列表与 token streaming 的帧耗时，再决定是否进一步缩小 UI 重建范围。
5. 两个平台验证局域网权限、HTTPS/WSS 代理与真实模型，并完成商店分发/隐私验收。


## 1.0.1 新增验收

- `test/mobile_refinements_test.dart` 新增 15 项：Codex 路由/历史、STT 配置、空白与思考行、父子模型树与搜索、multipart 认证与错误、附件选择/移除、录音拒权/取消/过期识别结果、浅深主题消息圆角底。
- 真实媒体测试额外设置 `CHATSTUDIO_TEST_MEDIA=1`；必须是无已有 STT 设置的隔离 Profile。CI 已配置此开关。
- Android Release 已验证仅新增 `RECORD_AUDIO`，没有广泛存储/媒体读取权限；原生系统文件/相册选择由插件处理。
- 真机重点补验：麦克风首次授权/拒绝后重试、60 秒自动结束、来电/后台取消、中文文件名、相册 HEIC、弱网上传取消、附件-only 发送、原签名覆盖安装。


## 1.0.2 阅读模式

`test/reading_mode_test.dart` 的 6 项组件测试覆盖真实列表手势与恢复、折叠栏停止生成、焦点/附件/录音保护。手动恢复前后编辑器实例相同，草稿与滚动 offset 保留，列表可见高度增加；短滚动和程序跳转不误触发。没有用组件动画代替真机性能测量。


## 1.0.3 悬浮双线

`reading_mode_test.dart` 现有 11 项，通过真实组件布局验证折叠后列表延伸至底部、无文字 footer，双线点击区仍可恢复草稿；进度与加载范围一致，并覆盖浅深主题、空范围/越界、320px 屏幕底部手势区以及停止/回到最新按钮不重叠。浅深预览分别为 `docs/screenshots/reading.png`、`reading-dark.png`。


## 1.0.4 完整聊天细节回归

新增 `test/conversation_polish_test.dart` 27 项，覆盖：按服务器/账号/Profile 隔离偏好与模型失效提示、失败/待核对消息不自动重发、草稿和服务器附件恢复、保留已有新草稿、工具去重/单轮分组、历史替换保留本地身份及早期页、Markdown 分段复用与嵌套代码/宽表格、基于字节流的上传进度、鉴权附件下载/重定向拒绝/401/403/404/响应限额/Profile 切换、图片失效重试、实际音量样本/无声提示、阅读锚点/新内容提示、首次引导与淡化插值。

真实联调新增上传后读取文本原文、`variant=app-image` 图片响应的端到端断言。此测试用本地确定性语音与文本模型夹具，不是收费模型或真机麦克风准确率测试。

### 重要：数据库隔离

上游开发模式的 SQLite 默认在 checkout 的 `packages/server/data`，仅设置 `HERMES_WEB_UI_HOME` 不足以隔离数据库。新版 Studio contract 与本地测试必须额外设置：

```sh
export NODE_ENV=test
export HERMES_WEB_UI_TEST_DB_DIR=/absolute/disposable/database
```

同时设置独立 HERMES_HOME / HERMES_WEB_UI_HOME，并将模型请求指向环回夹具。不要对生产数据运行破坏性契约测试。本轮真实联调使用 `.local/polish-contract*` 独立状态，没有删除旧开发数据库。

### 真机验收仍需设备

本轮 `adb devices -l` 返回空列表，SDK 没有已安装模拟器；没有把组件测试说成 Android 真机验收。必须后续验证：原生录音权限/中断、相册与文件保存、系统返回手势、输入法遮挡、切网/后台、1.0.3 → 1.0.4 原签名覆盖更新及长对话帧率。Windows 无 Xcode，iOS 编译/签名/真机测试仍待执行。


## 1.0.5 多会话 / 思考深度 / 紧凑历史

`test/multi_conversation_test.dart` 25 项回归覆盖：A/B 并行与输出隔离、后台完成/失败/待确认、停止只针对所选任务、同步完成前不提交旧权限提示、多个任务重连不重发输入、Profile 隔离与旧回调拒绝、快速切换/迟到历史、任务快照/旧时间戳、缺项待同步、后台任务防误删、思考深度 run/REST/偏好/失败回滚/会话模型切换重置、动态历史条目导航与字号/行距、减少动画、独立确认超时、注销清理、未发送草稿/文件/已上传引用/阅读位置恢复。

新增真实测试使用两个不同 device_code 登录，一个客户端运行 A/B，另一个仅观察活动快照。对话 A 使用 SLOW 本地夹具保持工作，B 独立完成，切回 A 后停止不会影响 B；reasoning-effort 经 REST 保存后由重连快照读回。完整真实套件需新建隔离数据库再运行媒体测试，避免已有 STT 配置影响破坏性夹具。

本轮保持 Android/iOS 共用 Flutter 状态层；未连接 Android 真机，未运行真实 Codex CLI；Xcode/iOS 编译与真机权限/性能仍待外部设备环境验证。多会话并行使用本地确定性模型，不表示所有供应商的并发限制已验证。


## 1.0.6 Linux 本地与自动化补验

- 完整本地测试：132 项通过，6 项默认跳过（5 项隔离服务测试及 1 项字体预览）。
- 隔离官方 Studio v1.0.3：5 项真实 HTTP/Socket.IO 测试通过，新增 `/usage`、`/context`、`/title`、`/clear`、`/clear --history` 与技能/Bundle 目录读取。
- 上游认证：2 个文件，57 项通过。模型与语音仍为本地确定性夹具，不代表完整 Hermes/Codex runtime 命令全覆盖。
- 脚本复现（Linux，Flutter/Node/JDK 已安装，上游已执行 npm ci）：

```sh
bash scripts/studio-contract.sh /absolute/path/to/pinned-studio
```

脚本核对上游 SHA、检查固定端口未占用，生成随机测试密码，隔离 HOME/Profile/数据库、禁用 LAN discovery/gateway autostart/MCP 注入，使用 BIND_HOST=127.0.0.1，结束后清理服务进程组和临时状态。仅设置 CHATSTUDIO_KEEP_CONTRACT_STATE=1 时保留私有诊断文件，不能上传这些文件。

流畅性结构测试检查 1000 条历史按需构建、输入及 120 次 token 更新不会重新创建 MaterialApp/Theme。真机 profile 测试脚本与限制见 docs/release-1.0.6.md；当前没有已连接设备，未声称实际帧率或能耗合格。未触发远端 GitHub Actions，iOS/Xcode 仍需 macOS 环境实跑。

## 1.0.8

新增审批回归覆盖失败不清卡、stale 清卡、审批 ID 隔离、重复提交拦截、永久授权条件与二次确认、过期不提交；队列覆盖启动前禁排队、服务器确认/取消/出队及用户消息去重；TTS 覆盖同 Profile 鉴权、重定向禁止、非音频拒绝、停止播放和合成前取消竞态。

隔离服务测试新增真实 queue + TTS 一项，完整 6 项通过。TTS 使用本地静音 WAV，仅验证协议，不宣称声音质量或原生扬声器/蓝牙端到端通过。首次发送修复有明确时序回归用例，仍需手机弱网环境验证偶发问题是否完全消失。

## 1.0.9 大文件下载

151 项本地测试通过，新增 64 MB 流式写盘回归及取消/权限失败/截断清理。下载不再调用聚合字节的预览接口。Android 文件导出新增 path-only MethodChannel + 系统文档保存；iOS 路径导出代码需 Xcode/真机验证。聊天恢复重复/闪动未在此版修复。

## 1.0.10 音频文件播放

155 项本地测试通过，7 项按环境默认跳过。现成音频文件走鉴权流式下载和原生 DeviceFileSource，不请求 TTS；单独验证停止清理、取消竞态、Markdown 音频链接直接播放及 audio 内容块保留。不把 mock 播放器测试说成真机实听验收。

## 1.0.11

159 项本地测试通过、7 项默认跳过；6 项隔离服务真实测试通过。新增转文字服务的 MIME/文件名/鉴权/缓存/取消与未配置错误测试；真实媒体测试新增“上传音频附件 → 鉴权流式下载 → STT 转文字”。普通文本 TTS 界面与自动执行已移除。既有底层 TTS 协议测试仅作为兼容契约检查，不是 App 普通文本语音功能。

## 1.0.13 自动分页

169 项本地测试通过、7 项默认跳过。新增 5 项 Widget 测试覆盖自动触发、单请求锁、阅读锚点、末页、短/隐藏页、失败重试与防循环、切会话和离线/同步保护。本次未重复架设真实服务或进行真机滚动帧率测量。


## 1.0.14 前台恢复

历史 1.0.14 验证记录为 175 项本地测试通过；7 项环境相关测试默认跳过。该记录对应此前版本；当前工作区新增的回归结果与未解决项见下方“当前前台恢复修复回归状态”。


## 1.0.15 前台恢复修复回归记录（2026-09-15）

对 `c31696a` 的评审复测为 174 项通过、8 项跳过、2 项失败。失败项是 `multi_conversation_test.dart` 的后台审批时序，以及 `resume_snapshot_test.dart` 中相同文本跨轮次保留；此前按内容抵扣事件及不校验 run 的兜底拼接是原因。

1.0.15 移除事件抵扣，在独立 reducer 中完整重放，再按同一 run 合并正文/思考及复用气泡身份；原有失败测试未删除、未放宽断言。新增 13 项 `resume_state_integrity_test.dart` 回归，并修正已有前台恢复测试文件的格式，使 CI 格式门禁也通过。

验证结果：

- `dart format --output=none --set-exit-if-changed lib test integration_test test_driver`：通过；
- `flutter analyze --fatal-infos`：通过；
- `flutter test`：189 项通过、8 项按环境默认跳过、0 项失败；
- Android 打包与签名验证记录见 [1.0.15 发布记录](release-1.0.15.md)。

本次未重跑真实 Studio HTTP/Socket.IO 联调，未运行远端 GitHub Actions。没有连接 Android 真机/模拟器，未验证真实断网、后台/前台、进程回收和帧率；iOS 原生编译与签名仍需 macOS/Xcode 验证。不可将单元测试通过等同于这些环境的验收。


## 1.0.17 Chat Studio（2026-09-15）

- `dart format` / `flutter analyze --fatal-infos`：通过。
- `flutter test`：212 项通过、8 项环境相关跳过；新增 10 项服务器迁移/隔离/重启/过期/并发/存储失败、Agent 标识和图片预览回归。
- 隔离真实 Studio v1.0.3：7 项 HTTP/Socket.IO 契约通过，包含截断事件缓存后的连续后台断网恢复。新增多服务器切换由 Mock HTTP + 真实控制器验证，未启动两个生产服务器。
- 截图测试：1 项通过，14 张 PNG；增加服务器管理、全屏图片预览，更新 Chat Studio 品牌。截图使用确定性测试数据和本地字体，非真机截图。
- AI 音频卡不再暴露转文字；保留底层 STT 协议测试来保护麦克风语音输入及兼容接口，不代表还提供音频附件转文字功能。
- Windows 上不要同时运行 Flutter 测试/pub get 和 Android Gradle 打包：它们会重写同一份生成的插件注册文件。此次一次并行尝试出现 `IntegrationTestPlugin` 缺失，随后改为串行执行质量检查和打包。
- Android 包、签名及本次范围说明见 [发布记录](release-1.0.17.md)。未验证 Android 真机交互/弱网、iOS 原生编译、真实 Codex/Hermes runtime 或远端 GitHub Actions。
