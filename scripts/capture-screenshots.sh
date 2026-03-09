#!/bin/bash
#
# capture-screenshots.sh
#
# Runs the ScreenshotTests UI tests on multiple simulator devices and
# exports screenshots to screenshots/<device-size>/.
#
# Usage:
#   ./scripts/capture-screenshots.sh
#
# Prerequisites:
#   - Run `xcodegen generate` first to ensure the Xcode project is up to date
#   - Simulators for the specified devices must be available

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$PROJECT_DIR/FiveThreeOne.xcodeproj"
SCHEME="FiveThreeOne"
OUTPUT_DIR="$PROJECT_DIR/screenshots"

# Device configurations: "display_size|simulator_name"
DEVICES=(
    "6.7-inch|iPhone 17 Pro Max"
)

main() {
    echo "=== App Store Screenshot Capture ==="
    echo ""

    rm -rf "$OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"

    for device_entry in "${DEVICES[@]}"; do
        IFS='|' read -r device_label simulator_name <<< "$device_entry"
        local result_path="/tmp/screenshots-${device_label}.xcresult"
        local dest_dir="$OUTPUT_DIR/$device_label"

        echo "--- $device_label ($simulator_name) ---"
        rm -rf "$result_path"

        echo "  Running UI tests..."
        if xcodebuild test \
            -project "$PROJECT" \
            -scheme "$SCHEME" \
            -destination "platform=iOS Simulator,name=$simulator_name" \
            -only-testing:ScreenshotTests/ScreenshotTests \
            -resultBundlePath "$result_path" \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO \
            2>&1 | tail -5; then
            echo "  Tests passed."
        else
            echo "  Warning: Some tests may have failed."
        fi

        echo "  Extracting screenshots..."
        mkdir -p "$dest_dir"
        xcrun xcresulttool export attachments \
            --path "$result_path" \
            --output-path "$dest_dir" 2>&1

        # Rename UUID files to human-readable names
        if [ -f "$dest_dir/manifest.json" ]; then
            python3 -c "
import json, os, shutil
os.chdir('$dest_dir')
with open('manifest.json') as f:
    data = json.load(f)
for entry in data:
    for att in entry.get('attachments', []):
        exported = att.get('exportedFileName', '')
        suggested = att.get('suggestedHumanReadableName', '')
        if exported and suggested and os.path.exists(exported):
            clean = suggested.split('_0_')[0] + '.png'
            shutil.move(exported, clean)
            print(f'  {clean}')
"
            rm -f "$dest_dir/manifest.json"
        fi

        rm -rf "$result_path"
        echo ""
    done

    echo "=== Done ==="
    echo "Screenshots saved to: $OUTPUT_DIR"
    echo ""
    find "$OUTPUT_DIR" -name "*.png" -type f | sort
}

main "$@"
