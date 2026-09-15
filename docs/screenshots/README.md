# 界面截图与复现

更新时间：2026-09-16。对应源码版本：`1.0.19+20`。

这些 PNG 由 `test/preview_test.dart` 直接渲染应用的真实 Flutter 组件，使用确定性测试数据。不是设计稿贴图，也不是真机截图。更新界面后应重新运行此测试，不能只替换 README 文案。

## 场景

| 文件 | 当前展示内容 |
| --- | --- |
| `task-plan.png` / `task-plan-expanded.png` | 轻量计划卡片、当前步骤、展开后的三种步骤状态 |
| `task-plan-dark.png` / `task-plan-completed.png` | 深色任务计划与全部步骤完成状态 |
| `login.png` | Chat Studio 登录、自定义服务器、局域网 HTTP 提示 |
| `servers.png` | 多服务器地址、Profile、登录状态与添加/删除入口 |
| `image-preview.png` | 无标题近全屏图片、右下角轻量保存/关闭入口 |
| `home.png` | 新对话、图标 Agent 选择入口，输入框内模型和思考入口 |
| `agents.png` | 服务端已安装 Agent 的图标/名称选择面板、当前项置顶和刷新 |
| `chat.png` / `chat-dark.png` | 会话标题、淡色用户/AI 气泡、紧凑 Markdown、浅深主题 |
| `models.png` | 提供商父子分组、当前模型选中状态 |
| `reasoning.png` | 思考深度选择及当前选项 |
| `history-tasks.png` / `history-tasks-dark.png` | 紧凑历史列表、运行/待确认/完成状态 |
| `attachments.png` | 图片、文件附件与折叠思考/工具状态 |
| `reading.png` / `reading-dark.png` | 输入框折叠、浮空双线与回到最新消息入口 |
| `message-status.png` | 发送失败状态，不展示成空白 AI 回复 |

逻辑视口为 `390 × 844`，导出比例为 2，因此 PNG 尺寸为 `780 × 1688`。运行指示动画截取固定时点；深色主题及嵌套文字过渡完成后再截图。预览保留真实组件布局，不叠加手机外壳、虚构状态栏或键盘。

## 重新生成

先安装项目指定的 Flutter SDK 并执行 `flutter pub get`。指定本机可用的中文字体文件；字体仅用于本地测试，不复制进应用或仓库，也不随截图分发。

PowerShell（Windows 示例）：

```powershell
$env:CHATSTUDIO_PREVIEW_FONT = 'C:\Windows\Fonts\msyh.ttc'
flutter test test/preview_test.dart --reporter expanded
Remove-Item Env:CHATSTUDIO_PREVIEW_FONT
```

macOS / Linux：

```sh
CHATSTUDIO_PREVIEW_FONT=/absolute/path/to/local-cjk-font.ttf \
  flutter test test/preview_test.dart --reporter expanded
```

测试加载本地字体与应用 Material Icons，覆盖本目录的 19 张 PNG。没有配置 `CHATSTUDIO_PREVIEW_FONT` 时，此测试默认跳过，不影响普通单元测试。不同字体/Flutter 引擎可能带来字形或抗锯齿差异，不把跨机器像素完全一致作为验收条件。

生成后检查中文是否完整、标题/模型是否合理、浅深主题对比度、弹层选中项、输入框和阅读入口是否被裁切。README 引用其中的主要场景，本目录保留完整浅深主题及错误状态预览。

## 验证边界

这些截图没有连接生产服务，不含真实账号、密钥、聊天或文件。它们不能证明原生权限、录音、文件选择、软键盘、后台网络恢复、真机帧率和 iOS 编译通过。协议测试与 Android 打包结果见 [测试记录](../testing.md)。

Agent 图标来自用户自己的服务器；离线预览未连接服务器，展示本地回退标识，不复制或分发上游图标资源。

Agent 选择预览使用七种已安装 Agent 的确定性接口夹具；未连接服务器的静态图标资源，展示本地标识/名称缩写回退。实际连接时优先显示当前服务器 Agent 管理页使用的图标；不在仓库重新分发第三方 Agent 图标。
