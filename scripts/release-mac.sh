#!/bin/zsh
# Builds, signs, notarizes and zips the Mac app: dist/BloodGlucoseBuddy-<version>-mac.zip
# Needs: xcodegen, a "Developer ID Application" certificate, and a notarytool keychain profile named "notarytool".
set -euo pipefail
cd "$(dirname "$0")/../mac"
xcodegen generate --quiet
xcodebuild test -project BloodGlucoseBuddy.xcodeproj -scheme BloodGlucoseBuddyTests -destination 'platform=macOS' -quiet
xcodebuild -project BloodGlucoseBuddy.xcodeproj -scheme BloodGlucoseBuddy -configuration Release -derivedDataPath build build -quiet
APP="build/Build/Products/Release/Blood Glucose Buddy.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
mkdir -p ../dist
ZIP="../dist/BloodGlucoseBuddy-$VERSION-mac.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile notarytool --wait
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"   # re-zip so the download carries the stapled ticket
spctl -a -vv "$APP"
echo "$ZIP"
