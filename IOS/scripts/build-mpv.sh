#!/usr/bin/env bash
# Builds IOS/Packages/ZelefinMPV/ZelefinMPV.xcframework from an MPVKit build (GPL-3.0) that adds mpv's
# vo_avfoundation output, so video lands in an AVSampleBufferDisplayLayer (Picture in Picture).
#
# The fork ships one static library with FFmpeg inside. AetherEngine links its own FFmpeg, so the static
# library is wrapped in a dynamic framework that exports only mpv_* symbols: mpv's FFmpeg stays private
# and Aether's calls can never bind to it.
#
# The fork has no Mac Catalyst build, so that slice comes from upstream MPVKit's static libraries
# (no vo_avfoundation; the app renders with gpu-next on MoltenVK there), linked the same way into a
# versioned framework, which Mac app bundles require.
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

# Upstream MPVKit $CATALYST_TAG, MPVKit-GPL's libraries, with the checksums its Package.swift pins.
CATALYST_TAG="1.0.0"
CATALYST_LIBS=(
  "Libmpv-GPL MPVKit/releases/download/1.0.0/Libmpv-GPL 45989efd473c9a2295a3d1d0da0bcd004d14f0eeea81bda671be89c78f3925ff"
  "Libavcodec-GPL MPVKit/releases/download/1.0.0/Libavcodec-GPL 8df07384ace5bd48520669db89203e51cc13ce99a6d0bef975a83a45e5ea5855"
  "Libavdevice-GPL MPVKit/releases/download/1.0.0/Libavdevice-GPL 14f3bfc950548eeb0d0686f9ddc2fb7ea120def036767c1490d2731df6e91f65"
  "Libavformat-GPL MPVKit/releases/download/1.0.0/Libavformat-GPL 90281cdac29184fb618dc8ab6e091faa05b471efbd0b9a1c1a67c235b6961483"
  "Libavfilter-GPL MPVKit/releases/download/1.0.0/Libavfilter-GPL f9789661088275acac3d84e545beb5def04407418b73283994b6863c4db1582e"
  "Libavutil-GPL MPVKit/releases/download/1.0.0/Libavutil-GPL 32849241cf71e949b4718dfdb1b69ece0f1ca9cb9d89b84a35051686b6bafbd0"
  "Libswresample-GPL MPVKit/releases/download/1.0.0/Libswresample-GPL f59191f210476e24a53a18a3b55158b82c5f685d19f2fb29582d95f5c3dff4eb"
  "Libswscale-GPL MPVKit/releases/download/1.0.0/Libswscale-GPL 1eb1cc2d67e933837be7e5937e440b6dcf0000fd799b96e212dd2c14c5fe2d62"
  "Libcrypto openssl-build/releases/download/3.3.5/Libcrypto 593283be2a90f7fd66f6e6ed331b2f099cf403e0926fe3b4ac09a7062b793965"
  "Libssl openssl-build/releases/download/3.3.5/Libssl ff5ffd43d015d7285fd37e4a3145b25cbd8d2842740bd629a711c299a20e226a"
  "gmp gnutls-build/releases/download/3.8.11/gmp ad33c7a08f4cdcb9924c8f0e6d9a054dad33d7794b97667bf8b6fb2b236ae585"
  "nettle gnutls-build/releases/download/3.8.11/nettle 0fdf3ebf8bd7b8bc8eee837cf27261cb4c52ae520b6576a2f468656aa1691e02"
  "hogweed gnutls-build/releases/download/3.8.11/hogweed 25727c9fa67287fa0a4f4722f88bb8be669b23cd7e837e2d00870eb8a25d3f27"
  "gnutls gnutls-build/releases/download/3.8.11/gnutls 3dbec5809339189bf9679e218c6cff387ebf8fb72745927835afc2678f5c9f4d"
  "Libunibreak libass-build/releases/download/0.17.5/Libunibreak 940d9833cf4477d0a260d9f2b4066125bc0ff7bbc111ac3c90e774765b77a559"
  "Libfreetype libass-build/releases/download/0.17.5/Libfreetype 496ca62488530e14b1e4624d20ee2b237c0bd675cd70c19da578a5768302d02d"
  "Libfribidi libass-build/releases/download/0.17.5/Libfribidi bc15e097b892f2f90424e4a27ba287070cc2f98a74a4da10e6d2481d15cf5ff9"
  "Libharfbuzz libass-build/releases/download/0.17.5/Libharfbuzz aa8e0b9ca0387dac74e3e93c86e34d11982bb013b28022d0e6966a8427a35b2e"
  "Libass libass-build/releases/download/0.17.5/Libass 3f4c576d2818ceb4544aa2a20e1f55846511c5e706fd19adc3ea9fd842270498"
  "Libsmbclient libsmbclient-build/releases/download/4.15.13-2512/Libsmbclient 3a53375fab11bc888cc553664ea5dd902208d04f0cc21ec746302bf356246b6f"
  "Libbluray libbluray-build/releases/download/1.4.0/Libbluray bc037d34e2b0b5ab7f202fb371f5fb298136cc66fdf406c2172185d06f53f18d"
  "Libuavs3d libuavs3d-build/releases/download/1.2.1-fix/Libuavs3d bd5256081486d16c51c868d755bf70266c424b54c895269580de44ec6707f789"
  "Libdovi libdovi-build/releases/download/3.3.2/Libdovi e693e239808350868e79c5448ef9f02e2716bc822dd8632a41a368a1eae5ca7d"
  "MoltenVK moltenvk-build/releases/download/1.4.2/MoltenVK aee189c54ad7c62bf734a3dc51eb4cfad5685d1d63b0ec519ecd1b437c332418"
  "Libshaderc_combined libshaderc-build/releases/download/2025.5.0/Libshaderc_combined 758047b615708575b580eb960a2d083f760a29dc462d6eaa360416c946ce433b"
  "lcms2 lcms2-build/releases/download/2.17.0/lcms2 dc0dce0606f6ab6841a8ec5a6bd4448e2f3ef00661a050460f806c9393dc6982"
  "Libplacebo libplacebo-build/releases/download/7.360.1/Libplacebo 2fa3d54cb81f302d6f11c7b2f509af30944381c3b11ee9d35096eb4637a6e2dd"
  "Libdav1d libdav1d-build/releases/download/1.5.3/Libdav1d d1a32ae6a1f0193e9f05c44c9176844af7f6d2a58cb33843f6f1b8dfd9224083"
  "Libuchardet libuchardet-build/releases/download/0.0.8/Libuchardet ea4f548a230a755e059144657cc9e2ff563c1cdeae03974c38f8b6e1a40303fb"
)
CATALYST_SLICE="ios-arm64_x86_64-maccatalyst"

