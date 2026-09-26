#!/bin/sh
# Aether's FFmpeg xcframeworks are stripped. Apple still wants a dSYM UUID
# match on TestFlight upload. dsymutil writes that UUID even without DWARF.
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

collect() {
  if [ -d "$1" ]; then
    find "$1" -maxdepth 5 -name 'AetherLib*.framework' 2>/dev/null
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
  xcrun dsymutil "$binary" -o "$dest"
done
