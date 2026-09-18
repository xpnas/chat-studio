import '../../l10n.dart';
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
          Text(
            context.tr("选择模型"),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr("按提供商分组 · 当前模型优先"),
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: TextField(
              decoration: InputDecoration(
                hintText: context.tr("搜索模型或提供商"),
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      search.isEmpty
                          ? context.tr("没有可用模型，请在 Studio 中配置")
                          : context.tr("没有匹配的提供商或模型"),
                    ),
                  )
                : ListView.builder(
                    key: ValueKey(search),
                    clipBehavior: Clip.hardEdge,
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
                              context.l10n.format("{0} · {1} 个模型", {
                                '0': row.provider,
                                '1': grouped[row.provider]!.length,
                              }),
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
                      // ListTile paints its selected/ink background on the
                      // nearest Material, not on its own RenderBox. Give each
                      // lazy row a clipped Material so paint cannot escape the
                      // list viewport into the fixed title/search area.
                      return Padding(
                        key: ValueKey('model-row:${model.key}'),
                        padding: const EdgeInsets.only(
                          left: 38,
                          right: 12,
                          bottom: 2,
                        ),
                        child: Material(
                          key: ValueKey('model-surface:${model.key}'),
                          color: selected
                              ? colors.primaryContainer.withValues(alpha: .42)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          clipBehavior: Clip.antiAlias,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(color: colors.outlineVariant),
                              ),
                            ),
                            child: ListTile(
                              key: ValueKey('model:${model.key}'),
                              selected: selected,
                              // Background belongs to the bounded Material.
                              selectedTileColor: Colors.transparent,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              title: Text(
                                model.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                              subtitle: Text(
                                '${selected ? context.tr("当前使用 · ") : ''}${model.id}',
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
