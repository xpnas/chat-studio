# 聊天横滑、服务器工作区与统一正文字号

## 原因与修复

### 横滑不是仅扩大边缘触发范围

之前只配置了 Scaffold 的左侧 Drawer，没有覆盖聊天区域。将边缘宽度改为 72 仍不能满足从正文开始滑动；可选文字还会消耗水平手势。

`ChatSwipeRegion` 只包裹阅读区（包括新建欢迎页），观察单指触摸：先判断横向意图、移动至少 64 逻辑像素后松手打开抽屉。右滑打开记录，左滑打开服务器工作区。不是全屏透明遮罩，不覆盖输入框。为避免与 Scaffold 的边缘拖动重复触发，关闭额外的边缘打开识别；按钮入口和抽屉关闭交互保留。

- 保留逐条用户文字/Markdown 段落的长按选择，移除额外的全列表 SelectionArea，避免嵌套选择手势冲突。
- 长按后拖选、纵向/斜向阅读、小幅移动、多指操作不打开抽屉。
- 收到子控件横向滚动通知时让代码/表格滚动优先。
- 不对鼠标拖选触发抽屉。
- 测试从屏幕中央和 AI 正文开始慢速拖动，而不是只测试点击菜单或边缘操作；这些是组件层触摸测试，不代表真机帧率或系统返回手势已验收。

### 工作区一直应是服务器路径

读取固定上游 `hermes-studio v1.0.3` 提交 `b44c74318fe5a0a1f3aed29d5095393964fc3d62` 的：

- `packages/server/src/modules/studio/controllers/sessions.ts`：`listWorkspaceFolders`、`setWorkspace`、`resolveSessionWorkspacePath`、`listWorkspaceFiles`。
- `packages/server/src/modules/studio/services/workspace/manager.ts`：服务端工作目录解析及 `WORKSPACE_BASE`。

目录选择接口返回两种用途不同的字段：

```json
{
  "base": "/srv/agents",
  "current": "",
  "folders": [
    {"name": "project", "path": "project", "fullPath": "/srv/agents/project"}
  ]
}
```

- `path` 用于下一层 `GET /api/studio/workspace/folders?path=...` 导航，Linux/设置 WORKSPACE_BASE 时可为相对路径。
- `fullPath` 才是 `POST /api/studio/sessions/:id/workspace` 的 `workspace` 参数。旧实现把相对 `path` 保存成工作目录，服务端又按其进程目录解析，从而可能返回 **ENOENT / no such file or directory**。
- App 不读取手机目录、不本地拼接或标准化服务器路径。路径校验兼容 POSIX、Windows 盘符及 UNC；没有合法 `fullPath` 的选项禁用，不再退回相对路径。
- 文件列表响应是 `absolutePath / path / entries`，不是旧实现读取的 `current`；修复后直接显示服务端的绝对路径，点击子目录可浏览并返回根目录。
- 文件夹选择支持分层进入、上一级及选择当前目录，不安装、创建或删除服务器文件。
- 新建页可以打开工作区面板；发送首条消息、建立实际会话后才能选择目录，不为选择目录预先创建错误类型的会话。
- 运行中、待同步、只读自动化会话不允许切换工作目录；保存期间禁止同会话发起新消息。
- ENOENT、无权限、读取失败在工作区内部显示并可重试，不把原始目录错误挂到聊天正文顶部。真实目录确实不存在时仍需选择服务器已有目录，不自动创建或假报成功。

状态与目录错误保存在各会话对象内；异步读写捕获客户端、登录 epoch、会话、导航版本与请求序号，防止旧服务器/旧会话/旧请求覆盖当前页面。服务器的真实权限判定和文件系统边界仍由服务端执行，客户端不绕过 403。

工作区刷新按钮现调用文件列表刷新，不再误调模型/Profile 初始化的同名旧方法。

### 正文字号

旧实现只改用户 SelectableText，AI Markdown 的段落样式仍单独设为 16。共用 `chatBodyStyle`（1.0.20 为 14.5，当前已按阅读反馈调为 15.5 字号、1.48 行高），Markdown 普通段落、列表标记、引用、表格正文使用统一基准；标题层级、粗体与 13 号等宽代码保留各自语义。遵从系统文字缩放，不固定 TextScaler。

## 验证

`test/workspace_gestures_test.dart` 新增 15 项测试，包括：中央慢滑、AI 文字滑动、左右抽屉、纵向/短距离/输入框不误触、长按/多指/横向内容保护、Linux/Windows 服务器绝对路径、目录分层选择、真实请求 body、ENOENT 本地提示、迟到读写/退出隔离、320px/1.8 倍字体及浅深主题字号一致性。

`test/live_contract_test.dart` 新增真实远程工作区契约：在隔离服务器上创建测试目录，读取目录选项，按 `fullPath` 保存会话工作区，检查服务端持久化结果，再写入测试文件并通过文件列表读回。两端测试脚本设置独立 `WORKSPACE_BASE`，不访问生产工作目录。

完整测试数量、截图和包校验见 [本次交付](release-1.0.20.md)。CodeGraph 查询本地上游时当前工具报告没有可用索引，因此本轮以直接读取固定上游源码为依据，未声称完成新的 CodeGraph 分析或擅自重建索引。
