import 'package:flutter/material.dart';
import '../../data/models.dart';

class ModelSheet extends StatefulWidget {
  const ModelSheet({super.key, required this.models, this.selected});
  final List<ModelChoice> models;
  final ModelChoice? selected;
  @override
  State<ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends State<ModelSheet> {
  String query = '';
  late final Set<String> expanded = {
    if (widget.selected != null) widget.selected!.provider,
  };
  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<ModelChoice>>{};
    final search = query.trim().toLowerCase();
    for (final model in widget.models) {
      if ('${model.label} ${model.id} ${model.providerLabel} ${model.provider}'
          .toLowerCase()
          .contains(search)) {
        grouped.putIfAbsent(model.provider, () => []).add(model);
      }
    }
    // Keep the selected provider and model visible at the top without
    // duplicating the model row when the list is long.
    final providerOrder = grouped.keys.toList()
      ..sort((a, b) {
        final selectedProvider = widget.selected?.provider;
        if (a == selectedProvider && b != selectedProvider) return -1;
        if (b == selectedProvider && a != selectedProvider) return 1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    final rows = <({String provider, ModelChoice? model})>[];
    for (final provider in providerOrder) {
      final items = grouped[provider]!
        ..sort((a, b) {
          final selected = widget.selected?.key;
          if (a.key == selected && b.key != selected) return -1;
          if (b.key == selected && a.key != selected) return 1;
          return a.label.toLowerCase().compareTo(b.label.toLowerCase());
        });
      rows.add((provider: provider, model: null));
      if (search.isNotEmpty || expanded.contains(provider)) {
        rows.addAll(items.map((m) => (provider: provider, model: m)));
      }
    }
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .78,
      child: Column(
        children: [
          const Text(
            '选择模型',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            '按提供商分组 · 当前模型优先',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: '搜索模型或提供商',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      search.isEmpty ? '没有可用模型，请在 Studio 中配置' : '没有匹配的提供商或模型',
                    ),
                  )
                : ListView.builder(
                    key: ValueKey(search),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index], model = row.model;
                      if (model == null) {
                        final first = grouped[row.provider]!.first;
                        final open =
                            search.isNotEmpty ||
                            expanded.contains(row.provider);
                        return Semantics(
                          expanded: open,
                          child: ListTile(
                            key: ValueKey('provider:${row.provider}'),
                            leading: Icon(
                              Icons.dns_outlined,
                              size: 21,
                              color: colors.primary,
                            ),
                            title: Text(
                              first.providerLabel.isEmpty
                                  ? row.provider
                                  : first.providerLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '${row.provider} · ${grouped[row.provider]!.length} 个模型',
                            ),
                            trailing: Icon(
                              open
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                            ),
                            onTap: search.isNotEmpty
                                ? null
                                : () => setState(() {
                                    if (open) {
                                      expanded.remove(row.provider);
                                    } else {
                                      expanded.add(row.provider);
                                    }
                                  }),
                          ),
                        );
                      }
                      final selected = widget.selected?.key == model.key;
                      return Padding(
                        padding: const EdgeInsets.only(left: 38, right: 12),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: colors.outlineVariant),
                            ),
                          ),
                          child: ListTile(
                            key: ValueKey('model:${model.key}'),
                            selected: selected,
                            selectedTileColor: colors.primaryContainer
                                .withValues(alpha: .35),
                            title: Text(model.label),
                            subtitle: Text(
                              '${selected ? '当前使用 · ' : ''}${model.id}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: selected
                                ? Icon(
                                    Icons.check_circle_rounded,
                                    color: colors.primary,
                                  )
                                : null,
                            onTap: () => Navigator.pop(context, model),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
