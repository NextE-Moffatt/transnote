#!/bin/bash
# 卸载 TransNote
set -euo pipefail

DEST="/Applications/TransNote.app"
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

killall TransNote 2>/dev/null || true
AGENT="$HOME/Library/LaunchAgents/com.transnote.app.plist"
launchctl bootout "gui/$UID/com.transnote.app" >/dev/null 2>&1 || true
rm -f "$AGENT"
rm -rf "$DEST"
rm -rf "$HOME/Library/Services/英译中.workflow"
rm -rf "$HOME/Library/Services/英译中并加入笔记.workflow"
"$LSREG" -f "$DEST" >/dev/null 2>&1 || true
killall pbs 2>/dev/null || true

echo "已卸载 TransNote。"
echo "配置（~/.transnote/config.json）和笔记文件都保留了。"
