import 'package:flutter/material.dart';
import '../../l10n.dart';
import '../../data/models.dart';
import '../../data/person_api.dart';
import '../../data/person_models.dart';
import '../../data/studio_api.dart';
import 'model_sheet.dart';

Future<PersonModelChoice?> showPersonModelPicker(
  BuildContext context, {
  required StudioApi api,
  required Listenable scopeChanges,
  required bool Function() valid,
  PersonModelChoice? selected,
  bool Function()? canSelect,
}) => showModalBottomSheet<PersonModelChoice>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => PersonModelPicker(
    api: api,
    scopeChanges: scopeChanges,
    valid: valid,
    selected: selected,
    canSelect: canSelect ?? () => true,
  ),
);

class PersonModelPicker extends StatefulWidget {
  const PersonModelPicker({
    super.key,
    required this.api,
    required this.scopeChanges,
    required this.valid,
    required this.canSelect,
    this.selected,
  });
  final StudioApi api;
  final Listenable scopeChanges;
  final bool Function() valid, canSelect;
  final PersonModelChoice? selected;
  @override
  State<PersonModelPicker> createState() => _PersonModelPickerState();
}

class _PersonModelPickerState extends State<PersonModelPicker> {
  List<PersonModelChoice> models = [];
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    widget.scopeChanges.addListener(changed);
    load();
  }

  void changed() {
    if (mounted) setState(() {});
    if (!widget.valid()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final route = ModalRoute.of(context);
        if (route != null) Navigator.of(context).removeRoute(route);
      });
    }
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final next = await widget.api.personModels();
      if (mounted && widget.valid()) setState(() => models = next);
    } catch (e) {
      if (mounted && widget.valid()) {
        setState(
          () => error = e is ApiException && e.status == 404
              ? '服务端不支持 BOT 模型选择，请升级 Studio'
              : 'BOT 模型列表加载失败，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    widget.scopeChanges.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .86,
    child: !widget.valid()
        ? Center(child: Text(context.tr('账号已变化')))
        : loading
        ? const Center(child: CircularProgressIndicator.adaptive())
        : error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.tr(error!)),
                TextButton(onPressed: load, child: Text(context.tr('重试'))),
              ],
            ),
          )
        : Column(
            children: [
              if (!widget.canSelect())
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(context.tr('请等待当前回复结束后修改模型')),
                ),
              Expanded(
                child: AbsorbPointer(
                  absorbing: !widget.canSelect(),
                  child: ModelSheet(models: models, selected: widget.selected),
                ),
              ),
            ],
          ),
  );
}
