#!/bin/sh
# Google の逆引きクライアント ID を、ビルド済み Info.plist の URL scheme に書く。
# 値は Xcode Cloud の環境変数 MOUTHY_GOOGLE_REVERSED_CLIENT_ID。
# 無ければ Info.plist の GoogleReversedClientID（xcconfig の GOOGLE_REVERSED_CLIENT_ID）。
# 空、または $(...) のままなら何もしない。秘密は扱わない。本番の plist は無い。
set -eu

PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
if [ ! -f "$PLIST" ]; then
  echo "embed_google_url_scheme: Info.plist が無いのでスキップ (${PLIST})"
  exit 0
fi

REVERSED="${MOUTHY_GOOGLE_REVERSED_CLIENT_ID:-}"
if [ -z "$REVERSED" ]; then
  REVERSED="$(/usr/libexec/PlistBuddy -c 'Print :GoogleReversedClientID' "$PLIST" 2>/dev/null || true)"
fi

unsubstituted=${REVERSED#*\$\(}
if [ -z "$REVERSED" ] || [ "$unsubstituted" != "$REVERSED" ]; then
  echo "embed_google_url_scheme: reversed client id が空なので URL scheme は埋め込まない"
  exit 0
fi

/usr/libexec/PlistBuddy -c 'Delete :CFBundleURLTypes' "$PLIST" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes array' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:0 dict' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:0:CFBundleURLName string Google' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:0:CFBundleURLSchemes array' "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string ${REVERSED}" "$PLIST"
echo "embed_google_url_scheme: embedded ${REVERSED}"
