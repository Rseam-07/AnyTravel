#!/usr/bin/env bash
set -euo pipefail

PACKAGE_NAME="cn.anytravel.app"
ACTIVITY_NAME="cn.anytravel.app/.MainActivity"
SCRIPT_DIRECTORY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_DIRECTORY="$(cd -- "$SCRIPT_DIRECTORY/.." && pwd)"
RUN_STAMP="$(date '+%Y%m%d-%H%M%S')"
OUTPUT_DIRECTORY="${1:-$ANDROID_DIRECTORY/diagnostics/xperia-$RUN_STAMP}"

find_adb() {
    if [[ -n "${ANYTRAVEL_ADB:-}" && -x "${ANYTRAVEL_ADB}" ]]; then
        printf '%s\n' "$ANYTRAVEL_ADB"
        return
    fi
    if command -v adb >/dev/null 2>&1; then
        command -v adb
        return
    fi
    if [[ -n "${ANDROID_SDK_ROOT:-}" && -x "$ANDROID_SDK_ROOT/platform-tools/adb" ]]; then
        printf '%s\n' "$ANDROID_SDK_ROOT/platform-tools/adb"
        return
    fi
    if [[ -x "/private/tmp/anytravel-android-sdk/platform-tools/adb" ]]; then
        printf '%s\n' "/private/tmp/anytravel-android-sdk/platform-tools/adb"
        return
    fi
    return 1
}

ADB_BINARY="$(find_adb || true)"
if [[ -z "$ADB_BINARY" ]]; then
    echo "找不到 adb。请安装 Android platform-tools，或设置 ANYTRAVEL_ADB=/path/to/adb。" >&2
    exit 1
fi

CONNECTED_DEVICES="$($ADB_BINARY devices | awk 'NR > 1 && $2 == "device" { count += 1 } END { print count + 0 }')"
if [[ "$CONNECTED_DEVICES" -ne 1 ]]; then
    echo "需要且只能连接一台已授权设备；当前可用设备数：$CONNECTED_DEVICES。" >&2
    "$ADB_BINARY" devices -l >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIRECTORY"

{
    echo "captured_at=$(date -Iseconds)"
    echo "manufacturer=$($ADB_BINARY shell getprop ro.product.manufacturer | tr -d '\r')"
    echo "model=$($ADB_BINARY shell getprop ro.product.model | tr -d '\r')"
    echo "device=$($ADB_BINARY shell getprop ro.product.device | tr -d '\r')"
    echo "android=$($ADB_BINARY shell getprop ro.build.version.release | tr -d '\r')"
    echo "sdk=$($ADB_BINARY shell getprop ro.build.version.sdk | tr -d '\r')"
    echo "abi=$($ADB_BINARY shell getprop ro.product.cpu.abi | tr -d '\r')"
    echo "hardware=$($ADB_BINARY shell getprop ro.hardware | tr -d '\r')"
    echo "gles=$($ADB_BINARY shell getprop ro.opengles.version | tr -d '\r')"
    echo "app=$($ADB_BINARY shell dumpsys package "$PACKAGE_NAME" | awk -F= '/versionName=|versionCode=/{gsub(/^ +/, ""); print}' | tr -d '\r')"
} > "$OUTPUT_DIRECTORY/device-info.txt"

if ! "$ADB_BINARY" shell pm path "$PACKAGE_NAME" >/dev/null 2>&1; then
    echo "设备上没有安装 $PACKAGE_NAME。请先安装待测 APK。" >&2
    exit 1
fi

cleanup() {
    if [[ -n "${LOGCAT_PROCESS_ID:-}" ]]; then
        kill "$LOGCAT_PROCESS_ID" >/dev/null 2>&1 || true
        wait "$LOGCAT_PROCESS_ID" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT INT TERM

"$ADB_BINARY" logcat -c
"$ADB_BINARY" shell am force-stop "$PACKAGE_NAME"
"$ADB_BINARY" logcat -v threadtime \
    AndroidRuntime:E libc:F DEBUG:F MapLibre:V Mbgl:V OpenGLRenderer:W \
    SurfaceFlinger:W ActivityManager:I ActivityTaskManager:I '*:S' \
    > "$OUTPUT_DIRECTORY/runtime.log" &
LOGCAT_PROCESS_ID=$!

"$ADB_BINARY" shell am start -W -n "$ACTIVITY_NAME" \
    > "$OUTPUT_DIRECTORY/launch.txt"

echo "AnyTravel 已启动。请在 Xperia 上复现闪退或卡顿，完成后回到这里按回车。"
read -r

cleanup
LOGCAT_PROCESS_ID=""
"$ADB_BINARY" logcat -b crash -d -v threadtime > "$OUTPUT_DIRECTORY/crash-buffer.log" || true
"$ADB_BINARY" shell dumpsys activity exit-info "$PACKAGE_NAME" > "$OUTPUT_DIRECTORY/exit-info.txt" || true
"$ADB_BINARY" shell dumpsys meminfo "$PACKAGE_NAME" > "$OUTPUT_DIRECTORY/memory.txt" || true

echo "诊断包已写入：$OUTPUT_DIRECTORY"
