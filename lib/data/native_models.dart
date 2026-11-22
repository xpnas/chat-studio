import 'models.dart';

enum NativeModelStatus {
  ready,
  empty,
  notInstalled,
  authRequired,
  unsupported,
  timeout,
  error,
}

class NativeModel {
  const NativeModel({
    required this.id,
    required this.name,
    this.resolvedModel = '',
    this.provider = '',
    this.isDefault = false,
    this.hidden = false,
    this.reasoningEfforts = const [],
    this.modelFamily = '',
    this.modelFamilyName = '',
    this.reasoningEffort = '',
    this.contextWindow,
    this.maxOutputTokens,
    this.inputModalities = const [],
  });
  final String id,
      name,
      resolvedModel,
      provider,
      modelFamily,
      modelFamilyName,
      reasoningEffort;
  final bool isDefault, hidden;
  final List<String> reasoningEfforts, inputModalities;
  final num? contextWindow, maxOutputTokens;
  ModelChoice get choice => ModelChoice(
    id: id,
    provider: '',
    label: resolvedModel.isEmpty ? name : resolvedModel,
    native: true,
    providerLabel: '原生模型',
    reasoningEfforts: reasoningEfforts,
  );
  factory NativeModel.fromJson(Map<String, dynamic> json) {
    final id = text(json['id']);
    if (id.isEmpty || json['name'] is! String) {
      throw const FormatException('Invalid native model');
    }
    return NativeModel(
      id: id,
      name: text(json['name']),
      resolvedModel: text(json['resolvedModel']),
      provider: text(json['provider']),
      isDefault: flag(json['isDefault']),
      hidden: flag(json['hidden']),
      reasoningEfforts: List.unmodifiable(
        asList(json['reasoningEfforts']).whereType<String>(),
      ),
      modelFamily: text(json['modelFamily']),
      modelFamilyName: text(json['modelFamilyName']),
      reasoningEffort: text(json['reasoningEffort']),
      contextWindow: json['contextWindow'] is num
          ? json['contextWindow'] as num
          : null,
      maxOutputTokens: json['maxOutputTokens'] is num
          ? json['maxOutputTokens'] as num
          : null,
      inputModalities: List.unmodifiable(
        asList(json['inputModalities']).whereType<String>(),
      ),
    );
  }
}

class NativeModelCatalog {
  const NativeModelCatalog({
    required this.agentId,
    required this.status,
    this.models = const [],
    this.source = '',
    this.scope = '',
    this.checkedAt = '',
    this.cached = false,
  });
  final String agentId, source, scope, checkedAt;
  final NativeModelStatus status;
  final List<NativeModel> models;
  final bool cached;
  bool get usable =>
      status == NativeModelStatus.ready || status == NativeModelStatus.empty;
  List<ModelChoice> get choices => [
    const ModelChoice(
      id: '',
      provider: '',
      label: 'Agent 默认模型',
      native: true,
      providerLabel: '原生模型',
      reasoningEfforts: [],
    ),
    ...models.where((model) => !model.hidden).map((model) => model.choice),
  ];
  factory NativeModelCatalog.fromJson(
    String agentId,
    Map<String, dynamic> json,
  ) {
    final status = switch (json['status']) {
      'ready' => NativeModelStatus.ready,
      'empty' => NativeModelStatus.empty,
      'not_installed' => NativeModelStatus.notInstalled,
      'auth_required' => NativeModelStatus.authRequired,
      'unsupported' => NativeModelStatus.unsupported,
      'timeout' => NativeModelStatus.timeout,
      'error' => NativeModelStatus.error,
      _ => throw const FormatException('Unknown native model status'),
    };
    if (json['models'] is! List) {
      throw const FormatException('Invalid native model directory');
    }
    return NativeModelCatalog(
      agentId: agentId,
      status: status,
      models: List.unmodifiable(
        asList(json['models']).map((row) => NativeModel.fromJson(asMap(row))),
      ),
      source: text(json['source']),
      scope: text(json['scope']),
      checkedAt: text(json['checkedAt']),
      cached: flag(json['cached']),
    );
  }
}
