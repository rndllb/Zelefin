#!/bin/sh
# Aether's FFmpeg xcframeworks are stripped and ship without dSYMs. Apple still
# wants a dSYM UUID match on TestFlight upload. dsymutil writes that UUID even
# without DWARF. ZelefinMPV's xcframework normally carries real dSYMs (see
# build-mpv.sh), which Xcode copies in first; this only fills the gap.
set -euo pipefail

case "${DEBUG_INFORMATION_FORMAT:-}" in
*dsym*) ;;
*) exit 0 ;;
esac

dsym_dir="${DWARF_DSYM_FOLDER_PATH:-}"
if [ -z "$dsym_dir" ]; then
  exit 0
fi

mkdir -p "$dsym_dir"

uuids() {
  xcrun dwarfdump --uuid "$1" 2>/dev/null | awk '{print $2}' | sort
}

collect() {
  if [ -d "$1" ]; then
    find "$1" -maxdepth 5 \( -name 'AetherLib*.framework' -o -name 'ZelefinMPV.framework' \) 2>/dev/null
  fi
}

{
  collect "${TARGET_BUILD_DIR:-}/${FRAMEWORKS_FOLDER_PATH:-}"
  collect "${BUILT_PRODUCTS_DIR:-}"
  collect "${TARGET_BUILD_DIR:-}"
} | awk '!seen[$0]++' | while IFS= read -r framework; do
  name="$(basename "$framework" .framework)"
  binary="${framework}/${name}"
  [ -f "$binary" ] || continue
  dest="${dsym_dir}/${name}.framework.dSYM"
  if [ -d "$dest" ] && [ "$(uuids "$dest")" = "$(uuids "$binary")" ]; then
    continue
  fi
  xcrun dsymutil "$binary" -o "$dest"
done
