// Loads the bundled library on the host, as an app would.

import 'dart:ffi';
import 'dart:io';

import 'package:wrangle/wrangle.dart';
import 'package:test/test.dart';

void main() {
  test('the bundled library is ours and exports EGL and OpenGL ES', () {
    final queryString = angle
        .lookupFunction<Pointer<Uint8> Function(Pointer<Void>, Int32), Pointer<Uint8> Function(Pointer<Void>, int)>(
          'EGL_QueryString',
        );

    // EGL_VERSION of no display: the client's version, which ANGLE tags with its commit.
    final text = queryString(nullptr, 0x3054);
    var length = 0;

    while (text[length] != 0) {
      length++;
    }

    expect(String.fromCharCodes(text.asTypedList(length)), contains('a35430f259e8'));
    expect(angle.providesSymbol('glDrawArrays'), isTrue);
    expect(angle.providesSymbol('eglGetDisplay'), isFalse);
  }, skip: !Platform.isMacOS);
}
