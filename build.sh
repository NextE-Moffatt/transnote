#!/bin/bash
# 构建 TransNote.app
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="$HERE/build"
APP="$BUILD/TransNote.app"
SRC="$HERE/src"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 编译主程序"
clang -fobjc-arc -fmodules -mmacosx-version-min=11.0 -O2 -Wall \
  -framework Cocoa -framework Carbon -framework ApplicationServices -framework AVFoundation \
  "$SRC/TransNoteEngine.m" "$SRC/TNHotKeys.m" "$SRC/TNSelection.m" \
  "$SRC/TNNotes.m" "$SRC/TNVocab.m" "$SRC/main.m" \
  -o "$APP/Contents/MacOS/TransNote"

echo "==> 生成图标"
clang -fobjc-arc -fmodules -mmacosx-version-min=11.0 -O2 \
  -framework Cocoa "$SRC/makeicon.m" -o "$BUILD/makeicon"
"$BUILD/makeicon" "$BUILD/TransNote.iconset" >/dev/null
iconutil -c icns "$BUILD/TransNote.iconset" -o "$APP/Contents/Resources/TransNote.icns"

echo "==> 写入 Info.plist"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>zh_CN</string>
	<key>CFBundleExecutable</key>
	<string>TransNote</string>
	<key>CFBundleIconFile</key>
	<string>TransNote</string>
	<key>CFBundleIdentifier</key>
	<string>com.transnote.app</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>TransNote</string>
	<key>CFBundleDisplayName</key>
	<string>TransNote</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>11.0</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.productivity</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>英译中</string>
			</dict>
			<key>NSMessage</key>
			<string>translateService</string>
			<key>NSReturnTypes</key>
			<array/>
			<key>NSSendTypes</key>
			<array>
				<string>public.utf8-plain-text</string>
			</array>
		</dict>
		<dict>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>英译中并加入笔记</string>
			</dict>
			<key>NSMessage</key>
			<string>translateAndNoteService</string>
			<key>NSReturnTypes</key>
			<array/>
			<key>NSSendTypes</key>
			<array>
				<string>public.utf8-plain-text</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
PLIST

/usr/bin/plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "==> 签名"
# 优先用固定的本地身份：ad-hoc 的指定要求只绑 cdhash，
# 重新编译就会让 macOS 的辅助功能授权失效。
"$HERE/make-identity.sh" >/dev/null 2>&1 || true
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
if security find-identity -p codesigning 2>/dev/null | grep -q "TransNote Local Signing" &&
   codesign --force --sign "TransNote Local Signing" --keychain "$KEYCHAIN" "$APP" >/dev/null 2>&1; then
  echo "   已用固定身份签名（重新编译不会丢辅助功能授权）"
else
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
  echo "   已用 ad-hoc 签名（重新编译后需要重新授权辅助功能）"
fi

echo "构建完成: $APP"
