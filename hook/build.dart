// Bundles ANGLE's libGLESv2 for the target: lib/native/<os>/<architecture>/, which tool/build.sh writes and a
// published package carries.

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final code = input.config.code;

    // Other targets have no build yet; there, opening the library fails with an error naming the target.
    if (code.targetOS != OS.macOS) {
      return;
    }

    final architecture = switch (code.targetArchitecture) {
      Architecture.arm64 => 'arm64',
      Architecture.x64 => 'x64',
      final other => throw UnsupportedError('ent_angle: no macOS build for $other.'),
    };
    final file = input.packageRoot.resolve('lib/native/macos/$architecture/libGLESv2.dylib');
    output.assets.code.add(
      CodeAsset(package: input.packageName, name: 'libGLESv2', linkMode: DynamicLoadingBundled(), file: file),
    );
    output.dependencies.add(file);
  });
}
