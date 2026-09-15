/// Reconcile two representations of the SAME run during resume only. Never
/// apply this to live deltas: repeated tokens in a normal stream are legitimate.
String reconcileResumeText(
  String known,
  String replay, {
  required bool completeReplay,
}) {
  if (known.isEmpty) return replay;
  if (replay.isEmpty) return known;
  if (replay.startsWith(known)) return replay;
  if (known.startsWith(replay)) return known;
  if (completeReplay) {
    // A replay containing run.started is the ordered stream for this run.
    // Persisted tool steps can differ in separators; concatenating both doubles
    // content. Use the replay, rather than guessing at paragraph boundaries.
    return replay;
  }
  if (known.contains(replay)) return known;
  // The official server retains only the latest 200 events. The replay can
  // start in the middle of an already-rendered paragraph. Linear-time KMP finds
  // the longest suffix(known) == prefix(replay), without quadratic substringing.
  final prefix = List<int>.filled(replay.length, 0);
  for (var i = 1, j = 0; i < replay.length; i++) {
    while (j > 0 && replay.codeUnitAt(i) != replay.codeUnitAt(j)) {
      j = prefix[j - 1];
    }
    if (replay.codeUnitAt(i) == replay.codeUnitAt(j)) j++;
    prefix[i] = j;
  }
  var matched = 0;
  for (var i = 0; i < known.length; i++) {
    while (matched > 0 &&
        (matched == replay.length ||
            known.codeUnitAt(i) != replay.codeUnitAt(matched))) {
      matched = prefix[matched - 1];
    }
    if (known.codeUnitAt(i) == replay.codeUnitAt(matched)) matched++;
  }
  return known + replay.substring(matched);
}
