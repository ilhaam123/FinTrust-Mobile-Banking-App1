import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The three authored PIN flows lead to different OTP/payment branches.
String? pinDestination(String screen) {
  const transfers = {
    '404:154',
    '404:226',
    '404:268',
    '404:310',
    '404:352',
    '404:398',
  };
  const savedPayee = {
    '445:193',
    '445:871',
    '445:834',
    '445:797',
    '445:721',
    '445:758',
  };
  const qrPayment = {
    '445:932',
    '445:1610',
    '445:1573',
    '445:1536',
    '445:1460',
    '445:1497',
  };
  if (transfers.contains(screen)) return '412:30';
  if (savedPayee.contains(screen)) return '445:1735';
  if (qrPayment.contains(screen)) return '445:1805';
  return null;
}

/// Local demo validation only; this does not authenticate a banking account.
class PinAuthentication extends StatefulWidget {
  const PinAuthentication({super.key, required this.onVerified});
  final VoidCallback onVerified;
  static const demoPin = '1210';

  @override
  State<PinAuthentication> createState() => _PinAuthenticationState();
}

class _PinAuthenticationState extends State<PinAuthentication> {
  String digits = '';
  String? error;
  bool completed = false;

  void enter(String digit) {
    if (completed || digits.length == 4) return;
    setState(() {
      error = null;
      digits += digit;
    });
    if (digits.length != 4) return;
    if (digits == PinAuthentication.demoPin) {
      completed = true;
      widget.onVerified();
    } else {
      setState(() {
        digits = '';
        error = 'Incorrect PIN. Try again.';
      });
    }
  }

  void erase() {
    if (completed) return;
    setState(() {
      error = null;
      if (digits.isNotEmpty) digits = digits.substring(0, digits.length - 1);
    });
  }

  KeyEventResult handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.delete) {
      erase();
      return KeyEventResult.handled;
    }
    final numpadDigits = {
      LogicalKeyboardKey.numpad0: '0',
      LogicalKeyboardKey.numpad1: '1',
      LogicalKeyboardKey.numpad2: '2',
      LogicalKeyboardKey.numpad3: '3',
      LogicalKeyboardKey.numpad4: '4',
      LogicalKeyboardKey.numpad5: '5',
      LogicalKeyboardKey.numpad6: '6',
      LogicalKeyboardKey.numpad7: '7',
      LogicalKeyboardKey.numpad8: '8',
      LogicalKeyboardKey.numpad9: '9',
    };
    final value =
        numpadDigits[event.logicalKey] ??
        event.character ??
        event.logicalKey.keyLabel;
    if (RegExp(r'^\d$').hasMatch(value)) {
      enter(value);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget keyButton(String digit, double left, double top) => Positioned(
    left: left,
    top: top,
    width: 70,
    height: 70,
    child: TextButton(
      key: ValueKey('pin-digit-$digit'),
      onPressed: () => enter(digit),
      style: TextButton.styleFrom(
        shape: const CircleBorder(),
        padding: EdgeInsets.zero,
      ),
      // The original Figma button artwork remains underneath this native button.
      child: Semantics(label: digit, child: const SizedBox.expand()),
    ),
  );

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: handleKey,
    child: Stack(
      children: [
        Positioned(
          left: 134,
          top: 380,
          width: 144,
          height: 26,
          child: Semantics(
            key: const ValueKey('pin-progress'),
            label: '${digits.length} of 4 PIN digits entered',
            liveRegion: true,
            child: Stack(
              children: [
                for (var i = 0; i < digits.length; i++)
                  Positioned(
                    left: [7.0, 46.0, 86.0, 125.0][i],
                    top: 7,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (error != null)
          Positioned(
            left: 24,
            top: 416,
            width: 364,
            height: 30,
            child: Semantics(
              liveRegion: true,
              child: Text(
                error!,
                key: const ValueKey('pin-error'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xffffd4d4), fontSize: 16),
              ),
            ),
          ),
        for (var digit = 1; digit <= 9; digit++)
          keyButton(
            '$digit',
            [76.0, 171.0, 265.0][(digit - 1) % 3],
            [459.0, 559.0, 657.0][(digit - 1) ~/ 3],
          ),
        keyButton('0', 171, 756),
        Positioned(
          left: 273,
          top: 756,
          width: 70,
          height: 70,
          child: TextButton(
            key: const ValueKey('pin-backspace'),
            onPressed: erase,
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            child: Semantics(
              label: 'Delete last PIN digit',
              child: SizedBox.expand(),
            ),
          ),
        ),
        const Positioned(
          left: 24,
          top: 850,
          width: 364,
          height: 24,
          child: Text(
            'Demo PIN: 1210',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.white70),
          ),
        ),
      ],
    ),
  );
}
