import 'package:flutter/material.dart';
import '../../l10n.dart';
import '../../state/app_controller.dart';

/// Native language names stay readable even when the current UI is unfamiliar.
class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => DropdownButton<String>(
    key: const ValueKey('app-language-picker'),
    value: controller.language,
    underline: const SizedBox.shrink(),
    borderRadius: BorderRadius.circular(16),
    hint: Text(context.tr('语言')),
    items: const [
      DropdownMenuItem(value: 'zh', child: Text('中文')),
      DropdownMenuItem(value: 'en', child: Text('English')),
    ],
    onChanged: (value) async {
      if (value == null) return;
      try {
        await controller.setLanguage(value);
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('语言已切换，但保存失败，重启后可能恢复原设置。'))),
        );
      }
    },
  );
}
