#!/bin/zsh -f
# Installs messages-readonly: read-only iMessage history for Claude, with no
# Full Disk Access for Claude and no way to send.
#
#   ./install.sh                 build, schedule, register, then guide you through the one manual step
#   ./install.sh --check         finish the manual step later, and run the self-test
#   ./install.sh --rebuild       rebuild the app now
#   ./install.sh --claude-code   also register the connector with the claude command in Terminal
#
# Safe to run again. Whenever Full Disk Access has to be granted, it first builds
# the app fresh from the source next to this script, so the grant always goes to
# code built from what you just read, never to whatever is already in ~/Applications.
set -euo pipefail
# Fixed system tools only, so nothing earlier on PATH can stand in for them.
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

here=${0:A:h}
name="Messages Export for Claude"
label=io.github.messages-readonly.export
# The MR_* variables exist only so the installer can be tested without touching a real setup.
app="${MR_APP_DIR:-$HOME/Applications}/$name.app"
agents="${MR_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
plist="$agents/$label.plist"
connector_dir="${MR_CONNECTOR_DIR:-$HOME/Library/Application Support/messages-readonly-connector}"
export_dir="$HOME/Library/Application Support/messages-readonly"
logs="$HOME/Library/Logs/messages-readonly"
desktop_config="${MR_DESKTOP_CONFIG:-$HOME/Library/Application Support/Claude/claude_desktop_config.json}"

check_only=0 rebuild=0 claude_code=0
started=$(date +%s)
for a in "$@"; do
  case $a in
    --check) check_only=1 ;;
    --rebuild) rebuild=1 ;;
    --claude-code) claude_code=1 ;;
    *) echo "Unknown option: $a"; exit 2 ;;
  esac
done

say() { print -P "%B==>%b $*"; }

[[ $(uname) == Darwin ]] || { echo "This works only on macOS."; exit 1; }

if ! xcode-select -p >/dev/null 2>&1; then
  say "Apple's Command Line Tools are needed to build the app. Opening Apple's installer."
  xcode-select --install || true
  echo "When that install finishes, run ./install.sh again."
  exit 1
fi

# Builds the app in place in ~/Applications.
build_app() {
  say "Building $name from $here/src"
  local b="$app"
  mkdir -p "${app:h}"
  rm -rf "$b"
  mkdir -p "$b/Contents/MacOS"
  # A clean environment, so no compiler settings from your shell can change what gets built.
  env -i PATH=/usr/bin:/bin /usr/bin/cc -O2 -Wall -o "$b/Contents/MacOS/messages-export" "$here/src/messages_export.c" -lsqlite3
  cat > "$b/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$label</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundleExecutable</key><string>messages-export</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSBackgroundOnly</key><true/>
</dict>
</plist>
EOF
  # Signed on this Mac with the hardened runtime: macOS ignores DYLD_* variables,
  # so nothing can load its own code into the app and borrow its access.
  /usr/bin/codesign --force --sign - --options runtime --identifier "$label" "$b"
}

if (( ! check_only )); then
  # 1. Build the one program that will hold Full Disk Access.
  if [[ ! -d $app ]] || (( rebuild )); then
    build_app
  else
    say "Keeping the existing app for now; it's rebuilt if Full Disk Access has to be granted again."
  fi

  # 2. Run it every hour.
  say "Scheduling an hourly copy"
  mkdir -p "$agents"
  mkdir -p -m 700 "$logs"
  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array><string>$app/Contents/MacOS/messages-export</string></array>
  <key>StartInterval</key><integer>3600</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$logs/out.log</string>
  <key>StandardErrorPath</key><string>$logs/err.log</string>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>10</integer>
</dict>
</plist>
EOF
  if [[ -z ${MR_AGENTS_DIR:-} ]]; then
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$plist"
  fi

  # 3. Install the connector and register it with Claude.
  say "Installing the read-only connector"
  mkdir -p -m 700 "$connector_dir"
  cp "$here/src/messages_mcp.py" "$connector_dir/messages_mcp.py"
  if [[ -f $desktop_config || -d ${desktop_config:h} ]]; then
    [[ -f $desktop_config ]] && cp -p "$desktop_config" "$desktop_config.bak-$(date +%Y%m%d-%H%M%S)"
    /usr/bin/python3 -I - "$desktop_config" "$connector_dir/messages_mcp.py" <<'EOF'
import json, os, sys
path, server = sys.argv[1], sys.argv[2]
cfg = json.load(open(path)) if os.path.exists(path) else {}
cfg.setdefault("mcpServers", {})["messages-readonly"] = {"command": "/usr/bin/python3", "args": ["-I", server]}
json.dump(cfg, open(path, "w"), indent=2)
EOF
    say "Registered with Claude Desktop (a backup of its config was saved next to it)"
  else
    say "Claude Desktop not found; skipped. Install it and run ./install.sh again to register."
  fi
  if (( claude_code )); then
    claude_cmd=$(/bin/zsh -lc 'command -v claude' 2>/dev/null || true)
    if [[ -n $claude_cmd ]]; then
      "$claude_cmd" mcp remove --scope user messages-readonly >/dev/null 2>&1 || true
      "$claude_cmd" mcp add --scope user messages-readonly -- /usr/bin/python3 -I "$connector_dir/messages_mcp.py"
      say "Registered with the Claude Code command line"
    else
      say "The claude command wasn't found; skipped Claude Code registration."
    fi
  fi
