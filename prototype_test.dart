import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ilham_app/main.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('Every imported section and screen navigation target exists', () {
    final scenes =
        jsonDecode(File('assets/design.json').readAsStringSync()) as Map;
    expect(scenes.length, 84);
    for (final scene in scenes.values) {
      for (final layer in scene['layers']) {
        expect(File(layer['asset']).lengthSync(), greaterThan(0));
        expect(layer['box'][2], greaterThan(0));
        expect(layer['box'][3], greaterThan(0));
      }
      for (final link in scene['links']) {
        // Figma's sentinel represents an unset destination, not a missing frame.
        if (link['target'] == '4294967295:4294967295') continue;
        expect(scenes.containsKey(link['target']), isTrue);
      }
    }
  });

  testWidgets(
    'Login validates input, opens home, navigates overview and back',
    (tester) async {
      tester.view.physicalSize = const Size(412, 961);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const FinTrustApp());
      await settle(tester);
      await tester.tapAt(const Offset(206, 784));
      await tester.pump();
      expect(
        find.text('Enter a username and password to explore the demo.'),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const ValueKey('username')), 'demo');
      await tester.enterText(find.byKey(const ValueKey('password')), 'demo');
      tester.testTextInput.hide();
      await tester.tapAt(const Offset(206, 784));
      await settle(tester);
      expect(find.byKey(const ValueKey('link-290:415')), findsOneWidget);
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('prototype-canvas')),
        );
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('design').create(recursive: true);
        await File('design/flutter-home.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });

      await tester.tap(find.byKey(const ValueKey('link-290:415')));
      await settle(tester);
      expect(find.byKey(const ValueKey('username')), findsNothing);
      await tester.tap(find.byTooltip('Back'));
      await settle(tester);
      expect(find.byKey(const ValueKey('link-290:415')), findsOneWidget);
      // Exercise the system back route used by Android, as well as the toolbar.
      await tester.tap(find.byKey(const ValueKey('link-290:415')));
      await settle(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byKey(const ValueKey('link-290:415')), findsOneWidget);
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('link-290:415')));
      await settle(tester);
      await tester.tap(find.byTooltip('Back'));
      await settle(tester);
      expect(find.byKey(const ValueKey('link-290:415')), findsOneWidget);
      tester.view.physicalSize = const Size(320, 640);
      await tester.pumpAndSettle();
      // Search's alternate suggestion/filter state must retain working tabs.
      await tester.tap(find.byKey(const ValueKey('link-290:419')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('link-269:1566')));
      await settle(tester);
      expect(
        find.byKey(const ValueKey('prototype-screen-299:951')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('link-417:143')), findsOneWidget);
      expect(find.byKey(const ValueKey('link-417:147')), findsOneWidget);
      expect(find.byKey(const ValueKey('link-417:155')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName ==
                  'assets/local/0c40da89152e32ca6b80.png',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('link-299:976')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('link-269:1566')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('link-417:147')));
      await settle(tester);
      expect(
        find.byKey(const ValueKey('prototype-screen-269:1631')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Back'));
      await settle(tester);
      expect(
        find.byKey(const ValueKey('prototype-screen-299:951')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('link-417:143')));
      await settle(tester);
      expect(
        find.byKey(const ValueKey('prototype-screen-269:1090')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Screens'));
      await settle(tester);
      expect(find.text('Prototype screens'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
