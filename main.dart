import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pin_authentication.dart';

void main() => runApp(const FinTrustApp());

class FinTrustApp extends StatelessWidget {
  const FinTrustApp({super.key, this.initialScreen = '280:18'});
  final String initialScreen;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'FinTrust',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff3930b7)),
      useMaterial3: true,
    ),
    home: Prototype(initialScreen: initialScreen),
  );
}

/// Composes separately exported Figma sections with native interaction widgets.
/// Original full-screen reference renders are never bundled into the app.
class Prototype extends StatefulWidget {
  const Prototype({super.key, required this.initialScreen});
  final String initialScreen;
  @override
  State<Prototype> createState() => _PrototypeState();
}

class _PrototypeState extends State<Prototype> {
  Map<String, dynamic>? scenes;
  String? error;
  late String screen = widget.initialScreen;
  final history = <String>[];
  Timer? timer;
  final username = TextEditingController();
  final password = TextEditingController();
  bool hidePassword = true;
  bool showTargets = false;
  bool playTimers = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = jsonDecode(
        await rootBundle.loadString('assets/design.json'),
      ) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        scenes = result;
        if (!result.containsKey(screen)) screen = '280:18';
      });
      schedule();
    } catch (e) {
      if (mounted) {
        setState(() => error = 'Unable to load the local design: $e');
      }
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    username.dispose();
    password.dispose();
    super.dispose();
  }

  void schedule() {
    timer?.cancel();
    if (!playTimers || pinDestination(screen) != null) return;
    final transitions = scenes?[screen]['timers'] as List? ?? [];
    for (final t in transitions) {
      if (!scenes!.containsKey(t['target'])) continue;
      final seconds = (t['event']['transitionTimeout'] as num? ?? 0.8)
          .toDouble();
      timer = Timer(
        Duration(milliseconds: (seconds * 1000).round().clamp(100, 60000)),
        () => go(t['target'], timed: true),
      );
      break;
    }
  }

  void go(String target, {bool timed = false}) {
    if (target == screen) return;
    if (scenes?.containsKey(target) != true) {
      message('This destination is not a screen in the local prototype.');
      return;
    }
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      if (!timed) history.add(screen);
      screen = target;
    });
    schedule();
  }

  void back() {
    if (history.isEmpty) {
      if (screen != '280:18') go('280:18');
      return;
    }
    timer?.cancel();
    setState(() => screen = history.removeLast());
    schedule();
  }

  void message(String text) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void followLink(Map<String, dynamic> link) {
    if (link['navigation'] == 'BACK' || link['navigation'] == 'CLOSE_OVERLAY') {
      back();
      return;
    }
    final target = link['target'];
    if (target is String && scenes!.containsKey(target)) {
      go(target);
      return;
    }
    message('This component interaction has no exported screen destination.');
  }

  void login() {
    if (username.text.trim().isEmpty || password.text.isEmpty) {
      message('Enter a username and password to explore the demo.');
      return;
    }
    // Demo only: no credentials are stored or transmitted.
    password.clear();
    go('269:1090');
  }

  Future<void> picker() async {
    timer?.cancel();
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .8,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Prototype screens',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final entry in scenes!.entries)
                      ListTile(
                        title: Text(entry.value['name']),
                        subtitle: Text(screenTitle(entry.value)),
                        selected: entry.key == screen,
                        leading: const Icon(Icons.phone_android),
                        onTap: () => Navigator.pop(context, entry.key),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (choice != null) {
      go(choice);
    } else {
      schedule();
    }
  }

  String screenTitle(dynamic scene) {
    final texts = (scene['texts'] as List)
        .map((t) => t['text'] as String)
        .where((t) => t.trim().isNotEmpty && t != '9:41')
        .take(3);
    return texts.join(' · ');
  }

  Widget positioned(List box, Widget child) => Positioned(
    left: (box[0] as num).toDouble(),
    top: (box[1] as num).toDouble(),
    width: (box[2] as num).toDouble(),
    height: (box[3] as num).toDouble(),
    child: child,
  );

  Widget hotspot(Map<String, dynamic> link) {
    final label = link['label'] as String;
    return positioned(
      link['box'],
      Semantics(
        button: true,
        label: label,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: ValueKey('link-${link['id']}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => followLink(link),
            onPanEnd: link['event']['interactionType'] == 'DRAG'
                ? (_) => followLink(link)
                : null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: showTargets
                    ? Colors.amber.withValues(alpha: .18)
                    : Colors.transparent,
                border: showTargets ? Border.all(color: Colors.amber) : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget action(List box, String label, VoidCallback callback) => positioned(
    box,
    Semantics(
      button: true,
      label: label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: callback,
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );

  Widget field({
    required double top,
    required TextEditingController controller,
    required String hint,
    bool secret = false,
  }) => positioned(
    [68, top, secret ? 270 : 304, 48],
    TextField(
      key: ValueKey(secret ? 'password' : 'username'),
      controller: controller,
      obscureText: secret && hidePassword,
      enableSuggestions: !secret,
      autocorrect: false,
      keyboardType: secret
          ? TextInputType.visiblePassword
          : TextInputType.emailAddress,
      textInputAction: secret ? TextInputAction.done : TextInputAction.next,
      onSubmitted: secret ? (_) => login() : null,
      style: const TextStyle(fontSize: 16, color: Color(0xff34364c)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xff9ca3af)),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
      ),
    ),
  );

  Widget design() {
    final pinTarget = pinDestination(screen);
    // Replace all prefilled/loading PIN frames with a fresh native entry state.
    final scene = scenes![pinTarget == null ? screen : '404:154'];
    final isLogin = screen == '280:18';
    final layers = [...scene['layers'] as List];
    final links = [...scene['links'] as List];
    final texts = [...scene['texts'] as List];
    // The alternate search frame omits its tab bar in the Figma export.
    // Keep the same Search-selected artwork, semantics and actions in both states.
    if (screen == '299:951') {
      final searchScene = scenes!['269:1535'];
      layers.addAll(
        (searchScene['layers'] as List).where(
          (layer) => layer['id'] == '417:142',
        ),
      );
      links.addAll(
        (searchScene['links'] as List).where(
          (link) => (link['box'][1] as num) >= 856,
        ),
      );
      texts.addAll(
        (searchScene['texts'] as List).where(
          (text) => (text['box'][1] as num) >= 856,
        ),
      );
    }
    // The two placeholder text nodes are replaced with real Flutter text fields.
    const nativeLoginNodes = {'282:173', '282:176'};
    return SizedBox(
      key: ValueKey('prototype-screen-$screen'),
      width: 412,
      height: 917,
      child: ClipRect(
        child: Stack(
          children: [
            for (final layer in layers)
              if (!(isLogin && nativeLoginNodes.contains(layer['id'])))
                positioned(
                  layer['box'],
                  Image.asset(
                    layer['asset'],
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                  ),
                ),
            // Text remains available to assistive technology even for outlined Figma glyphs.
            for (final text in texts)
              if (!(pinTarget != null &&
                      RegExp(r'^\d$').hasMatch(text['text'])) &&
                  (text['box'][2] as num) > 0 &&
                  (text['box'][3] as num) > 0)
                positioned(
                  text['box'],
                  IgnorePointer(
                    child: Semantics(
                      label: text['text'],
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
            for (final link in links)
              if (!isLogin &&
                  pinTarget == null &&
                  link['target'] != '4294967295:4294967295' &&
                  (link['box'][2] as num) > 0 &&
                  (link['box'][3] as num) > 0)
                hotspot(Map<String, dynamic>.from(link)),
            if (pinTarget != null)
              Positioned.fill(
                child: PinAuthentication(
                  key: ValueKey('pin-$screen'),
                  onVerified: () => go(pinTarget),
                ),
              ),
            if (isLogin) ...[
              field(
                top: 302,
                controller: username,
                hint: 'Enter your username',
              ),
              field(
                top: 396,
                controller: password,
                hint: 'Enter password',
                secret: true,
              ),
              action(
                [340, 396, 48, 48],
                'Toggle password visibility',
                () => setState(() => hidePassword = !hidePassword),
              ),
              action([24, 716, 364, 48], 'Log In', login),
              action(
                [24, 782, 364, 48],
                'Face ID demo',
                () => message(
                  'Face ID requires device authentication. Use the demo login.',
                ),
              ),
              action(
                [240, 450, 148, 36],
                'Forgot password',
                () => message(
                  'Password recovery is not connected in this local demo.',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: history.isEmpty,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) back();
    },
    child: Scaffold(
      backgroundColor: const Color(0xff101126),
      appBar: AppBar(
        toolbarHeight: 44,
        backgroundColor: const Color(0xff101126),
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('FinTrust · Demo', style: TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            tooltip: 'Screens',
            onPressed: scenes == null ? null : picker,
            icon: const Icon(Icons.grid_view),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'targets') {
                setState(() => showTargets = !showTargets);
              }
              if (value == 'timers') {
                setState(() => playTimers = !playTimers);
                schedule();
              }
              if (value == 'restart') {
                history.clear();
                go('280:18');
              }
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'targets',
                checked: showTargets,
                child: const Text('Highlight prototype links'),
              ),
              CheckedPopupMenuItem(
                value: 'timers',
                checked: playTimers,
                child: const Text('Play timed transitions'),
              ),
              const PopupMenuItem(
                value: 'restart',
                child: Text('Restart demo'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: error != null
            ? Center(
                child: Text(
                  error!,
                  style: const TextStyle(color: Colors.white),
                ),
              )
            : scenes == null
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) => Center(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: RepaintBoundary(
                      key: const ValueKey('prototype-canvas'),
                      child: design(),
                    ),
                  ),
                ),
              ),
      ),
    ),
  );
}
