import '../data/models.dart';
import '../data/person_models.dart';

/// The cache id describes `latest` exactly; older pages never alter that page.
class PersonTimeline {
  PersonTimelinePage? latest;
  final pages = <PersonTimelinePage>[];
  final messages = <String, ChatMessage>{};
  final flows = <String, PersonFlow>{};
  final items = <PersonTimelineItem>[];
  bool readingOlder = false, hasNewer = false;
  String before = '';
  bool hasMore = false;
  int generation = 0;
  String? anchorKey;
  int get historyRevision => latest?.historyRevision ?? -1;
  void clear() {
    generation++;
    latest = null;
    pages.clear();
    messages.clear();
    flows.clear();
    items.clear();
    before = '';
    hasMore = false;
    readingOlder = false;
    hasNewer = false;
    anchorKey = null;
  }

  void mergeFlows(Iterable<PersonFlow> updates) {
    for (final flow in updates) {
      final old = flows[flow.id];
      if (old == null ||
          flow.revision > old.revision ||
          flow.revision == old.revision &&
              old.stages.isEmpty &&
              flow.stages.isNotEmpty) {
        flows[flow.id] = flow;
      }
    }
  }

  bool applyLatest(PersonTimelinePage page) {
    final invalid =
        latest != null &&
        (page.reset ||
            page.historyRevision != historyRevision ||
            page.historyClearedAt != latest!.historyClearedAt ||
            page.projection != latest!.projection);
    if (invalid) clear();
    final changed =
        latest?.id != page.id ||
        latest?.items.map((i) => i.key).join('|') !=
            page.items.map((i) => i.key).join('|');
    latest = page;
    mergeFlows([...page.cards.values, ...page.flows]);
    if (readingOlder) {
      hasNewer = hasNewer || changed;
      _boundWindow();
      _prune();
      return invalid;
    }
    pages
      ..clear()
      ..add(page);
    items
      ..clear()
      ..addAll(page.items);
    messages
      ..clear()
      ..addAll(page.messages);
    before = page.before;
    hasMore = page.hasMore;
    _prune();
    return invalid;
  }

  void beginReading() {
    if (latest != null) readingOlder = true;
  }

  void showLatest() {
    final page = latest;
    if (page == null) return;
    readingOlder = false;
    hasNewer = false;
    applyLatest(page);
  }

  bool prepend(PersonTimelinePage page, int expectedGeneration) {
    if (generation != expectedGeneration ||
        latest == null ||
        page.historyRevision != historyRevision ||
        page.reset) {
      return false;
    }
    readingOlder = true;
    final known = items.map((i) => i.key).toSet();
    items.insertAll(0, page.items.where((i) => known.add(i.key)));
    messages.addAll(page.messages);
    mergeFlows([...page.cards.values, ...page.flows]);
    pages.insert(0, page);
    anchorKey = page.items.firstOrNull?.key ?? anchorKey;
    before = page.before;
    hasMore = page.hasMore;
    _boundWindow();
    _prune();
    return true;
  }

  void _boundWindow() {
    if (latest == null) return;
    // Keep the page being read and the exact latest snapshot under one budget.
    Set<String> retainedKeys() => {
      ...latest!.items.map((item) => item.key),
      for (final page in pages) ...page.items.map((item) => item.key),
    };
    while (pages.length > 1 && retainedKeys().length > 300) {
      var index = pages.lastIndexWhere(
        (page) => !page.items.any((item) => item.key == anchorKey),
      );
      if (index < 0) index = pages.length - 1;
      final removed = pages.removeAt(index);
      final keep = pages.expand((p) => p.items).map((i) => i.key).toSet();
      items.removeWhere(
        (i) =>
            removed.items.any((r) => r.key == i.key) && !keep.contains(i.key),
      );
    }
    if (pages.isNotEmpty) {
      before = pages.first.before;
      hasMore = pages.first.hasMore;
    }
  }

  void _prune() {
    final messageIds = items
        .where((i) => i.kind == 'message')
        .map((i) => i.id)
        .toSet();
    messages.removeWhere((id, _) => !messageIds.contains(id));
    final flowIds = {
      ...items.where((i) => i.kind == 'flow').map((i) => i.id),
      ...latest?.flows.map((f) => f.id) ?? <String>[],
    };
    flows.removeWhere((id, _) => !flowIds.contains(id));
  }

  Map<String, dynamic>? cacheData() => latest == null || latest!.id.isEmpty
      ? null
      : {
          'latest': latest!.raw,
          'window': [for (final page in pages) page.raw],
          'reading_older': readingOlder,
        };
  void restore(Map<String, dynamic> data) {
    final page = PersonTimelinePage.fromJson(asMap(data['latest']));
    clear();
    applyLatest(page);
    if (data['reading_older'] == true) {
      pages.clear();
      items.clear();
      messages.clear();
      for (final raw in asList(data['window']).reversed) {
        final older = PersonTimelinePage.fromJson(asMap(raw));
        prepend(older, generation);
      }
      readingOlder = true;
    }
  }

  int? get visibleReadCursor {
    if (readingOlder) return null;
    final ids = items
        .where(
          (item) =>
              item.kind == 'message' &&
              messages[item.id]?.role == 'assistant' &&
              messages[item.id]?.visible == true,
        )
        .map((item) => int.tryParse(item.id))
        .whereType<int>();
    return ids.isEmpty ? null : ids.reduce((a, b) => a > b ? a : b);
  }
}