catalyst="$WORK/catalyst-$CATALYST_TAG"
mkdir -p "$catalyst/zips"
catalyst_archives=()
for entry in "${CATALYST_LIBS[@]}"; do
  read -r name path sha <<<"$entry"
  if [[ ! -d "$catalyst/$name" ]]; then
    zip="$catalyst/zips/$name.xcframework.zip"
    curl -fsL --retry 3 -o "$zip" "https://github.com/mpvkit/$path.xcframework.zip"
    echo "$sha  $zip" | shasum -a 256 -c - >/dev/null || { echo "Checksum mismatch for $zip" >&2; exit 1; }
    # Every zip carries eight platforms; only the Catalyst slice is kept, and the zip goes.
    mkdir -p "$catalyst/$name.partial" && unzip -q "$zip" "*/$CATALYST_SLICE/*" -d "$catalyst/$name.partial"
    rm -f "$zip"
    mv "$catalyst/$name.partial" "$catalyst/$name"
  fi
  lib=$(find "$catalyst/$name" -path "*/$CATALYST_SLICE/*.framework/*" -type f -maxdepth 4 ! -name "*.plist" ! -path "*/Headers/*" ! -path "*/Modules/*" | head -1)
  [[ -n "$lib" ]] || lib=$(find "$catalyst/$name" -path "*/$CATALYST_SLICE/*.a" | head -1)
  [[ -n "$lib" ]] || { echo "$name has no $CATALYST_SLICE library" >&2; exit 1; }
  catalyst_archives+=("$lib")
done
catalyst_mpv="$(dirname "${catalyst_archives[0]}")"
nm -gU "${catalyst_archives[0]}" 2>/dev/null | awk '$3 ~ /^_mpv_/ {print $3}' | sort -u > "$build/mpv-catalyst.exp"

link_catalyst() {
  local target=$1 out=$2
  local sysroot ios fw=() keep=()
  sysroot="$(xcrun --sdk macosx --show-sdk-path)"
  ios="$sysroot/System/iOSSupport"
  for f in "${FRAMEWORKS[@]}" IOKit; do
    if [[ -d "$sysroot/System/Library/Frameworks/$f.framework" || -d "$ios/System/Library/Frameworks/$f.framework" ]]; then
      fw+=(-framework "$f")
    fi
  done
  while read -r sym; do keep+=("-Wl,-u,$sym"); done < "$build/mpv-catalyst.exp"
  xcrun --sdk macosx clang -dynamiclib -target "$target" -isysroot "$sysroot" \
    -iframework "$ios/System/Library/Frameworks" -F "$ios/System/Library/Frameworks" -L "$ios/usr/lib" -o "$out" \
    "${keep[@]}" "${catalyst_archives[@]}" \
    -Wl,-exported_symbols_list,"$build/mpv-catalyst.exp" -install_name @rpath/ZelefinMPV.framework/Versions/A/ZelefinMPV \
    "${fw[@]}" "${LIBS[@]}" -Wl,-dead_strip -Wl,-dead_strip_dylibs 2>&1 | grep -v "was built for newer" || true
}

