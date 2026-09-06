#!/bin/zsh
# Launch the dev build on a page, sized/positioned for inspection (ignores stale window state).
PAGE=${1:-home}
FRAME=${2:-"200,120,1000,700"}
pkill -x Speek 2>/dev/null; sleep 0.5
cd "$(dirname "$0")/.."
APP=.local-build/Build/Products/Debug/Speek.app
[ -d /Applications/Speek.app ] && APP=/Applications/Speek.app
# Launch through LaunchServices (like the Dock does) so the app is not tied to this
# shell; running the binary directly makes it exit when the shell goes away.
open -n "$APP" --args -ApplePersistenceIgnoreState YES -speekPage "$PAGE" -speekWindowFrame "$FRAME"
sleep 4
osascript -e 'tell application id "com.aveekpatra.speek" to activate' 2>/dev/null
echo "shown: $PAGE"
