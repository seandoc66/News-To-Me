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
# counter lives in .git/build-number, shared by every worktree; delete it to
# restart.
#
# The build is signed with the paid team (7UPTF38D36) using an Apple
# Development certificate and the wildcard "iOS Team Provisioning Profile: *".
# Both run a year from issue, so an install keeps working until the profile
# expires — there is no weekly re-install to do. (An earlier version of this
# comment claimed a 7-day personal-team limit. That was wrong, and it sends
# you chasing an expiry that has not happened.)
#
# If the app suddenly refuses to launch AND a fresh install fails with
# 0xe8008015 "A valid provisioning profile for this executable was not found",
# check the expiry dates before assuming signing broke:
#
#     security find-certificate -c "Apple Development: Shane Doherty" -p \
#         | openssl x509 -noout -dates
#     security cms -D -i ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision \
#         | plutil -extract ExpirationDate raw -
#
# If both are still valid, the fault is the phone's in-memory provisioning
# profile cache, which amfid consults for both launching and installing —
# one cache, so both break together. Reboot the phone and it rebuilds from
# disk. Happened 2026-09-10; nothing on the Mac needed changing.

set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="NewsApp.xcodeproj"
SCHEME="NewsApp"
BUNDLE_ID="com.shanedoc.NewsApp"
# Kept in the shared git directory rather than the working tree, so every
# worktree draws from one counter. Per-worktree files would each restart at 1
# and put the same build number on the phone twice, which is the one thing the
# number exists to prevent.
COUNTER_FILE="$(git rev-parse --git-common-dir)/build-number"
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
