/// Mirrored from official Studio v1.0.3 bridge-session-commands.ts and ChatInput.vue.
/// Commands are sent verbatim; interpretation belongs to the server/runtime.
class SlashCommand {
  const SlashCommand(this.insert, this.description, {this.args = ''});
  final String insert, description, args;
  String get name => insert.split(' ').first;
}

const slashCommands = [
  SlashCommand('usage', '计算当前会话用量', args: ''),
  SlashCommand('context', '查看当前上下文使用情况', args: ''),
  SlashCommand('status', '查看会话状态和队列', args: ''),
  SlashCommand('yolo', '切换当前会话 YOLO 模式并跳过危险命令审批', args: ''),
  SlashCommand('abort', '停止当前 Bridge 运行', args: ''),
  SlashCommand('queue', '把消息加入当前运行后的队列', args: '<消息>'),
  SlashCommand('skill', '<标题>', args: ''),
  SlashCommand('bundles', '查看 Skill Bundle', args: ''),
  SlashCommand('bundles create', '创建 Skill Bundle', args: ''),
  SlashCommand('learn', '从描述的来源学习可复用技能', args: '<文本>'),
  SlashCommand('plan', '生成一份 Markdown 实施计划', args: '<文本>'),
  SlashCommand('moa', '用默认组合模型运行一次性提示', args: '<文本>'),
  SlashCommand('goal', '设置一个跨轮次持续推进的目标', args: '<文本>'),
  SlashCommand('goal status', '查看当前目标状态', args: ''),
  SlashCommand('goal pause', '暂停当前目标循环', args: ''),
  SlashCommand('goal resume', '继续已暂停的目标循环', args: ''),
  SlashCommand('goal done', '完成并清除当前目标', args: ''),
  SlashCommand('goal clear', '清除当前目标', args: ''),
  SlashCommand('subgoal', '为当前目标追加验收条件', args: '<文本>'),
  SlashCommand('clear', '清空当前显示内容', args: ''),
  SlashCommand('clear --history', '删除当前会话已入库的消息历史', args: ''),
  SlashCommand('title', '<标题>', args: '<标题>'),
  SlashCommand('compress', '空闲时触发上下文压缩', args: ''),
  SlashCommand('compact', '压缩当前对话（桥接底层 CLI /compact）', args: ''),
  SlashCommand('fork', '将当前空闲会话 fork 成一个新的关联对话', args: '<标题>'),
  SlashCommand('steer', '向当前 Bridge 运行发送引导文本', args: '<文本>'),
  SlashCommand('destroy', '释放当前会话的 Bridge Agent', args: ''),
  SlashCommand('reload-mcp', '重载 MCP 服务器', args: ''),
  SlashCommand('reload-skills', '重载技能命令', args: ''),
];

List<SlashCommand> commandsForEngine(String engine) => engine == 'hermes'
    ? slashCommands
    : slashCommands
          .where(
            (c) => const [
              'context',
              'compact',
              'usage',
              'status',
            ].contains(c.name),
          )
          .toList();

String? readCommandName(String input) {
  final match = RegExp(r'^/([a-zA-Z][\w-]*)(?:\s|$)').firstMatch(input.trim());
  if (match == null) return null;
  final raw = match[1]!.toLowerCase();
  final name = raw == 'reload_skills' ? 'reload-skills' : raw;
  return slashCommands.any((c) => c.name == name) ? name : null;
}

String skillCommandName(String name) => name
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), '-')
    .replaceAll('_', '-')
    .replaceAll(RegExp(r'[^a-z0-9-]'), '')
    .replaceAll(RegExp(r'-+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');
