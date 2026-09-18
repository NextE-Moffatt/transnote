#!/bin/bash
# 构建并安装 TransNote.app 到 /Applications
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="/Applications/TransNote.app"
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

"$HERE/build.sh"

echo "==> 安装到 $DEST"
rm -rf "$DEST"
cp -R "$HERE/build/TransNote.app" "$DEST"

echo "==> 移除旧的「快速操作」版本（避免右击菜单重复）"
rm -rf "$HOME/Library/Services/英译中.workflow"
rm -rf "$HOME/Library/Services/英译中并加入笔记.workflow"

echo "==> 注册系统服务"
# 构建目录里那份必须注销并删掉，否则 LaunchServices 会记住那个路径，
# 一旦源目录被移动或删除，右击菜单就会失效。
"$LSREG" -u "$HERE/build/TransNote.app" >/dev/null 2>&1 || true
rm -rf "$HERE/build/TransNote.app"
"$LSREG" -f "$DEST" >/dev/null 2>&1 || true
"$DEST/Contents/MacOS/TransNote" --register >/dev/null 2>&1 || true
killall pbs 2>/dev/null || true

echo "==> 安装登录项（这样重启后全局快捷键依然有效）"
AGENT="$HOME/Library/LaunchAgents/com.transnote.app.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$AGENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.transnote.app</string>
	<key>ProgramArguments</key>
	<array>
		<string>/Applications/TransNote.app/Contents/MacOS/TransNote</string>
		<string>--background</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
</dict>
</plist>
PLIST
/usr/bin/plutil -lint "$AGENT" >/dev/null
launchctl bootout "gui/$UID/com.transnote.app" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$AGENT" >/dev/null 2>&1 || launchctl load "$AGENT" >/dev/null 2>&1 || true

echo
echo "完成。"
echo
echo "右击菜单（选中文本后）：  服务 / 快速操作  ->  英译中 / 英译中并加入笔记"
echo "全局快捷键：              $(/usr/bin/python3 -c "
import json,os
p=os.path.expanduser('~/.transnote/config.json')
c=json.load(open(p,encoding='utf-8')) if os.path.exists(p) else {}
print(c.get('hotkeyTranslate','opt+cmd+T'), '/', c.get('hotkeyAddNote','shift+opt+cmd+T'))
" 2>/dev/null)  (翻译剪贴板 / 翻译剪贴板并加入笔记)"
echo
echo "如果辅助功能授权换过版本后失效了，执行下面这行再重新授权一次："
echo "    tccutil reset Accessibility com.transnote.app"
echo
echo "打开应用：  open -a TransNote"
echo "自检：      $DEST/Contents/MacOS/TransNote --selftest"
echo "快捷键自检： $DEST/Contents/MacOS/TransNote --hotkeys"
