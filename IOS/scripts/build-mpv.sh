#!/usr/bin/env bash
# Builds IOS/Packages/ZelefinMPV/ZelefinMPV.xcframework from an MPVKit build (GPL-3.0) that adds mpv's
# vo_avfoundation output, so video lands in an AVSampleBufferDisplayLayer (Picture in Picture).
#
# The fork ships one static library with FFmpeg inside. AetherEngine links its own FFmpeg, so the static
# library is wrapped in a dynamic framework that exports only mpv_* symbols: mpv's FFmpeg stays private
# and Aether's calls can never bind to it.
#
#   IOS/scripts/build-mpv.sh
set -euo pipefail

FORK_REPO="streamyfin/MPVKit"
FORK_TAG="0.41.0-av5"
FORK_SHA256="80a79fbb34b1a3ae84744fe7bb9d365d2a006a5f617460933b7ce777251d3618"

IOS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$IOS_DIR/Packages/ZelefinMPV/ZelefinMPV.xcframework"
WORK="${TMPDIR:-/tmp}/zelefin-mpv-build"
mkdir -p "$WORK"

zip="$WORK/MPVKit-$FORK_TAG.xcframework.zip"
if [[ ! -f "$zip" ]]; then
  curl -fL --retry 3 -o "$zip" "https://github.com/$FORK_REPO/releases/download/$FORK_TAG/MPVKit.xcframework.zip"
fi
echo "$FORK_SHA256  $zip" | shasum -a 256 -c - >/dev/null || { echo "Checksum mismatch for $zip" >&2; exit 1; }

src="$WORK/src"
rm -rf "$src" && mkdir -p "$src" && unzip -q "$zip" -d "$src"
SRC="$src/MPVKit.xcframework"

build="$WORK/build"
rm -rf "$build" && mkdir -p "$build"
nm -gU "$SRC/ios-arm64/MPVKit.framework/MPVKit" 2>/dev/null | awk '$3 ~ /^_mpv_/ {print $3}' | sort -u > "$build/mpv.exp"

# Public frameworks only: -dead_strip_dylibs drops the ones nothing references.
FRAMEWORKS=(AudioToolbox AVFoundation CoreAudio CoreFoundation CoreMedia CoreVideo Metal QuartzCore VideoToolbox
  UIKit Security CoreText CoreGraphics IOSurface Foundation AVKit MediaPlayer CoreImage OpenGLES GLKit Accelerate ImageIO)
LIBS=(-lbz2 -lc++ -liconv -lxml2 -lz -lresolv -lexpat -lsqlite3)

link_slice() {
  local slice=$1 sdk=$2 target=$3 out=$4
  local sysroot fw=() keep=()
  sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
  for f in "${FRAMEWORKS[@]}"; do
    [[ -d "$sysroot/System/Library/Frameworks/$f.framework" ]] && fw+=(-framework "$f")
  done
  # -u pulls in exactly the mpv objects and what they need; -force_load would drag in the duplicate
  # copies of glslang and friends the archive carries.
  while read -r sym; do keep+=("-Wl,-u,$sym"); done < "$build/mpv.exp"
  xcrun --sdk "$sdk" clang -dynamiclib -target "$target" -isysroot "$sysroot" -o "$out" \
    "${keep[@]}" "$SRC/$slice/MPVKit.framework/MPVKit" \
    -Wl,-exported_symbols_list,"$build/mpv.exp" -install_name @rpath/ZelefinMPV.framework/ZelefinMPV \
    "${fw[@]}" "${LIBS[@]}" -Wl,-dead_strip -Wl,-dead_strip_dylibs 2>&1 | grep -v "was built for newer" || true
}

make_framework() {
  local slice=$1 fw="$2/ZelefinMPV.framework"
  mkdir -p "$fw/Headers/mpv" "$fw/Modules"
  cp "$SRC/$slice/MPVKit.framework/Headers/mpv/"*.h "$fw/Headers/mpv/"
  printf '#include <ZelefinMPV/mpv/client.h>\n#include <ZelefinMPV/mpv/render.h>\n' > "$fw/Headers/ZelefinMPV.h"
  printf 'framework module ZelefinMPV {\n    umbrella header "ZelefinMPV.h"\n    export *\n}\n' > "$fw/Modules/module.modulemap"
  /usr/libexec/PlistBuddy \
    -c "Add :CFBundleIdentifier string app.zelefin.ZelefinMPV" -c "Add :CFBundleName string ZelefinMPV" \
    -c "Add :CFBundleExecutable string ZelefinMPV" -c "Add :CFBundlePackageType string FMWK" \
    -c "Add :CFBundleShortVersionString string ${FORK_TAG%%-*}" -c "Add :CFBundleVersion string 1" \
    -c "Add :MinimumOSVersion string 18.0" "$fw/Info.plist" >/dev/null
}

# dsymutil reads DWARF from the archive's objects via the debug map, so it has to run before $src goes
# away. Stripping the debug map afterwards keeps build paths out of the app; the UUID stays the same.
make_dsym() {
  local fw=$1
  xcrun dsymutil "$fw/ZelefinMPV" -o "$fw.dSYM"
  xcrun strip -S "$fw/ZelefinMPV"
}

make_framework ios-arm64 "$build/device"
link_slice ios-arm64 iphoneos arm64-apple-ios18.0 "$build/device/ZelefinMPV.framework/ZelefinMPV"
make_dsym "$build/device/ZelefinMPV.framework"

make_framework ios-arm64_x86_64-simulator "$build/sim"
link_slice ios-arm64_x86_64-simulator iphonesimulator arm64-apple-ios18.0-simulator "$build/sim/arm64"
link_slice ios-arm64_x86_64-simulator iphonesimulator x86_64-apple-ios18.0-simulator "$build/sim/x86_64"
lipo -create "$build/sim/arm64" "$build/sim/x86_64" -output "$build/sim/ZelefinMPV.framework/ZelefinMPV"
make_dsym "$build/sim/ZelefinMPV.framework"

if nm -gU "$build/device/ZelefinMPV.framework/ZelefinMPV" | awk '{print $3}' | grep -qv '^_mpv_'; then
  echo "ZelefinMPV exports something other than mpv_*; FFmpeg would leak into the app." >&2
  exit 1
fi

rm -rf "$OUT"
xcodebuild -create-xcframework \
  -framework "$build/device/ZelefinMPV.framework" -debug-symbols "$build/device/ZelefinMPV.framework.dSYM" \
  -framework "$build/sim/ZelefinMPV.framework" -debug-symbols "$build/sim/ZelefinMPV.framework.dSYM" \
  -output "$OUT" >/dev/null
echo "Built $OUT"
