#!/usr/bin/env bash
set -euo pipefail

# Simple DMG builder for DayArc (local testing, no Developer ID required)
# This creates an unsigned DMG for testing on your own Mac

APP_NAME="DayArc"
SCHEME="DayArc"
CONFIG="Release"
PROJECT_PATH="DayArc.xcodeproj"
DERIVED_DATA="build"
VERSION="2.0.0"
DMG_NAME="${APP_NAME}-v${VERSION}-unsigned.dmg"

APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIG}/${APP_NAME}.app"

echo "================================================"
echo "Building ${APP_NAME} DMG (Unsigned Test Build)"
echo "================================================"

# Step 1: Build the app (without code signing)
echo ""
echo "[1/3] Building ${APP_NAME} (${CONFIG})..."
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIG}" \
  -derivedDataPath "${DERIVED_DATA}" \
  -destination 'platform=macOS' \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  clean build

if [[ ! -d "${APP_PATH}" ]]; then
  echo "ERROR: Built app not found at ${APP_PATH}"
  exit 1
fi

echo "✓ Build successful"

# Step 2: Check if create-dmg is installed
echo ""
echo "[2/3] Checking for create-dmg..."
if ! command -v create-dmg &>/dev/null; then
  echo "Installing create-dmg via Homebrew..."
  if ! command -v brew &>/dev/null; then
    echo "ERROR: Homebrew not found. Install it from https://brew.sh"
    echo "Or install create-dmg manually from https://github.com/create-dmg/create-dmg"
    exit 1
  fi
  brew install create-dmg
fi

echo "✓ create-dmg available"

# Step 3: Create DMG
echo ""
echo "[3/3] Creating DMG..."
rm -f "${DMG_NAME}"

create-dmg \
  --volname "${APP_NAME}" \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "${APP_NAME}.app" 175 190 \
  --app-drop-link 425 190 \
  --no-internet-enable \
  "${DMG_NAME}" \
  "${APP_PATH}"

echo ""
echo "================================================"
echo "✓ DMG created successfully!"
echo "================================================"
echo ""
echo "Output: ${DMG_NAME}"
echo "Size: $(du -h "${DMG_NAME}" | cut -f1)"
echo ""
echo "⚠️  NOTE: This is an unsigned build for LOCAL TESTING only."
echo "   - Works on your Mac"
echo "   - Will NOT work on other Macs (Gatekeeper will block)"
echo "   - For distribution, you need a Developer ID certificate"
echo ""
echo "To test:"
echo "  1. Double-click ${DMG_NAME}"
echo "  2. Drag ${APP_NAME}.app to Applications folder"
echo "  3. Run from Applications"
echo ""
