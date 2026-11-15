import '../entry.dart';

/// Folds an entry that repeats right after itself into one entry with a
/// count (`×30`), and near-duplicates into `↳ +N similar`.
///
/// It holds the latest entry back until a different one arrives or [flush]
/// is called, because the count is only known at the end of the run.
final class RepeatCollapser {
  Entry? _pending;

  List<Entry> add(Entry entry) {
    final pending = _pending;
    if (pending != null) {
      if (pending.key == entry.key) {
        pending.repeat++;
        return const [];
      }
      if (pending.similarKey != null && pending.similarKey == entry.similarKey) {
        pending.similar++;
        return const [];
      }
    }
    _pending = entry;
    return [?pending];
  }

  List<Entry> flush() {
    final pending = _pending;
    _pending = null;
    return [?pending];
  }
}