# Mac bundles are versioned: Versions/A holds the files, the top level only symlinks.
make_catalyst_framework() {
  local fw="$1/ZelefinMPV.framework" version
  version="$fw/Versions/A"
  mkdir -p "$version/Headers/mpv" "$version/Modules" "$version/Resources"
  cp "$catalyst_mpv/Headers/mpv/"*.h "$version/Headers/mpv/"
  printf '#include <ZelefinMPV/mpv/client.h>\n#include <ZelefinMPV/mpv/render.h>\n' > "$version/Headers/ZelefinMPV.h"
  printf 'framework module ZelefinMPV {\n    umbrella header "ZelefinMPV.h"\n    export *\n}\n' > "$version/Modules/module.modulemap"
  /usr/libexec/PlistBuddy \
    -c "Add :CFBundleIdentifier string app.zelefin.ZelefinMPV" -c "Add :CFBundleName string ZelefinMPV" \
    -c "Add :CFBundleExecutable string ZelefinMPV" -c "Add :CFBundlePackageType string FMWK" \
    -c "Add :CFBundleShortVersionString string $CATALYST_TAG" -c "Add :CFBundleVersion string 1" \
    -c "Add :CFBundleSupportedPlatforms array" -c "Add :CFBundleSupportedPlatforms:0 string MacOSX" \
    -c "Add :LSMinimumSystemVersion string 15.0" "$version/Resources/Info.plist" >/dev/null
  ln -s A "$fw/Versions/Current"
  for item in ZelefinMPV Headers Modules Resources; do ln -s "Versions/Current/$item" "$fw/$item"; done
}

make_framework ios-arm64 "$build/device"
link_slice ios-arm64 iphoneos arm64-apple-ios18.0 "$build/device/ZelefinMPV.framework/ZelefinMPV"
make_dsym "$build/device/ZelefinMPV.framework"

make_framework ios-arm64_x86_64-simulator "$build/sim"
link_slice ios-arm64_x86_64-simulator iphonesimulator arm64-apple-ios18.0-simulator "$build/sim/arm64"
link_slice ios-arm64_x86_64-simulator iphonesimulator x86_64-apple-ios18.0-simulator "$build/sim/x86_64"
lipo -create "$build/sim/arm64" "$build/sim/x86_64" -output "$build/sim/ZelefinMPV.framework/ZelefinMPV"
make_dsym "$build/sim/ZelefinMPV.framework"

make_catalyst_framework "$build/catalyst"
link_catalyst arm64-apple-ios18.0-macabi "$build/catalyst/arm64"
link_catalyst x86_64-apple-ios18.0-macabi "$build/catalyst/x86_64"
lipo -create "$build/catalyst/arm64" "$build/catalyst/x86_64" -output "$build/catalyst/ZelefinMPV.framework/Versions/A/ZelefinMPV"
xcrun dsymutil "$build/catalyst/ZelefinMPV.framework/Versions/A/ZelefinMPV" -o "$build/catalyst/ZelefinMPV.framework.dSYM"
xcrun strip -S "$build/catalyst/ZelefinMPV.framework/Versions/A/ZelefinMPV"

for binary in "$build/device/ZelefinMPV.framework/ZelefinMPV" "$build/catalyst/arm64"; do
  if nm -gU "$binary" | awk '{print $3}' | grep -qv '^_mpv_'; then
    echo "ZelefinMPV exports something other than mpv_*; FFmpeg would leak into the app." >&2
    exit 1
  fi
done

rm -rf "$OUT"
xcodebuild -create-xcframework \
  -framework "$build/device/ZelefinMPV.framework" -debug-symbols "$build/device/ZelefinMPV.framework.dSYM" \
  -framework "$build/sim/ZelefinMPV.framework" -debug-symbols "$build/sim/ZelefinMPV.framework.dSYM" \
  -framework "$build/catalyst/ZelefinMPV.framework" -debug-symbols "$build/catalyst/ZelefinMPV.framework.dSYM" \
  -output "$OUT" >/dev/null
echo "Built $OUT"
