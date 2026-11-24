/// Google's ANGLE, bundled into the app by this package's build hook: OpenGL ES 3 and EGL, on Metal on macOS.
library;

import 'dart:ffi';

// Resolved through the asset id, so to exactly the library this package bundles.
@Native<Int32 Function()>(symbol: 'EGL_GetError', assetId: 'package:ent_angle/libGLESv2')
external int _error();

// dladdr's Dl_info: the file of the image an address is in, then its base, the nearest symbol and its address.
final class _Info extends Struct {
  external Pointer<Uint8> file;
  external Pointer<Void> base;
  external Pointer<Uint8> symbol;
  external Pointer<Void> address;
}

/// ANGLE's library, loaded on first use: the OpenGL ES functions under their own names (`glClear`), and EGL under
/// `EGL_` in place of `egl` (`EGL_GetDisplay` for `eglGetDisplay`), as ANGLE's libGLESv2 exports them.
///
/// Symbols are looked up in this library only: an app process can hold other GL implementations (the system's
/// OpenGL, an ANGLE inside another framework), and a lookup across the process could reach theirs. Throws an
/// [ArgumentError] where the package has no build for the target.
final DynamicLibrary angle = () {
  final process = DynamicLibrary.process();
  final dladdr = process
      .lookupFunction<Int32 Function(Pointer<Void>, Pointer<_Info>), int Function(Pointer<Void>, Pointer<_Info>)>(
        'dladdr',
      );
  final malloc = process.lookupFunction<Pointer<Void> Function(IntPtr), Pointer<Void> Function(int)>('malloc');
  final free = process.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('free');
  final info = malloc(sizeOf<_Info>()).cast<_Info>();

  try {
    if (dladdr(Native.addressOf<NativeFunction<Int32 Function()>>(_error).cast(), info) == 0) {
      throw StateError('ent_angle: the bundled library has no file.');
    }

    final name = info.ref.file;
    var length = 0;

    while (name[length] != 0) {
      length++;
    }

    return DynamicLibrary.open(String.fromCharCodes(name.asTypedList(length)));
  } finally {
    free(info.cast());
  }
}();
