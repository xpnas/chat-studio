/// Same accounting as Studio ChatInput.vue: prefer context, otherwise input + output.
class ContextUsage {
  const ContextUsage({this.input = 0, this.output = 0, this.context});
  final int input, output;
  final int? context;
  int get used => context != null && context! > 0 ? context! : input + output;

  ContextUsage merge(Map<String, dynamic> data) {
    int? value(String camel, String snake) {
      final raw = data[camel] ?? data[snake];
      final n = raw is num ? raw : num.tryParse('$raw');
      return n != null && n.isFinite && n >= 0 ? n.toInt() : null;
    }

    return ContextUsage(
      input: value('inputTokens', 'input_tokens') ?? input,
      output: value('outputTokens', 'output_tokens') ?? output,
      context: value('contextTokens', 'context_tokens') ?? context,
    );
  }

  static String format(int n) => n >= 1000000
      ? '${(n / 1000000).toStringAsFixed(1)}M'
      : n >= 1000
      ? '${(n / 1000).toStringAsFixed(1)}k'
      : '$n';
}
