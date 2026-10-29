#!/usr/bin/env bash
# Builds the signed Android release APKs (arm64, 32-bit ARM, x86_64, universal) and, with --publish,
# puts them on a GitHub release that zelefin.app/android lists.
#
#   Android/scripts/release-android.sh                       build and check only
#   Android/scripts/release-android.sh --publish notes.md    build, then publish with these notes
#
# The release key lives at ~/.zelefin/android/zelefin-release.jks and its password in the macOS
# Keychain ("Zelefin Android release key"). Every release must use that key, or phones refuse the update.
set -euo pipefail

ANDROID_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="rndllb/Zelefin"
KEYSTORE="${ZELEFIN_KEYSTORE:-$HOME/.zelefin/android/zelefin-release.jks}"
KEYCHAIN_SERVICE="Zelefin Android release key"
JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
export JAVA_HOME

publish=false
notes=""
if [[ "${1:-}" == "--publish" ]]; then
  publish=true
  notes="${2:-}"
  [[ -f "$notes" ]] || { echo "Pass a release notes file: --publish notes.md" >&2; exit 1; }
fi

version=$(sed -n 's/^ *versionName = "\(.*\)"/\1/p' "$ANDROID_DIR/app/build.gradle.kts")
code=$(sed -n 's/^ *versionCode = \([0-9]*\)/\1/p' "$ANDROID_DIR/app/build.gradle.kts")
[[ -n "$version" && -n "$code" ]] || { echo "Could not read versionName and versionCode." >&2; exit 1; }
tag="android-v$version-$code"
echo "Zelefin $version ($code)"

[[ -f "$KEYSTORE" ]] || { echo "Release key not found at $KEYSTORE" >&2; exit 1; }
password=$(security find-generic-password -a zelefin-release -s "$KEYCHAIN_SERVICE" -w) || {
  echo "Release key password not found in the Keychain." >&2
  exit 1
}
export ZELEFIN_RELEASE_STORE_FILE="$KEYSTORE" ZELEFIN_RELEASE_STORE_PASSWORD="$password" ZELEFIN_RELEASE_KEY_ALIAS=zelefin
unset password

gradle="$ANDROID_DIR/gradlew"
[[ -x "$gradle" ]] || gradle="$(ls -d "$HOME"/.gradle/wrapper/dists/gradle-*/*/gradle-*/bin/gradle 2>/dev/null | sort | tail -1)"
# Packaging four large APKs at once needs more than the default 2 GB heap.
"$gradle" -p "$ANDROID_DIR" :app:assembleRelease -PzelefinSplitAbis -Dorg.gradle.jvmargs=-Xmx4g -q
unset ZELEFIN_RELEASE_STORE_PASSWORD

apksigner="$(ls -d "$HOME"/Library/Android/sdk/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1)"
out="$ANDROID_DIR/build/release/$version-$code"
rm -rf "$out" && mkdir -p "$out"
for abi in arm64-v8a armeabi-v7a x86_64 universal; do
  source_apk="$ANDROID_DIR/app/build/outputs/apk/release/app-$abi-release.apk"
  [[ -f "$source_apk" ]] || { echo "Missing $source_apk" >&2; exit 1; }
  target="$out/Zelefin-$version-$abi.apk"
  cp "$source_apk" "$target"
  if [[ -n "$apksigner" ]]; then
    signer=$("$apksigner" verify --print-certs "$target" | sed -n 's/.*certificate SHA-256 digest: //p' | head -1)
    [[ "$signer" == "93cd9b9563dfa73e6bfd8cf304040116b0569783d01ce397a31cd64b356afb74" ]] || {
      echo "$target is not signed with the Zelefin release key." >&2
      exit 1
    }
  fi
done
(cd "$out" && shasum -a 256 Zelefin-*.apk > SHA256SUMS.txt)
echo "Built and checked:"
(cd "$out" && ls -1 Zelefin-*.apk | while read -r apk; do printf '  %s  %s MB\n' "$apk" "$(( $(stat -f %z "$apk") / 1048576 ))"; done)

if $publish; then
  gh release create "$tag" -R "$REPO" --target main \
    --title "Zelefin $version (Build $code)" --notes-file "$notes" \
    "$out"/Zelefin-*.apk "$out/SHA256SUMS.txt"
  echo "Published $tag. Rebuild zelefin.app/android with: python3 ~/Projects/Websites/zelefin-tools/android_page.py"
fi
