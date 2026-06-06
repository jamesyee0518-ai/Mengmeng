#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/pocket_companion"
TARGET="${1:-android-apk}"
GATEWAY_URL="${AI_GATEWAY_BASE_URL:-http://192.168.1.111:8787}"

cd "$APP_DIR"

common_args=(
  "--dart-define=AI_GATEWAY_BASE_URL=$GATEWAY_URL"
)

case "$TARGET" in
  android-apk)
    flutter build apk --release "${common_args[@]}"
    echo "Android APK: $APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
    ;;
  android-apk-debug)
    flutter build apk --debug "${common_args[@]}"
    echo "Android debug APK: $APP_DIR/build/app/outputs/flutter-apk/app-debug.apk"
    ;;
  android-aab)
    flutter build appbundle --release "${common_args[@]}"
    echo "Android App Bundle: $APP_DIR/build/app/outputs/bundle/release/app-release.aab"
    ;;
  macos)
    flutter build macos --release "${common_args[@]}"
    echo "macOS app: $APP_DIR/build/macos/Build/Products/Release/pocket_companion.app"
    ;;
  linux)
    flutter build linux --release "${common_args[@]}"
    echo "Linux bundle: $APP_DIR/build/linux/x64/release/bundle"
    ;;
  windows)
    flutter build windows --release "${common_args[@]}"
    echo "Windows bundle: $APP_DIR/build/windows/x64/runner/Release"
    ;;
  all-local)
    flutter build apk --release "${common_args[@]}"
    case "$(uname -s)" in
      Darwin) flutter build macos --release "${common_args[@]}" ;;
      Linux) flutter build linux --release "${common_args[@]}" ;;
      MINGW*|MSYS*|CYGWIN*) flutter build windows --release "${common_args[@]}" ;;
      *) echo "Only Android was built; desktop target is not supported on this host." ;;
    esac
    ;;
  *)
    cat <<'USAGE'
Usage:
  scripts/build_pocket_companion.sh android-apk
  scripts/build_pocket_companion.sh android-apk-debug
  scripts/build_pocket_companion.sh android-aab
  scripts/build_pocket_companion.sh macos
  scripts/build_pocket_companion.sh linux
  scripts/build_pocket_companion.sh windows
  scripts/build_pocket_companion.sh all-local

Optional:
  AI_GATEWAY_BASE_URL=http://192.168.1.111:8787 scripts/build_pocket_companion.sh android-apk

Note:
  Flutter desktop apps are normally built on their own OS:
  macOS on macOS, Linux on Linux, Windows on Windows.
USAGE
    exit 2
    ;;
esac
