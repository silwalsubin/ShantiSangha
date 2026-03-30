#!/bin/bash
# Upload to TestFlight from local Mac
# Usage: cd ios && ./upload-testflight.sh

set -e

echo "🔨 Cleaning..."
xcodebuild clean -project ShantiSangha.xcodeproj -scheme ShantiSangha -configuration Release

# Increment build number
BUILD_NUMBER=$(date +%Y%m%d%H%M)
echo "📦 Build number: $BUILD_NUMBER"
agvtool new-version -all $BUILD_NUMBER

echo "🔨 Archiving..."
xcodebuild archive \
  -project ShantiSangha.xcodeproj \
  -scheme ShantiSangha \
  -configuration Release \
  -archivePath build/ShantiSangha.xcarchive \
  -sdk iphoneos \
  -destination generic/platform=iOS

echo "📤 Exporting IPA..."
cat > build/ExportOptions.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath build/ShantiSangha.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist \
  -exportPath build/export \
  -allowProvisioningUpdates

echo "🚀 Uploading to TestFlight..."
xcrun altool --upload-app \
  --type ios \
  --file build/export/ShantiSangha.ipa \
  --apiKey "$APP_STORE_API_KEY_ID" \
  --apiIssuer "$APP_STORE_API_ISSUER_ID"

echo "✅ Done! Check App Store Connect for the new build."
