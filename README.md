# FinTrust Flutter prototype

Interactive Flutter adaptation of the local Figma export in `../Untitled.fig`.
The app includes all 84 full-size FinTrust frames from Page 3, including earlier
screen drafts and PIN/OTP states. The unrelated Page 1 and Page 2 studies are
not included.

## Windows and Android

The project includes native Windows, Android, Linux and web runners. Use Flutter
3.47.5 or a compatible newer stable SDK (Dart 3.13.4 or later).

### Windows setup

1. Install Flutter and add its `bin` folder to PATH.
2. Install **Visual Studio** with **Desktop development with C++**, including
   its Windows SDK. VS Code is the editor; Visual Studio supplies build tools.
3. Open this project folder in VS Code and install its recommended Dart/Flutter
   extensions. Run `flutter doctor -v` and resolve Windows toolchain errors.
4. Run `flutter pub get`, select **Flutter: Windows desktop**, and press **F5**.

The VS Code SDK hint is `~/Documents/flutter`, resolved under your user account.
If your SDK is elsewhere, change **Dart: Flutter SDK Path** to that location;
when the hint is invalid, the extension also searches FLUTTER_ROOT and PATH.

From PowerShell:

```powershell
flutter pub get
flutter run -d windows
# Or use the helper, which checks Flutter and reports failed commands:
.\scripts\run.ps1 -Platform windows
# Build a distributable Windows app:
.\scripts\run.ps1 -Platform windows -Build
```

The Windows executable is `build/windows/x64/runner/Release/ilham_app.exe`.
Copy the **entire Release folder**, including DLLs and `data`, to distribute it.
Windows builds must be made on Windows; Linux cannot produce this executable.

### Android setup (Windows or Linux)

1. Install Android Studio and its Android SDK. In SDK Manager install Android
   SDK Platform 36, Build-Tools, Platform-Tools, Command-line Tools and
   NDK 28.2.13676358. Install an emulator/system image if you need a virtual device.
2. Run `flutter doctor --android-licenses` and review/accept the required terms,
   then run `flutter doctor -v` to verify the Android toolchain.
3. Start an emulator, or connect an Android 7.0/API 24+ phone with USB debugging
   enabled and authorize the computer on the phone.
4. In VS Code use **Flutter: Select Device** to select that Android device,
   choose **Flutter: Android (select device)**, then press **F5**.

```sh
flutter pub get
flutter devices
flutter run -d YOUR_ANDROID_DEVICE_ID
flutter build apk --debug
```

On Windows the helper can also select a single connected Android device:

```powershell
.\scripts\run.ps1 -Platform android
.\scripts\run.ps1 -Platform android -DeviceId emulator-5554
.\scripts\run.ps1 -Platform android -Build
# If Flutter is not on PATH:
.\scripts\run.ps1 -Platform android -FlutterSdk C:\src\flutter
```

The installable demo APK is `build/app/outputs/flutter-apk/app-debug.apk`.
Install it with `adb install -r build/app/outputs/flutter-apk/app-debug.apk`.
It uses a debug signature; production store distribution needs your own
application ID, release signing, and connected banking implementation.

Do not copy `android/local.properties`, `.dart_tool`, `build`, or platform
`ephemeral` folders between operating systems. Flutter regenerates these local
paths when you run `flutter pub get` and `flutter run`/`flutter build`.

Official setup references:
[Windows](https://docs.flutter.dev/platform-integration/windows/setup) and
[Android](https://docs.flutter.dev/platform-integration/android/setup).

### Linux and browser

Select **Flutter: Linux desktop** or **Flutter: web browser** in VS Code, or run:

```sh
flutter run -d linux
flutter run -d web-server
```

On the original Linux machine, Flutter is at
`/home/rex/Documents/flutter/bin/flutter` if it is not on PATH.

### Explore the demo

Enter any nonempty username and password to open the demo home screen.
On PIN Authentication screens, use demo PIN **1210**. All ten keypad buttons,
backspace, and physical keyboard/numpad input work. Incorrect PINs reset the
entry with an error; successful entry continues to the matching OTP screen.
Returning to PIN authentication always starts with an empty entry.
No login credentials are stored or transmitted. Use the grid button to browse
all imported screens, the back arrow to retrace navigation, and the overflow
menu to restart, highlight tappable targets, or pause timed transitions.

## Implementation and scope

- `lib/main.dart`: Flutter scene composition, editable login fields, input
  validation, prototype links, navigation history, timed transitions and picker.
- `assets/design.json`: section geometry, text semantics, and prototype links.
- `assets/local/`: individually exported original Figma sections. The app
  composes these sections; it does not display full-screen reference images.
- `design/manifest.json`: mapping of Figma nodes to assets and navigation.
- `design/reference/`: local reference renders for visual checks, not app assets.
- `design/flutter-home.png`: home-screen capture produced by the widget test.

This is an interactive prototype, not a connected banking service. Outside the
login and PIN forms, text and form-entry states reproduce the authored Figma transitions;
they are not yet general-purpose editable banking forms. Face ID, camera/QR
scanning, live balances, real transfers, OTP delivery, and the AI assistant have
no backend integration. Layout scales the authored 412 × 917 canvas to fit the
window. Screen-level links and timers are supported; Figma smart-animation
interpolation and component hover variants are not reproduced. An unset Figma
eye-icon link is ignored so the valid eye-icon transition remains accessible.

## Verify

```sh
flutter analyze --no-pub
flutter test --no-pub
flutter build windows --release   # On Windows
flutter build apk --debug         # With the Android SDK installed
```

Tests check imported assets and navigation destinations, login validation,
home/overview/back navigation, Android system-back handling, desktop-sized
layouts, and the picker at a narrow viewport. PIN tests cover all digits, deletion, invalid entries, keyboard/numpad input,
and all three payment branches. Windows compilation and Android
device execution still need verification on machines with those toolchains.

To create a source ZIP for another computer, run `python tool/package_project.py`.
The ZIP includes app assets and all native runners, but excludes SDK-specific
paths, caches, build outputs, and the original decoded design. Run `flutter pub
get` after extracting it. The optional original Figma source/reference renders
remain in the original workspace; they are not needed to run the app.

## Reimport the local design

Requires Node 24 (with zstd support), `kiwi-schema` 0.5.0, Python 3, and
`rsvg-convert`. Install the decoder dependency with `npm install --prefix tool`,
then run:

```sh
node tool/decode.cjs ../Untitled.fig/canvas.fig design/document.json
python tool/import_design.py
```

The importer reads the original assets, resolves shared paint styles, preserves
outlined glyphs and geometry, and exports clipped sections and nested hit areas.
The decoded document and reference images stay outside the Flutter asset bundle.
