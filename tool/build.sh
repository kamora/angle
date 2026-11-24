#!/bin/bash
# Builds Google's ANGLE at the pinned commit into lib/native/<platform>/<architecture>/libGLESv2.dylib: release, Metal
# backend only, for arm64 and x64. ANGLE's libGLESv2 holds EGL too (as EGL_<name>), so libEGL, which only forwards to
# it, is not built.
#
# Everything it downloads or caches stays in .build/ (git-ignored): depot_tools, the ANGLE checkout, its caches and
# the build output. Deleting .build/ removes all of it. Nothing is installed system-wide, and depot_tools neither
# updates itself nor reports metrics.
#
# Usage: tool/build.sh macos

set -euo pipefail

# ANGLE's chromium/8180 branch.
commit=a35430f259e8e277253c99cfcb5a0bf9226cdfe5
platform=${1:?usage: tool/build.sh macos}
root=$(cd "$(dirname "$0")/.." && pwd)
build=$root/.build

if [[ $platform != macos ]]; then
	echo "Only macos is supported for now." >&2
	exit 1
fi

export PATH=$build/depot_tools:$PATH
export DEPOT_TOOLS_UPDATE=0
export DEPOT_TOOLS_METRICS=0
export DEPOT_TOOLS_REPORT_BUILD=0
export VPYTHON_VIRTUALENV_ROOT=$build/cache/vpython
export CIPD_CACHE_DIR=$build/cache/cipd
export XDG_CACHE_HOME=$build/cache
unset GIT_CACHE_PATH

# Checkouts keep their LF line endings whatever the user's git config says: with core.autocrlf, depot_tools' shell
# scripts would end their lines in CR and fail to run.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=core.autocrlf
export GIT_CONFIG_VALUE_0=false

mkdir -p "$build"

if [[ ! -d $build/depot_tools ]]; then
	git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git "$build/depot_tools"
fi

# Its own Python and tools, which a self-update would fetch (updates are off); into depot_tools itself.
"$build/depot_tools/ensure_bootstrap"

# The checkout: ANGLE at the commit, then its dependencies without history, leaving out what only serves ANGLE's
# tests, its Vulkan backend or Chromium's tooling.
mkdir -p "$build/angle"
cd "$build/angle"

if [[ $(git rev-parse HEAD 2>/dev/null || true) != "$commit" ]]; then
	git init -q
	git fetch -q --depth 1 https://chromium.googlesource.com/angle/angle "$commit"
	git checkout -q FETCH_HEAD
fi

cat > .gclient <<EOF
solutions = [{
	'name': '.',
	'url': 'https://chromium.googlesource.com/angle/angle.git@$commit',
	'deps_file': 'DEPS',
	'managed': False,
	'custom_vars': {'checkout_angle_dawn_deps': False, 'checkout_angle_mesa': False},
	'custom_deps': {
		'third_party/catapult': None,
		'third_party/perfetto': None,
		'third_party/VK-GL-CTS/src': None,
		'third_party/SwiftShader': None,
		'third_party/lunarg-vulkantools/src': None,
		'third_party/vulkan-validation-layers/src': None,
		'third_party/vulkan-tools/src': None,
		'third_party/vulkan-loader/src': None,
		'third_party/OpenCL-Docs/src': None,
		'third_party/cherry': None,
		'third_party/Python-Markdown': None,
		'third_party/rapidjson/src': None,
		'tools/perf': None,
		'tools/memory': None,
		'tools/valgrind': None,
		'tools/md_browser': None,
		'tools/skia_goldctl/mac_amd64': None,
		'tools/skia_goldctl/mac_arm64': None,
	},
}]
EOF

gclient sync --no-history --shallow --nohooks -j 8
gclient runhooks

# Room in the library's header for a longer install name: Flutter renames it to the app's (or flutter test's) path
# when it bundles it, and install_name_tool cannot grow a header without the padding. gn has no argument for Apple
# linker flags, so the checkout's dynamic-library flags get it, once.
grep -q headerpad_max_install_names build/config/mac/BUILD.gn ||
	sed -i '' 's|ldflags = \[ "-Wl,-ObjC" \]|ldflags = [ "-Wl,-ObjC", "-Wl,-headerpad_max_install_names" ]|' build/config/mac/BUILD.gn
grep -q headerpad_max_install_names build/config/mac/BUILD.gn

# Release libraries with the Metal backend only; no tests, samples or debug symbols. gn refuses tabs in its arguments,
# so they are one line of spaces.
args=(
	is_debug=false
	use_siso=false
	use_remoteexec=false
	symbol_level=0
	angle_enable_metal=true
	angle_enable_gl=false
	angle_enable_vulkan=false
	angle_enable_swiftshader=false
	angle_enable_null=false
	angle_enable_perfetto=false
	angle_build_tests=false
	angle_has_rapidjson=false
	build_angle_deqp_tests=false
)

for cpu in arm64 x64; do
	gn gen "out/$cpu" --args="${args[*]} target_cpu=\"$cpu\""
	autoninja -C "out/$cpu" libGLESv2
done

out=$root/lib/native/$platform
rm -rf "$out"

# One library per architecture: a build hook hands each target its own. Named through @rpath as an app bundle loads
# it (gn names it ./libGLESv2.dylib), and signed ad hoc again after the name changes; the app signs it with its own
# identity when it embeds it.
for cpu in arm64 x64; do
	mkdir -p "$out/$cpu"
	cp "out/$cpu/libGLESv2.dylib" "$out/$cpu/"
	install_name_tool -id @rpath/libGLESv2.dylib "$out/$cpu/libGLESv2.dylib"
	codesign --force --sign - "$out/$cpu/libGLESv2.dylib"
done

# The notices of what the library holds: ANGLE and the third-party code gn links into libGLESv2 (gn desc out/arm64
# //:libGLESv2 deps --all).
notices=(
	"ANGLE|.|LICENSE"
	"Abseil|third_party/abseil-cpp|LICENSE"
	"astc-encoder|third_party/astc-encoder/src|LICENSE.TXT"
	"LLVM libc++|third_party/libc++/src|LICENSE.TXT"
	"LLVM libc++abi|third_party/libc++abi/src|LICENSE.TXT"
	"LLVM libc|third_party/llvm-libc/src|LICENSE.TXT"
	"Vulkan-Headers|third_party/vulkan-headers/src|LICENSE.md"
	"zlib|third_party/zlib|LICENSE"
)

{
	echo "# Third-party notices"
	echo
	echo "The libraries in lib/native/ are Google's ANGLE, built by tool/build.sh with the third-party code it links,"
	echo "from ANGLE commit \`$commit\`. Their licenses follow."

	for entry in "${notices[@]}"; do
		IFS='|' read -r name path file <<< "$entry"
		echo
		echo "## $name"
		echo
		echo '```'
		tr -d '\r' < "$path/$file"
		echo '```'
	done
} > "$root/THIRD_PARTY_NOTICES.md"

echo "Built ANGLE $commit into $out:"
ls -lR "$out"
