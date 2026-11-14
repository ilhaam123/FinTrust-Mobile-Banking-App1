import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ilham_app/main.dart';
import 'package:ilham_app/pin_authentication.dart';

Future<void> press(WidgetTester tester, String digit) async {
  await tester.tap(find.byKey(ValueKey('pin-digit-$digit')));
  await tester.pump();
}

void main() {
  test('Every authored PIN state maps to an existing OTP branch', () {
    final scenes =
        jsonDecode(File('assets/design.json').readAsStringSync()) as Map;
    final pins = scenes.entries.where(
      (e) => (e.value['texts'] as List).any(
        (t) => t['text'] == 'PIN Authentication',
      ),
    );
    expect(pins.length, 18);
    for (final entry in pins) {
      expect(pinDestination(entry.key), isNotNull);
      expect(scenes.containsKey(pinDestination(entry.key)), isTrue);
    }
    expect(pinDestination('269:1090'), isNull);
  });

  testWidgets('All digits, deletion, invalid PIN and physical keyboard work', (
    tester,
  ) async {
    var verified = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 412,
            height: 917,
            child: PinAuthentication(onVerified: () => verified++),
          ),
        ),
      ),
    );
    tester.view.physicalSize = const Size(412, 917);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pump();
    for (final digit in '0123456789'.split('')) {
      await press(tester, digit);
      final status = tester.widget<Semantics>(
        find.byKey(const ValueKey('pin-progress')),
      );
      expect(status.properties.label, '1 of 4 PIN digits entered');
      await tester.tap(find.byKey(const ValueKey('pin-backspace')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('pin-backspace')));
    for (final digit in '9999'.split('')) {
      await press(tester, digit);
    }
    expect(verified, 0);
    expect(find.text('Incorrect PIN. Try again.'), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(find.byKey(const ValueKey('pin-progress')))
          .properties
          .label,
      '0 of 4 PIN digits entered',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad9);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad2);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump(const Duration(seconds: 3));
    expect(verified, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad0);
    await tester.pump();
    expect(verified, 1);
    await press(tester, '0');
    expect(verified, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PIN entry advances each payment branch and resets on back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 961);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Include a formerly auto-advancing, prefilled frame to prevent bypasses.
    for (final screen in ['404:154', '445:193', '445:932', '404:352']) {
      await tester.pumpWidget(
        FinTrustApp(key: ValueKey(screen), initialScreen: screen),
      );
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
        if (find.byType(PinAuthentication).evaluate().isNotEmpty) break;
      }
      expect(find.byType(PinAuthentication), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(PinAuthentication), findsOneWidget);
      for (final digit in '1210'.split('')) {
        await press(tester, digit);
      }
      await tester.pump();
      expect(
        find.byKey(ValueKey('prototype-screen-${pinDestination(screen)}')),
        findsOneWidget,
      );
      expect(find.byType(PinAuthentication), findsNothing);
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      expect(find.byType(PinAuthentication), findsOneWidget);
      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('pin-progress')))
            .properties
            .label,
        '0 of 4 PIN digits entered',
      );
      expect(tester.takeException(), isNull);
    }
  });
}
