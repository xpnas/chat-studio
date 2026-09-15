# 1.0.15（16）会话恢复状态完整性修复

## 修复

- 删除按事件内容计数的实时事件抵扣，独立 reducer 重放服务端保留的有序事件。审批、澄清、工具状态不再因“已经实时收到”而丢失。
- 已解决或过期的审批/澄清以恢复事件为准，不通过盲目保留本地 pending 状态来恢复过时交互。
- 仅使用 runMarker 与当前 run 相同的 pending assistant 作为本地缓存及 renderKey 来源。删除不检查 run 的二次前缀拼接，防止跨轮正文与思考污染。
- 保留完整回放/截断回放的正文重叠合并，正常重复增量不去重；重复恢复不重复正文，不重发用户请求。
- 修正原有测试文件的格式以满足 CI 门禁，并修正 1.0.14 文档中与实际回归不一致的表述。

## 验证（2026-09-15）

- 原先后台审批、恢复正文两项失败测试通过，未删除测试或放宽断言。
- 新增 13 项状态完整性回归：审批/澄清完整及截断恢复、resolved/expired 不复活、工具事件恢复、重复增量、旧 pending/已完成 run 隔离及空回放。
- 格式检查和 `flutter analyze --fatal-infos` 通过。
- `flutter test`：189 项通过，8 项环境相关测试跳过，0 项失败。

## Android 产物

使用本机已有 Release 签名配置构建，没有更换密钥或提交签名材料：

| 产物 | 路径 | 大小 |
| --- | --- | --- |
| Release APK | `build/app/outputs/flutter-apk/app-release.apk` | 59,269,743 bytes |
| Release AAB | `build/app/outputs/bundle/release/app-release.aab` | 57,586,638 bytes |

- APK：`apksigner verify --verbose --print-certs` 通过（v2）；`aapt dump badging` 确认 `versionName=1.0.15`、`versionCode=16`、非 debuggable，包含 arm64-v8a / armeabi-v7a / x86_64。
- APK 包内包含 Dart AOT `libapp.so`，没有 debug `kernel_blob.bin`。
- AAB：`bundletool validate` 返回成功；`jarsigner -verify` 返回 0。后者仍输出自签名证书、无时间戳及 JarFile/JarInputStream 条目顺序警告，不应表述为“无警告验证”或已通过商店上传验收。
- 签名证书 SHA-256：`51b8f4a1a78f7cb5689601fc762606790c2006b4001658baf5c1480dfc64ff28`。覆盖安装要求已安装应用使用同一证书。

SHA-256（本次本地产物）：

```text
8bac2efa4664bcf7ecdea9591abef5e16c1a8a62d176a16973617ceb9de262ae  app-release.apk
c9fe0ef695731d5ed58d3a9686952cd0ff180dcdc949a3a414ef28f33d349e13  app-release.aab
```

## 验证边界

本次没有运行真实 Studio 联调或 GitHub Actions，未进行 Android 真机/模拟器操作验收，也没有在 Windows 上进行 iOS/Xcode 编译。客户端共享 Dart 状态修复适用于双端，但不代表原生权限、系统后台生命周期和帧率已通过实机验证。历史版本联调结果不能替代本版本验收。
