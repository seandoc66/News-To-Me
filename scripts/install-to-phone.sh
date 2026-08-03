#!/usr/bin/env bash
#
# Builds the app and installs it on a connected iPhone.
#
#     scripts/install-to-phone.sh
#
# Release configuration on purpose. Debug builds point FeedEndpoint at
# http://localhost:8765 — on the phone that means the phone itself, so the feed
# fetch and every photo fail and you get "could not connect to the server" over
# whatever stories were already cached. Release reads the published feed at
# seandoc66.github.io, which works anywhere with a network.
#
# Each run bumps the build number so two installs can be told apart in the app's
# Sections screen, which shows "News <version> (build <n>)" at the bottom. The
# counter lives in .build-number and isn't committed; delete it to restart.
#
# The build is signed with a personal development profile, so iOS stops
# launching it about 7 days after install. Re-run this to get another week.

set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="NewsApp.xcodeproj"
SCHEME="NewsApp"
BUNDLE_ID="com.shanedoc.NewsApp"
COUNTER_FILE=".build-number"
DERIVED_DATA="build/phone"

# --- Pick the device ------------------------------------------------------
# Uses DEVICE_ID if set, otherwise the single connected iPhone. More than one
# connected and it asks rather than guessing.
if [[ -n "${DEVICE_ID:-}" ]]; then
    device_id="$DEVICE_ID"
else
    devices_json="$(mktemp)"
    trap 'rm -f "$devices_json"' EXIT
    xcrun devicectl list devices --json-output "$devices_json" >/dev/null 2>&1

    device_list="$(python3 - "$devices_json" <<'PY'
import json, sys

with open(sys.argv[1]) as f:
    payload = json.load(f)

for device in payload.get("result", {}).get("devices", []):
    properties = device.get("deviceProperties", {})
    connected = device.get("connectionProperties", {}).get("tunnelState")
    if connected == "unavailable":
        continue
    identifier = device.get("identifier")
    name = properties.get("name", "unnamed")
    print(f"{identifier}\t{name}")
PY
)"

    if [[ -z "$device_list" ]]; then
        echo "No connected device found. Plug the phone in, unlock it, and tap Trust." >&2
        exit 1
    fi

    if [[ "$(wc -l <<<"$device_list")" -gt 1 ]]; then
        echo "More than one device connected — set DEVICE_ID to pick one:" >&2
        echo "$device_list" >&2
        exit 1
    fi

    device_id="$(cut -f1 <<<"$device_list")"
    device_name="$(cut -f2 <<<"$device_list")"
    echo "Device: $device_name"
fi

# --- Bump the build number ------------------------------------------------
previous="$(cat "$COUNTER_FILE" 2>/dev/null || echo 1)"
build_number=$((previous + 1))
echo "$build_number" >"$COUNTER_FILE"
echo "Build number: $build_number"

# --- Build ----------------------------------------------------------------
# CURRENT_PROJECT_VERSION is overridden here rather than edited in the project
# file, so bumping it leaves no diff to commit. GENERATE_INFOPLIST_FILE is on,
# so this becomes CFBundleVersion.
echo "Building..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "id=$device_id" \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    CURRENT_PROJECT_VERSION="$build_number" \
    build \
    >/dev/null

app_path="$DERIVED_DATA/Build/Products/Release-iphoneos/$SCHEME.app"
if [[ ! -d "$app_path" ]]; then
    echo "Build reported success but $app_path is missing." >&2
    exit 1
fi

# --- Install and launch ---------------------------------------------------
echo "Installing..."
xcrun devicectl device install app --device "$device_id" "$app_path" >/dev/null

# Launching needs the phone unlocked. It's already installed by this point, so a
# locked phone is worth a note rather than a failure.
echo "Launching..."
if xcrun devicectl device process launch --device "$device_id" "$BUNDLE_ID" >/dev/null 2>&1; then
    echo "Done — build $build_number is on the phone and running."
else
    echo "Done — build $build_number is installed. Couldn't launch it (phone locked?); open it by hand."
fi
