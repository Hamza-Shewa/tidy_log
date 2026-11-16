import 'dart:async';

import 'package:flutter/material.dart';

/// Pages that are wrong on purpose. Each one triggers a single, well-known
/// Flutter build or layout error inside its body; the app bar stays usable
/// so you can go back.
///
/// | Page                         | Error in the console                                   |
/// |------------------------------|--------------------------------------------------------|
/// | [NullInBuildPage]            | Null check operator used on a null value (red screen)  |
/// | [OverflowPage]               | A RenderFlex overflowed by … pixels on the right       |
/// | [UnboundedHeightPage]        | Vertical viewport was given unbounded height           |
/// | [UnboundedWidthFieldPage]    | An InputDecorator … cannot have an unbounded width     |
/// | [WrongParentDataPage]        | Incorrect use of ParentDataWidget                      |
/// | [BrokenImagePage]            | Exception caught by image resource service             |
/// | [RepeatingErrorPage]         | The same build error on every animation frame          |
/// | [LateSetStatePage]           | setState() called after dispose()                      |
class _BrokenPage extends StatelessWidget {
  const _BrokenPage({required this.title, required this.body});

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title)), body: body);
}

class Profile {
  const Profile(this.displayName);
  final String displayName;
}

class NullInBuildPage extends StatelessWidget {
  const NullInBuildPage({super.key, this.profile});

  /// Left null by the caller, as if the profile had not loaded yet.
  final Profile? profile;

  @override
  Widget build(BuildContext context) => _BrokenPage(title: 'Null in build', body: _ProfileName(profile: profile));
}

class _ProfileName extends StatelessWidget {
  const _ProfileName({required this.profile});
  final Profile? profile;

  @override
  Widget build(BuildContext context) => Text(profile!.displayName);
}

class OverflowPage extends StatelessWidget {
  const OverflowPage({super.key});

  @override
  Widget build(BuildContext context) => _BrokenPage(
    title: 'Overflow',
    body: Padding(
      padding: const EdgeInsets.all(16),
      // The Text is not wrapped in Expanded, so it asks for its full width.
      child: Row(
        children: [
          const Icon(Icons.account_balance),
          const SizedBox(width: 8),
          const Text('Transfer to Mohammed Abdulrahman Al-Senussi, Savings account 0020100120361'),
          FilledButton(onPressed: () {}, child: const Text('Send')),
        ],
      ),
    ),
  );
}

class UnboundedHeightPage extends StatelessWidget {
  const UnboundedHeightPage({super.key});

  @override
  Widget build(BuildContext context) => _BrokenPage(
    title: 'Unbounded height',
    // A ListView directly inside a Column, without Expanded.
    body: Column(
      children: [
        const ListTile(title: Text('Recent transfers')),
        ListView(children: [for (var i = 1; i <= 5; i++) ListTile(title: Text('Transfer #$i'))]),
      ],
    ),
  );
}

class UnboundedWidthFieldPage extends StatelessWidget {
  const UnboundedWidthFieldPage({super.key});

  @override
  Widget build(BuildContext context) => const _BrokenPage(
    title: 'Unbounded width',
    // A TextField directly inside a Row, without Expanded.
    body: Padding(
      padding: EdgeInsets.all(16),
      child: Row(children: [Text('Amount'), SizedBox(width: 8), TextField()]),
    ),
  );
}

class WrongParentDataPage extends StatelessWidget {
  const WrongParentDataPage({super.key});

  @override
  Widget build(BuildContext context) => const _BrokenPage(
    title: 'Wrong parent data',
    // Expanded only works inside a Row, Column or Flex.
    body: Stack(children: [Expanded(child: ColoredBox(color: Colors.teal))]),
  );
}

class BrokenImagePage extends StatelessWidget {
  const BrokenImagePage({super.key});

  @override
  Widget build(BuildContext context) => _BrokenPage(
    title: 'Broken image',
    // Nothing listens on port 9, and there is no errorBuilder.
    body: Center(child: Image.network('http://127.0.0.1:9/avatars/7.png', width: 96, height: 96)),
  );
}

class RepeatingErrorPage extends StatefulWidget {
  const RepeatingErrorPage({super.key});

  @override
  State<RepeatingErrorPage> createState() => _RepeatingErrorPageState();
}

/// Rebuilds a broken price ticker on every frame, the way an animated widget
/// with a bug floods the console.
class _RepeatingErrorPageState extends State<RepeatingErrorPage> with SingleTickerProviderStateMixin {
  late final AnimationController _ticker = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..repeat();

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _BrokenPage(
    title: 'Repeating error',
    // A new widget each frame (not const), so the broken build really reruns.
    body: AnimatedBuilder(animation: _ticker, builder: (_, _) => _PriceTicker(tick: _ticker.value)),
  );
}

class _PriceTicker extends StatelessWidget {
  const _PriceTicker({required this.tick});

  final double tick;

  @override
  Widget build(BuildContext context) => throw StateError('Price feed not loaded');
}

class LateSetStatePage extends StatefulWidget {
  const LateSetStatePage({super.key, this.delay = const Duration(milliseconds: 600)});

  /// When the "response" arrives; the caller closes the page before that.
  final Duration delay;

  @override
  State<LateSetStatePage> createState() => _LateSetStatePageState();
}

/// Starts a fake request and calls setState when it "returns", without
/// checking `mounted` and without cancelling the timer in dispose().
class _LateSetStatePageState extends State<LateSetStatePage> {
  String _balance = 'Loading…';

  @override
  void initState() {
    super.initState();
    Timer(widget.delay, () => setState(() => _balance = '1,250.500 LYD'));
  }

  @override
  Widget build(BuildContext context) => _BrokenPage(title: 'Late setState', body: Center(child: Text(_balance)));
}
