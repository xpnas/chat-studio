import 'models.dart';

/// Mirrors Studio v1.0.3 chat-run/compression.ts, not a live session status.
class CompressionSettings {
  const CompressionSettings({
    required this.enabled,
    required this.threshold,
    required this.defaultEnabled,
  });
  final bool enabled, defaultEnabled;
  final double threshold;

  factory CompressionSettings.fromConfig(Map<String, dynamic> config) {
    final raw = asMap(config['compression']);
    final value = raw['threshold'];
    return CompressionSettings(
      enabled: raw['enabled'] != false,
      defaultEnabled: !raw.containsKey('enabled'),
      threshold: (value is num && value.isFinite ? value.toDouble() : .5).clamp(
        .05,
        .95,
      ),
    );
  }

  String get percent => formatPercent(threshold * 100);
  String get summary =>
      '${enabled ? '已启用' : '已关闭'}'
      '${defaultEnabled ? '（服务端默认）' : ''} · 阈值 $percent%';

  static String formatPercent(double value) =>
      value.toStringAsFixed(4).replaceFirst(RegExp(r'\.?0+$'), '');
}
