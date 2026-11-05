#!/bin/zsh -f
# Removes everything install.sh added. The Full Disk Access entry is the one
# thing a script can't remove; this opens the page so you can do it.
set -uo pipefail

name="Messages Export for Claude"
label=io.github.messages-readonly.export
app="$HOME/Applications/$name.app"
desktop_config="$HOME/Library/Application Support/Claude/claude_desktop_config.json"

launchctl bootout "gui/$(id -u)/$label" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$label.plist"
rm -rf "$app" "$HOME/Library/Application Support/messages-readonly-connector" "$HOME/Library/Logs/messages-readonly"

copies="$HOME/Library/Application Support/messages-readonly"
if [[ ${1:-} == --keep-copies ]]; then
  echo "Kept the copied messages and contacts in $copies. Delete that folder when you're done with them."
else
  rm -rf "$copies"
  echo "Deleted the copied messages and contacts."
fi

if [[ -f $desktop_config ]]; then
  cp "$desktop_config" "$desktop_config.bak-$(date +%Y%m%d-%H%M%S)"
  /usr/bin/python3 -I - "$desktop_config" <<'EOF'
import json, sys
path = sys.argv[1]
cfg = json.load(open(path))
cfg.get("mcpServers", {}).pop("messages-readonly", None)
json.dump(cfg, open(path, "w"), indent=2)
EOF
fi
command -v claude >/dev/null && claude mcp remove --scope user messages-readonly >/dev/null 2>&1

echo "Removed. Last step: in the Full Disk Access list that's opening, select \"$name\" and click the minus button."
echo "(Remove the entry rather than switching it off.) Claude Desktop config backups named claude_desktop_config.json.bak-* are left next to the config; delete them if you like."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
