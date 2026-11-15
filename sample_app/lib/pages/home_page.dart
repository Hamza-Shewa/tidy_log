import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../scenarios/scenario.dart';

/// Lists every scenario by group. Tapping one runs it; "Run all" taps each
/// one in turn through real pointer events, so errors reach Flutter by the
/// same path as a finger tap.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.scenarios,
    required this.demos,
    required this.modeLabel,
    this.autorun = false,
  });

  final List<Scenario> scenarios;
  final Demos demos;

  /// Says whether tidy_log is on, so screenshots are unambiguous.
  final String modeLabel;

  /// Starts "Run all" after the first frame (`--dart-define=AUTORUN=true`).
  final bool autorun;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final Map<String, GlobalKey> _keys = {
    for (final s in widget.scenarios) s.id: GlobalKey(debugLabel: s.id),
  };
  String _status = 'Tap a scenario and watch the console.';
  bool _runningAll = false;
  int _nextPointer = 1000;

  @override
  void initState() {
    super.initState();
    if (widget.autorun) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_runAll()));
    }
  }

  void _run(Scenario scenario) {
    _setStatus('${scenario.title}: see the console.');
    // Not caught on purpose: a sync throw goes to the gesture handler and a
    // failed Future becomes an uncaught async error.
    final result = scenario.run(context, widget.demos);
    if (result is Future<String?>) {
      unawaited(result.then((message) => message == null ? null : _setStatus(message)));
    } else if (result != null) {
      _setStatus(result);
    }
  }

  /// On a cold start the first frames can be laid out in a zero-sized view,
  /// and a tap sent then hits nothing. Wait until the view has a size.
  Future<void> _waitForLayout() async {
    for (var i = 0; i < 50 && mounted && View.of(context).physicalSize.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _runAll() async {
    if (_runningAll) return;
    setState(() => _runningAll = true);
    await _waitForLayout();
    debugPrint('>>> run all: ${widget.scenarios.length} scenarios');
    for (final scenario in widget.scenarios) {
      if (!mounted) return;
      debugPrint('>>> scenario ${scenario.id}');
      await _tap(_keys[scenario.id]!);
      await Future<void>.delayed(scenario.settle);
      if (scenario.opensPage && mounted) {
        Navigator.of(context).pop();
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    debugPrint('>>> run all done');
    if (mounted) setState(() => _runningAll = false);
  }

  /// Scrolls [key]'s tile into view and sends a pointer down and up at its
  /// centre.
  Future<void> _tap(GlobalKey key) async {
    final target = key.currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(target, alignment: 0.5);
    await WidgetsBinding.instance.endOfFrame;
    if (!target.mounted) return;
    final box = target.findRenderObject()! as RenderBox;
    final centre = box.localToGlobal(box.size.center(Offset.zero));
    final pointer = _nextPointer++;
    GestureBinding.instance.handlePointerEvent(PointerDownEvent(pointer: pointer, position: centre));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    GestureBinding.instance.handlePointerEvent(PointerUpEvent(pointer: pointer, position: centre));
  }

  void _setStatus(String text) {
    if (mounted) setState(() => _status = text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('tidy_log sample')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Card.filled(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.modeLabel, key: const Key('mode'), style: theme.textTheme.labelLarge),
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: Text(_status, key: const Key('status'), style: theme.textTheme.bodyLarge),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _runningAll ? null : () => unawaited(_runAll()),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(_runningAll ? 'Running all…' : 'Run all'),
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            for (final group in ScenarioGroup.values) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Semantics(
                  header: true,
                  child: Text(group.label, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)),
                ),
              ),
              for (final scenario in widget.scenarios.where((s) => s.group == group))
                ListTile(
                  key: _keys[scenario.id],
                  title: Text(scenario.title),
                  subtitle: Text(scenario.expected),
                  trailing: Icon(scenario.opensPage ? Icons.open_in_new : Icons.play_circle_outline),
                  onTap: () => _run(scenario),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
