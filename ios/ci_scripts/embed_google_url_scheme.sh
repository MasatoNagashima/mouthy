#!/bin/sh
# GoogleService-Info.plist の REVERSED_CLIENT_ID を、ビルド済み Info.plist の URL scheme に書く。
# STG の plist は ios/Mouthy/GoogleService-Info.plist。オーナーが firebase apps:sdkconfig で作る。
# plist が無い、または REVERSED_CLIENT_ID が空なら何もしない。本番用の plist は無い。
set -eu

PLIST="${SRCROOT}/Mouthy/GoogleService-Info.plist"
INFO="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"

if [ ! -f "$PLIST" ] || [ ! -f "$INFO" ]; then
  exit 0
fi

REVERSED=$(/usr/libexec/PlistBuddy -c "Print :REVERSED_CLIENT_ID" "$PLIST" 2>/dev/null || true)
if [ -z "$REVERSED" ]; then
  exit 0
fi

/usr/libexec/PlistBuddy -c "Delete :CFBundleURLTypes" "$INFO" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" "$INFO"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0 dict" "$INFO"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLName string google-sign-in" "$INFO"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$INFO"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string ${REVERSED}" "$INFO"
