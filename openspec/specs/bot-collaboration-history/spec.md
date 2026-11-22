# bot-collaboration-history Specification

## Purpose

支持用户用已配置 BOT 发起和控制多角色协作，并以统一时间线阅读消息、协作卡片及阶段结果，在跨设备更新、分页、断线和历史清空时维持完整且不泄露内部记录的可恢复阅读体验。

## Requirements

### Requirement: 使用既有 BOT 发起协作
客户端 SHALL 提供协作创建入口，指定发起 BOT、标题、目标、既有 BOT 阶段、各阶段目标与返回期望，支持顺序阶段、并行组和有限轮次；提交前 SHALL 展示执行路线，非法路由不能发送。

#### Scenario: 顺序和并行混合协作
- **WHEN** 用户配置另一 BOT 执行第一组，两名不同 BOT 并行执行第二组
- **THEN** 确认界面显示组间顺序及组内并行关系，服务端按该路线创建协作

#### Scenario: 无效自交接或重复角色
- **WHEN** 路由包含服务端禁止的自交接、同一并行组重复 BOT 或超出阶段/轮次边界
- **THEN** 客户端指出问题并阻止提交，不能静默改写成另一条路线

#### Scenario: 创建确认丢失
- **WHEN** 创建已交出但未获得结果
- **THEN** 客户端先查询发起 BOT 的协作，不自动重复创建；明确重试同一操作时复用幂等键和原始负载

### Requirement: 协作控制遵守状态和版本
客户端 SHALL 展示协作及阶段状态、轮次、参与 BOT、交付或确认中的状态和错误，并提供服务端允许的 stop/resume；控制 SHALL 携带 expected_revision 与幂等键，不向用户提供仅运行上下文可执行的阶段 complete。

#### Scenario: Web 已改变协作版本
- **WHEN** 手机以旧版本停止或恢复协作得到 409
- **THEN** 刷新详情并让用户重新选择，不自动使用新版本覆盖远端操作

#### Scenario: 停止后 worker 尚未结束
- **WHEN** 协作处于停止过程中且服务端尚不允许恢复
- **THEN** 手机展示实际状态及不可恢复原因，不将停止视为立即终止所有执行

#### Scenario: 已完成协作
- **WHEN** 协作状态为 completed
- **THEN** 历史和结果仍可查看，停止/恢复不可操作，不伪造重新执行入口

### Requirement: 消息与卡片遵循统一游标
客户端 SHALL 按服务端 timeline.items 顺序混合展示 message/flow，以类型和 ID 共同识别项目；before 游标 SHALL 保持不透明，翻页依据 timeline.has_more，不能依据普通消息数量或总数终止。

#### Scenario: 页面只含协作卡片
- **WHEN** messages 为空但 timeline.has_more 为 true
- **THEN** 卡片仍展示且继续使用返回的 before 加载更早内容

#### Scenario: 消息与协作 ID 相同
- **WHEN** 一条 message 和一张 flow 卡片拥有相同文本 ID
- **THEN** 两项分别保留，重叠页只对相同类型及 ID 去重

### Requirement: 活动协作更新不破坏历史窗口
客户端 SHALL 合并活动 flows、终态 cards 与 card_updates，并保留已加载旧页和阅读锚点；同一协作的陈旧版本不得覆盖新状态，活动计数和历史分页计数 SHALL 分开。

#### Scenario: 阅读旧页时协作完成
- **WHEN** person.updated 带来终态卡片更新
- **THEN** 原阅读窗口不被全部替换，新增内容给出提示，重复更新不产生重复卡片

### Requirement: 协作详情展示授权阶段结果
客户端 SHALL 通过协作详情路径显示各参与 BOT、阶段、轮次及可见对话，支持独立分页并按 history_key 失效旧页；内部工具、思考和私有 worker 原始记录 SHALL 不作为主时间线内容重新展开。

#### Scenario: 被投影隐藏的消息占据原始页
- **WHEN** 详情页过滤后没有可见消息但返回 has_more 和 next_before_id
- **THEN** 客户端按返回游标继续分页，不以空显示页认定结束

#### Scenario: 查看某阶段结果
- **WHEN** 用户点击卡片中的阶段
- **THEN** 详情明确标示对应 BOT 和轮次，显示服务端授权结果；记录已清空或无权限时明确反馈

### Requirement: 恢复缓存同时包含消息和协作信息
客户端 SHALL 将投影版本、服务端缓存 ID、消息、卡片、顺序、分页元数据和历史版本作为一致快照保存，按服务器、账号和 BOT 隔离；缓存命中仍 SHALL 更新实时状态，不能把缺失消息字段当作空历史。

#### Scenario: App 条件恢复命中
- **WHEN** app.resumed 返回 messagesCached=true 且本地具有同 ID 的完整快照
- **THEN** 恢复消息和卡片并应用本次运行状态与交互，旧实时状态不覆盖新状态

#### Scenario: 缓存损坏或投影升级
- **WHEN** 服务端报告命中但本地缺页，或本地投影版本不匹配
- **THEN** 不展示残缺快照，清除失效缓存 ID 后请求完整投影，不回退读取内部原始消息

#### Scenario: 缓存有界
- **WHEN** 连续翻页使读取窗口超出保留预算
- **THEN** 消息和卡片合并计入最多 300 个时间线项目，淘汰页仍可用游标重新加载且不会无界增长

### Requirement: 历史修订使旧游标和缓存失效
客户端 SHALL 区分协作 revision、主时间线 history_revision 和详情 history_key；权威清空、timeline.reset 或历史修订 SHALL 使对应旧页、游标、卡片及缓存失效，同时保留未发送草稿。

#### Scenario: Web 清空后使用旧游标
- **WHEN** 服务端返回 reset 或新的历史修订
- **THEN** 手机回到有效最新窗口，不把旧消息或旧卡片重新合并进来

#### Scenario: 协作状态更新但历史未清空
- **WHEN** 只有 flow revision 增加
- **THEN** 客户端更新该协作内容而不清除整段历史

### Requirement: 展示投影不能反推出已读
客户端 SHALL 仅使用已展示内容对应的服务端阅读/attention 游标确认 BOT 已读，不根据 timeline 游标、flow ID、卡片时间戳或隐藏原始消息的总数推导已读。

#### Scenario: 有卡片但没有可确认阅读游标
- **WHEN** 最新页面已经显示而服务端未提供能够对应可见内容的阅读游标
- **THEN** 客户端保留未读并刷新可确认状态，不为清除标记而猜测最大消息 ID
