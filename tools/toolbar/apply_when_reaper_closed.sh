#!/bin/zsh
# Waits for REAPER to quit (it rewrites reaper-menu.ini on quit), then applies the
# Nathaniel Tools toolbar patch once. Safe to re-run; exits after one application.
LOG="$HOME/Library/Application Support/REAPER/nt-toolbar-apply.log"
while pgrep -x REAPER >/dev/null; do sleep 15; done
sleep 4
python3 "$HOME/Documents/nph-reaper-suite/tools/toolbar/apply_toolbar.py" >> "$LOG" 2>&1
echo "$(date) applied" >> "$LOG"
