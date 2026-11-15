/// `RenderViewport#0c59b relayoutBoundary=up10 NEEDS-LAYOUT NEEDS-PAINT`
/// → `RenderViewport`. The ids and dirty flags change on every run, so they
/// stop identical errors from being recognised as repeats.
String stripRenderIds(String text) => text.replaceAll(_renderIds, '');

final _renderIds = RegExp(r'#[0-9a-f]{5}(?:\s+relayoutBoundary=\S+)?(?:\s+NEEDS-[A-Z-]+)*');

/// Errors Flutter reports as a side effect of an earlier layout error, such
/// as the dozen `RenderBox was not laid out` errors after one
/// `Vertical viewport was given unbounded height`.
bool isFollowOnError(String message) => _followOn.hasMatch(message);

final _followOn = RegExp(
  r'^(RenderBox was not laid out|Cannot hit test a render box that has never been laid out|'
  r'RenderBox.size accessed beyond the scope of resize)',
);

/// The short name of a follow-on error, for the "hidden" note.
String followOnKind(String message) => _followOn.firstMatch(message)?[1] ?? message;