fi

[[ -n ${MR_AGENTS_DIR:-} ]] && { say "Test mode: stopping before Full Disk Access."; exit 0; }

# 4. The one step a person has to do: Apple requires Full Disk Access to be granted by hand.
# The person is guided by dialog boxes on screen, so it works the same whether they
# run this in Terminal or Claude Code runs it for them, and they can take as long as they need.

# Wait for a copy made during this run, so an old copy doesn't count.
fresh() { [[ -f $export_dir/chat.db ]] && (( $(stat -f %m "$export_dir/chat.db") >= started )); }
try_copy() {
  : > "$logs/err.log"
  launchctl kickstart -k "gui/$(id -u)/$label" 2>/dev/null || true
  sleep 3
  while launchctl print "gui/$(id -u)/$label" 2>/dev/null | grep -q "state = running"; do sleep 2; done
  fresh
}
show_settings() {
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
  open -R "$app"
}
# dialog TEXT BUTTON... : shows a dialog, prints the button clicked. The last button is the default.
dialog() {
  osascript - "$@" <<'EOF' 2>/dev/null
on run argv
  set msg to item 1 of argv
  set btns to items 2 thru -1 of argv
  activate
  return button returned of (display dialog msg with title "Messages Export for Claude" buttons btns default button (count of btns) with icon note)
end run
EOF
}
done_msg="Messages Export for Claude made its first copy, so the hard part is done.

Last step: quit Claude Desktop completely (Claude menu > Quit Claude, or Command-Q) and open it again. Then, in a new chat, ask:

Who are the last 3 people I texted with, and when?

macOS may also show a \"Background Items Added\" notice for the hourly copy. That's expected."

if try_copy; then
  say "Full Disk Access is already on."
else
  # Access has to be granted, so build fresh first: the grant goes to code built from the source here.
  build_app
  say "Waiting for you to give \"$name\" Full Disk Access (instructions are in a dialog box on screen)."
  choice=$(dialog "Everything else is installed. One step is yours, because macOS only lets a person give an app Full Disk Access.

When you click Open System Settings:

1. System Settings opens at Privacy & Security > Full Disk Access, and a Finder window shows the app.

2. If \"$name\" is already in the list, select it, click the minus button, and remove it. An entry from an earlier copy won't stay on.

3. Drag \"$name\" from the Finder window into the list, and make sure its switch is on.

System Settings itself may ask for your password or Touch ID. These boxes never will; if a box like this one asks for your password, cancel it.

Take your time. Another box will wait for you, and the install finishes by itself once the switch is on." "Not now" "Open System Settings")
  if [[ -z $choice ]]; then
    # No dialogs available (for example over SSH): fall back to instructions here and keep checking.
    echo "   Open System Settings > Privacy & Security > Full Disk Access, add \"$name\""
    echo "   from ~/Applications (the Applications folder in your home folder), and turn it on."
    show_settings
    until try_copy; do sleep 5; done
  elif [[ $choice == "Not now" ]]; then
    echo "Stopped before Full Disk Access. When you're ready, run ./install.sh --check"
    exit 0
  else
    show_settings
    while ! fresh; do
      # Keep a "Done" box up while checking in the background; whichever comes first wins.
      reply=$(mktemp)
      dialog "Waiting for the switch next to \"$name\" to be on.

This continues by itself once it is, or click Done to check now.

Can't find the app? In the Finder window it's the one selected. Or click + in System Settings, press Shift-Command-H, open Applications there, and choose it." "Stop" "Show me again" "Done" > "$reply" &
      box=$!
      while kill -0 $box 2>/dev/null; do
        if try_copy; then pkill -P $box 2>/dev/null; kill $box 2>/dev/null; break; fi
        sleep 2
      done
      fresh && break
      case $(<"$reply") in
        Stop) echo "Stopped before Full Disk Access. When you're ready, run ./install.sh --check"; exit 0 ;;
        "Show me again") show_settings ;;
        Done) try_copy || dialog "Not seeing access yet.

Check that the switch next to \"$name\" is on. If it is on and this still appears, an old entry is probably in the way. In Terminal, run: tccutil reset SystemPolicyAllFiles $label  Then add the app again with + and wait for the new entry to appear before turning it on." "OK" >/dev/null ;;
      esac
      rm -f "$reply"
    done
  fi
fi

# 5. Self-test: ask the connector for the three most recent conversations.
say "Self-test: your three most recent conversations"
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_recent_conversations","arguments":{"limit":3}}}' |
  /usr/bin/python3 -I "$connector_dir/messages_mcp.py" |
  /usr/bin/python3 -I -c 'import json,sys; [print(r["result"]["content"][0]["text"]) for r in map(json.loads, sys.stdin) if r["id"] == 2]'

say "Done. Quit Claude Desktop completely (Cmd-Q) and reopen it to load the connector."
dialog "$done_msg" "OK" >/dev/null || true
