# ent_angle

[ANGLE](https://chromium.googlesource.com/angle/angle) is Google's implementation of OpenGL ES and EGL on top of
each platform's native graphics API. This package is our build of it, from a pinned commit, bundled into Flutter and
Dart apps by a build hook. It is not an official Google package.

| Platform | Backend | Status |
|---|---|---|
| macOS (arm64, x64) | Metal | Built and tested on an M1 |
| iOS, Windows | Metal, Direct3D 11 | Planned |
| Android, Linux | — | Not needed: they have OpenGL ES drivers of their own |

The build is ANGLE's `chromium/8180` branch at commit `a35430f259e8`: release `libGLESv2` with the Metal backend only,
about 6 MB per architecture. ANGLE's `libGLESv2` holds EGL too, so `libEGL` is not shipped.

## Use

```dart
import 'dart:ffi';

import 'package:ent_angle/ent_angle.dart';

final glClear = angle.lookupFunction<Void Function(Uint32), void Function(int)>('glClear');

// EGL is exported as EGL_<name>: EGL_GetDisplay for eglGetDisplay.
final eglGetError = angle.lookupFunction<Int32 Function(), int Function()>('EGL_GetError');
```

`angle` looks symbols up in the bundled library only. A Flutter app's process also holds the system's OpenGL and the
ANGLE inside Apple's WebKit, and a lookup across the process (`DynamicLibrary.process()`) can reach theirs.

To show what GL draws in a Flutter widget on macOS, render into an IOSurface-backed EGL pbuffer
(`EGL_ANGLE_iosurface_client_buffer`) shared with a `FlutterTexture`.

## Build

`tool/build.sh macos` fetches ANGLE at the pinned commit with `depot_tools` and builds the libraries into
`lib/native/`, with `THIRD_PARTY_NOTICES.md` generated from the checkout. Everything it downloads stays in `.build/`
(about 8 GB), which can be deleted afterwards. It needs Xcode with its Metal Toolchain
(`xcodebuild -downloadComponent MetalToolchain`).

The repository keeps the script, not the libraries: releases carry them, and a published package includes them.

## License

The package's own code is MIT, © 2026 KAMORA Ltd.; see `LICENSE`. The bundled libraries are ANGLE and the
third-party code it links, under their own licenses: see `THIRD_PARTY_NOTICES.md`.
